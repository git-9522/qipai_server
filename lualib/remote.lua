local skynet = require "skynet"
local server_def = require "server_def"

local make_dest = server_def.make_dest
local make_broadcast_dest = server_def.make_broadcast_dest
local make_random_dest = server_def.make_random_dest
local is_broadcast_dest = server_def.is_broadcast_dest
--[[
    usage:
    R().hallsvr(1):send()
    R().hallsvr({rand = true}):send()
    R().hallsvr({key = 10000}):call()
    R().hallsvr():broadcast()
    R().dest(dest):send()
    R().dest(dest):call()
    R().get_source()
    R().hallsvr(1):dest()
]]

local METHODS = {}
function METHODS:send(...)
    assert(self._dest,'you must specify a destination')
    skynet.send('.forwarder','lua',0,'SEND',self._dest,...)
end

function METHODS:broadcast(...)
    assert(is_broadcast_dest(self._dest),'broadcast must not have any params!')
    skynet.send('.forwarder','lua',0,'SEND',self._dest,...)
end

function METHODS:call(...)
    assert(self._dest,'you must specify a destination')
    return skynet.call('.forwarder','lua',0,'CALL',self._dest,...)
end

function METHODS:dest()
    assert(self._dest,'you must specify a destination')
    return self._dest
end

local function server_name_func(self,param)
    local server_name = self.server_name
    local server_type = assert(server_def.server_name_map[server_name],'unknown server name ' .. server_name)
    local dest
    if type(param) == 'number' then
        dest = make_dest(server_type,param)
    elseif type(param) == 'table' then
        if param.rand then
            assert(not param.key,'can not exist both `rand` and `key`')
            dest = make_random_dest(server_type)
        elseif param.key then
            local server_id = require("router_selector")(server_name,0,param.key)
            dest = make_dest(server_type,server_id)
        elseif next(param) then
            errlog('unknwon param...',next(param))
        end
    elseif param == nil then
        --可以是nil，当是广播的情况下
        dest = make_broadcast_dest(server_type)
    else
        errlog('unknown param...',param)
    end

    self._dest = dest

    return self
end

local SMT = {
    __index = METHODS,
    __call = server_name_func
}

local DMT = {
    __index = METHODS,
    __call = function(self,dest)
        self._dest = dest
        return self
    end
}

local from_src
local function get_source()
    if from_src then
        return from_src
    end
    local server_name = skynet.getenv"server_name"
    local server_id = skynet.getenv"server_id"
    from_src = make_dest(server_def.server_name_map[server_name],server_id)
    return from_src
end
local MT = {}
MT.__index = function(t,k)
    if k == 'dest' then 
        return setmetatable({}, DMT)
    elseif k == 'get_source' then
        return get_source
    end
    return setmetatable({server_name = k}, SMT)
end

local REMOTE = setmetatable({},MT)

return REMOTE