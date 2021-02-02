local _M = {}

-- Duration Seconds
function _M.duration(duration)
	assert(duration, 'Duration missing')

	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)

	if unit == 'd' then
		return c * 3600 * 24
	end
	if unit == 'w' then
		return c * 3600 * 24 * 7
	end
	if unit == 'm' then
		return c * 3600 * 24 * 31  -- max month
	end
	if unit == 'y' then
		return c * 3600 * 24 * 366
	end

	return 0
end

return _M
