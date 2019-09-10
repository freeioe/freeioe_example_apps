local class = require 'middleclass'

local split = class('Modbus_App_Packet_Split')

local DATA_TYPES = {
	bit = { len = 1 },
	uint8 = { len = 1 },
	int8 = { len = 1 },
	uint16 = { len = 2 },
	int16 = { len = 2 },
	uint32 = { len = 4 },
	int32 = { len = 4 },
	uint32_r = { len = 4 },
	int32_r = { len = 4 },
	uint64 = { len = 8 },
	int64 = { len = 8 },
	float = { len = 4 },
	float_r = { len = 4 },
	double = { len = 8 },
	double_r = { len = 8 },
}

local MAX_COUNT = {
	MC_0x01 = 2000,
	MC_0x02 = 2000,
	MC_0x03 = 125,
	MC_0x04 = 125,
	MC_0x05 = 1,
	MC_0x06 = 1,
	MC_0x0F = 2000,
	MC_0x10 = 125,
}

function split:initialize(pack, unpack)
	self._pack = pack
	self._unpack = unpack
end

function split:sort(inputs)
	return table.sort(inputs, function(a, b)
		if a.fc > b.fc then
			return false
		end
		if a.fc < b.fc then
			return true
		end

		if a.addr > b.addr then
			return false
		end
		if a.addr < b.addr then
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
		if pack.fc ~= v.fc then
			if pack.fc ~= nil then
				table.insert(packets, pack)
			end
			pack = { fc=v.fc }
			pack.start = v.addr
			pack.inputs = {}
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end
		v.offset = v.offset or 0

		local DT = DATA_TYPES[v.dt]
		local max_len = assert(MAX_COUNT['MC_0x'..string.format('%02X', v.fc)], 'function code '..v.fc..' not supported!')

		--- slen is the raw string length which
		local input_end = v.addr + ( (DT and DT.len or v.slen) or 1 )

		--- If bit unpack on non-bit function code, then skip the offset
		if v.dt ~= 'bit' then
			--- If there is offset needs to be added to index
			input_end = input_end + v.offset
		end

		if input_end - pack.start > max_len then
			table.insert(packets, pack)
			pack = { fc=v.fc }
			pack.start = v.addr
			pack.inputs = {}
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end

		if pack.fc == 0x01 or pack.fc == 0x02 then
			v.pack_index = v.addr - pack.start + v.offset + 1
		elseif pack.fc == 0x03 or pack.fc == 0x04 then
			if v.dt == 'bit' then
				--- The bit unpack using bitwise index
				v.pack_index = (v.addr - pack.start) * 2 * 8 + v.offset + 1
			else
				--- Index is native for 0x01 or 0x03
				v.pack_index = (v.addr - pack.start) * 2 + v.offset + 1
			end
		end

		table.insert(pack.inputs, v)
		pack.len = input_end - pack.start
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
