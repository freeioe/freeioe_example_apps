local date = require 'date'

local _M = {}

function _M.duration_div(start_time, end_time, duration)
	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)
	if unit == 'd' then
		return date.diff(date(end_time):tolocal(), date(start_time):tolocal()):spandays() / c
	end
	if unit == 'm' then
		local diff = 0
		local t = date(start_time):tolocal()
		local te = date(end_time):tolocal()
		while t:addmonths(c) < te do
			diff = diff + 1
		end
		return diff
	end
	if unit == 'y' then
		local diff = 0
		local t = date(start_time)
		local te = date(end_time):tolocal()
		while t:addyears(c) < te do
			diff = diff + 1
		end
		return diff
	end
	return nil, 'Invalid duration'
end

function _M.duration_calc(start_time, duration)
	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)
	if unit == 'd' then
		return date.diff(date(start_time):adddays(c):toutc(), date(0)):spanseconds()
	end
	if unit == 'm' then
		return date.diff(date(start_time):addmonths(c):toutc(), date(0)):spanseconds()
	end
	if unit == 'y' then
		return date.diff(date(start_time):addyears(c):toutc(), date(0)):spanseconds()
	end
	return nil, 'Invalid duration'
end

return _M
