local ipairs = ipairs
local ngx = ngx
local string = string
local tonumber = tonumber
local math = math
local os = os
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local http = require("resty.http")
local signal = require("resty.signal")
local ngx_timer_at = ngx.timer.at
local shared_endpoints = ngx.shared.discovery

local apiserver_host = ""
local apiserver_port = ""
local namespace = ""
local token = ""

local default_weight = 50

local lrucache = core.lrucache.new({
    ttl = 300,
    count = 1024
})

local cache_table = {}

local function end_world(reason)
    core.log.emerg(reason)
    signal.kill(process.get_master_pid(), signal.signum("QUIT"))
end

local function sort_by_key_host(a, b)
    return a.host < b.host
end

local function on_endpoint_added(endpoint)
    local subsets = endpoint.subsets
    if subsets == nil or #subsets == 0 then
        return
    end

    local subset = subsets[1]

    local addresses = subset.addresses
    if addresses == nil or #addresses == 0 then
        return
    end

    local ports = subset.ports
    if ports == nil or #ports == 0 then
        return
    end

    core.table.clear(cache_table)
    for _, port in ipairs(ports) do
        local nodes = core.table.new(#addresses, 0)
        for i, address in ipairs(addresses) do
            nodes[i] = {
                host = address.ip,
                port = port.port,
                weight = default_weight
            }
        end
        core.table.sort(nodes, sort_by_key_host)
        cache_table[port.name] = nodes
    end

    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    local _, err
    _, err = shared_endpoints:safe_set(endpoint_key .. "#version", endpoint.metadata.resourceVersion)
    if err then
        core.log.emerg("set endpoint version into discovery DICT failed ,", err)
    end

    shared_endpoints:safe_set(endpoint_key, core.json.encode(cache_table, true))
    if err then
        core.log.emerg("set endpoint into discovery DICT failed ,", err)
    end
end

local function on_endpoint_deleted(endpoint)
    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    shared_endpoints:delete(endpoint_key .. "#version")
    shared_endpoints:delete(endpoint_key)
end

local function on_endpoint_modified(endpoint)
    local subsets = endpoint.subsets
    if subsets == nil or #subsets == 0 then
        return on_endpoint_deleted(endpoint)
    end

    local subset = subsets[1]

    local addresses = subset.addresses
    if addresses == nil or #addresses == 0 then
        return on_endpoint_deleted(endpoint)
    end

    local ports = subset.ports
    if ports == nil or #ports == 0 then
        return on_endpoint_deleted(endpoint)
    end

    core.table.clear(cache_table)
    for _, port in ipairs(ports) do
        local nodes = core.table.new(#addresses, 0)
        for i, address in ipairs(addresses) do
            nodes[i] = {
                host = address.ip,
                port = port.port,
                weight = default_weight
            }
        end
        core.table.sort(nodes, sort_by_key_host)
        cache_table[port.name] = nodes
    end

    local endpoint_key = endpoint.metadata.namespace .. "/" .. endpoint.metadata.name
    local _, err
    _, err = shared_endpoints:safe_set(endpoint_key .. "#version", endpoint.metadata.resourceVersion)
    if err then
        core.log.emerg("set endpoints version into discovery DICT failed ,", err)
    end

    shared_endpoints:safe_set(endpoint_key, core.json.encode(cache_table, true))
    if err then
        core.log.emerg("set endpoints into discovery DICT failed ,", err)
    end
end

local function event_dispatch(resource, event, object, drive)
    if event == "BOOKMARK" then
        -- do nothing because we had record max_resource_version to resource.max_resource_version
        return
    end

    if drive == "watch" then
        local resource_version = object.metadata.resourceVersion
        local rvv = tonumber(resource_version)
        if rvv <= resource.max_resource_version then
            return
        end
        resource.max_resource_version = rvv
    end

    if event == "ADDED" then
        resource:added_callback(object, drive)
    elseif event == "MODIFIED" and object.deletionTimestamp == nil then
        resource:modified_callback(object)
    else
        resource:deleted_callback(object)
    end
end

local function list_resource(httpc, resource, continue)
    httpc:set_timeouts(2000, 2000, 3000)
    local res, err = httpc:request({
        path = resource:list_path(),
        query = resource:list_query(),
        headers = {
            ["Authorization"] = string.format("Bearer %s", token)
        }
    })

    if not res then
        return false, "RequestError", err or ""
    end

    if res.status ~= 200 then
        return false, res.reason, res.read_body() or ""
    end

    local body, err = res:read_body()
    if err then
        return false, "ReadBodyError", err
    end

    local data, _ = core.json.decode(body)
    if not data or data.kind ~= resource.listKind then
        return false, "UnexpectedBody", body
    end

    local resource_version = data.metadata.resourceVersion
    resource.max_resource_version = tonumber(resource_version)

    for _, item in ipairs(data.items) do
        event_dispatch(resource, "ADDED", item, "list")
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
            ["Authorization"] = string.format("Bearer %s", token)
        }
    })

    if err then
        return false, "RequestError", err
    end

    if res.status ~= 200 then
        return false, res.reason, res.read_body and res.read_body()
    end

    local remaindBody = ""
    local body = ""
    local reader = res.body_reader
    local gmatchIterator;
    local captures;
    local capturedSize = 0
    while true do

        body, err = reader()
        if err then
            return false, "ReadBodyError", err
        end

        if not body then
            break
        end

        if #remaindBody ~= 0 then
            body = remaindBody .. body
        end

        gmatchIterator, err = ngx.re.gmatch(body, "{\"type\":.*}\n", "jiao")
        if not gmatchIterator then
            return false, "GmatchError", err
        end

        while true do
            captures, err = gmatchIterator()
            if err then
                return false, "GmatchError", err
            end
            if not captures then
                break
            end
            capturedSize = capturedSize + #captures[0]
            local v, _ = core.json.decode(captures[0])
            if not v or not v.object or v.object.kind ~= resource.kind then
                return false, "UnexpectedBody", captures[0]
            end
            event_dispatch(resource, v.type, v.object, "watch")
        end

        if capturedSize == #body then
            remaindBody = ""
        elseif capturedSize == 0 then
            remaindBody = body
        else
            remaindBody = string.sub(body, capturedSize + 1)
        end
    end
    watch_resource(httpc, resource)
end

local function fetch()
    local resource = {
        version = "v1",
        kind = "Endpoints",
        listKind = "EndpointsList",
        plural = "endpoints",
        max_resource_version = 0,

        list_path = function(self)
            return string.format("/api/v1/endpoints", namespace)
        end,

        list_query = function(self, continue)
            if continue == nil or continue == "" then
                return "limit=45"
            else
                return "limit=45&continue=" .. continue
            end
        end,

        watch_path = function(self)
            return string.format("/api/v1/namespaces/%s/endpoints", namespace)
        end,

        watch_query = function(self, timeout)
            return string.format("watch=1&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%d", timeout,
                    self.max_resource_version)
        end,

        pre_list_callback = function(self)
            self.max_resource_version = 0
            shared_endpoints:flush_all()
        end,

        post_list_callback = function(self)
            shared_endpoints:flush_expired()
        end,

        added_callback = function(self, object, drive)
            on_endpoint_added(object)
        end,

        modified_callback = function(self, object)
            on_endpoint_modified(object)
        end,

        deleted_callback = function(self, object)
            on_endpoint_deleted(object)
        end
    }

    while true do
        local ok = false
        local reason, message = "", ""
        local intervalTime = 0
        repeat
            local httpc = http.new()
            resource.watch_state = "connecting"
            core.log.info("begin to connect ", resource.plural)
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
                intervalTime = 200
                break
            end

            core.log.info("begin to list ", resource.plural)
            resource.watch_state = "listing"
            resource:pre_list_callback()
            ok, reason, message = list_resource(httpc, resource)
            if not ok then
                resource.watch_state = "listing failed"
                core.log.error("list failed , resource: ", resource.plural, " reason: ", reason, "message : ", message)
                intervalTime = 200
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
                intervalTime = 100
                break
            end
            resource.watch_state = "watch finished"
            intervalTime = 0
        until true
        ngx.sleep(intervalTime)
    end
end

local function create_lrucache(endpoint_key, endpoint_port)
    local endpoint, _, _ = shared_endpoints:get_stale(endpoint_key)
    if not endpoint then
        core.log.error("get emppty endpoint from discovery DICT,this should not happen ", endpoint_key)
        return nil
    end

    local t, _ = core.json.decode(endpoint)
    if not t then
        core.log.error("decode endpoint failed, this should not happen, content : ", endpoint)
    end
    return t[endpoint_port]
end

local _M = {
    version = 0.01
}

function _M.nodes(service_name)
    local pattern = "^(.*):(.*)$"
    local match, _ = ngx.re.match(service_name, pattern, "jiao")
    if not match then
        core.log.info("get ｕnexpected upstream service_name:　", service_name)
        return nil
    end
    local endpoint_key = match[1]
    local endpoins_port = match[2]
    local version, _, _ = shared_endpoints:get_stale(endpoint_key .. "#version")
    if not version then
        core.log.info("get emppty endpoint version from discovery DICT ", endpoint_key)
        return nil
    end
    return lrucache(service_name, version, create_lrucache, endpoint_key, endpoins_port)
end

function _M.init_worker()
    if process.type() ~= "privileged agent" then
        return
    end

    local err
    namespace, err = util.read_file("/var/run/secrets/kubernetes.io/serviceaccount/namespace")
    if not namespace or namespace == "" then
        end_world("get empty namespace value " .. (err or ""))
        return
    end

    token, err = util.read_file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    if not token or token == "" then
        end_world("get empty token value " .. (err or ""))
        return
    end

    apiserver_host = os.getenv("KUBERNETES_SERVICE_HOST")
    if not apiserver_host or apiserver_host == "" then
        end_world("get empty KUBERNETES_SERVICE_HOST value")
    end

    apiserver_port = os.getenv("KUBERNETES_SERVICE_PORT")
    if not apiserver_port or apiserver_port == "" then
        end_world("get empty KUBERNETES_SERVICE_PORT value")
    end

    ngx_timer_at(0, fetch)
end

return _M
