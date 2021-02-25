---[[
-- 微信服务端接口SDK
--
-- 包括：
--   微信Auth2.0鉴权函数
--   企业转账函数
--
-- 2020-12-08
---]]



local _env = ""

local CONST = {
    ["APPNAME"]     = "", -- 应用名称
    ["APPID"]       = "", -- 微信后台AppID
    ["APPSECRET"]   = "", -- 微信后台密钥
    ["MCHID"]       = "", -- 微信后台商户ID
    ["SERVERADDR"]  = "", -- 服务端IP(企业转账设置IP白名单)
}

local http     = require(_env .. "resty.http")
local cjson    = require(_env .. "cjson")
local xml2lua  = require(_env .. "xml2lua")
local handler  = require(_env .. "xmlhandler.tree")
local uuid     = require(_env .. "resty.jit-uuid")

local sformat     = string.format
local supper      = string.upper
local schar       = string.char
local tsort       = table.sort
local tconcat     = table.concat
local math_random = math.random
local jencode     = cjson.encode
local jdecode     = cjson.decode
local ngx_log     = ngx.log
local ngx_BUG     = ngx.DEBUG
local ngx_WARN    = ngx.WARN
local ngx_ERR     = ngx.ERR
local ngx_md5     = ngx.md5
local ngx_time    = ngx.time
local ngx_null    = ngx.null
local ngx_re_gsub = ngx.re.gsub

uuid.seed()
math.randomseed(os.time()*1000)

local xml_handler = xml2lua.parser(handler)


local _M = {
    ["_VERSION"] = '1.0',
}

local mt = { __index = _M }


-- 返回指定长度的随机字符串
local random_str = function(len)
    local t = {}
    for i = 0, len do
        if math_random(1, 3) == 1 then
            -- 大写字符
            t[#t+1] = schar(math_random(0, 25) + 65)
        elseif math_random(1, 3) == 2 then    
            -- 小写字符
            t[#t+1] = schar(math_random(0, 25) + 97)
        else
            -- 10 个数字
            t[#t+1] = math_random(0, 9)
        end
    end
    return tconcat(t)
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
            "=== WX-SDK-ERROR ===",
            "Unknown Exception",
            err)
        return nil
    end

    if res["status"] ~= 200 then
        ngx_log(ngx_ERR,
            "=== WX-SDK-ERROR ===",
            " HTTP_STATUS: ", res["status"],
            "; ", res["body"], err,
            "; PARAM: ", data)
        return nil
    end

    ngx_log(ngx_BUG, "=== WX-SDK-DEBUG ===", res.body)

    xml_handler:parse(res.body)

    return handler.root.xml
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

    local r_data = {
        ["method"]     = data and data["method"] or "GET",
        ["body"]       = data["body"] or nil,
        ["headers"]    = data["headers"],
        ["ssl_verify"] = ssl_verify,
    }

    ngx_log(ngx_BUG, "=== WX-SDK-DEBUG ===",
        "URL: ", url, "; PARAMS: ", jencode(r_data))

    local res, err = httpc:request_uri(url, r_data)

    _httpc_keepalive(httpc, err)

    -- 响应处理
    return _response_handler(res, err, r_data)
end


-- New 函数
_M.new = function(self)
    -- 实例属性表
    local _table = {}

    return setmetatable(_table, mt)
end


---签名算法
-- @Param args 接收到或发送的所有数据集合
_M.gen_sign = function(self, args)
    -- 对所有参数名按 Ascii 码顺序排序
    local keys = {}
    for k, _ in pairs(args) do
        if k ~= "sign" then
            keys[#keys+1] = k
        end
    end

    tsort(keys)

    -- 使用URL键值格式拼接成字符串，最后拼接密钥键值对
    local str_t = {}
    for _, k in pairs(keys) do
        str_t[#str_t+1] = sformat("%s=%s", k, args[k])
    end

    str_t[#str_t+1] = sformat("key=%s", CONST["APPSECRET"])
    local str_encode = tconcat(str_t, "&")

    ngx.log(ngx.DEBUG, "=== str_encode: ", str_encode)

    -- MD5
    return ngx_md5(str_encode)
end


---企业转账至微信函数
-- @Param open_id 用户授权的微信ID
-- @Param money   单位：元
_M.transfer = function(self, open_id, money)

    ---[[
	--  部署微信服务端证书
	--  server {
    --      listen 8888;
    --
    --      location / {
    --          proxy_ssl_certificate ../ssl/apiclient_cert.pem;
    --          proxy_ssl_certificate_key ../ssl/apiclient_key.pem;
    --
    --          proxy_pass https://api.mch.weixin.qq.com$request_uri;
    --          proxy_set_header Host api.mch.weixin.qq.com;
    --      }
    --  }
	---]]

    local url = "http://127.0.0.1:8888/mmpaymkttransfers/promotion/transfers"  -- 提现URL
    local data = { 
        ["mch_appid"]        = CONST["APPID"],    -- 公众账号ID
        ["mchid"]            = CONST["MCHID"],    -- 商户号
        ["nonce_str"]        = random_str(16),   -- 16位随机字符串
        ["partner_trade_no"] = ngx_re_gsub(uuid(), "-", "", "jo"),   -- 商户订单号
        ["openid"]           = open_id,                -- 用户ID
        ["check_name"]       = "NO_CHECK",             -- 不校验用户姓名
        ["amount"]           = money * 100,            -- 提现金额；元-->分
        ["desc"]             = CONST["APPNAME"] .. " 用户提现",  -- 企业付款备注
        ["spbill_create_ip"] = CONST["SERVERADDR"],    -- 服务端IP
    }   
    data["sign"] = supper(self:gen_sign(data))

    -- 转成 xml 格式
    local data_xml = xml2lua.toXml(data, "xml")

    ngx_log(ngx_BUG, "=== data: ", data_xml)

    local _body, err = _http_request(url, {
        ["method"]  = "POST",
        ["headers"] = {
            ["Content-Type"] = "application/xml"
        },
        ["body"] = data_xml
    })

    -- 转账结果处理
    if _body and _body.return_code == "SUCCESS"
        and _body.result_code == "SUCCESS" then

        return _body
    elseif _body and _body.return_code == "SUCCESS"
        and _body.result_code == "FAIL" then

        if _body.err_code == "V2_ACCOUNT_SIMPLE_BAN" then
            return nil, "open_id error"
        end

        return nil, _body
    else
        ngx_log(ngx_ERR,
            "=== WX-SDK-ERROR ===", " WXTRANSFER ERR ",
            _body and _body.return_msg or _body.err_code or _body.err_code_des)
 
        return nil, _body
    end
end


return _M
