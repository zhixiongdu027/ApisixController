local ngx = ngx
local ipairs = ipairs
local pairs = pairs
local open = io.open
local string = string
local tonumber = tonumber
local math = math
local os = os
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local http = require("resty.http")
local profile = require("apisix.core.profile")
local apisix_yaml_path = profile:yaml_path("apisix")
local lyaml = require "lyaml"

local apiserver_token = ""
local apiserver_host = ""
local apiserver_port = ""
local controller_name = ""

local dump_cache = {}
local dump_version = 0
local fetch_version = 0

local pending_resources

local empty_table = {}

local function dump()
    if dump_version == fetch_version then
        return
    end
    core.table.clear(dump_cache)

    for _, v in ipairs(pending_resources) do
        v:dump_callback(dump_cache)
    end

    local yaml = lyaml.dump({ dump_cache })
    local file = open(apisix_yaml_path, "w+")
    if not file then
        core.log.emerg("open file: ", apisix_yaml_path .. " failed")
    end
    file:write(string.sub(yaml, 1, -5))
    file:write("#END")
    file:close()
    dump_version = fetch_version
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

local plugin_name = "controller"

local schema = {
    type = "object",
    properties = {},
    additionalProperties = false
}

local _M = {
    version = 0.1,
    priority = 99,
    name = plugin_name,
    schema = schema
}

function _M.check_schema(conf)
    return true
end

local function fill_pending_resources()
    pending_resources = core.table.new(3, 0)

    pending_resources[1] = {
        group = "apisix.apache.org",
        version = "v1alpha1",
        kind = "Rule",
        listKind = "RuleList",
        plural = "rules",
        storage = {},
        list_storage = {},
        newest_resource_version = "",
        watch_state = "uninitialized",

        label_selector = function()
            return "&labelSelector=apisix.apache.org%2Fcontroller-by%3D" .. controller_name
        end,

        list_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/rules"
        end,

        list_query = function(self, continue)
            if continue == nil or continue == "" then
                return "limit=30" .. self.label_selector()
            else
                return "limit=30&continue=" .. continue .. self.label_selector()
            end
        end,

        watch_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/rules"
        end,

        watch_query = function(self, timeout)
            return string.format("watch=1&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%s",
                    timeout, self.newest_resource_version) .. self.label_selector()
        end,

        pre_list_callback = function(self)
            self.newest_resource_version = "0"
            core.table.clear(self.list_storage)
        end,

        post_list_callback = function(self)
            self.storage, self.list_storage = self.list_storage, {}
            fetch_version = fetch_version + 1
        end,

        added_callback = function(self, object, drive)
            if drive == "list" then
                self.list_storage[object.metadata.namespace .. "/" .. object.metadata.name] = object.data
                return
            end
            self.storage[object.metadata.namespace .. "/" .. object.metadata.name] = object.data
        end,

        modified_callback = function(self, object)
            self.storage[object.metadata.namespace .. "/" .. object.metadata.name] = object.data
        end,

        deleted_callback = function(self, object)
            self.storage[object.metadata.namespace .. "/" .. object.metadata.name] = nil
        end,

        event_dispatch = function(self, event, object, drive)
            if event == "DELETED" or object.deletionTimestamp ~= nil then
                self:deleted_callback(object)
                fetch_version = fetch_version + 1
                return
            end

            local id_suffix = object.metadata.namespace .. object.metadata.name
            id_suffix = "_" .. ngx.crc32_short(id_suffix)

            for _, upstream in ipairs(object.data.upstreams or empty_table) do
                upstream.id = upstream.id .. id_suffix
                if upstream.service_name and upstream.discovery_type == "k8s" then
                    upstream.service_name = object.metadata.namespace .. "/" .. upstream.service_name
                end
            end

            for _, service in ipairs(object.data.services or empty_table) do
                service.id = service.id .. id_suffix
                if service.upstream_id then
                    service.upstream_id = service.upstream_id .. id_suffix
                end
            end

            for _, route in ipairs(object.data.routes or empty_table) do
                route.id = route.id .. id_suffix
                if route.upstream_id then
                    route.upstream_id = route.upstream_id .. id_suffix
                end
                if not route.labels then
                    route.labels = { namespace = object.metadata.namespace }
                else
                    route.labels.namespace = object.metadata.namespace
                end
            end

            for _, stream_route in ipairs(object.data.stream_routes or empty_table) do
                stream_route.id = stream_route.id .. id_suffix
                if stream_route.upstream_id then
                    stream_route.upstream_id = object.upstream_id .. id_suffix
                end
                if not stream_route.labels then
                    stream_route.labels = { namespace = object.metadata.namespace }
                else
                    stream_route.labels.namespace = object.metadata.namespace
                end
            end

            if event == "ADDED" then
                self:added_callback(object, drive)
            elseif event == "MODIFIED" then
                self:modified_callback(object)
            end

            if drive == "watch" then
                fetch_version = fetch_version + 1
            end
        end,

        dump_callback = function(self, t)
            for _, v1 in pairs(self.storage) do
                for k2, v2 in pairs(v1) do
                    if not t[k2] then
                        t[k2] = core.table.new(#v2 + 10, 0)
                    end
                    for _, v3 in ipairs(v2) do
                        core.table.insert(t[k2], v3)
                    end
                end
            end
        end
    }

    pending_resources[2] = {
        group = "apisix.apache.org",
        version = "v1alpha1",
        kind = "Config",
        listKind = "ConfigList",
        plural = "configs",
        storage = {},
        list_storage = {},
        newest_resource_version = "0",
        watch_state = "uninitialized",

        label_selector = function()
            return "&labelSelector=apisix.apache.org%2Fcontroller-by%3D" .. controller_name
        end,

        list_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/configs"
        end,

        list_query = function(self, continue)
            if continue == nil or continue == "" then
                return "limit=30" .. self.label_selector()
            else
                return "limit=30&continue=" .. continue .. self.label_selector()
            end
        end,

        watch_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/configs"
        end,

        watch_query = function(self, timeout)
            return string.format("watch=1&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%s",
                    timeout, self.newest_resource_version) .. self.label_selector()
        end,

        pre_list_callback = function(self)
            self.newest_resource_version = "0"
            core.table.clear(self.list_storage)
        end,

        post_list_callback = function(self)
            self.storage, self.list_storage = self.list_storage, {}
            fetch_version = fetch_version + 1
        end,

        added_callback = function(self, object, drive)
            if drive == "list" then
                self.list_storage[object.metadata.name] = object.data
                return
            end
            self.storage[object.metadata.name] = object.data
        end,

        modified_callback = function(self, object)
            self.storage[object.metadata.name] = object.data
        end,

        deleted_callback = function(self, object)
            self.storage[object.metadata.name] = nil
        end,

        event_dispatch = function(self, event, object, drive)

            if event == "DELETED" or object.deletionTimestamp ~= nil then
                self:deleted_callback(object)
                fetch_version = fetch_version + 1
                return
            end

            if event == "ADDED" then
                self:added_callback(object, drive)
            elseif event == "MODIFIED" then
                self:modified_callback(object)
            end

            if drive == "watch" then
                fetch_version = fetch_version + 1
            end
        end,

        dump_callback = function(self, t)
            for _, v1 in pairs(self.storage) do
                for k2, v2 in pairs(v1) do
                    if not t[k2] then
                        t[k2] = core.table.new(#v2 + 10, 0)
                    end
                    for _, v3 in ipairs(v2) do
                        core.table.insert(t[k2], v3)
                    end
                end
            end
        end
    }

    pending_resources[3] = {
        group = "apisix.apache.org",
        version = "v1alpha1",
        kind = "Cert",
        listKind = "CertList",
        plural = "certs",
        storage = {},
        list_storage = {},
        newest_resource_version = "0",
        watch_state = "uninitialized",

        label_selector = function()
            return ""
        end,

        list_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/certs"
        end,

        list_query = function(self, continue)
            if continue == nil or continue == "" then
                return "limit=30" .. self.label_selector()
            else
                return "limit=30&continue=" .. continue .. self.label_selector()
            end
        end,

        watch_path = function(self)
            return "/apis/apisix.apache.org/v1alpha1/certs"
        end,

        watch_query = function(self, timeout)
            return string.format("watch=1&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%s",
                    timeout, self.newest_resource_version) .. self.label_selector()
        end,

        pre_list_callback = function(self)
            self.newest_resource_version = "0"
            core.table.clear(self.list_storage)
        end,

        post_list_callback = function(self)
            self.storage, self.list_storage = self.list_storage, {}
            fetch_version = fetch_version + 1
        end,

        added_callback = function(self, object, drive)
            if drive == "list" then
                self.list_storage[object.metadata.name] = object.data
                return
            end
            self.storage[object.metadata.name] = object.data
        end,

        modified_callback = function(self, object)
            self.storage[object.metadata.name] = object.data
        end,

        deleted_callback = function(self, object)
            self.storage[object.metadata.name] = nil
        end,

        event_dispatch = function(self, event, object, drive)

            if event == "DELETED" or object.deletionTimestamp ~= nil then
                self:deleted_callback(object)
                fetch_version = fetch_version + 1
                return
            end

            if event == "ADDED" then
                self:added_callback(object, drive)
            elseif event == "MODIFIED" then
                self:modified_callback(object)
            end

            if drive == "watch" then
                fetch_version = fetch_version + 1
            end
        end,

        dump_callback = function(self, t)
            for _, v1 in pairs(self.storage) do
                for _, v2 in pairs(v1) do
                    if t.ssl == nil then
                        t.ssl = { v2 }
                    else
                        core.table.insert(t.ssl, v2)
                    end
                end
            end
        end
    }

end

function _M.init()
    if process.type() ~= "privileged agent" then
        return
    end

    local local_conf = core.config.local_conf()

    local controller_conf = core.table.try_read_attr(local_conf, "plugin_attr", "controller")
    if controller_conf then
        controller_name = controller_conf.name
    end

    if not controller_name or controller_name == "" then
        core.log.error("get empty controller.name value")
    end

    apiserver_host = os.getenv("KUBERNETES_SERVICE_HOST")

    if not apiserver_host or apiserver_host == "" then
        error("get empty KUBERNETES_SERVICE_HOST value")
    end

    apiserver_port = os.getenv("KUBERNETES_SERVICE_PORT")
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

    ngx.timer.every(1.1, dump)
end

return _M