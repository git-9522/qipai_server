package.path = '../tablesvr/games/?.lua;../tablesvr/strategy/?.lua;../lualib/?.lua;' .. package.path
package.cpath = '../luaclib/?.so;' .. package.cpath
local cjson = require "cjson"
local util = require "util"

local mt = {}
mt.__index = {
    start = function(self)
        local time4,time5 = util.get_now_time() 
        self.start = time4 * 1000000 + time5
    end,
    stop = function(self)
        local time4,time5 = util.get_now_time() 
        return time4 * 1000000 + time5 - self.start
    end
}
local profiler = function()
    local o = setmetatable({},mt)
    o:start()
    return o
end
_ENV.profiler = profiler

local getupvaluefuncs
local function getupvaluetable(src,unique,ut)
    if type(src) == 'function' then
        getupvaluefuncs(src, unique, ut)
    elseif type(src) == 'table' then
        if not ut[src] then
            ut[src] = true
            for k,v in pairs(src) do
                getupvaluetable(v,unique,ut)
            end
            local mt = getmetatable(src)
            while mt do
                getupvaluetable(mt.__index,unique,ut)
                mt = getmetatable(mt)
            end
        end
    end
end

local function collect_module_funcs(module,mfuncs,mtables)
    for k,v in pairs(module) do
        if type(v) == 'function' then
            mfuncs[v] = k
        elseif type(v) == 'table' then
            if not mtables[v] then 
                mtables[v] =  true
                collect_module_funcs(v,mfuncs)
            end
        end
    end
end

function getupvaluefuncs(func, unique,ut)
	local i = 1
	while true do
		local name, value = debug.getupvalue(func, i)
		if name == nil then
			return
		end
		local t = type(value)
		if t == "table" then
            --getupvaluetable(value,unique,ut)
		elseif t == "function" then
			if not unique[value] then
				unique[value] = {func = func, i = i, name = name}
				getupvaluefuncs(value, unique, ut)
			end
		end
		i=i+1
	end
end

local table_unpack = table.unpack
local string_format = string.format
local tostring = tostring

local records = {}
local prequire = function(mname)
    local module = require(mname)
    local mfuncs = {}
    local mtables = {}
    collect_module_funcs(module,mfuncs,mtables)
    local mt = getmetatable(module)
    while mt do
        collect_module_funcs(mt.__index,mfuncs,mtables)
        mt = getmetatable(mt)
    end

    -------TEST--------------
    for k,v in pairs(mfuncs) do
        print(v,k)
    end


    local ut = {}
    local unique = {}

    for func in pairs(mfuncs) do
        getupvaluefuncs(func,unique,ut)
    end

    for k,v in pairs(unique) do
        --print(v.name,v.func,k,v.i)
        debug.setupvalue(v.func, v.i, function(...)
            local p = profiler()
            local rets = {k(...)}
            local rk = string_format('%s[%s]',v.name,tostring(k))
            local r = records[rk] or {c = 0, t = 0, m = 0}
            local elapsed = p:stop()
            r.c = r.c + 1
            r.t = r.t + elapsed
            if r.m < elapsed then r.m = elapsed end
            records[rk] = r
            return table_unpack(rets)
        end)
    end

    return module
end

local function show_measurement()
    local result = {}
    for k,v in pairs(records) do
        result[#result + 1] = {name = k, c = v.c , t = v.t, m = v.m}
    end
    table.sort(result,function(a,b) return a.c > b.c end)
    for _,v in pairs(result) do
        print(string_format('<%s>\ttimes:%d\ttotal:%d(us)\taverage:%.4f(us)\tmax:%d(us)',
            v.name,v.c,v.t,v.t/v.c,v.m))
    end
end

return {require = prequire, show_measurement = show_measurement}