--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--

local ngx = ngx
local ipairs = ipairs
local string = string
local tonumber = tonumber
local tostring = tostring
local math = math
local os = os
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local http = require("resty.http")
local endpoints_shared = ngx.shared.discovery or ngx.shared.stream_discovery

local apiserver_host = ""
local apiserver_port = ""
local apiserver_token = ""

local default_weight = 50

local endpoint_lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local empty_table = {}
local pending_resources

local endpoint_cache = {}

local function on_endpoint_deleted(endpoint)
    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    endpoints_shared:delete(endpoint_key .. "#version")
    endpoints_shared:delete(endpoint_key)
end

local function on_endpoint_modified(endpoint)
    if endpoint.subsets == nil or #endpoint.subsets == 0 then
        return on_endpoint_deleted(endpoint)
    end
    local subsets = endpoint.subsets

    core.table.clear(endpoint_cache)

    for _, subset in ipairs(subsets) do
        if subset.addresses == nil or #subset.addresses == 0 then
            break
        end

        local addresses = subset.addresses
        for _, port in ipairs(subset.ports or empty_table) do
            local port_name = ""
            if port.name then
                port_name = port.name
            else
                port_name = tostring(port.port)
            end

            local t = endpoint_cache[port_name]
            if t == nil then
                t = core.table.new(0, #addresses * #subsets)
                endpoint_cache[port_name] = t
            end

            for _, address in ipairs(addresses) do
                core.table.insert(t, {
                    host = address.ip,
                    port = port.port,
                    weight = default_weight
                })
            end
        end
    end

    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    local endpoint_content = core.json.encode(endpoint_cache, true)
    local endpoint_version = ngx.crc32_long(endpoint_content)

    local _, err
    _, err = endpoints_shared:safe_set(endpoint_key .. "#version", endpoint_version)
    if err then
        core.log.emerg("set endpoint version into discovery DICT failed ,", err)
        return
    end
    endpoints_shared:safe_set(endpoint_key, endpoint_content)
    if err then
        core.log.emerg("set endpoint into discovery DICT failed ,", err)
        endpoints_shared:delete(endpoint_key .. "#version")
    end
end

local function list_resource(httpc, resource, continue)
    httpc:set_timeouts(2000, 2000, 3000)
    local res, err = httpc:request({
        path = resource:list_path(),
        query = resource:list_query(continue),
        headers = {
            ["Host"] = string.format("%s:%s", apiserver_host, apiserver_port),
            ["Authorization"] = string.format("Bearer %s", apiserver_token),
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    if not res then
        return false, "RequestError", err or ""
    end

    if res.status ~= 200 then
        return false, res.reason, res:read_body() or ""
    end

    local body, err = res:read_body()
    if err then
        return false, "ReadBodyError", err
    end

    local data, _ = core.json.decode(body)
    if not data or data.kind ~= resource.listKind then
        return false, "UnexpectedBody", body
    end

    resource.newest_resource_version = data.metadata.resourceVersion

    for _, item in ipairs(data.items or empty_table) do
        resource:event_dispatch("ADDED", item, "list")
    end

    if data.metadata.continue ~= nil and data.metadata.continue ~= "" then
        list_resource(httpc, resource, data.metadata.continue)
    end

    return true, "Success", ""
end

local function watch_resource(httpc, resource)
    math.randomseed(process.get_master_pid())
    local watch_seconds = 1800 + math.random(60, 1200)
    local allowance_seconds = 120
    httpc:set_timeouts(2000, 3000, (watch_seconds + allowance_seconds) * 1000)
    local res, err = httpc:request({
        path = resource:watch_path(),
        query = resource:watch_query(watch_seconds),
        headers = {
            ["Host"] = string.format("%s:%s", apiserver_host, apiserver_port),
            ["Authorization"] = string.format("Bearer %s", apiserver_token),
            ["Accept"] = "application/json",
            ["Connection"] = "keep-alive"
        }
    })

    if err then
        return false, "RequestError", err
    end

    if res.status ~= 200 then
        return false, res.reason, res:read_body() or ""
    end

    local remainder_body = ""
    local body = ""
    local reader = res.body_reader
    local gmatch_iterator;
    local captures;
    local captured_size = 0
    while true do

        body, err = reader()
        if err then
            return false, "ReadBodyError", err
        end

        if not body then
            break
        end

        if #remainder_body ~= 0 then
            body = remainder_body .. body
        end

        gmatch_iterator, err = ngx.re.gmatch(body, "{\"type\":.*}\n", "jiao")
        if not gmatch_iterator then
            return false, "GmatchError", err
        end

        while true do
            captures, err = gmatch_iterator()
            if err then
                return false, "GmatchError", err
            end
            if not captures then
                break
            end
            captured_size = captured_size + #captures[0]
            local v, _ = core.json.decode(captures[0])
            if not v or not v.object or v.object.kind ~= resource.kind then
                return false, "UnexpectedBody", captures[0]
            end

            resource.newest_resource_version = v.object.metadata.resource_version
            if v.type ~= "BOOKMARK" then
                resource:event_dispatch(v.type, v.object, "watch")
            end
        end

        if captured_size == #body then
            remainder_body = ""
        elseif captured_size == 0 then
            remainder_body = body
        else
            remainder_body = string.sub(body, captured_size + 1)
        end
    end
    watch_resource(httpc, resource)
end

local function fetch_resource(resource)
    local begin_time = ngx.time()
    while true do
        local ok = false
        local reason, message = "", ""
        local retry_interval = 0
        repeat
            local httpc = http.new()
            resource.watch_state = "connecting"
            core.log.info("begin to connect ", apiserver_host, ":", apiserver_port)
            ok, message = httpc:connect({
                scheme = "https",
                host = apiserver_host,
                port = tonumber(apiserver_port),
                ssl_verify = false
            })
            if not ok then
                resource.watch_state = "connecting"
                core.log.error("connect apiserver failed , apiserver_host: ", apiserver_host, "apiserver_port",
                        apiserver_port, "message : ", message)
                retry_interval = 100
                break
            end

            core.log.info("begin to list ", resource.plural)
            resource.watch_state = "listing"
            resource:pre_list_callback()
            ok, reason, message = list_resource(httpc, resource, nil)
            if not ok then
                resource.watch_state = "list failed"
                core.log.error("list failed , resource: ", resource.plural, " reason: ", reason, "message : ", message)
                retry_interval = 100
                break
            end
            resource.watch_state = "list finished"
            resource:post_list_callback()

            core.log.info("begin to watch ", resource.plural)
            resource.watch_state = "watching"
            ok, reason, message = watch_resource(httpc, resource)
            if not ok then
                resource.watch_state = "watch failed"
                core.log.error("watch failed, resource: ", resource.plural, " reason: ", reason, "message : ", message)
                retry_interval = 0
                break
            end
            resource.watch_state = "watch finished"
            retry_interval = 0
        until true

        -- every 3 hours,we should quit and use another timer
        local now_time = ngx.time()
        if now_time - begin_time >= 10800 then
            break
        end
        if retry_interval ~= 0 then
            ngx.sleep(retry_interval)
        end
    end
    local runner = function()
        fetch_resource(resource)
    end
    ngx.timer.at(0, runner)
end

local function create_endpoint_lrucache(endpoint_key, endpoint_port)
    local endpoint_content, _, _ = endpoints_shared:get_stale(endpoint_key)
    if not endpoint_content then
        core.log.emerg("get empty endpoint content from discovery DICT,this should not happen ", endpoint_key)
        return nil
    end

    local endpoint, _ = core.json.decode(endpoint_content)
    if not endpoint then
        core.log.emerg("decode endpoint content failed, this should not happen, content : ", endpoint_content)
    end

    return endpoint[endpoint_port]
end

local _M = {
    version = 0.01
}

function _M.nodes(service_name)
    local pattern = "^(.*):(.*)$"
    local match, _ = ngx.re.match(service_name, pattern, "jiao")
    if not match then
        core.log.info("get unexpected upstream service_name:　", service_name)
        return nil
    end

    local endpoint_key = match[1]
    local endpoint_port = match[2]
    local endpoint_version, _, _ = endpoints_shared:get_stale(endpoint_key .. "#version")
    if not endpoint_version then
        core.log.info("get empty endpoint version from discovery DICT ", endpoint_key)
        return nil
    end
    return endpoint_lrucache(service_name, endpoint_version, create_endpoint_lrucache, endpoint_key, endpoint_port)
end

local function fill_pending_resources()
    pending_resources = core.table.new(1, 0)

    pending_resources[1] = {

        group = "",
        version = "v1",
        kind = "Endpoints",
        listKind = "EndpointsList",
        plural = "endpoints",

        newest_resource_version = "",

        label_selector = function()
            return ""
        end,

        list_path = function(self)
            return "/api/v1/endpoints"
        end,

        list_query = function(self, continue)
            if continue == nil or continue == "" then
                return "limit=32"
            else
                return "limit=32&continue=" .. continue
            end
        end,

        watch_path = function(self)
            return "/api/v1/endpoints"
        end,

        watch_query = function(self, timeout)
            return string.format("watch=true&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%s",
                    timeout, self.newest_resource_version)
        end,

        pre_list_callback = function(self)
            self.newest_resource_version = "0"
            endpoints_shared:flush_all()
        end,

        post_list_callback = function(self)
            endpoints_shared:flush_expired()
        end,

        added_callback = function(self, object, drive)
            on_endpoint_modified(object)
        end,

        modified_callback = function(self, object)
            on_endpoint_modified(object)
        end,

        deleted_callback = function(self, object)
            on_endpoint_deleted(object)
        end,

        event_dispatch = function(self, event, object, drive)
            if event == "DELETED" or object.deletionTimestamp ~= nil then
                self:deleted_callback(object)
                return
            end

            if event == "ADDED" then
                self:added_callback(object, drive)
            elseif event == "MODIFIED" then
                self:modified_callback(object)
            end
        end,
    }
end

function _M.init_worker()
    if process.type() ~= "privileged agent" then
        return
    end

    apiserver_host = os.getenv("KUBERNETES_SERVICE_HOST")
    --apiserver_host = "127.0.0.1"
    if not apiserver_host or apiserver_host == "" then
        error("get empty KUBERNETES_SERVICE_HOST value")
    end

    apiserver_port = os.getenv("KUBERNETES_SERVICE_PORT")
    --apiserver_port = "6443"
    if not apiserver_port or apiserver_port == "" then
        error("get empty KUBERNETES_SERVICE_PORT value")
    end

    local err
    apiserver_token, err = util.read_file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    if not apiserver_token or apiserver_token == "" then
        error("get empty token value " .. (err or ""))
        return
    end

    fill_pending_resources()
    for _, resource in ipairs(pending_resources) do
        local runner = function()
            fetch_resource(resource)
        end
        ngx.timer.at(0, runner)
    end
end

return _M
