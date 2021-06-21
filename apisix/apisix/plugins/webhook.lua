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

local function check_schema(plugins)
    local ok, err, p
    for k, v in pairs(plugins) do
        ok, p = pcall(require, "apisix.plugins." .. k)
        if not ok then
            return false, "not found plugin " .. k
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

function _M.validating()
    local request_body = core.request.get_body()
    local admission_review = core.json.decode(request_body)
    if not admission_review or not admission_review.request or not admission_review.request.object then
        ngx.exit(ngx.HTTP_BAD_REQUEST)
        return
    end

    local request = admission_review.request

    local object = request.object
    if object.kind ~= "Rule" then
        ngx.exit(ngx.HTTP_BAD_REQUEST)
        return
    end

    local response_table = validating_passed_cache
    if object.content.routes then
        local ok, err
        for _, route in ipairs(object.content.routes) do
            if route.plugins then
                ok, err = check_schema(route.plugins)
                if not ok then
                    core.log.error(" check schema error ", err)
                    response_table = validating_denied_cache
                    response_table.response.status.message = err or ""
                    break
                end
            end
        end
    end

    response_table.apiVersion = admission_review.apiVersion
    response_table.response.uid = request.uid

    local response = core.json.encode(response_table, true)

    core.log.error(" validating ", response)
    ngx.say(response)
    ngx.exit(200)
    return
end

return _M