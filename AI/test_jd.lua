package.path = '../tablesvr/games/?.lua;../tablesvr/strategy/?.lua;../common/?.lua;../lualib/?.lua;' .. package.path
package.cpath = '../luaclib/?.so;' .. package.cpath
local cjson = require "cjson"
local util = require "util"
local xprofiler = require "xprofiler"
xprofiler.require("jd_strategy_high")

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
local CARD_SUIT_TYPE_FEIJIDAICIBANG = 10 --飞机带翅膀
local CARD_SUIT_TYPE_SIDAIER = 11        --四带二
local CARD_SUIT_TYPE_RUANZHA = 12        --软炸
local CARD_SUIT_TYPE_SANDAIYIDUI = 13    --三带一对
local CARD_SUIT_TYPE_SIDAILIANGDUI = 14  --四带两对


local DESCRIPTIONS = {
    "王炸","炸弹","单牌","对牌","三张牌",
    "三带一","单顺","双顺","飞机","飞机带翅膀",
    "四带二","软炸","三带一对","四带两对",
}
local JD_strategy = require "jd_strategy_high"

local AI = {}
function AI.new()
    return setmetatable({},{__index = JD_strategy})
end

local function make_game_robot_config()
    return {
        weigh_value_conf = {
                    [1] = {
                        ["name"] = "王炸",
                        ["base"] = 7,
                        ["base_len"] = 1,
                        ["add"] = 0,
                    },
                    [2] = {
                        ["name"] = "炸弹",
                        ["base"] = 7,
                        ["base_len"] = 1,
                        ["add"] = 0,
                    },
                    [3] = {
                        ["name"] = "单牌",
                        ["base"] = 1,
                        ["base_len"] = 1,
                        ["add"] = 0,
                    },
                    [4] = {
                        ["name"] = "对牌",
                        ["base"] = 2,
                        ["base_len"] = 1,
                        ["add"] = 0,
                    },
                    [5] = {
                        ["name"] = "三条",
                        ["base"] = 3,
                        ["base_len"] = 1,
                        ["add"] = 0,
                    },
                    [7] = {
                        ["name"] = "单顺",
                        ["base"] = 4,
                        ["base_len"] = 5,
                        ["add"] = 1,
                    },
                    [8] = {
                        ["name"] = "双顺",
                        ["base"] = 5,
                        ["base_len"] = 3,
                        ["add"] = 2,
                    },
                    [9] = {
                        ["name"] = "飞机",
                        ["base"] = 6,
                        ["base_len"] = 2,
                        ["add"] = 3,
                    },
                    [12] = {
                        ["name"] = "软炸",
                        ["base"] = 7,
                        ["base_len"] = 2,
                        ["add"] = 3,
                    },
                },
        rob_dizhu_conf = {
                    [1] = {
                        ["score"] = 0,
                        ["probability"] = 0,
                    },
                    [2] = {
                        ["score"] = 4,
                        ["probability"] = 20,
                    },
                    [3] = {
                        ["score"] = 6,
                        ["probability"] = 50,
                    },
                    [4] = {
                        ["score"] = 9,
                        ["probability"] = 100,
                    },
                },
        jia_bei_conf = {
                    [1] = {
                        ["count"] = 3,
                        ["probability"] = 100,
                    },
                    [2] = {
                        ["count"] = 5,
                        ["probability"] = 80,
                    },
                    [3] = {
                        ["count"] = 7,
                        ["probability"] = 10,
                    },
                    [4] = {
                        ["count"] = 99,
                        ["probability"] = 0,
                    },
                    },
                }
end

function JD_strategy:init(uid,ddz_instance,conf)
    self.uid = uid
    self.ddz_instance = ddz_instance
    self.is_rob = false
    self.conf = conf
end

local ddz = require "ddz"
local players = {1111,2222,3333}


for i=1,1 do
    local ddz_ins= ddz.new()
    ddz_ins:init()

    local user_ais = {}
    local conf = make_game_robot_config()
    for _,uid in pairs(players) do
        ddz_ins:enter(uid)

        local robot_ai = AI.new()
        robot_ai:init(uid,ddz_ins,conf)
        user_ais[uid] = robot_ai
    end

    assert(ddz_ins:check_and_start())

    local dizhu_uid = players[math.random(1,#players)]
    print(string.format('dizhu is [%d]',dizhu_uid))
    ddz_ins:shuffle()
    ddz_ins:deal()

    ddz_ins:setingdizhu_status(1)
    ddz_ins:test_set_dizhu(dizhu_uid)
    ddz_ins:start_play()

    for uid,robot in pairs(user_ais) do
        print("--------------",uid)
        robot:analyse_jiabei(robot)
    end
   

    local last_cards 
    local last_card_suit_type,last_card_suit_key 
    local last_uid 

    local  count = 1
    while not ddz_ins:is_game_over() do
        local uid = ddz_ins:get_next_player_uid()
        local robot_ai = user_ais[uid]

        if last_uid == uid then
            last_card_suit_type,last_card_suit_key,last_cards = nil
        end

        local my_cards = ddz_ins:get_player_card_ids(uid)
        table.sort( my_cards,function(a,b) return a % 100 > b % 100 end )
        local second,tiny_second = util.get_now_time()
        local ret = robot_ai:analyse_play()
        local second_end,tiny_second_end = util.get_now_time()
        print("end+++++++++++++++++++++++++++++++++",count,second_end - second,tiny_second_end - tiny_second)
        count = count + 1
        local curr_cards = ret.card_suit

        if not next(curr_cards) then
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
    print(string.format('record is [%s] winners are [%s],losers are [%s]',
        tostring(i),
        table.concat(winners,','),
        table.concat(losers,',')))
    --print(cjson.encode(result))
end

xprofiler.show_measurement()