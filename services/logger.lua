local skynet = require "skynet"
require "skynet.manager"
local slog = require "slog"

local is_daemon = skynet.getenv "daemon"

local string_format = string.format
local server_name = skynet.getenv "server_name"
local server_id = tonumber(skynet.getenv "server_id")
local syslog = slog.syslog
local notice_level = slog.level.LOG_NOTICE
local info_level = slog.level.LOG_INFO

skynet.register_protocol {
	name = "text",
	id = skynet.PTYPE_TEXT,
	unpack = skynet.tostring,
	dispatch = function(_, address, msg)
		if not is_daemon then
			raw_print(string_format("[:%08x] %s", address, msg))
		end
		syslog(slog.facility.LOG_LOCAL6 | info_level,string_format("[:%08x] %s", address, msg))
	end
}

skynet.start(function()
    local ret = slog.openlog(string_format('skynet_%s_%d',server_name,server_id),slog.option.LOG_NDELAY|slog.option.LOG_PID,0)
    skynet.dispatch("lua",function(_,_,msg)
        syslog(slog.facility.LOG_LOCAL6 | notice_level,msg)        
    end)

	skynet.register ".logger"
end)
