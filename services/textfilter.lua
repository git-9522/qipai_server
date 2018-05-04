local skynet = require "skynet"
local textfilter = require "textfilter"

local CMD = {}
local instance

function CMD.is_sensitive(text)
    skynet.retpack(textfilter.is_sensitive(instance,text))
end

function CMD.replace_sensitive(text)
	skynet.retpack(textfilter.replace_sensitive(instance,text))
end

skynet.start(function()
    local path = skynet.getenv "sensitive_words_path"
    instance = assert(textfilter.init(path))

    skynet.dispatch("lua",function(_,_,cmd,...)
        CMD[cmd](...)
    end)
end)
