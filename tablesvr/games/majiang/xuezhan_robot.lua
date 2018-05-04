local skynet = require "skynet"
local util = require "util"
local table_unpack = table.unpack
local table_insert = table.insert

local M = {}

local Methods = {}
local MT = {
    __index = Methods
}

function M.new(uid,AI,addr,fd)
    local o = {
        uid = uid,
        AI = AI,
        addr = addr,
        fd = fd,
    }

    return setmetatable(o, MT)
end

--自己进桌
function Methods:on_enter()
    skynet.send(self.addr,'lua','enter',self.uid,self.fd)
end


local function analyse_play(self)
    if not self.cur_instance:is_playing() then
        return
    end
    print("player",self.cur_instance:get_curr_player_uid(),self.uid)
    if self.cur_instance:get_curr_player_uid() == self.uid then
        self.play_time = util.get_now_time() + util.randint(1,1)
        local hu,tile = self.AI.trustee_play(self.uid,self.cur_instance)
        print("analyse_play666666666666666666",hu,tile)
        if hu then
            self.win_request = {}
        else
            dbglog('player---------------------',self.uid,tile)
            self.play_request = {tile = tile}
        end
    end
end

--游戏开始触发
function Methods:on_start(cur_instance)
    self.cur_instance = cur_instance
end

function Methods:on_start_play()
    dbglog('on_start_play')
    analyse_play(self)
end

--出牌
function Methods:on_play(uid)
    dbglog('on_play ....')
    if uid == self.uid then return end
    analyse_play(self)
end

--游戏结束
function Methods:on_game_over()
    self.ddz_instance = nil
    --下一轮准备
end

function Methods:on_option(op)
    print_r(op)
    if op.hu then
        skynet.send(self.addr,'lua','REQ_WIN',self.uid,{},self.fd)
    else
        skynet.send(self.addr,'lua','REQ_PASS',self.uid,{},self.fd)    
    end
end

function Methods:on_ready()
    if not self.ready_time then
        self.ready_time = util.get_now_time() + util.randint(2,5)
    end    
end

function Methods:check_ready(curr_time)
    if not self.ready_time then
        return
    end

    if curr_time >= self.ready_time then
        self.ready_time = nil
        skynet.send(self.addr,'lua','REQ_READY',self.uid,{ready=2},self.fd)
    end
end

function Methods:update_play(curr_time)
    local cur_instance = self.cur_instance
    if not cur_instance:is_playing() then
        return
    end
    --轮到自己出牌
    print("update_play====================",cur_instance:get_curr_player_uid(),self.uid)
    if cur_instance:get_curr_player_uid() == self.uid then
        analyse_play(self)

        if self.win_request then
            local req_msg = assert(self.win_request)
            self.win_request = nil
            skynet.send(self.addr,'lua','REQ_WIN',self.uid,req_msg)
        elseif self.play_request then
            local req_msg = assert(self.play_request)
            self.play_request = nil
            skynet.send(self.addr,'lua','REQ_DISCARD',self.uid,req_msg)
            dbglog_r(self.uid,req_msg)
        end
    end
end

--游戏结束
function Methods:on_game_over()
    self.cur_instance = nil
end

function Methods:update_huansanzhang(curr_time)
    local cur_instance = self.cur_instance
    if not cur_instance:is_huansanzhang() then
        return
    end
    assert(cur_instance:get_player_huansanzhang_map(self.uid))
    if #cur_instance:get_player_huansanzhang_map(self.uid) == 0 then
        self.huansanzhang_request = {tile_list = cur_instance:get_auto_huansanzhang(self.uid)}
        local req_msg = assert(self.huansanzhang_request)
        self.huansanzhang_request = nil
        skynet.send(self.addr,'lua','REQ_HUANSANZHANG',self.uid,req_msg,self.fd)
        dbglog_r(self.uid,req_msg)
    end
end

function Methods:update_dingque(curr_time)
    local cur_instance = self.cur_instance
    if not cur_instance:is_dingque() then
        return
    end
    local dingque_map = cur_instance:get_player_dingque_map()
    if not dingque_map[self.uid] then
        local player_tile_list = cur_instance:get_player_tile_list(self.uid)
        self.dingque_request = {flower = cur_instance:auto_dingque(player_tile_list)}
        local req_msg = assert(self.dingque_request)
        self.dingque_request = nil
        skynet.send(self.addr,'lua','REQ_DINGQUE',self.uid,req_msg,self.fd)
        dbglog_r(self.uid,req_msg)
    end
end

function Methods:update()
    while self.exit do
        local curr_time = util.get_now_time()
        if self.cur_instance then
            --当前是换三张？
            self:update_huansanzhang(curr_time)
            --当前是定缺？
            self:update_dingque(curr_time)
            --当前可以出牌？
            self:update_play(curr_time)
        else
            --游戏未开始则需要检查自己是否准备了
            self:check_ready(curr_time)
        end

        skynet.sleep(50)    --500ms
    end

    dbglog(self.uid,'exit !!!!')
end

function Methods:exit()
    self.exit = true
end

return M