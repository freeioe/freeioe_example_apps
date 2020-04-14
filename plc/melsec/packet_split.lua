local class = require 'middleclass'
local types = require 'melsec.command.types'

local split = class('Modbus_App_Packet_Split')

local MAX_PACKET_DATA_LEN = 960
local MAX_INDEX_GAP = 64

local DATA_TYPES = {
	bit = { len = 1 },
	uint8 = { len = 1 },
	int8 = { len = 1 },
	uint16 = { len = 2 },
	int16 = { len = 2 },
	uint32 = { len = 4 },
	int32 = { len = 4 },
	uint64 = { len = 8 },
	int64 = { len = 8 },
	float = { len = 4 },
	double = { len = 8 },
}

function split:initialize()
end

function split:sort(inputs)
	return table.sort(inputs, function(a, b)
		if a.sc_name ~= b.sc_name then
			return false
		end

		if a.index > b.index then
			return false
		end
		if a.index < b.index then
			return true
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

function split:split(inputs)
	self:sort(inputs)
	--[[
	local cjson = require 'cjson'
	print(cjson.encode(inputs))
	]]--

	local packets = {}
	local pack = {}
	local org_input = nil
	for _, v in ipairs(inputs) do
		if pack.sc_name ~= v.sc_name then
			if pack.sc_name ~= nil then
				table.insert(packets, pack)
			end
			pack = { sc_name=v.sc_name }
			pack.start = v.index
			pack.inputs = {}
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end
		v.offset = v.offset or 0
		assert(v.offset < 16 and v.offset >= 0, 'bit offset isssue')

		local max_len = MAX_PACKET_DATA_LEN
		local max_gap = MAX_INDEX_GAP

		local is_word = types.SC_VALUE_TYPE[v.sc_name] == 'WORD' 

		max_len = max_len * (is_word and 8 or 4)
		max_gap = max_gap * (is_word and 8 or 4)

		local input_len = 0
		if v.dt ~= 'raw' and v.dt ~= 'string' then
			local DT = assert(DATA_TYPES[v.dt])
			if not is_word and v.dt ~= 'bit' then
				input_len = DT.len * 8
			else
				input_len = DT.len
			end
		else
			input_len = assert(v.slen, "String length missing")
		end

		local index_new = org_input ~= nil and v.index - org_input.index > max_gap
		if v.index - pack.start > max_len or index_new then
			table.insert(packets, pack)
			pack = { sc_name = v.sc_name }
			pack.start = v.index
			pack.inputs = {}
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end

		table.insert(pack.inputs, v)
		print(pack.start, v.index, pack.len)
		if is_word then
			pack.len = (input_len * 8 + v.index - pack.start + 8) // 16
		else
			pack.len = input_len + v.index - pack.start 
		end
	end
	if pack.sc_name then
		table.insert(packets, pack)
	end

	return packets
end

return split
