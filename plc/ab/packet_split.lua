local class = require 'middleclass'

local split = class('FREEIOE_PLC_AB_PLCTAG_APS')

local ELEM_SIZE = {
	uint8 = 1,
	int8 = 1,
	uint16 = 2,
	int16 = 2,
	uint32 = 4,
	int32 = 4,
	uint64 = 8,
	int64 = 8,
	float32 = 4,
	float64 = 8,
	string = 88
}

function split:elem_size(prop)
	return ELEM_SIZE[prop.dt]
end

function split:sort(props)
	return table.sort(props, function(a, b)
		local dta = ELEM_SIZE[a.dt]
		local dtb = ELEM_SIZE[b.dt]
		if dta > dtb then
			return false
		end
		if dta < dtb then
			return true
		end

		if a.elem_name ~= b.elem_name then
			return false
		end

		if a.offset > b.offset then
			return false
		end
		if a.offset < b.offset then
			return true
		end

		return false
	end)
end

function split:split(props)
	self:sort(props)
	--[[
	local cjson = require 'cjson'
	print(cjson.encode(props))
	]]--

	local packets = {}
	local pack = {}
	for _, v in ipairs(props) do
		v.offset = v.offset or 0
		v.elem_size = assert(ELEM_SIZE[v.dt], 'data_type '..v.dt..' not supported!')

		if pack.elem_size ~= v.elem_size or pack.elem_name ~= v.elem_name then
			if pack.elem_size ~= nil then
				table.insert(packets, pack)
			end
			pack = { elem_size = v.elem_size, elem_name = v.elem_name }
			pack.props = {}
		end

		table.insert(pack.props, v)

		pack.elem_count = v.offset + 1
	end
	if pack.elem_size then
		table.insert(packets, pack)
	end

	return packets
end

return split
