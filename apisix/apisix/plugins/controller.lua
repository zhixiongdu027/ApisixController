local ipairs = ipairs
local pairs = pairs
local ngx = ngx
local open = io.open
local string = string
local tonumber = tonumber
local math = math
local os = os
local ngx_timer_at = ngx.timer.at
local process = require("ngx.process")
local core = require("apisix.core")
local util = require("apisix.cli.util")
local http = require("resty.http")
local signal = require("resty.signal")
local profile = require("apisix.core.profile")
local apisix_yaml_path = profile:yaml_path("apisix")
local lyaml = require "lyaml"

local token = ""
local apiserver_host = ""
local apiserver_port = ""
local controller_name = ""

local dump_cache = {}

local function end_world(reason)
    core.log.emerg(reason)
    signal.kill(process.get_master_pid(), signal.signum("QUIT"))
end

local function dump_yaml(resource)
    -- todo delay 0.5 second to write
    core.table.clear(dump_cache)
    resource:dump_callback(dump_cache)
    local yaml = lyaml.dump({ dump_cache })
    local file, err = open(apisix_yaml_path, "w+")
    if not file then
        core.log.emerg("open file: ", apisix_yaml_path .. " failed , error info:" .. err)
    end
    file:write(string.sub(yaml, 1, -5))
    file:write("#END")
    file:close()
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

    if (object.content.routes) then
        for _, v in ipairs(object.content.routes) do
            if not v.labels then
                v.labels = { namespace = object.metadata.namespace }
            else
                v.labels.namespace = object.metadata.namespace
            end
        end
    end

    if (object.content.upstreams) then
        for _, v in ipairs(object.content.upstreams) do
            if v.service_name and v.discovery_type == "k8s" then
                v.service_name = object.metadata.namespace .. "/" .. v.service_name
            end
        end
    end

    if event == "ADDED" then
        resource:added_callback(object, drive)
    elseif event == "MODIFIED" and object.deletionTimestamp == nil then
        resource:modified_callback(object)
    else
        resource:deleted_callback(object)
    end

    if drive == "watch" then
        dump_yaml(resource)
    end
end

local function list_resource(httpc, resource, continue)
    httpc:set_timeouts(2000, 2000, 3000)
    local res, err = httpc:request({
        path = resource:list_path(),
        query = resource:list_query(continue),
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
        group = "apisix.apache.org",
        version = "v1alpha1",
        kind = "Rule",
        listKind = "RuleList",
        plural = "rules",
        storage = {},
        list_storage = {},
        max_resource_version = 0,
        watch_state = "uninitialized",

        label_selector = function()
            if controller_name == "default" then
                return "&labelSelector=apisix.apache.org%2Fcontroller-by+in+%28%2C" .. controller_name .. "%29"
            end
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
            return string.format("watch=1&allowWatchBookmarks=true&timeoutSeconds=%d&resourceVersion=%d", timeout, self.max_resource_version) .. self.label_selector()
        end,

        pre_list_callback = function(self)
            core.table.clear(self.list_storage)
        end,

        post_list_callback = function(self)
            self.storage, self.list_storage = self.list_storage, {}
            dump_yaml(self)
        end,

        added_callback = function(self, object, drive)
            if drive == "list" then
                self.list_storage[object.metadata.name] = object.content
                return
            end
            self.storage[object.metadata.name] = object.content
        end,

        modified_callback = function(self, object)
            self.storage[object.metadata.name] = object.content
        end,

        deleted_callback = function(self, object)
            self.storage[object.metadata.name] = nil
        end,

        dump_callback = function(self, t)
            for _, v1 in pairs(self.storage) do
                for k2, v2 in pairs(v1) do
                    for _, v3 in pairs(v2) do
                        if t[k2] == nil then
                            t[k2] = { v3 }
                        else
                            core.table.insert(t[k2], v3)
                        end
                    end
                end
            end
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
                resource.watch_state = "list failed"
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

function _M.init()
    if process.type() ~= "privileged agent" then
        return
    end

    local local_conf = core.config.local_conf()

    local controller_conf = core.table.try_read_attr(local_conf, "plugin_attr",
            "controller")
    if controller_conf then
        controller_name = controller_conf.name
    end

    if not controller_name or controller_name == "" then
        end_world("get empty controller_name value")
    end

    apiserver_host = os.getenv("KUBERNETES_SERVICE_HOST")
    if not apiserver_host or apiserver_host == "" then
        end_world("get empty KUBERNETES_SERVICE_HOST value")
    end

    apiserver_port = os.getenv("KUBERNETES_SERVICE_PORT")
    if not apiserver_port or apiserver_port == "" then
        end_world("get empty KUBERNETES_SERVICE_PORT value")
    end

    local err
    token, err = util.read_file("/var/run/secrets/kubernetes.io/serviceaccount/token")
    if not token or token == "" then
        end_world("get empty token value " .. (err or ""))
        return
    end

    ngx_timer_at(0, fetch)
end

return _M