package.path = '../tablesvr/games/?.lua;../lualib/?.lua;' .. package.path
package.cpath = '../luaclib/?.so;' .. package.cpath
local cjson = require "cjson"
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


local DESCRIPTIONS = {
    "王炸","炸弹","单牌","对牌","三张牌",
    "三带一","单顺","双顺","飞机","四带二",
}
local AI = require "trustee_AI"
local ddz = require "ddz"
local players = {1111,2222,3333}




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
        local curr_cards = robot_ai:select_cards(last_card_suit_type,last_card_suit_key,last_cards)
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
            last_card_suit_type,last_card_suit_key = ddz.get_card_suit_type(card_number_set)
            print(string.format('[%d] type<%s> key<%s> cards<%s> mycards<%s>',
                uid,DESCRIPTIONS[last_card_suit_type],
                tostring(last_card_suit_key),
                table.concat(curr_cards,','),
                table.concat(my_cards,','))
                )
            ddz_ins:play(uid,curr_cards)
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
end
