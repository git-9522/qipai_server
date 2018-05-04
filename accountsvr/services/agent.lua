local skynet = require "skynet"
local proxypack = require "proxypack"
local msgdef = require "msgdef"
local utils = require "utils"
local pb = require 'protobuf'
local httpc = require "http.httpc"
local cjson = require "cjson"
local error_code = require "error_code"

httpc.timeout = 10 * 100 --ten seconds.

local ACCOUNT_WEBSERVER_URL = skynet.getenv("ACCOUNT_WEBSERVER_URL") or "127.0.0.1:6668"
local DEBUG = skynet.getenv('DEBUG')
local client_fd

local account = {}

if DEBUG then
function account.REQ_VERIFY(msg)
    local uid = tonumber(msg.uid)
    local rsp = {
        result = 0,
        uid = uid,
        key_token = msg.key_token
    }
    utils.send_to_gateway(0,uid,client_fd,'account.RSP_VERIFY',rsp,uid)
end
else
function account.REQ_VERIFY(msg)
    local body = cjson.encode({uid = msg.uid,key_token = msg.key_token})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/check_token",nil,nil,body)
    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY',
            {result = error_code.VERIFY_ERROR_RETRY})
    end
    
    local result = cjson.decode(body)
    if result.code ~= 0 then
        local ret = error_code.VERIFY_ERROR_RETRY
        if result.code == -100 then
            ret = error_code.EXPIRED_LOGIN
        end
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY',
            {result = ret,channel = result.channel})
    end

    if not result.uid or not result.key_token then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY',
            {result = error_code.VERIFY_ERROR_RETRY,channel = result.channel})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY',{
        uid = uid,key_token = result.key_token, channel = result.channel},uid)
end
end

function account.REQ_REGISTER_TOURIST(msg)
    local seed_token = msg.seed_token
    local body = cjson.encode({seed_token = seed_token})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/register_tourist",nil,nil,body)
    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_TOURIST',{result = 10002})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_TOURIST',{result = 10002})
    end

    if not result.uid or not result.key_token then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_TOURIST',{result = 10002})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_TOURIST',{
        uid = uid,key_token = result.key_token},uid)
end

function account.REQ_REGISTER_PHONE(msg)
    local phone_number = msg.phone_number
    local tourist_key_token = msg.tourist_key_token
    if #tourist_key_token == 0 then
        tourist_key_token = nil
    end

    local body = cjson.encode({
            phone_number = phone_number,
            tourist_key_token = tourist_key_token
        })
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/register_phone_number",nil,nil,body)
    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_PHONE',{result = 10005})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        local ret = 10005
        if result.code == -11 then
            ret = 10003
        elseif result.code == -15 then
            ret = 10004
        end
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_PHONE',{result = ret})
    end

    --验证码已发送
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_REGISTER_PHONE',{})
end

function account.REQ_VERIFY_REGISTER_CODE(msg)
    local phone_number = msg.phone_number
    local code = msg.code

    local body = cjson.encode({
            phone_number = phone_number,
            code = code
        })
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/verify_register_rand_code",nil,nil,body)

    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_REGISTER_CODE',{result = 10010})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_REGISTER_CODE',{result = 10008})
    end

    if not result.uid or not result.key_token then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_REGISTER_CODE',{result = -3})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_REGISTER_CODE',
        {uid = uid,key_token = result.key_token,
        tourist_key_token = result.tourist_key_token},uid)
end

function account.REQ_GET_LOGIN_CODE(msg)
    local phone_number = msg.phone_number
    
    local body = cjson.encode({phone_number = phone_number})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/get_login_rand_code",nil,nil,body)
    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_GET_LOGIN_CODE',{result = 10010})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        local ret = 10006
        if result.code == -31 then
            ret = 10009
        elseif result.code == -32 then
            ret = 10004
        end
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_GET_LOGIN_CODE',{result = ret})
    end

    --验证码已发送
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_GET_LOGIN_CODE',{result = 0})
end

function account.REQ_VERIFY_LOGIN_CODE(msg)
    local phone_number = msg.phone_number
    local code = msg.code

    local body = cjson.encode({phone_number = phone_number,code = code})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/verify_login_rand_code",nil,nil,body)

    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_LOGIN_CODE',{result = 10010})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_LOGIN_CODE',{result = 10008})
    end

    if not result.uid or not result.key_token then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_LOGIN_CODE',{result = -3})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_LOGIN_CODE',
        {uid = uid,key_token = result.key_token},uid)
end

function account.REQ_VERIFY_3RD_LOGIN(msg)
    local code = msg.code
    local channel = msg.channel
    local uid = msg.uid

    local body = cjson.encode({code = code,channel = channel,uid = uid})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/verify_3rd_login",nil,nil,body)

    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_3RD_LOGIN',{result = 10010})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_3RD_LOGIN',{result = 10008})
    end

    if not result.uid or not result.key_token then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_3RD_LOGIN',{result = 10010})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_VERIFY_3RD_LOGIN',
        {uid = uid,key_token = result.key_token,channel = channel},uid)
end

local ACCOUNT_PAY_WEBSERVER_URL = skynet.getenv("ACCOUNT_PAY_WEBSERVER_URL") or "127.0.0.1:6669"

function account.REQ_MAKE_ORDER(msg)
    local product_id = msg.product_id
    local channel_id = msg.channel_id
    local uid = msg.uid

    local body = cjson.encode({product_id = product_id,channel_id = channel_id,uid = uid})
    local status, body = httpc.request('POST',ACCOUNT_PAY_WEBSERVER_URL, 
        "/starry/order/make_order",nil,nil,body)

    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_MAKE_ORDER',{result = -1})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_MAKE_ORDER',{result = -2})
    end

    local order_id = result.order_id
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_MAKE_ORDER',{order_id = order_id})
end


function account.REQ_CHECK_PAYMENT(msg)
    local receipt = msg.receipt
    local order_id = msg.order_id

    local body = cjson.encode({receipt = receipt,order_id = order_id})
    local status, body = httpc.request('POST',ACCOUNT_PAY_WEBSERVER_URL, 
        "/starry/order/check_payment",nil,nil,body)

    if status ~= 200 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_CHECK_PAYMENT',{result = -1})
    end

    local result = cjson.decode(body)
    if result.code ~= 0 then
        return utils.send_to_gateway(0,-1,client_fd,'account.RSP_CHECK_PAYMENT',{result = -2})
    end

    local uid = result.uid
    return utils.send_to_gateway(0,-1,client_fd,'account.RSP_CHECK_PAYMENT',{})
end

local handler = {
    account = account
}

local function get_msg_module_name(msgid)
    print("msgid",msgid)
    local m = msgdef.id_to_name[msgid]
    if not m then return end
    return m[1],m[2] --[1]->module,[2]->name
end

local function handler_message(...)
    local seq,msgid,msg,sz = ...
    local module,name = get_msg_module_name(msgid)
    if not module or not name then
        print('invalid msgid',msgid,module,name)
        return
    end

    local pbname = module .. '.' .. name
    local req_msg = pb.decode(pbname,msg,sz)
    if not req_msg then
        errlog("pb decode error",pbname)
        return
    end

    print(string.format('[%s]>>>>>got a request[%s] content(%s)',
        skynet.address(skynet.self()),module .. '.' ..name,tostring_r(req_msg)))

    local module_table = handler[module]
    if not module_table or not module_table[name] then
        skynet.error(string.format('unknown requrest(%s.%s)',module,name))
        return
    end

    return module_table[name](req_msg)
end

local function dispatch(_, _,  ...)
    --就处理一次，处理完毕完则退出，非常简单暴力的一个服务
    local ret,msg = pcall(handler_message,...)
    if not ret then
        errlog(msg,...)
    end
    skynet.exit()
end

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	unpack = function (msg, sz)
        return proxypack.unpack_client_message(msg,sz)
	end,
	dispatch = dispatch
}


local CMD = {}

function CMD.start(fd)
    client_fd = fd
    skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua", function(_,_, action, ...)
		local f = CMD[action]
        f(...)
	end)
end)
