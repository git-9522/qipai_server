local skynet = require "skynet"
local proxypack = require "proxypack"
local driver = require "socketdriver"
local server_def = require "server_def"
local util = require "util"

local table_insert = table.insert
local math_random = math.random
local xpcall = xpcall

local watchdog

local connections = {}
local server_id_to_fd_map = {}

--------------------------------流量统计----------------------------------
local last_stat_time = skynet.now()
local last_stat_traffic = 0
local total_traffic = 0
local function stat_traffic(sz)
	local now = skynet.now()
	if now - last_stat_time >= 1000 then
		billlog({op="proxytraffic",
			total=total_traffic,
			period_traffic=last_stat_traffic,
			period_traffic_KB = last_stat_traffic / 1024,
			period_traffic_MB = last_stat_traffic / 1048576,
			})
		last_stat_traffic = 0
		last_stat_time = now
	end

	last_stat_traffic = last_stat_traffic + sz
	total_traffic = total_traffic + sz
end
--------------------------------流量统计----------------------------------

local function disconnect(fd)
	print('disconnect',fd)
	local conn = connections[fd]
	if not conn then
		errlog('no such fd in connections',fd)
		return
	end

	local from = conn.from
	local server_id = conn.server_id

	assert(server_id_to_fd_map[from][server_id])
	server_id_to_fd_map[from][server_id] = nil
	connections[fd] = nil
end

local function sendto(fd,...)
    driver.send(fd,proxypack.pack_proxy_message(skynet.pack(...)))
end

local handler = {}
-------------------------------------------------
function handler.REGISTER(fd,from,server_id)
	print('registering from ',fd,from,server_id,type(server_id))

	assert(not connections[fd])
	local new_conn = {
		from = from,
		server_id = server_id,
		server_type = assert(server_def.server_name_map[from]),
		last_ping_time = util.get_now_time()
	}

	local server_type = server_id_to_fd_map[from]
	if not server_type then
		server_type = {}
		server_id_to_fd_map[from] = server_type
	end

	if server_type[server_id] then
		errlog('server id had been registered',server_id)
		return
	end

	connections[fd] = new_conn
	server_type[server_id] = fd

	sendto(fd,'REGISTERED',true)
end

-------------------------------------------------
local function relay_to(conn,dest,...)
	local server_name,server_id = server_def.get_server_info(dest)
	if not server_name or not server_id then
		errlog('unknown server type',dest)
		return
	end

	local server_list = server_id_to_fd_map[server_name]
	if not server_list then
		errlog('could not find server',server_name)
		return
	end

	local destfd = server_list[server_id]
	if not destfd then
		errlog('could not find server id',server_id)
		return
	end
	
	local from_src = server_def.make_dest(conn.server_type,conn.server_id)
	sendto(destfd,'RELAY',from_src,...)
end

local function multi_relay_to(conn,dest_list,...)
	local from_src = server_def.make_dest(conn.server_type,conn.server_id)

	local get_server_info = server_def.get_server_info
	--这里不去重了，由其它服务自己保证dest_list不会重复
	for _,dest in pairs(dest_list) do
		local server_name,server_id = get_server_info(dest)
		if not server_name or not server_id then
			errlog('unknown server type',dest)
			goto continue
		end

		local server_list = server_id_to_fd_map[server_name]
		if not server_list then
			errlog('could not find server',server_name)
			goto continue
		end

		local destfd = server_list[server_id]
		if not destfd then
			errlog('could not find server id',server_id)
			goto continue
		end
		
		sendto(destfd,'RELAY',from_src,...)

		::continue::
	end
end

local function broadcast(conn,dest,...)
	local from_src = server_def.make_dest(conn.server_type,conn.server_id)

	local server_name = server_def.get_server_info(dest)
	if not server_name then
		errlog('unknown dest',dest)
		return
	end

	local server_list = server_id_to_fd_map[server_name]
	if not server_list then
		errlog('could not find server',server_name)
		return
	end

	for server_id,destfd in pairs(server_list) do
		sendto(destfd,'RELAY',from_src,...)
	end
end

local function random_relay_to(conn,dest,...)
	local from_src = server_def.make_dest(conn.server_type,conn.server_id)

	local server_name = server_def.get_server_info(dest)
	if not server_name then
		errlog('unknown dest',dest,...)
		return
	end
	
	local server_list = server_id_to_fd_map[server_name]
	if not server_list then
		errlog('could not find server',server_name)
		return
	end

	local ordered_server_list = {}
	for server_id,destfd in pairs(server_list) do
		table_insert(ordered_server_list,destfd)
	end

	if #ordered_server_list < 1 then
		errlog('not available server',server_name)
		return
	end

	local destfd = ordered_server_list[math_random(1,#ordered_server_list)]
	sendto(destfd,'RELAY',from_src,...)
end

function handler.RELAY(fd,dest,...)
	--dbglog('relay from ',fd,'to',tostring_r(dest),...)

	local conn = connections[fd]
	if not conn then
		errlog(fd,'this is connection was closed before...')
		return
	end

	conn.last_ping_time = util.get_now_time()

	if type(dest) == 'table' then
		return multi_relay_to(conn,dest,...)
	elseif server_def.is_broadcast_dest(dest) then
		return broadcast(conn,dest,...)
	elseif server_def.is_random_dest(dest) then
		return random_relay_to(conn,dest,...)
	else
		return relay_to(conn,dest,...)
	end
end
-------------------------------------------------

-------------------------------------------------
function handler.PING(fd)
	local conn = connections[fd]
	if not conn then
		errlog(fd,'this is connection was closed before...')
		return
	end
	conn.last_ping_time = util.get_now_time()
	sendto(fd,'PONG')
end


local function routine_check()
	while true do
		skynet.sleep(10 * 100)
		local curr_time = util.get_now_time()
		local timeout_seconds = tonumber(skynet.getenv("ping_time_out")) or 120
		for fd,conn in pairs(connections) do
			if curr_time - conn.last_ping_time >= timeout_seconds then
				print('close the lost fd',fd)
				skynet.send(watchdog,'lua','socket','close',fd)
			end
		end
	end
end

local function start(watchdog_)
	watchdog = watchdog_
	skynet.fork(routine_check)
	skynet.retpack(true)
end

local function handle_message(fd,cmd,...)
	--dbglog(fd,'received paramters:',...)
	handler[cmd](fd,...)
end


skynet.start(function()
	skynet.dispatch("lua", function(session, source, action, ...)
		if action == 'disconnect' then
			return disconnect(...)
		elseif action == 'start' then
			return start(...)
		end
		local  fd, msg, sz = ...
		local ok,err = xpcall(handle_message,debug.traceback,
			fd,skynet.unpack(msg,sz))
		--这里的msg会由事件派发器自行释放
		skynet.trash(msg,sz)
		if not ok then
			errlog(err)
		end

		stat_traffic(sz)
	end)
end)