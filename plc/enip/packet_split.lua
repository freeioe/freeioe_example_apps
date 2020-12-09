local class = require 'middleclass'
local ab_tag_parser = require 'enip.ab.tag.parser'

local split = class('FREEIOE_PLC_ENIP_PACKET_SPLIT')

local function sort_props(props)
	for _, v in ipairs(props) do
		v.tag = ab_tag_parser(v.elem_name)
	end
	table.sort(props, function(a, b)
		return a.tag < b.tag
	end)
end

function split:split(props, max_count)
	--[[
	local cjson = require 'cjson'
	print(cjson.encode(props))
	]]--
	local max_count = max_count or 64
	sort_props(props)

	local packets = {}
	local pack = {props = {}}
	local tag = nil
	for _, v in ipairs(props) do

		if #pack.props >= max_count then
			table.insert(packets, pack)
			pack = { props = {} }
			tag = nil
		end

		if tag then
			tag:join(v.tag)
		end
		tag = v.tag

		table.insert(pack.props, v)
	end

	if #pack.props > 0 then
		table.insert(packets, pack)
	end

	return packets
end

return split
