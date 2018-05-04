package.path = '../tablesvr/games/?.lua;../lualib/?.lua;' .. package.path
package.cpath = '../luaclib/?.so;' .. package.cpath
--require "preload"
local cjson = require "cjson"
local lz_remind = require "lz_remind"
local ddz = require "ddz"
--[[local CARD_SUIT_TYPE_INVALID = 0        --无效牌型
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

local DESCRIPTIONS = {
    "王炸","炸弹","单牌","对牌","三张牌",
    "三带一","单顺","双顺","飞机","飞机带翅膀",
    "四带二","软炸","三带一对","四带两对"
}
local AI = require "lz_trustee_AI"
local ddz = require "lzddz"
local players = {1111,2222,3333}
local remind = require "lz_remind"

while true do
    local ddz_ins= ddz.new()

    ddz_ins:init()

    local user_ais = {}
    for _,uid in pairs(players) do
        ddz_ins:enter(uid)
        local robot_ai = AI.new()
        robot_ai:init(uid,ddz_ins)
        user_ais[uid] = robot_ai
    end

    assert(ddz_ins:check_and_start())

    local dizhu_uid = players[math.random(1,#players)]
    print(string.format('dizhu is [%d]',dizhu_uid))
    ddz_ins:shuffle()
    ddz_ins:deal()
    ddz_ins:set_dizhu(dizhu_uid)
    print("laizi:###############",ddz_ins:get_laizi_id())

    local laizi = ddz_ins:get_laizi_id()
    local last_cards 
    local last_card_suit_type,last_card_suit_key 
    local last_uid 

    while not ddz_ins:is_game_over() do
        local uid = ddz_ins:get_next_player_uid()
        local robot_ai = user_ais[uid]

        if last_uid == uid then
            last_card_suit_type,last_card_suit_key,last_cards = nil
        end

        local my_cards = ddz_ins:get_player_card_ids(uid)
        table.sort( my_cards,function(a,b) return a % 100 > b % 100 end )
        if last_cards then
            local ret = remind.card_remind(my_cards,last_cards,last_card_suit_type,last_card_suit_key,laizi)
            print_r(my_cards)
            print("LAST PLAY++++++++++++++++++",uid,DESCRIPTIONS[last_card_suit_type],last_card_suit_key,laizi)
        --    print_r(ret)
            if ret then
                print("要出的牌型为:")
                for k,v in ipairs(ret) do 
                    print_r(v.card_suit)
                end
            end
            io.read()
        end
        local curr_cards,type,key = robot_ai:select_cards(last_card_suit_type,last_card_suit_key,last_cards)
        print("++++++++++++++++++++++++LAST",last_card_suit_type,last_card_suit_key)
        print_r(curr_cards)
        if not curr_cards then
            assert(ddz_ins:donot_play(uid))
            print(string.format('[%d] give up=>[%d] mycards<%s>',uid,
                ddz_ins:get_next_player_uid(),table.concat(my_cards,',')))
        else
            last_uid = uid
            local card_number_set = {}
            for _,card_id in pairs(curr_cards) do
                local number = card_id % 100
                card_number_set[number] = (card_number_set[number] or 0) + 1
            end
            last_card_suit_type,last_card_suit_key = type,key
            
            
            ddz_ins:play(uid,curr_cards,type,key)
            last_cards = curr_cards

        end
    end

    local ok,result = ddz_ins:get_game_result()
    assert(ok)
    local winners = {}
    local losers = {}
    for _,v in ipairs(result.winners) do
        table.insert(winners,v.uid )
    end
    for _,v in ipairs(result.losers) do
        table.insert(losers,v.uid)
    end
    print(string.format('winners are [%s],losers are [%s]',
        table.concat(winners,','),
        table.concat(losers,',')))
    --print(cjson.encode(result))
    os.execute("sleep 0.1")
end]]

-- local cards_id_list = {101,102,104,205,306,107,108,309,402,310,312,313,208,113,408,305}
local cards_id_list = {105,207,307,208,309,410,111,112,101,201,202,102,302,402}


local last_card_suit = {103,203,303,104,204,304,105,206}
local card_number_set = {}
for _,card_id in pairs(last_card_suit) do
    local number = card_id % 100
    card_number_set[number] = (card_number_set[number] or 0) + 1
end
local last_card_suit_type,last_card_suit_key = ddz.get_card_suit_type(card_number_set)

print(last_card_suit_type,last_card_suit_key)
local remind = lz_remind.card_remind(cards_id_list,last_card_suit,last_card_suit_type,last_card_suit_key,laizi)
for i=1,#remind do
    print("------------------------------------")
    for k,v in pairs(remind[i]) do
        if k == "card_suit" then
            for i=1,#v do
                print(v[i])
            end
        else
            print(k,v)    
        end
    end
end