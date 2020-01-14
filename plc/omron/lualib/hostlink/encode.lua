local class = require 'middleclass'

local encode = class('HOSTLINK_DATA_ENCODE')

function encode:short(value)
	return string.format('%04X', value % 0xFFFF)
end

encode.word = encode.short

function encode:sbcd(value)
	if value > 9999 or value < 0 then
		return nil, "SBCD limitation"
	end
	raw = string.format('%04d', value % 0xFFFF)
end

function encode:long(value)
	return string.format('%08X', value % 0xFFFFFFFF)
end

encode.dword = encode.long

function encode:lbcd(value)
	if value > 99999999 or value < 0 then
		return nil, "LBCD limitation"
	end
	return string.format('%08d', value % 0xFFFFFFFF)
end

function encode:float(value)
	local fstr = string.pack('<f', value)
	local sfstr = fstr:sub(2,2)..fstr:sub(1,1)..fstr:sub(4,4)..fstr:sub(3,3)
	local vals = {}
	for i = 1, #sfstr  do
		vals[#vals + 1] = string.format('%02X', string.byte(sfstr, i))
	end
	return table.concat(vals)
end

function encode:fbcd(value)
	if value > 99999999 or value < 0 then
		return nil, "FBCD limitation"
	end
	local nEx = 0
	local bSign = value >= 0.1 and 0 or 1
	while true do
		if value < 1 and value > 0.1 then
			break
		end
		if value >= 1 then
			value = value / 10
		else
			value = value * 10
		end
		nEx = nEx + 1
	end
	local val = 0
	val = (bSign << 3 + nEx)

	for i = 1, 7 do
		value = value * 10
		val = val << 4 + math.floor(value)
	end

	return string.format('%08X', val)
end


function encode:__call(value_type, value)
	local value_type = string.lower(value_type)
	local f = self[value_type]
	if not f then
		return nil, "Unknown value type to encode"
	end

	return f(self, value)
end
