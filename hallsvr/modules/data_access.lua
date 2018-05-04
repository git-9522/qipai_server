local skynet = require "skynet"
local cjson = require "cjson"
local select_server = require("router_selector")

local M = {}

function M.pull_user_data(uid)
    local default_data = {uid = uid}

	local ok,ret = R().dbsvr({key=uid}):call('.msg_handler','fetch_or_insert',uid,cjson.encode(default_data))
    if not ok then
        errlog(uid,'failed to fetch user data')
        return false
    end

    if not ret then
        errlog(uid,'invalid querying')
        return false
    end

    dbglog('ffffffffffffffff',tostring_r(ret))

    return ret
end

function M.pull_user_info(uid)
	local ok,ret = R().accountsvr({rand=true}):call('.info_mgr','get_user_info',uid)
    if not ok then
        errlog('failed to query payment info',uid)
        return
    end

    dbglog('ffffffffffffffff',tostring_r(ret))
    return ret
end


function M.pull_base_data(uid)
    local ok,ret = R().basesvr({key=uid}):call('.msg_handler','get_base_data',uid)
    if not ok then
        errlog(uid,'failed to fetch base data')
        return
    end

    return ret
end


function M.pull_offline_data(uid)
    local ok,ret = R().exdbsvr(1):call('.msg_handler','pull_offline_data',uid)
    if not ok then
        errlog('failed to query offline info',uid)
        return
    end

    return ret
end

function M.take_compensation(uid)
    local ok,got,ret = R().basesvr({key=uid}):call('.msg_handler','take_compensation',uid)
    if not ok then
        errlog(uid,'failed to take_compensation',server_id)
        return false
    end

    if not got then
        dbglog(uid,'there is no compensation for you')
        return false
    end

    local ntf = {
        compensation_times = ret.compensation_times,
        compensation_coins = ret.compensation_coins,
    }

    return true,ntf,ret.curr_coins
end

return M