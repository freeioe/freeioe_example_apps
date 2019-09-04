local class = require 'middleclass'

local block = class('MODBUS_APP_DATA_BLOCK')

function block:initialize(data_pack, max_lens)
	self._pack = data_pack
	self._data = {}
	self._data[0x01] = string.rep('\0', 10240)
	self._data[0x02] = string.rep('\0', 10240)
	self._data[0x03] = string.rep('\0\0', 10240)
	self._data[0x04] = string.rep('\0\0', 10240)
end

function block:write(input, value)
	local fc = input.fc
	local addr = input.addr
	local rate = input.rate
	local offset = input.offset
	assert(fc, 'Function code required!')
	assert(addr, 'Address required!')

	local d = self._data[fc]
	if not d then
		return nil, 'Not supported function code!'
	end
	local val = value / input.rate
	if input.dt ~= 'float' and input.dt ~= 'double' then
		val = math.floor(val)
	end
	if input.dt == 'bit' then
		local index = 0
		local bit_offset = 0
		if fc == 0x01 or fc == 0x02 then
			index = addr // 8 -- addresss start from zore
			bit_offset = addr % 8
		else
			index = addr + (offset // 8)
			bit_offset = offset % 8
		end

		local bd = string.sub(d, 1, index)
		local rd = string.sub(d, index + 1, index + 1)
		local ed = string.sub(d, index + 2)

		if val ~= 0 then
			local dv = string.byte(rd) | (1 << bit_offset)
			rd = string.char(dv)
		else
			local dv = string.byte(rd) & ~( 1 << bit_offset)
			rd = string.char(dv)
		end

		self._data[fc] == bd..data.ed
	else
		local dpack = self._pack
		local df = dpack[input.dt]
		if not df then
			return nil, 'Data type not supported!'
		end
		local data, err = df(dpack, val)
		if not data then
			return nil, err
		end

		local index = addr + offset -- addresss start from zore

		local bd = string.sub(d, 1, index)
		local ed = string.sub(d, index + string.len(data) + 1)
		--
		self._data[fc] = bd..data..ed

	end

	return true
end

function block:read(fc, addr, len)
	local d = self._data[fc]
	if not d then
		return nil, 'Not supportted function code!'
	end
	if fc == 0x01 or fc == 0x02 then
		len = math.ceil(len / 8)
	end

	return string.sub(d, addr + 1, addr + len)
end

return block
