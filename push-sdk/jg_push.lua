---[[
-- 极光推送服务端SDK
--
-- Doc: 基于极光 REST API-V3 开发
--   推送接口文档参照：http://docs.jiguang.cn/jpush/server/push/rest_api_v3_push/
--   设备信息几口文档参照：http://docs.jiguang.cn/jpush/server/push/rest_api_v3_device/
-- 
-- 2020-12-02
---]]

local _env = ""  -- Lib 库路径

local CONST = {
    ["AppKey"]         = "",    -- 极光后台 AppKey
    ["MasterSecret"]   = "",    -- 极光后台 Master Secret
    ["PRE_PUSH_URL"]   = "https://api.jpush.cn/v3",     -- 推送地址前缀
    ["PUSH_CID_URI"]   = "/push/cid",                   -- 推送 CID URI
    ["PUSH_URI"]       = "/push",                       -- 推送 URI
    ["PRE_DEVICE_URL"] = "https://device.jpush.cn/v3",  -- 设备地址前缀
    ["DEVICE_URI"]     = "/devices",                    -- 设备信息 URI
    ["ALIAS_URI"]      = "/aliases",                    -- 设备别名 URI
    ["TAGS_URI"]       = "/tags",                       -- 设备标签 URI
    ["Platform"]       = {
        "android", "ios", "quickapp","winphone"
    },                                                  -- 极光后台支持的推送平台列表
    ["Audience"]       = {
         ["tag"]             = true,  -- 设备标签
         ["tag_and"]         = true,
         ["tag_not"]         = true,
         ["alias"]           = true,  -- 设备别名
         ["registration_id"] = true,  -- 设备注册ID
         ["segment"]         = true,  -- 极光后台的用    ??分群ID
         ["abtest"]          = true,  -- 极光后台创建    ?? A/B 测试ID
    },                                                  -- 极光后台支持的推送目标关键字
    ["Timeout"]        = 2000,                          -- HTTP 请求超时时间
}

local http  = require(_env .. "resty.http")
local cjson = require(_env .. "cjson")

local sformat = string.format
local tconcat = table.concat
local jencode = cjson.encode
local jdecode = cjson.decode

local ngx_log  = ngx.log
local ngx_BUG  = ngx.DEBUG
local ngx_WARN = ngx.WARN
local ngx_ERR  = ngx.ERR
local ngx_encode_base64 = ngx.encode_base64


local _M = {
    ["_VERSION"] = '1.0',
}

local mt = { __index = _M }


-- 数组元素有效性过滤器
-- @sample_arr 标准值数组
-- @test_arr   待过滤数组
local _array_filter = function(sample_arr, test_arr)
    local sample_set = {}
    for _, v in pairs(sample_arr or {}) do
        sample_set[tostring(v)] = true
    end

    local ret = {}
    for _, v in pairs(test_arr or {}) do
        ret[#ret+1] = sample_set[tostring(v)] and v or nil
    end

    return #ret > 0 and ret or nil
end


-- 空table检查
local _valid_table = function(t)
    return t
        and type(t) == "table"
        and next(t)
        and true
        or  false
end


-- 生成 HTTP 基本认证头
local _gen_auth_header = function()
    return sformat("Basic %s",
        ngx_encode_base64(sformat("%s:%s",
            CONST["AppKey"],
            CONST["MasterSecret"]),
        no_padding))
end


-- 保持长连接
local _httpc_keepalive = function(httpc, err)
    if err then
        httpc:close()
    end
    local _, err1 = httpc:get_reused_times()
    if err1 then
        httpc:close()
    end

    -- 1min * 100
    httpc:set_keepalive(60 * 1000, 100)
end


-- 响应统一处理函数
local _response_handler = function(res, err, data)
    if not res or not res["status"] then
        ngx_log(ngx_ERR,
            "=== JG-SDK-ERROR ===",
            "Unknown Exception",
            err)
        return nil
    end

    if res["status"] ~= 200 then
        ngx_log(ngx_ERR,
            "=== JG-SDK-ERROR ===",
            " HTTP_STATUS: ", res["status"],
            "; ", res["body"], err,
            "; PARAM: ", jencode(data or {}))
        return nil
    end

    if not res["body"] or res["body"] == "" then return nil end

    ngx_log(ngx_BUG, "=== JG-SDK-DEBUG ===", "RESPONSE: ", res["body"])

    local ok, resp_body = pcall(jdecode, res["body"])
    if not ok then
        ngx_log(ngx_ERR,
            "=== JG-SDK-ERROR ===",
            " JSON_DECODE: ", resp_body,
            "; ENSTR: ", res["body"])
        return nil
    end

    return resp_body
end


-- 异步 HTTP 请求函数
local _http_request = function(url, data)
    local httpc = http.new()

    -- 设置超时
    httpc:set_timeout(CONST["Timeout"] or 2000)

    -- 没有配置根证书的情况
    local ssl_verify = nil
    if url:sub(1,5) == 'https' then
        ssl_verify = false
    end

    -- 请求头
    local headers = {
        ["Authorization"] = _gen_auth_header(),
        ["Accept"]        = "application/json",
        ["Content-Type"]  = "application/json",
    }

    local r_data = {
        ["method"]     = data and data["method"] or "GET",
        ["body"]       = data and jencode(data["body"]) or nil,
        ["headers"]    = headers,
        ["ssl_verify"] = ssl_verify,
    }

    ngx_log(ngx_BUG, "=== JG-SDK-DEBUG ===",
        "URL: ", url, "; PARAMS: ", jencode(r_data))

    local res, err = httpc:request_uri(url, r_data)

    _httpc_keepalive(httpc, err)

    -- 响应处理
    return _response_handler(res, err, r_data)
end


-- Platform 参数确认
local _valid_platform = function(platform)
    return type(platform) == "table" and #platform > 0
        and _array_filter(CONST["Platform"], platform)
        or  "all"
end


-- Audience 参数确认
local _valid_audience = function(audience)

    -- 过滤可用参数
    local _valid_filter = function()
        if type(audience) == "string" then return end

        local audience_set = CONST["Audience"]
        for k, v in ipairs(audience) do
            if not (audience_set[k]
                and type(v) == "table"
                and #v > 0) then

                v = nil
            end
        end
    end

    _valid_filter()

    return type(audience) == "table" and next(audience)
        and audience
        or  "all"
end


-- 从极光 cid 池获取推送 cid
local _get_push_id = function(cnt)
    local _url = sformat("%s%s?count=%s&type=push",
        CONST["PRE_PUSH_URL"],
        CONST["PUSH_CID_URI"],
        tonumber(cnt) or 1)

    local resp = _http_request(_url)

    return resp and resp["cidlist"]
        and resp["cidlist"][1]
        or nil
end


-- New 函数
_M.new = function(self)
    -- 实例属性表
    local _table = {}

    return setmetatable(_table, mt)
end


-- Push 函数
-- @return {
--     sendno 调用方记录 ID，0 标识无 ID
--     msg_id 此次推送消息ID，当需要覆盖、删除上一条推送时使用
-- }
_M.push = function(self, args)
    -- "通知" or "透传消息" 二者必选其一
    if not args or not (_valid_table(args["notification"])
        or _valid_table(args["message"])) then

        return nil, "invalid param: notification or message"
    end

    -- 推送数据体，JSON 格式
    local data = {
        ["cid"]      = args["cid"] or _get_push_id(),      -- 一次推送的标识ID（极光 cid 池分配）
        ["platform"] = _valid_platform(args["platform"]),  -- 推送平台
        ["audience"] = _valid_audience(args["audience"]),  -- 推送目标
        ["notification"]     = args["notification"],       -- 通知内容体
        ["message"]          = args["message"],            -- 透传消息
        ["inapp_message"]    = args["inapp_message"],      -- VIP功能，应用内提醒功能
        ["notification_3rd"] = args["notification_3rd"],   -- 自定义消息赚厂商通知内容体
        ["sms_message"]      = args["sms_message"],        -- 额外付费功能，短信渠道补充送达内容体
        ["options"]  = args["options"],                    -- 推送参数
        ["callback"] = args["callback"],                   -- VIP功能，回调参数
    }

    local _url = sformat("%s%s",
        CONST["PRE_PUSH_URL"],
        CONST["PUSH_URI"])

    return _http_request(_url, {
        ["method"] = "POST",
        ["body"]   = data,
    }), data["cid"]
end


-- Push 撤销函数
_M.push_cancle = function(self, msgid)
    if not msgid or not tonumber(msgid) then
        return nil, "invalid param: msgid"
    end

    local _url = sformat("%s%s/%s",
        CONST["PRE_PUSH_URL"],
        CONST["PUSH_URI"],
        msgid)

    return _http_request(_url, {
        ["method"] = "DELETE",
    })
end


-- 设备信息查询函数
-- @return {
--     tags   设备标签，数组结构
--     alias  设备别名
--     mobile 手机号
-- }
_M.device_get = function(self, registration_id)
    if not registration_id then
        return nil, "invalid param: registration_id"
    end

    local _url = sformat("%s%s/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["DEVICE_URI"],
        registration_id)

    return _http_request(_url)
end


-- 设备信息设置函数
-- @param data {
--     tags   设备标签设置
--         add     新增标签，数组结构
--         remove  删除指定标签，数组结构
--     alias  设备别名
--     mobile 手机号
-- }
_M.device_set = function(self, registration_id, data)
    if not registration_id then
        return nil, "invalid param: registration_id"
    end
    if not _valid_table(data) then
        return nil, "invalid param: data"
    end

    local _url = sformat("%s%s/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["DEVICE_URI"],
        registration_id)

    return _http_request(_url, {
        ["method"] = "POST",
        ["body"]   = data,
    })
end


-- 查询别名设备列表
-- @alias    别名
-- @platform 平台，数组结构
-- @return null or {
--     registration_ids 设备ID，数组结构
-- }
_M.alias_get = function(self, d_alias, platform)
    if not d_alias or d_alias == "" then
        return nil, "invalid param: alise"
    end

    platform = _valid_platform(platform) ~= "all"
        and tconcat(platform, ",") or nil

    local _url = sformat("%s%s/%s%s",
        CONST["PRE_DEVICE_URL"],
        CONST["ALIAS_URI"],
        d_alias,
        platform and sformat("?platform=%s",
            platform or "")
    )

    return _http_request(_url)
end


-- 删除设备别名
_M.alias_del = function(self, d_alise)
    if not d_alias or d_alias == "" then
        return nil, "invalid param: alise"
    end

    platform = _valid_platform(platform) ~= "all"
        and tconcat(platform, ",") or nil

    local _url = sformat("%s%s/%s%s",
        CONST["PRE_DEVICE_URL"],
        CONST["ALIAS_URI"],
        d_alias,
        platform and sformat("?platform=%s",
            platform or "")
    )

    return _http_request(_url, {
        ["method"] = "DELETE"
    })
end


-- 解绑设备与别名的绑定关系
-- @param registration_ids 设备ID列表，数组结构
_M.alias_unbind = function(self, d_alias, registration_ids)
    if not d_alias or d_alias == "" then
        return nil, "invalid param: alise"
    end

    if not _valid_table(registration_ids) then
        return nil, "invalid param: registration_ids"
    end
    
    local _url = sformat("%s%s/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["ALIAS_URI"],
        d_alias)

    return _http_request(_url, {
        ["method"] = "POST",
        ["body"]   = {
            ["registration_ids"] = {
                ["remove"] = registration_ids
            }
        }
    })
end


-- 查询标签列表
_M.tags_list = function(self)
    local _url = sformat("%s%s/",
        CONST["PRE_DEVICE_URL"],
        CONST["TAGS_URI"])

    return _http_request(_url)
end


-- 判断标签与设备的绑定关系
-- @return {
--     result 绑定关系，布尔值
-- }
_M.tags_bind_status = function(self, tag, registration_id)
    if (not tag or tag == "")
        or (not registration_id or registration_id == "") then
        return nil, "invalid param: tag or registration_id"
    end

    local _url = sformat("%s%s/%s/registration_ids/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["TAGS_URI"],
        tag, registration_id)

    return _http_request(_url)
end


-- 更新设备标签
-- @param registration_ids {
--     add     新增设备，数组结构
--     remove  删除设备，数组结构
-- }
_M.tags_set = function(self, tag, registration_ids)
    if (not tag or tag == "")
        or (not _valid_table(registration_ids)) then
        return nil, "invalid param: tag or registration_ids"
    end

    local _url = sformat("%s%s/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["TAGS_URI"], tag)

    return _http_request(_url, {
        ["method"] = "POST",
        ["body"]   = {
            ["registration_ids"] = registration_ids
        } 
    })
end


-- 删除标签
_M.tag_del = function(self, tag)
    if not tag or tag == "" then
        return nil, "invalid param: tag"
    end

    local _url = sformat("%s%s/%s",
        CONST["PRE_DEVICE_URL"],
        CONST["TAGS_URI"], tag)

    return _http_request(_url, {
        ["method"] = "DELETE"
    })
end


return _M
