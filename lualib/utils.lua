require "skynet.manager"
local skynet = require "skynet"
local socket = require "socket"
local cjson = require "cjson"
local server_def = require "server_def"
local proxypack = require "proxypack"
local msgdef = require "msgdef"
local pb = require 'protobuf'
local table_insert = table.insert

local server_name = skynet.getenv "server_name"
local M = {}

local function get_msgid(msgname)
    return msgdef.name_to_id[msgname]
end

function M.send_to_gateway(seq,uid,client_fd,msgname,msg,...)
    local msgid = get_msgid(msgname)
    if not msgid then
        skynet.error('unknown msgname',msgname,msgid)
        return
    end

    print("msgid++++++msgname++++++",msgid,msgname)

    local msg_body = pb.encode(msgname,msg)
    local package = proxypack.pack_client_message(seq,msgid,msg_body)

    local gateway_id = client_fd >> 31
    R().gateway(gateway_id):send('.watchdog',server_name,'sendto',client_fd,package,...)

    print(string.format('<<<<<player[%s] send to a request[%s] content(%s)',
        tostring(uid),msgname,cjson.encode(msg)))

    return true
end

function M.is_in_table(table,key)
    assert(table)
    for k,v in pairs(table) do
        if v == key then
            return true
        end
    end

    return false
end

function M.is_between_min_max(key,min,max)
    if key >= min and key <= max then
        return true
    end

    return false
end

function M.str_split(str, delimiter)
    if str==nil or str=='' or delimiter==nil then
        return nil
    end
    
    local result = {}
    for match in (str..delimiter):gmatch("(.-)%"..delimiter) do
        table_insert(result, match)
    end
    return result
end

--return <server_id><table_id>
function M.extract_table_gid(table_gid)
    return table_gid >> 32,table_gid & 0xFFFFFFFF
end

function M.make_table_gid(server_id,table_id)
    return server_id << 32 | table_id
end
return M