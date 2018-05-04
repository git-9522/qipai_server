local util = require "util"
local skynet = require "skynet"
local cjson = require "cjson"
local constant = require "constant"
local handler = require "handler"

local math_random = math.random
local math_randomseed = math.randomseed
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort

local TASK_CYCLE_DAILY = 1  --日常任务
local TASK_CYCLE_WEEK = 2     --周常任务

local MAIL_COUNT_LIMIT = 50

local meta = {}

local meta_index = {}
meta.__index = meta_index

local global_configs

function meta.init(global_configs_)
    global_configs = global_configs_
end

function meta.new(uid,user_data)
    local o = {
        uid = uid,
        user_data = user_data,
    }
    return setmetatable(o, meta)
end

function meta_index:billlog(op,params)
    params['brand'] = self.dev_brand
    params['id'] = self.dev_id
    params['uid'] = self.uid
    params['op'] = op

    billlog(params)
end

--------------------------------------------------
function meta_index:check_user_data(result)
    local is_new_player = false
    local user_data = self.user_data
    if not user_data.sign_info then
        local sign_info = user_data:new_table_field('sign_info')
        sign_info.last_sign_time = 0
        sign_info.sign_count = 0
    end

    if not user_data.name then
        is_new_player = true
        if result.user_info and result.user_info.name then
            user_data.name = result.user_info.name
        else
            local names_library = global_configs.names_library
            user_data.name = names_library[util.randint(1,#names_library)]
        end
    end

    if not user_data.sex then
        user_data.sex = (result.user_info and result.user_info.sex) or util.randint(1,2)
    end

    if user_data.icon then
        if result.user_info and result.user_info.icon and 
            result.user_info.icon ~= user_data.icon then
            user_data.icon = result.user_info.icon
        end
    elseif result.user_info and result.user_info.icon then
        user_data.icon = result.user_info.icon
    else
        user_data.icon = tostring(user_data.sex)
    end

    if result.user_info and result.user_info.channel and not user_data.channel then
        --目前渠道只有微信
        user_data.channel = result.user_info.channel
    end

    if not user_data.level then
        user_data.level = 0
    end

    if not user_data.play_total_count then
        user_data.play_total_count = 0
    end

    if not user_data.play_win_count then
        user_data.play_win_count = 0
    end

    if not user_data.last_check_day_time then
        user_data.last_check_day_time = 0
    end

    if not user_data.has_change_name then
        user_data.has_change_name = 0
    end

    if not user_data.jiabei_card then
        user_data.jiabei_card = 0
    end

    if not user_data.last_login_time then
        last_login_time = 0
    end

    if not user_data.last_login_ip then
        last_login_ip = ''
    end

    if not user_data.task_info then                 --任务存储结构：task_info{daily_task_list{task_type:{{task_id,process,status}}}}
        user_data:new_table_field('task_info')
    end

    if not user_data.mail_info then
        local mail_info = user_data:new_table_field('mail_info')
        mail_info.mail_seq = 0
        mail_info:new_table_field('mail_list')
    end

    if skynet.getenv("debug") then
        if user_data.coins == 0 and user_data.gems == 0 and user_data.roomcards == 0 then
            user_data.coins = 99999999
            user_data.gems = 99999999
            user_data.roomcards = 99999999
        end
    end

    return is_new_player
end
-------------------------------------------------------


--这里的道具ID也有可能是货币ID
function meta_index:can_add_item(item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return self:can_add_coins(item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return self:can_add_gems(item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return self:can_add_roomcards(item_num,reason)    
    end

    return false
end

function meta_index:can_reduce_item(item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return self:can_reduce_coins(item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return self:can_reduce_gems(item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return self:can_reduce_roomcards(item_num,reason)    
    end

    return false
end

function meta_index:add_item(item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return self:add_coins(item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return self:add_gems(item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return self:add_roomcards(item_num,reason)
    end

    return false
end

function meta_index:reduce_item(item_id,item_num,reason)
    if item_id == constant.ITEM_COIN_ID then
        return self:reduce_coins(item_num,reason)
    elseif item_id == constant.ITEM_GEM_ID then
        return self:reduce_gems(item_num,reason)
    elseif item_id == constant.ITEM_ROOMCARD_ID then
        return self:reduce_roomcards(item_num,reason)
    end
    
    return false
end

function meta_index:can_add_coins(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.coins + value >= 10000000 then
        return false
    end
    
    return true
end

function meta_index:add_coins(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.coins + value >= 10000000 then
        return false
    end
    user_data.coins = user_data.coins + value

    --记上账单
    self:billlog('addcoins',{curr=user_data.coins,v=value,r=reason})

    return true
end

function meta_index:can_reduce_coins(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.coins - value < 0 then
        return false
    end

    return true
end

function meta_index:reduce_coins(value,reason)
    local user_data = self.user_data
    if user_data.coins - value < 0 then
        return false
    end
    user_data.coins = user_data.coins - value

    --记上账单
    self:billlog('reducecoins',{curr=user_data.coins,v=value,r=reason})

    return true
end
------------------------------------------------------------------------------
function meta_index:can_add_gems(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.gems + value >= 10000000 then
        return false
    end
    
    return true
end

function meta_index:add_gems(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.gems + value >= 10000000 then
        return false
    end

    user_data.gems = user_data.gems + value

    --记上账单
    self:billlog('addgems',{curr=user_data.gems,v=value,r=reason})

    return true
end

function meta_index:can_reduce_gems(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.gems - value < 0 then
        return false
    end

    return true
end

function meta_index:reduce_gems(value,reason)
    local user_data = self.user_data
    if user_data.gems - value < 0 then
        return false
    end

    user_data.gems = user_data.gems - value

    --记上账单
    self:billlog('reducegems',{curr=user_data.gems,v=value,r=reason})

    return true
end
------------------------------------------------------------------------------
function meta_index:can_add_roomcards(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.roomcards + value >= 10000000 then
        return false
    end
    
    return true
end

function meta_index:add_roomcards(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.roomcards + value >= 10000000 then
        return false
    end

    user_data.roomcards = user_data.roomcards + value

    --记上账单
    self:billlog('addroomcards',{curr=user_data.roomcards,v=value,r=reason})

    return true
end

function meta_index:can_reduce_roomcards(value,reason)
    if value <= 0 then
        return false
    end
    local user_data = self.user_data
    if user_data.roomcards - value < 0 then
        return false
    end

    return true
end

function meta_index:reduce_roomcards(value,reason)
    local user_data = self.user_data
    if user_data.roomcards - value < 0 then
        return false
    end

    user_data.roomcards = user_data.roomcards - value

    --记上账单
    self:billlog('reduceroomcards',{curr=user_data.roomcards,v=value,r=reason})

    return true
end
------------------------------------------------------------------------------
local function new_mail_seq(mail_info)
	local mail_seq = mail_info.mail_seq
	if mail_seq >= 2000000000 then
		mail_info.mail_seq =  1
	else
		mail_info.mail_seq = mail_seq + 1 --新邮件必须保证先加seq
	end

	return mail_seq
end

function meta_index:add_task_process(task_type,daily_task)
    local user_data = self.user_data
    local task_info = user_data.task_info
    local type_task_list
    for cycle,cycle_list in pairs(task_info) do
        if cycle_list[tostring(task_type)] then
            type_task_list = cycle_list[tostring(task_type)]
            break
        end
    end

    if not type_task_list then
        errlog("this task_type is not in curr_task",uid,task_type)
        return
    end

    local task_obj = type_task_list[#type_task_list]
    if task_obj.status == constant.TASK_STATUS_FINISHED then
        errlog("this task is finished",uid,task_obj.task_id)
        return
    end

    if task_obj.status == constant.TASK_STATUS_TAKEN then
        --如果已领取，从配置读入新的任务
        local next_id = daily_task[task_obj.task_id].next_id
        if not next_id then
            errlog("you have finished this task",uid,daily_task)
            return
        end
        local task = type_task_list:new_table_field(#type_task_list+1)
        task.task_id = next_id
        task.process = 0
        task.status = constant.TASK_STATUS_UNFINISH
        task_obj = task
    end
    
    task_obj.process = task_obj.process + 1
 
    local limit = daily_task[task_obj.task_id].process

    if task_obj.process >= limit then
        task_obj.status = constant.TASK_STATUS_FINISHED
    end
    return task_obj.task_id,task_obj.process
end

local function get_list_count(data_list)
    local count = 0
    for k,v in pairs(data_list) do
        count = count + 1
    end
    return count
end

--删除最老的邮件
local function delete_oldest_mail(mail_list)
	local count = get_list_count(mail_list)
	local oldest_time = 0
	local oldest_seq = -1
	for seq,mail_obj in pairs(mail_list) do
		if oldest_time == 0 then
			oldest_time = mail_obj.send_time
			oldest_seq = seq
		end
		local mail_info_send_time = mail_obj.send_time
		if mail_info_send_time < oldest_time then
			oldest_time = mail_info_send_time
			oldest_seq = seq
		end
	end
    mail_list:delete_from_hash(tostring(oldest_seq))
	return true
end

function meta_index:add_mail(mail_id,param1,param2,attach_list)
    local user_data = self.user_data
    local mail_info = user_data.mail_info
    local mail_list = mail_info.mail_list

    local mail_seq = new_mail_seq(mail_info)
    
    --检查邮件是否超出限制
    local count = get_list_count(mail_list)
    if count >= MAIL_COUNT_LIMIT then
        delete_oldest_mail(mail_list)
    end

    local one_mail = mail_list:new_table_field(tostring(mail_seq))

    one_mail.mail_seq = mail_seq
    one_mail.mail_id = mail_id
    if param1 then one_mail.param1 = param1 end
    if param2 then one_mail.param2 = param2 end
    
    if attach_list then
        local mail_attach_list = one_mail:new_table_field('attach_list')
        for id,count in pairs(attach_list) do
            local attach_info = mail_attach_list:new_table_field(#mail_attach_list + 1)
            attach_info.id = id
            attach_info.count = count
        end
    end

    return true
end

local function rand_from_table(count,tb)
    local selected = {}
    
    math_random(0,#tb)
    math_randomseed(util.get_now_time())
    if count >= #tb then
        return tb
    end
    while #selected < count do
        math_random(1,#tb)
        table_insert(selected,table_remove(tb,math_random(1,#tb)))
    end
    return selected
end


local function reset_task(player,cycle,task)
    local user_data = player.user_data
    local task_info = user_data.task_info

    --清空任务数组
    local cycle_task_list = task_info[cycle]
    if not cycle_task_list then
        cycle_task_list = task_info:new_table_field(cycle)
    end

    cycle_task_list:clear_from_array()
    local task_id_list = {}
    for id,o in pairs(task) do
        if o.cycle == cycle then
            table_insert(task_id_list,id)
        end
    end
    --初始化任务列表
    local task_type_list = {}
    local task_type_set = {}

    for _,id in ipairs(task_id_list) do
        local task_type = task[id].task_type
        task_type_list[task_type] = 1
        local t = task_type_set[task_type] or {}
        table_insert(t,id)
        task_type_set[task_type] = t
    end
    --每个任务按id排序
    for _,t in pairs(task_type_set) do
        table_sort(t)
    end


    for k,v in pairs(task_type_list) do
        local task_id = task_type_set[k][1]
        local type_task_list = cycle_task_list:new_table_field(tostring(k))
        local one_task = type_task_list:new_table_field(#type_task_list + 1)
        one_task.task_id = task_id 
        one_task.process = 0
        one_task.status = 0         --任务状态  0：未完成   1：已完成未领取    2：已领取
    end

    handler.daily.notify_curr_task()
    dbglog('reset_task',uid)
end

local function check_and_cross_sunup_day(player,time_secs,global_configs)
    --任务重置
    local user_data = player.user_data
    if util.is_same_day(time_secs,user_data.last_check_day_time) then
       return false
    end

    
    --任务跨天
    local ok,msg = pcall(reset_task,player,TASK_CYCLE_DAILY,global_configs.task)
    if not ok then errlog(msg) end
    
    --签到跨天
    local sign_info = user_data.sign_info
    sign_info.special_award = 0
    return true
end

local function check_and_cross_week(player,time_secs,global_configs)
    local user_data = player.user_data
    if util.is_same_week(time_secs,user_data.last_check_day_time) then
        return false
    end

    --跨周
    local ok,msg = pcall(reset_task,player,TASK_CYCLE_WEEK,global_configs.task)
    if not ok then errlog(msg) end

    return true
end

local function check_time_cross(player,global_configs)
    local time_secs = util.get_now_time()
    check_and_cross_week(player,time_secs,global_configs)
    check_and_cross_sunup_day(player,time_secs,global_configs)
    player.user_data.last_check_day_time = time_secs
end

meta_index.check_time_cross = check_time_cross

function meta_index:add_paid_product(payment)
    local curr_uid = self.uid
    --在这里为玩家进行发货处理
    print(tostring_r(payment))

    local goods_id = payment.product_id
    local goods_conf = global_configs.shop[goods_id]
    if not goods_conf then
        errlog('could not find goods_id',goods_id)
        return
    end

    --判断下价格是否满足
    assert(goods_conf.price.currency == constant.ITEM_RMB_ID)
    local required_amount = goods_conf.price.amount
    if required_amount > goods_conf.price.amount then
        errlog(curr_uid,'not enough amount to pay',required_amount,goods_conf.price.amount,goods_id)
        self:billlog('rmbbuy',{goods_id = goods_id,amount = required_amount,success = false})
        return
    end

    local reason = 0
    --钱够了，则给加上道具
    local goods = goods_conf.goods
    if not self:can_add_item(goods.item_id,goods.item_count,reason) then
        errlog(curr_uid,'can not add item',goods.item_id,goods.item_count)
        return
    end

    print(curr_uid,'now add item',goods.item_id,goods.item_count)
    self:add_item(goods.item_id,goods.item_count,reason)

    self:billlog('rmbbuy',{goods_id = goods_id,amount = required_amount,success = true})

    return true
end

function meta_index:can_change_name()
    local user_data = self.user_data
    if user_data.channel ~= constant.CHANNEL_WECHAT and 
        user_data.has_change_name == 0 then
        return true
    end
    return false
end

return meta