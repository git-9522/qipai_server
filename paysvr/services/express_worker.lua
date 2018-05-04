local skynet = require "skynet"
local mysql = require "mysql"
local redis = require "redis"
local util = require "util"
local cjson = require "cjson"
local server_def = require "server_def"
local sharedata = require "sharedata"
local constant = require "constant"

local select_server = require("router_selector")

local table_insert = table.insert
local string_format = string.format
local global_configs

local handlers = {}

local function add_paid_product(r)
    local uid = r.uid
    --在这里为玩家进行发货处理

    local goods_id = r.product_id
    local goods_conf = global_configs.shop[goods_id]
    if not goods_conf then
        errlog('could not find goods_id',goods_id)
        return
    end

    --判断下价格是否满足
    assert(goods_conf.price.currency == constant.ITEM_RMB_ID)
    local required_amount = goods_conf.price.amount
    if required_amount > goods_conf.price.amount then
        errlog(uid,'not enough amount to pay',required_amount,goods_conf.price.amount,goods_id)
        billlog({uid = uid,op = 'rmbbuy',goods_id = goods_id,amount = required_amount,success = -1})
        return
    end

    local reason = 0
    --钱够了，则给加上道具
    local goods = goods_conf.goods

    dbglog(uid,'now add item',goods.item_id,goods.item_count)

    local server_id = select_server('basesvr',0,uid)
    local ok,succ,ret = skynet.call('.forwarder','lua','TOBASESVR',server_id,'add_item',uid,
        goods.item_id,goods.item_count,reason)

    if not ok then
        errlog(uid,'failed to add item',required_amount,goods_conf.price.amount,goods_id)
        billlog({uid = uid,op = 'rmbbuy',goods_id = goods_id,amount = required_amount,success = -2})
    end

    if not succ then
        errlog(uid,'failed to add item',required_amount,goods_conf.price.amount,goods_id)
        billlog({uid = uid,op = 'rmbbuy',goods_id = goods_id,amount = required_amount,success = -3})
    end

    billlog({uid = uid,op = 'rmbbuy',goods_id = goods_id,amount = required_amount,success = 0})

    dbglog(uid,'pay successfully...',required_amount)

    R().hallsvr({key=uid}):send('.msg_handler','notify_agent',uid,'on_paid')

    return true
end

function handlers.new_payment(r)
    add_paid_product(r)
end

skynet.start(function()
	skynet.dispatch("lua", function(session, source, action, ...)
		local f = assert(handlers[action])
		f(...)
	end)
    
    sharedata.query("global_configs")

    global_configs = setmetatable({},{
        __index = function(t,k) 
            return sharedata.query("global_configs")[k]
        end
    })
end)
