table_insert = table.insert
local M = {}

function M.trustee_play(uid,cur_instance)
    if cur_instance:is_player_can_win(uid) then
        return true
    else
        local player_tile_list = cur_instance:get_player_tile_list(uid)
        local dinque_flower = cur_instance:get_player_dinque(uid)
        print("=================",dinque_flower)
        local dinque_tile = {}
        for k,v in pairs(player_tile_list) do
            if math.floor(v/10) == dinque_flower then
                table_insert(dinque_tile,v)
            end
        end

        print_r(dinque_tile)
        if #dinque_tile > 0 then
            return false,dinque_tile[1]
        end

        return false,player_tile_list[#player_tile_list] or cur_instance:get_curr_player_drawn_tile() 
    end
end

return M