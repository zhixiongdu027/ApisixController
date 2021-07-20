local ngx = ngx
local type = type
local pairs = pairs
local ipairs = ipairs
local pcall = pcall
local require = require
local core = require("apisix.core")

local validating_passed_cache = {
    apiVersion = "placeholder",
    kind = "AdmissionReview",
    response = {
        uid = "placeholder",
        allowed = true,
    }
}

local validating_denied_cache = {
    apiVersion = "placeholder",
    kind = "AdmissionReview",
    response = {
        uid = "placeholder",
        allowed = false,
        status = {
            code = 403,
            message = "placeholder"
        }
    }
}

local _M = {
    version = 0.1,
}

local function check_plugins(plugins, subsystem)
    local plugin_path = "apisix.plugins."
    if subsystem == "stream" then
        plugin_path = "apisix.stream.plugins."
    end

    local ok, err, p
    for k, v in pairs(plugins) do
        ok, p = pcall(require, plugin_path .. k)
        if not ok then
            core.log.error("require false , ", p or " ")
            return false, "not found plugin " .. k
        end

        if type(p) ~= "table" then
            core.log.error("require false , ", p)
            return false, "bad plugin " .. k
        end

        if type(p.check_schema) ~= "function" then
            return false, "not found check_schema function in plugin " .. k
        end

        ok, err = p.check_schema(v)

        if not ok then
            return false, err
        end
    end
    return true, nil
end

local function validating_rule(rule)
    local ok, err
    local empty_table = {}
    local upstream_ids = core.table.new(0, 5)
    local service_ids = core.table.new(0, 3)

    for _, upstream in ipairs(rule.data.upstreams or empty_table) do
        upstream_ids[upstream.id] = true
    end

    for _, service in ipairs(rule.data.services or empty_table) do
        service_ids[service.id] = true

        if service.plugins then
            ok, err = check_plugins(service.plugins, "http")
            if not ok then
                return ok, err
            end
        end

        if service.upstream_id then
            if not upstream_ids[service.upstream_id] then
                return false, "upstreams_id : " .. service.upstreams_id .. "not exist"
            end
        end
    end

    for _, route in ipairs(rule.data.routes or empty_table) do
        if route.plugins then
            ok, err = check_plugins(route.plugins, "http")
            if not ok then
                return ok, err
            end
        end

        if route.upstream_id then
            if not upstream_ids[route.upstream_id] then
                core.log.error("upstream ids ", core.json.encode(upstream_ids, true))
                return false, "upstream_id : " .. route.upstream_id .. "not exist"
            end
        end

        if route.service_id then
            if not service_ids[route.service_id] then
                return false, "service_id : " .. route.service_id .. "not exist"
            end
        end
    end

    for _, stream_route in ipairs(rule.data.stream_routes or empty_table) do

        if stream_route.plugins then
            ok, err = check_plugins(stream_route.plugins, "stream")
            if not ok then
                return ok, err
            end
        end

        if stream_route.upstream_id then
            if not upstream_ids[stream_route.upstream_id] then
                core.log.error("upstream ids ", core.json.encode(upstream_ids, true))
                return false, "upstream_id : " .. stream_route.upstream_id .. "not exist"
            end
        end

    end

    return true, nil
end

local function validating_create_config(config)
    return false, "create configs.apisix.apache.org operation is defined"
end

local function validating_delete_config(config)
    return false, "delete configs.apisix.apache.org operation is defined"
end

local function validating_update_config(config)
end

local function validating_unknown_object(object)
    return false, "unknown kind " .. object.kind
end

local _ft = {
    ["CREATERule"] = validating_rule,
    ["UPDATERule"] = validating_rule,
    ["CREATEConfig"] = validating_create_config,
    ["UPDATEConfig"] = validating_update_config,
    ["DELETEConfig"] = validating_delete_config,
}

function _M.validating()
    local request_body = core.request.get_body()
    local admission_review = core.json.decode(request_body)
    if not admission_review or not admission_review.request or not admission_review.request.object then
        ngx.exit(ngx.HTTP_BAD_REQUEST)
        return
    end

    local request = admission_review.request
    local object = request.object

    local key = request.operation .. object.kind
    local validating_fun = _ft[key] or validating_unknown_object
    local ok, err = validating_fun(object)
    local response_table
    if ok then
        response_table = validating_passed_cache
    else
        response_table = validating_denied_cache
        response_table.response.status.message = err or ""
    end

    response_table.apiVersion = admission_review.apiVersion
    response_table.response.uid = request.uid
    local response = core.json.encode(response_table, true)
    ngx.say(response)
    ngx.exit(200)
end

return _M