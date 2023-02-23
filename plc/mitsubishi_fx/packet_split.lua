local class = require 'middleclass'

local split = class('APP_PLC_FX_PACKET_SPLIT')

local DATA_TYPES = {
	bit = { len = 1 },
	bit_num = { len = 1 },
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
	uint64_r = { len = 8 },
	int64_r = { len = 8 },
	float = { len = 4 },
	float_r = { len = 4 },
	double = { len = 8 },
	double_r = { len = 8 },
}

local MAX_COUNT_FX1 = {
	BR = { 54, 0 },
	WR = { 208, 13 },
	BW = { 46, 0 },
	WW = { 160, 11 },
	BT = { 10, 0 },
	WT = { 96, 6 },
}

local MAX_COUNT = {
	BR = { 256, 0 },
	WR = { 512, 64 },
	QT = { 512, 64 },
	BW = { 160, 0 },
	WW = { 160, 64 },
	QW = { 160, 64 },
	BT = { 20, 0 },
	WT = { 160, 10 },
	QT = { 160, 10 },
}

local BIT_REG = { 
	X = true, 
	Y = true,
	M = true,
	S = true,
	TS = true,
	CS = true,
}

local function max_addr(cmd, name, start_addr, is_fx1)
	local max_t = is_fx1 and MAX_COUNT_FX1 or MAX_COUNT
	if BIT_REG[name] then
		return max_t[string.upper(cmd)][1]
	else
		return max_t[string.upper(cmd)][1]
	end
end

function split:initialize(pack, unpack)
	self._pack = pack
	self._unpack = unpack
end

function split:sort(inputs)
	return table.sort(inputs, function(a, b)
		if a.cmd > b.cmd then
			return false
		end
		if a.cmd < b.cmd then
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

function split:split(inputs, option, is_fx1)
	self:sort(inputs)
	--[[
	local cjson = require 'cjson'
	print(cjson.encode(inputs))
	]]--

	local packets = {}
	local pack = {}
	for _, v in ipairs(inputs) do
		if pack.cmd ~= v.cmd then
			if pack.cmd ~= nil then
				table.insert(packets, pack)
			end
			pack = { cmd = v.cmd, name = v.name }
			pack.start = v.addr
			pack.inputs = {}
			pack.len = 0
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end
		v.offset = v.offset or 0

		local DT = DATA_TYPES[v.dt]
		local max_len = max_addr(pack.cmd, pack.name, pack.start, is_fx1)

		--- slen is the raw string length which
		local input_len = (DT and DT.len or v.slen) or 1

		local same_p = true
		if option == 'compact' then
			same_p = v.addr == pack.start + pack.len
		else
			same_p = input_len + v.addr - pack.start < max_len
		end

		if not same_p then
			table.insert(packets, pack)
			pack = { cmd=v.cmd }
			pack.start = v.addr
			pack.inputs = {}
			pack.len = 0
			pack.unpack = function(input, data, index)
				return self:unpack(input, data, index)
			end
		end

		v.pack_index = v.addr - pack.start

		table.insert(pack.inputs, v)
		pack.len = input_len + v.addr - pack.start
	end
	if pack.cmd then
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
