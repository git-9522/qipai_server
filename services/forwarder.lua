local skynet = require "skynet.manager"
local server_def = require "server_def"

local FORWARDER_SLEEP_TIME = 5

local proxy_conn
local msg_handler

local pending_calls = {}
local handler = {}

local curr_sequence_id = 0
local max_sequence_id = 1 << 32 - 1

local function new_seq()
	local seq = curr_sequence_id
	curr_sequence_id =  curr_sequence_id + 1
	if curr_sequence_id >= max_sequence_id then
		curr_sequence_id = 0
	end
	return seq
end

local function call_to_remote_server(dest,...)
	local seq = new_seq()
	assert(not pending_calls[seq])
    
    local response = skynet.response()
	pending_calls[seq] = {
        response = response,
        co = coroutine.running()
    }

	skynet.send(proxy_conn,'lua','relay',dest,'TO',seq,...)

	--这里还需要处理超时的情况:5秒
    if skynet.sleep(FORWARDER_SLEEP_TIME * 100) ~= 'BREAK' then
        local call = pending_calls[seq]
        if call then
            pending_calls[seq] = nil
            call.response(true,false,'timeout for waiting for response seq:' .. seq)
            return
        end
    end
end

local function response_to_service(seq,...)
    local call = pending_calls[seq]
	if not call then
		skynet.error('could not find call for seq ' .. seq)
		print('invalid seq',seq)
		return
	end

    pending_calls[seq] = nil
    local response = call.response
    skynet.wakeup(call.co)

    response(true,true,...)
end

local function TO(from_src,seq,toservice,...)
    --对端发过来给自己的
    if seq then
        skynet.send(proxy_conn,'lua','relay',from_src,'BACK',seq,skynet.call(toservice,'lua',...))
    else
        skynet.send(toservice,'lua',...)
    end
end

local function BACK(from_src,...)
    response_to_service(...)
end

local function CALL(from_src,dest,...)
    call_to_remote_server(dest,...)
end

local function SEND(from_src,dest,...)
    skynet.send(proxy_conn,'lua','relay',dest,'TO',false,...)
end

local handler = {
    TO = TO,
    BACK = BACK,
    CALL = CALL,
    SEND = SEND,
}

--内部服务用的是CALL跟SEND,而外部服务用的是TO跟BACK，由于都用了同一套接口，因此需要注意区别
local function dispatch(session,source,from_src,cmd,...)
    local f = handler[cmd]
    if not f then
        errlog('unknown cmd',cmd,from_src,...)
        return
    end

    f(from_src,...)
end

local CMD = {}
function CMD.start(conf)
	proxy_conn = assert(conf.proxy_conn)
    skynet.dispatch("lua",dispatch)
	skynet.retpack(true)
end

skynet.start(function()
	skynet.dispatch("lua",function(session,source,cmd, ...)
        CMD[cmd](...)
    end)

	skynet.register(".forwarder")
end)


