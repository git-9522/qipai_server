local skynet = require "skynet"
local table_insert = table.insert
local math_random = math.random
local table_remove = table.remove
local util = require "util"
local sharedata = require "sharedata"
local xuezhan = require "xuezhan"

local GAME_STATUS_STARTED = 1           --游戏开始
local GAME_STATUS_HUANSANZHANG = 2          --牌局换三张
local GAME_STATUS_DINGQUE = 3           --游戏定缺

local FLOWER_WAN = 1
local FLOWER_TIAO = 3
local FLOWER_TONG = 2
--换三张
local HUANSANZHANG_WAITING_TIME = 1000

local global_configs = setmetatable({},{
        __index = function(t,k) 
            return sharedata.query("global_configs")[k]
        end
    })

local function shuffle_tile(self,peipai_list,peipai_self,player_uid)
    assert(not self.player_tiles_map)
    local player_tiles_map = {}
    local index = 1
    for _,uid in ipairs(self.player_list) do
        if uid == player_uid then
            player_tiles_map[uid] = peipai_self
        else
            player_tiles_map[uid] = peipai_list[index]
            index = index + 1
        end
    end

    local all_used_tiles = {}
    for i = 1,3 do
        for j = 1,9 do
            local tile = i*10+j
            all_used_tiles[tile] = 4
        end
    end
    print("fff",tostring_r(all_used_tiles))
    for k,player_tile_list in pairs(peipai_list) do
        for _,tile in pairs(player_tile_list) do
            tile = tonumber(tile)
            print("============",tile)
            local c = all_used_tiles[tile]
            assert(c > 0)
            c = c -1
            if c > 0 then
                all_used_tiles[tile] = c
            else
                all_used_tiles[tile] = nil
            end
        end
    end
    
    for _,tile in pairs(peipai_self) do
        tile = tonumber(tile)
        local c = all_used_tiles[tile] or 0
        assert(c > 0)
        c = c -1
        if c > 0 then
            all_used_tiles[tile] = c
        else
            all_used_tiles[tile] = nil
        end
    end

    local tile_list = {}
    for tile,count in pairs(all_used_tiles) do
        for i = 1,count do
            tile_list[#tile_list + 1] = tile
        end
    end
    self.tile_list = tile_list

    --洗牌
    local tile_count = #tile_list
    for i = 1,tile_count do
        local n = math_random(1,tile_count)
        local m = math_random(1,tile_count)
        if n ~= m then
            tile_list[n],tile_list[m] = tile_list[m],tile_list[n]
        end
    end
    
    --计算骰子,骰子其实仅仅供客户端做表现用
    local dies = {math_random(1,6),math_random(1,6)}
    self.dies = dies[1] * 10 + dies[2]

     
    --补牌
    for _,uid in ipairs(self.player_list) do
        local player_tile_list = player_tiles_map[uid]
        for i = #player_tile_list + 1,13 do
            local tile = table_remove(tile_list)
            table_insert(player_tile_list,tile)
        end
        assert(#player_tile_list == 13)
        
        --按照[万筒条]排序
        table.sort(player_tile_list)

    end
    print_r(player_tiles_map)

    --庄家多发一张牌
    self.curr_player_drawn_tile = table_remove(self.tile_list)
    table_insert(player_tiles_map[self.banker_uid],self.curr_player_drawn_tile)
    self.game_sub_status = xuezhan.GAME_SUB_STATUS_AFTER_DRAW

    --每个人的牌已经确定了
    self.player_tiles_map = player_tiles_map

    if self.rules.huansanzhang then
        local huansanzhang_map = {}
        for _,uid in ipairs(self.player_list) do
            huansanzhang_map[uid] = {}
        end
        self.huansanzhang_map = huansanzhang_map
        self.curr_status_end_time = util.get_now_time() + xuezhan.HUANSANZHANG_WAITING_TIME
        self.game_status = GAME_STATUS_HUANSANZHANG
    else
        local player_dingque_map = {}
        for _,uid in ipairs(self.player_list) do
            player_dingque_map[uid] = false
        end
        self.player_dingque_map = player_dingque_map
        self.curr_status_end_time = util.get_now_time() + xuezhan.DINGQUE_WAITING_TIME
        self.game_status = GAME_STATUS_DINGQUE
    end
    
    return true
end

--是否有配牌
local function get_peipai_info(self,game_type)
    local player_uid = 0
    for _,uid in pairs(self.player_list) do
        local key = string.format('player_%d_%d',game_type,uid)
        cards_info = skynet.call(".cache_data",'lua','get',key)
        if cards_info then
            return true,uid,cards_info
        end
    end
    return false
end

local function ddz_peipai(C)
    local origin_deal = C.deal
    C.deal = function(self)
        local cards = self.cards
        local player_cards_map = self.player_cards_map
        local bret,cards_info
        local need_peipai,player_uid,cards_info = get_peipai_info(self,1)
    
        print("+++++++++++++++++++++++",player_uid,cards_info)
        if not need_peipai then
            return origin_deal(self)
        else
            local huase = {}
            for i=1,13 do
                huase[i] = 1
            end 
            local new_cards = {}
            for id,card_id in ipairs(self.cards) do
                new_cards[card_id] = true
            end

            local self_cards = cards_info.self_cards
            local cards1 = cards_info.cards1
            local cards2 = cards_info.cards2
            print("#################",table.concat( self_cards, ", "))

            local peipai_func = function(card_id_list,self_cards)
                for id,card in ipairs(self_cards) do
                    if card > 13 then
                        table_insert(card_id_list,card)
                        new_cards[card] = nil
                    else
                        local card_id = huase[card] * 100 + card
                        huase[card] = huase[card] + 1
                        new_cards[card_id] = nil
                        table_insert(card_id_list,card_id)
                    end 
                end
            end

            local mycard_id_list = {}
            local card_id_list1 = {}
            local card_id_list2 = {}

            peipai_func(mycard_id_list,self_cards)
            peipai_func(card_id_list1,cards1)
            peipai_func(card_id_list2,cards2)

            local function full_cards(card_id_list,card_id_set)
                local count = 17 - #card_id_list

                for _,card_id in pairs(card_id_list) do
                    card_id_set[card_id] = true
                end
                if cards_info.laizi_id < 14 then
                    if count > 0 then
                        for id,_ in pairs(new_cards) do
                            card_id_set[id] = true
                            new_cards[id] = nil
                            count = count - 1 
                            if count == 0 then
                                break
                            end    
                        end
                    end
                end
            end
            --随机给牌，凑齐17张
            local player_cards_map = self.player_cards_map
            local index = 1
            for uid,card_id_set in pairs(player_cards_map) do
                if uid == player_uid then
                    full_cards(mycard_id_list,card_id_set)
                elseif index == 1 then
                    index = index + 1
                    full_cards(card_id_list1,card_id_set)
                else
                    full_cards(card_id_list2,card_id_set)
                end 
            end
            local dizhu_cards = self.dizhu_cards

            local index = 0
            for card_id,_ in pairs(new_cards) do
                table_insert(dizhu_cards,card_id)
                index = index + 1
                if index == 3 then
                    break
                end
            end

            if self.laizi then
                local laizi = 0
                laizi = cards_info.laizi_id % 14    
                self.laizi = laizi
            end
        end    
    end
end

local function get_position_total_power(table_round,power_list)
    local total_power = 0
    for i=1,#power_list do
        total_power = total_power + table_round[power_list[i]].power
    end
    return total_power
end

local function rand_index(table_round,power_list)
    if not power_list then
        return false
    end
    local total_power = get_position_total_power(table_round,power_list)
    if total_power == 0 then
        return false
    end
    
    local rand_num = math_random(1,total_power)
    local curr_power = 0
    for i=1,#power_list do
        curr_power = curr_power + table_round[power_list[i]].power
        if curr_power >= rand_num then
            return power_list[i]
        end
    end
    return false
end

local function get_max_flower_count(index_id)
    local index_info = global_configs.haopai_index[index_id]
    local count = index_info["wan"] or 0
    local flower = FLOWER_WAN
    if index_info["tiao"] and index_info["tiao"] > count then
        count = index_info["tiao"]
        flower = FLOWER_TIAO
    end

    if index_info["tong"] and index_info["tong"] > count then
        count = index_info["tong"]
        flower = FLOWER_TONG
    end
    return count,flower
end

local function select_tiles(all_used_tiles,flower,duizi_count,kezi_count,shunzi_count,kaopai_count,gangpai_count,max_flower_count)
    local this_count = 0
    local tile_list = {}
    local round_count = 0
    while duizi_count > 0 do
        if this_count + 2 > 13 then
            return tile_list
        end

        local round = math_random(1,9)
        local tile = flower*10 + round
        
        if (all_used_tiles[tile] or 0) + 2 > 4 then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            goto continue
        else
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            all_used_tiles[tile] = (all_used_tiles[tile] or 0) + 2
            this_count = this_count + 2    
        end
        duizi_count = duizi_count - 1

        print("continue111111111111111111111111")
        ::continue::
    end

    while kezi_count > 0 do
        if this_count + 3 > 13 then
            return tile_list
        end

        local round = math_random(1,9)
        local tile = flower*10 + round

        if (all_used_tiles[tile] or 0) + 3 > 4 then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            goto continue
        else
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            all_used_tiles[tile] = (all_used_tiles[tile] or 0) + 3
            this_count = this_count + 3 
        end
        kezi_count = kezi_count - 1

        print("continue222222222222222222222222")
        ::continue::
    end

    while shunzi_count > 0 do
        if this_count + 3 > 13 then
            return tile_list
        end

        local round = math_random(1,7)

        if (all_used_tiles[flower*10 + round] or 0) + 1 > 4 or 
        (all_used_tiles[flower*10 + round + 1] or 0) + 1 > 4 or 
        (all_used_tiles[flower*10 + round + 2] or 0) + 1 > 4 then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            goto continue
        else
            table_insert(tile_list,flower*10 + round)
            table_insert(tile_list,flower*10 + round + 1)
            table_insert(tile_list,flower*10 + round + 2)
            all_used_tiles[flower*10 + round] = (all_used_tiles[flower*10 + round] or 0) + 1
            all_used_tiles[flower*10 + round + 1] = (all_used_tiles[flower*10 + round + 1] or 0) + 1
            all_used_tiles[flower*10 + round + 2] = (all_used_tiles[flower*10 + round + 2] or 0) + 1
            this_count = this_count + 3 
        end
        shunzi_count = shunzi_count - 1
        print("continue333333333333333333333333333")
        ::continue::     
    end

    if kaopai_count > 0 then
        if this_count + kaopai_count > 13 then
            return tile_list
        end
        local round_kaopai = math_random(1,10-kaopai_count)
        if not round_kaopai then
            goto continue
        end
        local i = 0
        while kaopai_count > 0 do
            tile = flower*10 + round_kaopai + i
            if (all_used_tiles[tile] or 0) + 1 > 4 then
                return tile_list
            end
            table_insert(tile_list,tile)
            all_used_tiles[tile] = (all_used_tiles[tile] or 0) + 1
            this_count = this_count + 1
            i=i+1
            kaopai_count = kaopai_count - 1
        end
        ::continue::
    end
    while gangpai_count > 0 do
        if this_count + 4 > 13 then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            return tile_list
        end

        local round = math_random(1,9)
        local tile = flower*10 + round

        if all_used_tiles[tile] then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            goto continue
        else
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            table_insert(tile_list,tile)
            all_used_tiles[tile] = 4
            this_count = this_count + 4
        end
        gangpai_count = gangpai_count - 1

        print("continue444444444444444444444444")
        ::continue::
    end

    while this_count < max_flower_count do
        local round = math_random(1,9)
        local tile = flower*10 + round
        
        if (all_used_tiles[flower*10 + round] or 0) + 1 > 4 then
            if round_count > 10 then
                break
            end
            round_count = round_count + 1
            goto continue
        end

        table_insert(tile_list,tile)
        all_used_tiles[tile] = (all_used_tiles[tile] or 0) + 1
        this_count = this_count + 1

        print("continue55555555555555555555555")
        ::continue::
    end
    print("tile77777777777777777777777777777777")
    return tile_list
end

local function select_tile_by_index(index_id,all_used_tiles)
    local max_flower_count,flower = get_max_flower_count(index_id)
    local haopai_detail = global_configs.haopai_detail
    local haopai_detail_map = {}
    for id,detail_info in pairs(haopai_detail) do
        local t = haopai_detail_map[detail_info.count] or {}
        table_insert(t,id)
        haopai_detail_map[detail_info.count] = t
    end
    --print_r(haopai_detail_map)

    local detail_index = rand_index(global_configs.haopai_detail,haopai_detail_map[max_flower_count])
    if not detail_index then
        return {}
    end

    local haopai_info = haopai_detail[detail_index]

    local duizi_count = haopai_info.duizi or 0
    local kezi_count = haopai_info.kezi or 0
    local shunzi_count = haopai_info.shunzi or 0
    local kaopai_count = haopai_info.kaopai or 0
    local gangpai_count = haopai_info.gangpai or 0
    return select_tiles(all_used_tiles,flower,duizi_count,kezi_count,shunzi_count,kaopai_count,gangpai_count,max_flower_count)
end

local function haopai(self)
    --sharedata.query("global_configs")
    local haopai_index = global_configs.haopai_index
    local haopai_position_map = {}
    for id,index_info in pairs(haopai_index) do
        local position_info = haopai_position_map[index_info.position] or {}
        table_insert(position_info,id)
        haopai_position_map[index_info.position] = position_info
    end
    print_r(haopai_position_map)
    local all_used_tiles = {}
    local player_tile_list = {}
    for i=1,4 do
        local index_id = rand_index(global_configs.haopai_index,haopai_position_map[i],rand_num)
        if not index_id then
            table_insert(player_tile_list,{})
        else
            local tile_list = select_tile_by_index(index_id,all_used_tiles)
            table_insert(player_tile_list,tile_list)
        end
    end
    print_r(player_tile_list)
    local peipai_list = {}
    for i=2,4 do
        table_insert(peipai_list,player_tile_list[i])
    end
    return shuffle_tile(self,peipai_list,player_tile_list[1],self.player_list[1])
end

if skynet.getenv("DEBUG") then
    return function(ddz)        
        local C = getmetatable(ddz.new()).__index
        local game_type = C.get_game_type()
        print("game_type",game_type)
        if game_type == 1 then
            ddz_peipai(C)
        elseif game_type == 2 then
        --血战到底配牌逻辑
            local origin_shuffle_and_deal = C.shuffle_and_deal
            C.shuffle_and_deal = function(self)
                local need_peipai,player_uid,cards_info = get_peipai_info(self,2)
                print("+++++++++++++++++++++++",player_uid,cards_info)
                if not need_peipai then                    
                    --TODO:麻将需要做好牌系统
                    if global_configs.system_switch.haopai.status == 1 then
                        return haopai(self)
                    else
                        return origin_shuffle_and_deal(self)
                    end
                else    
                    assert(self.game_status == 1)
                    print("cards_info",tostring_r(cards_info))
                    --先发配牌
                    local peipai_list = {}
                    local get_num_form_string = function(t)
                        local ret = {}
                        for i=1,#t do
                            table_insert(ret,tonumber(t[i]))
                        end
                        return ret
                    end
                    peipai_list[1] = get_num_form_string(cards_info.cards1)
                    peipai_list[2] = get_num_form_string(cards_info.cards2)
                    peipai_list[3] = get_num_form_string(cards_info.cards3)
                    peipai_self = get_num_form_string(cards_info.self_cards)

                    return shuffle_tile(self,peipai_list,peipai_self,player_uid)
                    
                end
            end
        end            
        return ddz
    end
elseif global_configs.system_switch.haopai.status == 1 then
    return function(ddz)
        local C = getmetatable(ddz.new()).__index
        local game_type = C.get_game_type()
        if game_type == 2 then
            local origin_shuffle_and_deal = C.shuffle_and_deal
            C.shuffle_and_deal = function(self)
                return haopai(self)
            end
        end
        return ddz
    end    
else
    return function(ddz) return ddz end
end