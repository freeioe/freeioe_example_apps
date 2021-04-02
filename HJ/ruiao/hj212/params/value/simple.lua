local base = require 'hj212.params.value.base'

local simple = base:subclass('hj212.params.value.simple')

local parsers = {
	C = {
		encode = function(fmt, val)
			local count = tonumber(fmt:sub(2))
			assert(count)

			local raw = tostring(val)
			if string.len(raw) > count then
				return raw:sub(0 - count)
			end
			return raw
		end,
		decode = function(fmt, raw)
			local count = tonumber(fmt:sub(2))
			assert(count)

			local val = raw
			if string.len(val) > count then
				val = val:sub(0 - count)
			end
			return val, string.len(val)
		end,
	},
	N = {
		encode = function(fmt, val)
			local i, f = string.match(fmt, 'N(%d+).?(%d*)')
			i = tonumber(i)
			f = tonumber(f)
			assert(i)
			assert(val)
			--[[
			i = val < 0 and i + 1 or i
			local raw = nil
			raw = tostring(math.floor(val))
			if string.len(raw) > i then
				print('length error', raw, i)
				--raw = string.sub(raw, 0 - i)
			end
			if f and string.len(f) > 0 then
				local fraw = tostring(math.floor((val % 1) * (10 ^ f)))
				print(val, i, f, fmt, raw, fraw, (val % 1), 10 ^ f)
				raw = raw..'.'..fraw
			else
				print(val, i, f, fmt, raw)
			end
			]]--
			if f then
				local raw = tostring(val)
				local raw_len = string.len(raw)
				local pi = string.find(raw, '.', 1, true)
				if pi and raw_len > pi + f then
					raw = string.sub(raw, 1, pi + f)
				end
				return raw
			else
				return tostring(math.floor(val))
			end
		end,
		decode = function(fmt, raw)
			--[[
			local i, f = string.match(fmt, 'N(%d+).?(%d*)')
			i = tonumber(i)
			f = tonumber(f)
			assert(i)
			local raw, index = string.match(raw, '^(%d+)()')
			assert(string.len(raw) <= i)

			if f and index < string.len(raw) then
				if string.sub(raw, index) == '.' then
					sub_raw = string.match(raw, '^(%d+)', index)
					if string.len(sub_raw) > f then
						sub_raw = string.sub(sub_raw, 0 - f)
					end
					index = index + string.len(sub_raw) + 1
					raw = raw..'.'..sub_raw
				else
					assert(false, "Error string")
				end
			end

			return tonumber(raw), index
			]]
			return tonumber(raw), string.len(raw)
		end,
	},
}

function simple:initialize(name, value, fmt)
	base.initialize(self, name, value)
	self._format = fmt
end

function simple:format()
	return self._format
end

function simple:encode()
	assert(self._value)
	if not self._format then
		return tostring(self._value)
	end

	local fmt = string.sub(self._format, 1, 1)
	local parser = assert(parsers[fmt])

	return parser.encode(self._format, self._value)
end

function simple:decode(raw)
	if not self._format then
		self._value = tonumber(raw) or raw
		return string.len(raw)
	end

	local fmt = string.sub(self._format, 1, 1)
	local parser = assert(parsers[fmt])

	self._value, index = parser.decode(self._format, raw)
	return index
end

simple.static.EASY = function(pn, fmt)
	local sub = simple:subclass(pn)
	function sub:initialize(name, value)
		simple.initialize(self, name, value, fmt)
	end
	return sub
end

return simple
