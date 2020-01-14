local class = require 'middleclass'

local decode = class('HOSTLINK_DATA_DECODE')

function decode:short(raw)
	return tonumber(string.sub(raw, 1, 4), 16)
end

decode.word = decode.short

function decode:sbcd(raw)
	return tonumber(string.sub(raw, 1, 4))
end

function decode:long(raw)
	return tonumber(string.sub(raw, 1, 8), 16)
end

decode.dword = decode.long

function decode:lbcd(raw)
	return tonumber(string.sub(raw, 1, 8))
end

function decode:float(raw)
	local fstr  = ''
	for i = 0, 3 do
		local sraw = string.sub(raw, i * 2 + 1, i * 2 + 2)
		fstr = fstr .. string.char(tonumber(sraw, 16))
	end
	local str = fstr:sub(2,2)..fstr(1,1)..fstr(4,4)..fstr(3,3)

	return string.unpack('<f', value)
end

function decode:fbcd(raw)
	-- TODO:
end

function decode:__call(raw, value_type)
	local value_type = string.lower(value_type)
	local f = self[value_type]
	if not f then
		return nil, "Not supported value type"
	end

	return f(self, raw)
end


return decode


