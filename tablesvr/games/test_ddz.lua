package.cpath = '../../luaclib/?.so;' .. package.cpath
package.path = '../../lualib/?.lua;' .. package.path
local ddz = require "ddz"
require "preload"

local CARD_SUIT_TYPE_INVALID = 0        --无效牌型
local CARD_SUIT_TYPE_WANGZHA = 1        --王炸
local CARD_SUIT_TYPE_ZHADAN = 2         --炸弹
local CARD_SUIT_TYPE_DANPAI = 3         --单牌
local CARD_SUIT_TYPE_DUIPAI = 4         --对牌
local CARD_SUIT_TYPE_SANZANGPAI = 5     --三张牌
local CARD_SUIT_TYPE_SANDAIYI = 6       --三带一
local CARD_SUIT_TYPE_DANSHUN = 7        --单顺
local CARD_SUIT_TYPE_SHUANGSHUN = 8     --双顺
local CARD_SUIT_TYPE_FEIJI = 9          --飞机
local CARD_SUIT_TYPE_SIDAIER = 11       --四带二

local DESCRIPTION = {
    [CARD_SUIT_TYPE_INVALID ] =         "无效牌型",
    [CARD_SUIT_TYPE_WANGZHA ] =         "王炸",
    [CARD_SUIT_TYPE_ZHADAN ] =          "炸弹",
    [CARD_SUIT_TYPE_DANPAI ] =          "单牌",
    [CARD_SUIT_TYPE_DUIPAI ] =          "对牌",
    [CARD_SUIT_TYPE_SANZANGPAI ] =      "三张牌",
    [CARD_SUIT_TYPE_SANDAIYI ] =        "三带一",
    [CARD_SUIT_TYPE_DANSHUN ] =         "单顺",
    [CARD_SUIT_TYPE_SHUANGSHUN ] =      "双顺",
    [CARD_SUIT_TYPE_FEIJI ] =           "飞机",
    [CARD_SUIT_TYPE_SIDAIER ] =        "四带二",
}

local function get_card_suit_type(...)
    local rets = {ddz.get_card_suit_type(...)}
    local type = rets[1]
    rets[1] = DESCRIPTION[type]
    return table.unpack(rets)
end

print(get_card_suit_type({[1]= 4,[13]=4}))
print(get_card_suit_type({[1]= 4,[13]=4,[12]=4}))
print(get_card_suit_type({[1]= 4,[13]=4,[12]=4}))
print(get_card_suit_type({[1]= 3,[13]=3,[12]=3}))
print(get_card_suit_type({[3]= 3,[4]=3,[5]=3,[6]= 4,[2] = 3}))
print(get_card_suit_type({[3]= 3,[4]=3,[5]=3,[6]= 3,[7] = 3,[8]=4,[9] = 1}))
print(get_card_suit_type({[3]= 4,[4]=3,[5]=3,[6]= 3,[7] = 3,[8] = 4}))
print(get_card_suit_type({[3]= 3,[4]=3,[5]=4}))
print(get_card_suit_type({[3]= 4,[4]=4,[5]=3,[6]=3,[7]=4,[8]=2}))
print(get_card_suit_type({[4]= 4,[5]=3,[6]=1}))
