local util = require "util"
local table_insert = table.insert 
local table_concat = table.concat
local string_format = string.format
local tostring = tostring

local debug_traceback = debug.traceback

local function draw_indent(indent)
    local s = {}
    for i = 1,indent do
        table_insert(s,'  ')
    end

    return table_concat(s,'')
end

local function _tostring_r(data,depth)
    if depth >= 6 then return '...' end
    if type(data) == 'table' then
        local s = {'{\n'}
        for k,v in pairs(data) do
            table_insert(s,string_format('%s%s:%s,\n',draw_indent(depth+1),tostring(k),_tostring_r(v,depth+1)))
        end
        table_insert(s,draw_indent(depth) .. '}\n')
        return table_concat(s,'')
    elseif type(data) == 'string' then
        return string_format('"%s"',tostring(data))
    else
        return tostring(data)
    end
end

local function tostring_r(data)
    return _tostring_r(data,0)
end

local raw_print = print
local function _print(level,loglevel,...)
    local time_secs,time_usecs = util.get_now_time()
    local date = os.date('*t',time_secs)
    local info = debug.getinfo(level,'nSl')
    local func_name = info.name
    if func_name and func_name ~= '?' then func_name = ' ::' .. func_name
    else func_name = '' end
    local s = {}
    local args = {...}
    for _,v in pairs(args) do 
        table_insert(s,tostring(v))
    end

    local output = require("skynet").error
    output(string_format('[%04d-%02d-%02d %02d:%02d:%02d.%06d] [%s] <%s:%d%s> %s',
        date.year,date.month,date.day,date.hour,date.min,date.sec,time_usecs,loglevel,
        info.source,info.currentline,func_name,table_concat(s,'  ')))
end

local function _billlog(log_table)
    local data = require("cjson").encode(log_table)
    require("skynet").send('.logger','lua',string_format('%d %s',util.get_now_time(),data)) 
end

local info_print = function(...) _print(3,"INFO",...) end
local dbg_print = function(...) _print(3,"DEBUG",...) end
local err_print = function(...) _print(3,"ERROR",...) end

--重载该方法便于递归打印table
_ENV.tostring_r = tostring_r
_ENV.print = info_print
_ENV.print_r = function(data) _print(3,"INFO",tostring_r(data)) end
_ENV.errlog = err_print
_ENV.dbglog = dbg_print
_ENV.billlog = function(log_table)
    xpcall(_billlog,debug_traceback,log_table)
end
_ENV.math.random = util.randint
_ENV.math.randomseed = function() end
_ENV.raw_print = raw_print

_ENV.dbglog_r = function(...)
    local args = {...}
    local newargs = {}
    for _,o in ipairs(args) do
        table.insert(newargs, tostring_r(o))
    end
    _print(3,"DEBUG",table.unpack(newargs))
end

_ENV.R = function() return require("remote") end