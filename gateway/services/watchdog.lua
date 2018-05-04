local skynet = require "skynet"
local proxypack = require "proxypack"
local socket = require "socket"
local server_def = require "server_def"
local select_server = require "router_selector"
local util = require "util"
local pcall = pcall

local ACCOUNT_MSG_RANGE_MIN = 80000
local ACCOUNT_MSG_RANGE_MAX = 80099

local server_id
local CMD = {}
local SOCKET = {}
local gate
local proxy_conn
local client_sessions = {}
local game_session_fds = {}

local game_session_counter = 0
local function create_game_session()
	if game_session_counter >= (1 << 31) then
		print('game_session_counter has been overflow ',game_session_counter)
		game_session_counter = 0
	end

	local game_session = server_id << 31 | game_session_counter
	game_session_counter = game_session_counter + 1
	return game_session
end

--[[
	watchdog全盘托管所有的网络流量，根据规则打包成内部协议再转发给后端的proxy
]]
function SOCKET.open(fd, addr)
	skynet.error("New client from : " .. addr)
	skynet.call(gate,'lua','accept',fd)

	local game_session = create_game_session()
	print('open new session',game_session)
	client_sessions[fd] = {
		s = game_session,
		p = util.get_now_time(),	--last received time
		ip = addr,
	}
	game_session_fds[game_session] = fd
end

local function close_agent(fd)
	local client = client_sessions[fd]
	if client then
		local game_session = client.s
		assert(game_session_fds[game_session])
		client_sessions[fd] = nil
		game_session_fds[game_session] = nil
		skynet.call(gate, "lua", "kick", fd)
		
		if client.uid and client.observers then
			for dest,target in pairs(client.observers) do
				R().dest(dest):send(target,'close',client.uid,game_session,'closed')
			end
		end

		dbglog('close socket',fd,client.uid,tostring_r(client.observers))
	end
end

function SOCKET.close(fd)
	print("socket close",fd)
	close_agent(fd)
end

function SOCKET.error(fd, msg)
	print("socket error",fd, msg)
	close_agent(fd)
end

function SOCKET.warning(fd, size)
	-- size K bytes havn't send out in fd
	print("socket warning", fd, size)
end

local function check_client_request(c,msgid,server_name)
	if c.uid then
		--已经有uid了则放行
		return true
	end

	--该用户目前仍未有uid，则需要去accountsvr取得uid
	if server_name ~= 'accountsvr' or 
		msgid <  ACCOUNT_MSG_RANGE_MIN or 
		msgid > ACCOUNT_MSG_RANGE_MAX then
		return false
	end

	return true
end

local function handle_data(fd,msg,sz)
	--dbglog('got data from client',fd,msg,sz)

	local dest,msgid = proxypack.peek_client_message(msg,sz)

	local client = assert(client_sessions[fd])
	client.p = util.get_now_time()
	
	local server_name,server_id = server_def.get_server_info(dest)
	if not check_client_request(client,msgid,server_name) then
		errlog(fd,'illegal destination or msgid',dest,msgid)
		--断开链接吧
		close_agent(fd)
		return
	end

	if server_name == 'hallsvr' then
		--hallsvr由不得客户端自己选择id
		local uid = assert(client.uid)
		proxypack.modify_dest_to_uid(uid,msg,sz)
		R().hallsvr({key=uid}):send('.msg_handler','data',client.s,skynet.tostring(msg,sz),client.uid,client.ip)
	elseif server_name == 'tablesvr' then
		local uid = assert(client.uid)
		proxypack.modify_dest_to_uid(uid,msg,sz)
		R().dest(dest):send('.msg_handler','data',client.s,skynet.tostring(msg,sz),client.uid)
	elseif server_name == 'accountsvr' then
		R().accountsvr({rand=true}):send('.msg_handler','data',client.s,skynet.tostring(msg,sz))
	else
		--玩家除了既定的一些服务器之外，没法主动选择其它服务器
		errlog(fd,'illegal destination',dest,server_name,server_id)
		close_agent(fd)
		return
	end
end

function SOCKET.data(fd, msg,sz)
	local ok,ret = pcall(handle_data,fd,msg,sz)
	--此处必须释放内存
	skynet.trash(msg,sz)
	if not ok then 
		errlog(ret,fd,msg,sz)
	end
end

local function sendto(game_session,body)
	--dbglog('now relay from watchdog....',game_session)
	local fd = game_session_fds[game_session]
	if not fd then
		print('invalid game_session',game_session)
		return
	end

	socket.write(fd,body)
end

local function observe_fd(from_src,game_session,uid,target)
	-- body
	local fd = game_session_fds[game_session]
	if not fd then
		errlog('invalid game_session',game_session)
		return
	end
	local client = assert(client_sessions[fd])
	if client.uid ~= uid then
		errlog('not the same uid',game_session,client.uid,uid)
		return
	end
	local observers = client.observers
	if not observers then
		observers = {}
		client.observers = observers
	end
	observers[from_src] = target or '.msg_handler'
end

local function unobserve_fd(from_src,game_session,uid)
	-- body
	local fd = game_session_fds[game_session]
	if not fd then
		errlog('invalid game_session',game_session)
		return
	end
	local client = assert(client_sessions[fd])
	if client.uid ~= uid then
		errlog('not the same uid',game_session,client.uid,uid)
		return
	end
	local observers = client.observers
	if observers then
		observers[from_src] = nil
		if not next(observers) then
			client.observers = nil
		end
	end
end

local HALLSVR = {}
HALLSVR.sendto = sendto
HALLSVR.observe_fd = observe_fd
HALLSVR.unobserve_fd = unobserve_fd

function HALLSVR.active_close(game_session,uid,from_src)
	local fd = game_session_fds[game_session]
	if not fd then
		errlog('could not find gamesession',game_session,uid)
		return
	end

	local client = client_sessions[fd]
	if client and client.uid ~= uid then
		errlog('active_close received but uid is not match',client.uid,uid)
		return
	end

	if client.observers then
		client.observers[from_src] = nil
	end

	close_agent(fd)
end

local TABLESVR = {}
TABLESVR.sendto = sendto
TABLESVR.observe_fd = observe_fd
TABLESVR.unobserve_fd = unobserve_fd

local ACCOUNTSVR = {}
function ACCOUNTSVR.sendto(game_session,body,uid)
	--dbglog('now relay from watchdog....',game_session,#body,uid)
	local fd = game_session_fds[game_session]
	if not fd then
		errlog('invalid game_session',game_session)
		return
	end
	local c = assert(client_sessions[fd])
	if not c.uid and uid and uid ~= 0 then
		c.uid = uid
	end

	socket.write(fd,body)
end

local COMMON = {
	sendto = sendto,
	observe_fd = observe_fd,
	unobserve_fd = unobserve_fd,
}

local MODULES = {
	socket = SOCKET,
	hallsvr = HALLSVR,
	tablesvr = TABLESVR,
	accountsvr = ACCOUNTSVR,
	common = COMMON,
}

local function check_timeout()
	local curr_time = util.get_now_time()
	local to = {}
	for fd,client in pairs(client_sessions) do
		if curr_time - client.p >= 80 then
			--已经超时了,踢之
			to[fd] = true
		end
	end

	local num = 0
	for fd in pairs(to) do
		local ok,ret = pcall(close_agent,fd)
		if not ok then
			errlog(fd,ret)
		end

		num = num + 1
	end

	return num
end

local function routine_check()
	while true do
		local ok,ret = pcall(check_timeout)
		if ok then
			if ret > 0 then
				print('timeout number',ret)
			end
		else
			errlog(ret)
		end
		skynet.sleep(1000) --10 seconds
	end
end

function CMD.start(conf)
	server_id = conf.server_id
	skynet.call(proxy_conn,'lua','start',{
		server_id = server_id,
		server_name = conf.server_name,
		watchdog = skynet.self(),
	})
	skynet.call(gate,"lua","open",conf)
	if not (skynet.getenv "debug") then
		skynet.fork(routine_check)
	end		
end

function CMD.close(fd)
	close_agent(fd)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, subcmd, ...)
		--dbglog('watchdog message',cmd,subcmd,...)
		if MODULES[cmd] then
			MODULES[cmd][subcmd](...)
		else
			local f = assert(CMD[cmd])
			skynet.ret(skynet.pack(f(subcmd, ...)))
		end
	end)
	
	proxy_conn = skynet.newservice('proxy_conn')
	gate = skynet.newservice("cgate")
end)
