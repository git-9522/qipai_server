local lz_remind = require "lz_remind"
local table_insert = table.insert
local table_remove = table.remove
local table_sort = table.sort

local assert = assert
local pairs = pairs
local ipairs = ipairs

local M = {}

local CARD_SUIT_TYPE_INVALID = 0        --无效牌型
local CARD_SUIT_TYPE_WANGZHA = 1        --王炸
local CARD_SUIT_TYPE_ZHADAN = 2         --炸弹
local CARD_SUIT_TYPE_DANPAI = 3         --单牌
local CARD_SUIT_TYPE_DUIPAI = 4         --对牌
local CARD_SUIT_TYPE_SANZANGPAI = 5     --三张牌
local CARD_SUIT_TYPE_SANDAIYI = 6       --三带一
local CARD_SUIT_TYPE_DANSHUN = 7        --单顺
local CARD_SUIT_TYPE_SHUANGSHUN = 8     --双顺
local CARD_SUIT_TYPE_FEIJI = 9       --飞机 
local CARD_SUIT_TYPE_FEIJIDAICIBANG = 10          --飞机带翅膀
local CARD_SUIT_TYPE_SIDAIER = 11       --四带二
local CARD_SUIT_TYPE_RUANZHA = 12    --软炸
local CARD_SUIT_TYPE_SANDAIYIDUI = 13   --三带一对
local CARD_SUIT_TYPE_SIDAILIANGDUI = 14 --四带两对

local FIRST_PLAY = {
    [1] = CARD_SUIT_TYPE_DANPAI,
    [2] = CARD_SUIT_TYPE_DUIPAI,
    [3] = CARD_SUIT_TYPE_SANZANGPAI,
    [4] = CARD_SUIT_TYPE_ZHADAN,
}

--[[
    每张卡牌分别由1-10,J,Q,K,black joker,red jocker 定义为1-15
--]]
local BLACK_JOKER_NUMBER = 14
local RED_JOKER_NUMBER = 15
local POWER_MAP = {
    [3] = 1,
    [4] = 2,
    [5] = 3,
    [6] = 4,
    [7] = 5,
    [8] = 6,
    [9] = 7,
    [10] = 8,
    [11] = 9, --J
    [12] = 10, --Q
    [13] = 11, --K
    [1] = 12,    --A

    [2] = 14,    --2

    [BLACK_JOKER_NUMBER] = 16,  --black joker
    [RED_JOKER_NUMBER] = 18,  --red joker
}
assert(#POWER_MAP == 15)
local CONTINUOUS_CARD_MAP = {}
for k,v in ipairs(POWER_MAP) do CONTINUOUS_CARD_MAP[v] = k end

local function extract_card_number(card_id)
    return card_id % 100
end

local function translate_to_count_number(card_suit)
    local card_number_set = {}
    for _,card_id in pairs(card_suit) do
		local number = extract_card_number(card_id)
		card_number_set[number] = (card_number_set[number] or 0) + 1
    end

    local count_number_map = {}
    for number,count in pairs(card_number_set) do
        local t = count_number_map[count]
        if not t then 
            t = {}
            count_number_map[count] = t
        end
        table_insert(t,number)
    end

    return count_number_map,card_number_set
end


--第一次出牌时，选择最小的牌出
local function random_select(card_id_list,laizi)
    local real_card_number_set = {}
    for _,card_id in pairs(card_id_list) do
        local number = extract_card_number(card_id)
        local t = real_card_number_set[number]
        if not t then t = {} real_card_number_set[number] = t end
        table_insert(t,card_id)
    end

    local count_number_map,card_number_set = translate_to_count_number(card_id_list)
    --按大小排序
    local play_list = {}
    for k,v in pairs(card_number_set) do
        local power = 0
        local t = {}
        if k == laizi then
            power = 100
        else 
            power = POWER_MAP[k]    
        end
        t.id = k
        t.power = power
        table_insert(play_list,t)
    end
    table_sort(play_list,function(a,b) return a.power < b.power end)

    local must_play = false
    while true do
        for i=1,#play_list do
            local count = card_number_set[play_list[i].id]
            if must_play or count < 4 then
                local key = play_list[i].id
                local type = FIRST_PLAY[count]
                local card_suit = real_card_number_set[key]
                return card_suit,type,key
            end
        end
        must_play = true
    end
end

M.random_select = random_select

local function select_card(uid,ddz_instance,last_card_suit_type,last_card_suit_key,last_card_suit)
    local laizi = ddz_instance:get_laizi_id()
    local cards_id_list = ddz_instance:get_player_card_ids(uid)
   
    local remind = lz_remind.card_remind(cards_id_list,last_card_suit,last_card_suit_type,last_card_suit_key,laizi)
    if remind and remind[1] then
        return remind[1].card_suit,remind[1].type,remind[1].key
    end
    return false
end

function M.trustee_play(uid,ddz_instance)
    local card_id_list,type,key
    local laizi = ddz_instance:get_laizi_id()
    if ddz_instance:is_must_play(uid) then
        --这里必须出牌，直接调用托管AI的方法出牌
        card_id_list,type,key = random_select(ddz_instance:get_player_card_ids(uid),laizi)
    else
        local last_record = ddz_instance:get_last_record()
        card_id_list,type,key = select_card(uid,ddz_instance,last_record.card_suit_type,last_record.key,last_record.card_suit)
        if not card_id_list or (uid ~= ddz_instance:get_dizhu_uid() and last_record.uid ~= ddz_instance:get_dizhu_uid() 
                and #card_id_list ~= #ddz_instance:get_player_card_ids(uid)) then
                     return {{}}
                end 
    end
    return {card_id_list,type,key}
end

return M