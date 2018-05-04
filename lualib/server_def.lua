local M = {}

M.defines = {
    SERVER_TYPE_GATEWAY = 1,
    SERVER_TYPE_PROXY = 2,
    SERVER_TYPE_TABLESVR = 3,
    SERVER_TYPE_HALLSVR = 4,
    SERVER_TYPE_DBSVR = 5,
    SERVER_TYPE_MATCHSVR = 6,
    SERVER_TYPE_ACCOUNTSVR = 7,
	SERVER_TYPE_MAILSVR = 8,
    SERVER_TYPE_PAYSVR = 9,
    SERVER_TYPE_EXDBSVR = 10,
	SERVER_TYPE_BASESVR = 11,
	SERVER_TYPE_FMATCHSVR = 12,
}

local server_type_map = {
	[M.defines.SERVER_TYPE_GATEWAY] = 'gateway',
	[M.defines.SERVER_TYPE_PROXY] = 'proxy',
	[M.defines.SERVER_TYPE_TABLESVR] = 'tablesvr',
	[M.defines.SERVER_TYPE_HALLSVR] = 'hallsvr',
	[M.defines.SERVER_TYPE_DBSVR] = 'dbsvr',
	[M.defines.SERVER_TYPE_MATCHSVR] = 'matchsvr',
	[M.defines.SERVER_TYPE_ACCOUNTSVR] = 'accountsvr',
	[M.defines.SERVER_TYPE_MAILSVR] = 'mailsvr',
	[M.defines.SERVER_TYPE_PAYSVR] = 'paysvr',
	[M.defines.SERVER_TYPE_EXDBSVR] = 'exdbsvr',
	[M.defines.SERVER_TYPE_BASESVR] = 'basesvr',
	[M.defines.SERVER_TYPE_FMATCHSVR] = 'fmatchsvr',
}

M.server_type_map = server_type_map

local server_name_map = {}
for k,v in pairs(server_type_map) do
    server_name_map[v] = k
end
M.server_name_map = server_name_map

function M.get_server_info(dest) 
	local server_type = dest >> 16
	local server_id = dest & 0xFF

	local server_name = server_type_map[server_type]
	if not server_name then
		return
	end

	return server_name,server_id
end

function M.make_dest(server_type,server_id)
    return server_type << 16 | server_id
end

function M.make_broadcast_dest(server_type)
    return server_type << 16
end

function M.make_random_dest(server_type)
    return server_type << 16 | 0xFFFF
end

function M.is_broadcast_dest(dest)
	return dest & 0xFFFF == 0
end

function M.is_random_dest(dest)
	return dest & 0xFFFF == 0xFFFF
end

return M