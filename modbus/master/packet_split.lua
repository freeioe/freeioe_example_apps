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
	uint64 = { len = 8 },
	int64 = { len = 8 },
	float = { len = 4 },
	double = { len = 8 },
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
		pack.fc = pack.fc or v.fc
		--print(pack.fc, v.fc, v.addr, v.dt)
		if pack.fc == v.fc then
			pack.start = pack.start or v.addr
			local len = DATA_TYPES[v.dt]
			if v.offset ~= nil then
				len = len + v.offset // 8
			end
			if v.addr + len - pack.start <= MAX_COUNT then
				pack.inputs = pack.inputs or {}

				if v.dt == 'bit' and (pack.fc == 0x01 or pack.fc == 0x02) then
					v.pack_index = (v.addr - pack.start) * 8 + (v.offset or 0)
				else
					v.pack_index = v.addr - pack.start 
				end

				table.insert(pack.inputs, v)
				pack.len = v.addr + len - pack.start
			else
				table.insert(packets, pack)
				pack = {}
			end
		else
			table.insert(packets, pack)
			pack = {}
		end
	end
	if pack.fc then
		table.insert(packets, pack)
		pack = {}
	end

	return packets
end

function split:pack(input, value)
	local dtf = assert(self._pack[input.dt])
	return dtf(self._pack, value)
end

function split:unpack(input, data, index)
	local index = index or input.pack_index
	local dtf = assert(self._unpack[input.dt])
	return dtf(self._unpack, data, index)
end


return split
