local skynet = require "skynet.manager"
local httpc = require "http.httpc"
local cjson = require "cjson"

httpc.timeout = 10 * 100 --ten seconds.

local ACCOUNT_WEBSERVER_URL = skynet.getenv("ACCOUNT_WEBSERVER_USERINFO_URL") or "127.0.0.1:6668"

local handlers = {}

local function get_user_info(uid)
    local body = cjson.encode({uid = uid})
    local status, body = httpc.request('POST',ACCOUNT_WEBSERVER_URL, 
        "/starry/user/get_user_info",nil,nil,body)
    if status ~= 200 then
        errlog(uid,'failed to get_user_info',status)
        return {}
    end
    
    if not body then
        errlog(uid,'invalid response',body)
        return {}
    end

    return cjson.decode(body)
end

function handlers.get_user_info(uid)
    local ok,ret = xpcall(get_user_info,debug.traceback,uid)
    if not ok then
        errlog(uid,ret)
        return {}
    end
    return ret
end

skynet.start(function()
	skynet.dispatch("lua",function(_,_,action, ...)
		local f = assert(handlers[action])
        skynet.retpack(f(...))
	end)
end)


