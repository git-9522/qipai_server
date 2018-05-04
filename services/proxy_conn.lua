local skynet = require "skynet.manager"
local proxypack = require "proxypack"
local driver = require "socketdriver"

local os_time = os.time
local table_insert = table.insert
local table_remove = table.remove
local xpcall = xpcall

local server_name = skynet.getenv "server_name"
local server_id = tonumber(skynet.getenv "server_id")

local queue		-- message queue
local CMD = setmetatable({}, { __gc = function() proxypack.clear(queue) end })

local forwarder_service = (...) or 'forwarder'
local forwarder
local watchers = {}

local proxy_connections = {}

--控制proxy连接的状态
local PROXY_STATUS_CONNECTING = 1       --连接中
local PROXY_STATUS_CONNECTED = 2        --已经连接上
local PROXY_STATUS_REGISTERING = 3      --注册中
local PROXY_STATUS_REGISTERED = 4       --已经注册
local PROXY_STATUS_OUTOFSERVICE = 5     --该proxy不再提供服务

local function send_message(fd,...)
    driver.send(fd,proxypack.pack_proxy_message(skynet.pack(...)))
end

local function load_all_proxy_address(address_conf)
    local proxy_addrs = {}
    for host,port in address_conf:gmatch('([^%s:]+):(%d+);*%s*') do
        local key = string.format('%s:%d',host,port)
        proxy_addrs[key] = {host = host,port = port,key = key}
    end
    return proxy_addrs
end

local function connect_to(proxy_addr)
    local fd = assert(driver.connect(proxy_addr.host,proxy_addr.port))
    proxy_connections[fd] = {
        fd = fd,
        key = proxy_addr.key,
        host = proxy_addr.host,
        port = proxy_addr.port,
        status = PROXY_STATUS_CONNECTING,
        last_ping = 0,
		workload = 0,
    }

    print('connect to:',proxy_addr.key,fd)
end

local function check_and_connect()
    local proxy_addrs = load_all_proxy_address(skynet.getenv("all_proxy_address"))
    local connected_proxys = {}
    for fd,proxy_conn in pairs(proxy_connections) do
        connected_proxys[proxy_conn.key] = true
    end

    for key,proxy_addr in pairs(proxy_addrs) do
        if not connected_proxys[key] then
            connect_to(proxy_addr)
        end
    end
end

local function check_connections()
    for fd,proxy_conn in pairs(proxy_connections) do
        if proxy_conn.status == PROXY_STATUS_CONNECTED then
			--已经注册上
            send_message(fd,'REGISTER',server_name,server_id)
            proxy_conn.status = PROXY_STATUS_REGISTERING
		elseif proxy_conn.status == PROXY_STATUS_REGISTERED then
			local elapsed = os_time() - proxy_conn.last_ping
			if elapsed >= 120 then
				--已经2分钟没有交互了，则认为该proxy已经挂掉
				print('the proxy is unreachable...',proxy_conn.key,fd)
				driver.shutdown(fd)
			elseif elapsed >= 20 then
				--每20秒心跳一次
				send_message(fd,'PING')
			end
        end
    end
end

local function routine_check()
    while true do
        local ok,err = pcall(check_and_connect)
        if not ok then 
            skynet.error(err)
        end

        local ok,err = pcall(check_connections)
        if not ok then
            skynet.error(err)
        end

        skynet.sleep(200) --20 seconds
    end
end

--select by robin
local next_candidate = 0
local function select_one_proxy_conn()
	local candidate = {}
    for fd,proxy_conn in pairs(proxy_connections) do
        if proxy_conn.status == PROXY_STATUS_REGISTERED then
			candidate[#candidate + 1] = proxy_conn
        end
    end

	if #candidate == 0 then return end
	next_candidate = next_candidate % #candidate + 1
	return candidate[next_candidate]
end

local proxy_handler = {}

local function response_to_waiting()
    local response = table_remove(watchers)
    while response do
        response(true)
        response = table_remove(watchers)
    end
end

function proxy_handler.REGISTERED(fd,ok)
    print('registered',fd,ok)
    assert(ok)
    local conn = proxy_connections[fd]
    if not conn then
        skynet.error('proxy connection is closed',fd)
        return
    end

    conn.status = PROXY_STATUS_REGISTERED
    conn.last_ping = os_time()

    response_to_waiting()
end

function proxy_handler.PONG(fd)
    local conn = proxy_connections[fd]
    if not conn then
        skynet.error('proxy connection is closed',fd)
        return
    end

    conn.last_ping = os_time()
end

--[[
function proxy_handler.RELAY(fd,from_src,...)
    local from = server_def.get_server_info(from_src)
    --print('got a relay',fd,from,from_src)
    local f = delegate[from]
    if not f then 
        errlog(from_src,'could not handler message from ',from)
        return
    end
    f(from_src,...)
end
--]]
function proxy_handler.RELAY(fd,from_src,...)
    skynet.send(forwarder,'lua',from_src,...)
end

local function handle_message(fd,cmd,...)
    proxy_handler[cmd](fd,...)
end

local function dispatch_msg(fd, msg, sz)
    local ok,err = xpcall(handle_message,debug.traceback,
        fd,skynet.unpack(msg,sz))
    skynet.trash(msg,sz)    --free
    if not ok then
        errlog(err)
    end
end

local MSG = {}

MSG.data = dispatch_msg

local function dispatch_queue()
    local fd, msg, sz = proxypack.pop(queue)
    if fd then
        -- may dispatch even the handler.message blocked
        -- If the handler.message never block, the queue should be empty, so only fork once and then exit.
        skynet.fork(dispatch_queue)
        dispatch_msg(fd, msg, sz)

        for fd, msg, sz in proxypack.pop, queue do
            dispatch_msg(fd, msg, sz)
        end
    end
end

MSG.more = dispatch_queue

function MSG.close(fd)
    local proxy_conn = proxy_connections[fd]
    if proxy_conn == nil then
        skynet.error('multiple closing',fd)
        return
    end

    print('close the connect',fd)
    proxy_connections[fd] = nil
end

function MSG.error(fd, msg)
    local conn = proxy_connections[fd]
    if conn == nil then
        skynet.error("socket: error on unknown", fd, err)
        return
    end

    --发生错误后直接关掉
    driver.shutdown(fd)
    --shutdown后会skynet会回传close事件
end

function MSG.warning(fd, size)
    errlog('warning...',fd,size)
end

function MSG.connected(fd)
    local proxy_conn = assert(proxy_connections[fd])
    assert(proxy_conn.status == PROXY_STATUS_CONNECTING)
    proxy_conn.status = PROXY_STATUS_CONNECTED

    print('connected to',proxy_conn.key)
end

skynet.register_protocol {
    name = "socket",
    id = skynet.PTYPE_SOCKET,	-- PTYPE_SOCKET = 6
    unpack = function ( msg, sz )
        return proxypack.filter( queue, msg, sz)
    end,
    dispatch = function (_, _, q, type, ...)
        queue = q
        if type then
            MSG[type](...)
        end
    end
}

function CMD.start()
    forwarder = skynet.newservice(forwarder_service)
    skynet.call(forwarder,'lua','start',{proxy_conn = skynet.self()})
    
    skynet.fork(routine_check)
    skynet.retpack(true)
end

function CMD.relay(dest,...)
    local proxy_conn = select_one_proxy_conn()
    if not proxy_conn then
        skynet.error('no proxy_conn available...',...)
        return
    end

    send_message(proxy_conn.fd,'RELAY',dest,...)
end

function CMD.wait_for_registered()
    if select_one_proxy_conn() then
        return skynet.retpack(true)
    end
    table_insert(watchers, skynet.response())
end

skynet.start(function()
    skynet.dispatch("lua", function(session, source, cmd, ...)
        local f = assert(CMD[cmd])
        f(...)
    end)

    skynet.register('.proxy_conn')
end)
