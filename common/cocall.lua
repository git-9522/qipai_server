local skynet = require "skynet"

local table_unpack = table.unpack
local table_insert = table.insert

return function (timeout,...)
    local blocking
    local results
    local waiting_co

    local function call_wrapper(f,id,...)
        blocking[coroutine.running()] = id
        local ok,ret = xpcall(f,debug.traceback,...)
        if ok then
            results[id] = ret or false
        else
            errlog(ret)
        end

        if not blocking then
            return
        end
    
        blocking[coroutine.running()] = nil
        if next(blocking) then
            return
        end

        skynet.wakeup(waiting_co)
        blocking = nil
    end

    local func_objs = {...}
    if #func_objs < 1 then
        return true,{}
    end

    blocking = {}
    results = {}
    waiting_co = coroutine.running()
    for _,fo in ipairs(func_objs) do
        results[fo.id] = false
        skynet.fork(call_wrapper,fo.f,fo.id,table_unpack(fo.params or {}))
    end

    timeout = timeout or 5
    if skynet.sleep(timeout * 100) == 'BREAK' then
        return true,results
    end

    return false,results
end