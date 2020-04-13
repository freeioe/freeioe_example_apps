local class = require 'middleclass'
local types = require 'melsec.command.types'

local split = class('Modbus_App_Packet_Split')

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

function split:initialize(pack, unpack)
	self._pack = pack
	self._unpack = unpack
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

		local max_len = 480 -- TODO:
		if types.SC_VALUE_TYPES[v.sc_name] == 'BIT' then
			max_len = max_len * 2
		end

		local input_len = v.slen or 1
		if v.dt ~= 'raw' and v.dt ~= 'string' then
			local DT = assert(DATA_TYPES[v.dt])
			input_len = DT.len
		end

		if v.index - pack.start > max_len then
			table.insert(packets, pack)
			pack = { fc=v.fc }
			pack.start = v.index
			pack.inputs = {}
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end

		table.insert(pack.inputs, v)
	end
	if pack.fc then
		table.insert(packets, pack)
	end

	return packets
end

function split:pack(input, value)
	if input.dt == 'raw' then
		value = tostring(value)
		if string.len(value) > input.slen then
			value = string.sub(value, 1, input.slen)
		end
		if string.len(value) < input.slen then
			value = value .. string.rep('\0', input.slen - string.len(value))
		end
	end
	local dtf = assert(self._pack[input.dt])
	return dtf(self._pack, value)
end

function split:unpack(input, data, index)
	local index = index or input.pack_index
	local dtf = assert(self._unpack[input.dt])
	--print(input.name, index, string.byte(data, 1, 1))
	if input.dt == 'raw' then
		return dtf(self._unpack, data, index, input.slen)
	end
	return dtf(self._unpack, data, index)
end


return split
