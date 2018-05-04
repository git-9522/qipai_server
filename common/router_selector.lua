local skynet = require "skynet"

local function load_router_config(conf_path)
	assert(conf_path,'invalid router configuration path')
	local conf = assert(loadfile(conf_path)())
	for k,v in pairs(conf) do
		local num = 0 
		for _,_ in pairs(v) do
			num = num + 1
		end
		assert(num == #v and #v > 0,k)
	end

	return conf
end

local router_config = load_router_config(skynet.getenv "router_path")

local function select_server(server_name,server_id,key)
	local sub_conf = router_config[server_name]
	if sub_conf then
		return sub_conf[key % #sub_conf + 1]
	end
	return server_id
end

return select_server