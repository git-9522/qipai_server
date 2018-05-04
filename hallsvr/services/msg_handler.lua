local skynet = require "skynet"
local proxypack = require "proxypack"
local server_def = require "server_def"
local constant = require "constant"
local utils = require "utils"

skynet.register_protocol {
	name = "client",
	id = skynet.PTYPE_CLIENT,
	pack = proxypack.pack_raw
}

local closing_sever = false
local agents = {}
local uid_session_map = {}

local CMD = {}

function CMD.data(game_session,data,uid,ip)
	print('got data',game_session,#data,uid,ip)
	if closing_sever then
		errlog('hallsvr is closing now!!!',uid)
		return
	end

	local agent = agents[uid]
	if not agent then
		print("New client from : ",uid,game_session)
		agents[uid] = 0
		agent = skynet.newservice("agent")
		agents[uid] = agent
		skynet.call(agent, "lua", "start", {
			fd = game_session,
			uid = uid,
			msg_handler = skynet.self(),
			ip = ip,
		})
		assert(not uid_session_map[uid])
		uid_session_map[uid] = game_session
	elseif agent == 0 then
		errlog('sending request too fast,service is not created completely yet')
		return
	end

	local origin_session = assert(uid_session_map[uid])
	if origin_session == 0 then
		errlog(uid,'intersected data when insteading')
		return
	end

	--假如不是同一个会话，则需要新会话覆盖旧会话
	if game_session ~= origin_session then
		dbglog('now instead uid',uid,origin_session,game_session)
		uid_session_map[uid] = 0
		if not skynet.call(agent, "lua", "instead", game_session) then
			--还回去
			uid_session_map[uid] = origin_session
			errlog(uid,'failed to instead',game_session)
			return
		end
		assert(uid_session_map[uid] == 0,string.format('inconsistency state %d',uid))
		uid_session_map[uid] = game_session
	end

	skynet.send(agent,'client',data)
end

function CMD.close(uid,game_session,reason)
	print(game_session,'closed','reason',reason)
	local agent = agents[uid]
	if not agent then
		errlog('could not find game session',uid,game_session)
		return
	end

	local curr_session = assert(uid_session_map[uid])
	if game_session ~= curr_session then
		errlog('game_session not match uid session',game_session,curr_session)
		return
	end

	skynet.send(agent,'lua','disconnect',reason)
	uid_session_map[uid] = -1
end

function CMD.start()
	print('start....')
	skynet.retpack(true)
end

function CMD.on_agent_exit(uid,source)
	local addr = assert(agents[uid],'could not find agent ' .. uid)
	assert(addr == source,string.format('%s ~= %s',addr,source))
	assert(uid_session_map[uid],'no such session map ' .. uid)

	agents[uid] = nil
	uid_session_map[uid] = nil
end

function CMD.get_agent(uids)
	if type(uids) == 'table' then
		local rets = {}
		for _,uid in pairs(uids) do
			rets[uid] = agents[uid]
		end
		return skynet.retpack(rets)
	elseif type(uids) == 'number' then
		local uid = uids
		return skynet.retpack(agents[uid])
	else
		return skynet.retpack(nil)
	end
end

function CMD.get_all_agent()
	return skynet.retpack(agents)
end

function CMD.get_agent_count()
	local online_count = 0
	for uid,_ in pairs(agents) do
		online_count = online_count + 1
	end
	return skynet.retpack(online_count)
end

function CMD.toagent(uid,...)
	local agent = agents[uid]
	if not agent then
		errlog('could not find player',uid)
		return
	end

	skynet.send(agent,'lua',uid,...)
end

function CMD.new_platform_mail(mail_type,range)

	if mail_type == constant.PLATFORM_MAIL_TYPE_ALL then
		for uid,agent in pairs(agents) do
			skynet.send(agent,'lua',uid,'new_platform_mail')
		end
	elseif mail_type == constant.PLATFORM_MAIL_TYPE_SPEC then
		local uid_list = utils.str_split(range,",")
		for id,uid in pairs(uid_list) do
			uid = tonumber(uid)
			if agents[uid] then
				skynet.send(agents[uid],'lua',uid,'new_platform_mail')
			end
		end
	end
end

function CMD.notify_all_agent(messages)
	for uid,agent in pairs(agents) do
		skynet.send(agent,'lua',uid,'send_opration_message',messages)
	end
	skynet.send('.opration_message_mgr','lua','add_messages',messages)
end

function CMD.get_enter_data(uid)
	local agent = agents[uid]
	local data = skynet.call(agent,'lua',uid,'get_enter_data')
	skynet.retpack(data)
end

function CMD.money_change(uid,chg_tb)
	local agent = agents[uid]
	if agent then
		skynet.send(agent,'lua',uid,'notify_money_changed',chg_tb)
	end
end

function CMD.close_server()
	dbglog("close_server begin!!!!")
	closing_sever = true
	skynet.sleep(500)  --睡眠5秒
	for uid,agent in pairs(agents) do
		skynet.send(agent,'lua','close_server')
	end
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd],'unknown cmd ' .. cmd)
		f(...)
	end)
end)
