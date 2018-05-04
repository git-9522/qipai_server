local skynet = require "skynet.manager"

local opration_message_worker

local CMD = {}

function CMD.on_registered()
	if opration_message_worker then
		return
	end

	opration_message_worker = true
 	opration_message_worker = skynet.newservice('opration_message_worker')
	skynet.call(opration_message_worker,'lua','start')
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, cmd, ...)
		local f = assert(CMD[cmd])
		f(...)
	end)

	skynet.register(".opration_message_worker_mgr")
end)
