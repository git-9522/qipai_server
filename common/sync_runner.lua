local table_remove = table.remove
local table_insert = table.insert
local xpcall = xpcall

local sync_keys = {}

return function(key,f,...)
    local waiting_list = sync_keys[key]
    if waiting_list == nil then
        sync_keys[key] = true
    else
        if waiting_list == true then
            waiting_list = {}
            sync_keys[key] = waiting_list
        end
        local co = coroutine.running()
        table_insert(waiting_list,co)
        skynet.wait(co) --等待唤醒
    end

    local ok,err = xpcall(f,debug.traceback,...)
    if not ok then errlog(err) end

    --再接着调度
    local waiting_list = sync_keys[key]
    if waiting_list == true or #waiting_list == 0 then
        sync_keys[key] = nil
        return
    end    

    local co = table_remove(waiting_list,1)
    skynet.wakeup(co)
end