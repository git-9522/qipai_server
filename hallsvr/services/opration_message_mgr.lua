local skynet = require "skynet.manager"
local socket = require "socket"
local handler = require "handler" 
local server_def = require "server_def"
local utils = require "utils"
local util = require "util"
local table_insert = table.insert

local CMD = {}
local messages = {}

function CMD.get_messages()
	local now = util.get_now_time()
	local msgs = {}
	for _,v in pairs(messages) do
		if v.end_time >= now then
			table_insert(msgs,v)
		end
	end

	return skynet.retpack(msgs)
end

function CMD.add_messages(msgs)
	for _,v in pairs(msgs) do
        table_insert(messages,v)
    end
end

skynet.start(function()
	skynet.dispatch("lua",function(_,_,action, ...)
		local f = assert(CMD[action])
		f(...)
	end)

	skynet.register(".opration_message_mgr")
end)


