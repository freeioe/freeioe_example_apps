
local DATA_TYPES = {
	bit = function(val)
		if type(val) == 'boolean' then
			return val and 1 or 0
		end
		if val == 0 or val == 1 then
			return val
		end
		return nil, 'Invalid number value'
	end,
	uint8 = function(val)
		if val < 0 or val > 0xFF then
			return nil, 'Invalid number value'
		end
		return val
	end,
	int8 = function(val)
		if val < -128 or val > 127 then
			return nil, 'Invalid number value'
		end
		return val
	end,
	uint16 = function(val)
		if val < 0 or val > 0xFFFF then
			return nil, 'Invalid number value'
		end
		return val
	end,
	int16 = function(val)
		if val < -32768 or val > 32767 then
			return nil, 'Invalid number value'
		end
		return val
	end,
	uint32 = function(val)
		if val < 0 or val > 0xFFFFFFFF then
			return nil, 'Invalid number value'
		end
		return val
	end,
	int32 = function(val)
		if val < -2147483648 or val > 2147483647 then
			return nil, 'Invalid number value'
		end
		return val
	end,
	uint32_r = function(val)
		if val < 0 or val > 0xFFFFFFFF then
			return nil, 'Invalid number value'
		end
		return val
	end,
	int32_r = function(val)
		if val < -2147483648 or val > 2147483647 then
			return nil, 'Invalid number value'
		end
		return val
	end,
	float = function(val)
		return val
	end,
	float_r = function(val)
		return val
	end,
	double = function(val)
		return val
	end,
	double_r = function(val)
		return val
	end,
	raw = function(val)
		return tostring(val)
	end,
	string = function(val)
		return tostring(val)
	end
}

return function(dt, value)
	if not DATA_TYPES[dt] then
		return nil, 'Not support value type '..dt
	end
	local val = value
	if dt ~= 'raw' and dt ~= 'string' then
		val = tonumber(value)
		if not val then
			return nil, "Invalid number input"
		end
		if dt ~= 'float' and dt ~= 'float_r' and dt ~= 'double' and dt ~= 'double_r' then
			val = math.tointeger(val)
			if not val then
				return nil, "Invalid integer numnber"
			end
		end
	end
	return DATA_TYPES[dt](val)
end

