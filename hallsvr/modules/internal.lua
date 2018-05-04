local skynet = require "skynet"
local server_def = require "server_def"
local cjson = require "cjson"
local offline_op = require "offline_op"
local reason = require "reason"
local handler = require "handler"

local select_server = require("router_selector")

local M = {}

local player
local send_to_gateway
local global_configs

function M._init_(player_,send_to_gateway_,global_configs_)
    player = player_
    send_to_gateway = send_to_gateway_
    global_configs = global_configs_
end

local function _pull_payment_info()
    local curr_uid = player.uid
    local ok,ret = skynet.call('.forwarder','lua','TOPAYSVR','query',curr_uid)
    if not ok then
        errlog('failed to query payment info',curr_uid)
        return
    end

    for _,payment_str in ipairs(ret) do
        --判断要购买的商品id
        local payment = cjson.decode(payment_str)
        local ok,ret = pcall(player.add_paid_product,player,payment)
        if not ok then
            errlog(ret)
        end
    end
end

function M.pull_payment_info_for_login()
    local ok,ret = pcall(_pull_payment_info)
    if not ok then
        errlog(ret)
    end
end

function M.pull_payment_info()
    local ok,ret = pcall(_pull_payment_info)
    if not ok then
        errlog(ret)
    end

    handler.hall.notify_user_money(player)
end

local function handle_offline_op(op_data)
    local reason = REASON.PLAY_CARD
    local value = assert(tonumber(op_data.value))
    local key = assert(op_data.key)

    if key == offline_op.OFFLINE_ADD_CONIS then

    end

    return true
end

local function _pull_offline_op_info()
    local curr_uid = player.uid
    local ok,ret = skynet.call('.forwarder','lua','TOEXDBSVR','pull_offline_data',curr_uid)
    if not ok then
        errlog('failed to query offline info',curr_uid)
        return
    end

    for _,data in ipairs(ret) do
        local op_data = cjson.decode(data)
        local ok,ret = pcall(handle_offline_op,op_data)
        if not ok then
            errlog(ret)
        end
    end
end

function M.pull_offline_op_info_for_login()
    local ok,ret = pcall(_pull_offline_op_info)
    if not ok then
        errlog(ret)
    end
end

function M.pull_offline_op_info()
    local ok,ret = pcall(_pull_offline_op_info)
    if not ok then
        errlog(ret)
    end

    handler.hall.notify_user_money(player)
end
----------------------------------------------------matchserver---------------------------------------------
function M.report_player_matched(dest,table_gid)
    send_to_gateway('hall.NTF_MATCH_SUCESS',{dest = dest,table_gid = table_gid})
end
----------------------------------------------------matchserver---------------------------------------------

function M.send_opration_message(messages)
    for _,v in pairs(messages) do
        local rsp = {
            message = v.message,
            interval = v.interval,
            end_time = v.end_time,
        }
        send_to_gateway('hall.NTF_CIRCLE_NOTIFICATION',rsp)
    end
end

function M.new_platform_mail()
    local ntf = {
        count = 1
    }
    send_to_gateway("mail.NTF_NEW_MAIL",ntf)
end

function M.on_paid()
    local base_data = _pull_base_data()
    handler.hall.notify_money_changed(player.uid,{
        gems = base_data.gems,
    })
end

function M.get_enter_data()
    local enter_data = {
        name = player.user_data.name,
        icon = player.user_data.icon,
        sex = player.user_data.sex,
        player_ip = player.user_data.last_login_ip,
    }
    skynet.retpack(enter_data)
end

function M.notify_money_changed(values)
    handler.hall.notify_money_changed(player.uid,values)
end

function M.add_task_process(task_type)
    local task_id,process = player:add_task_process(task_type,global_configs.task)
    if task_id then
        handler.daily.notify_task_change(task_id,process)
    end    
end

return M
