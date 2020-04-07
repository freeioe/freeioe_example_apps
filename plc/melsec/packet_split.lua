local class = require 'middleclass'

local split = class('FREEIOE_PLC_ENIP_PACKET_SPLIT')

function split:split(props, max_count)
	--[[
	local cjson = require 'cjson'
	print(cjson.encode(props))
	]]--
	local max_count = max_count or 64

	local packets = {}
	local pack = {props = {}}
	for _, v in ipairs(props) do

		if #pack.props >= max_count then
			table.insert(packets, pack)
			pack = { props = {} }
		end

		table.insert(pack.props, v)
	end

	if #pack.props > 0 then
		table.insert(packets, pack)
	end

	return packets
end

return split
