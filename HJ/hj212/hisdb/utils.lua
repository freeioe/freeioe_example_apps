local date = require 'date'

local _M = {}

local function to_seconds(val)
	return date.diff(val:toutc(), date(0)):spanseconds()
end

-- Duration Start Time
function _M.duration_base(duration, start)
	assert(duration, 'Duration missing')
	local now = start and date(start):tolocal() or date(false) -- local time

	now:setseconds(0)
	now:setminutes(0)
	now:sethours(0)

	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)

	if unit == 'd' then
	end
	if unit == 'm' then
		now:setday(1)
	end
	if unit == 'y' then
		now:setday(1)
		now:setmonth(1)
	end

	return to_seconds(now)
end

-- Duration DIV
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

--- Duration END Time
function _M.duration_add(start_time, duration)
	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)
	local start = date(start_time):tolocal()
	if unit == 'd' then
		return to_seconds(start:adddays(c))
	end
	if unit == 'm' then
		return to_seconds(start:addmonths(c))
	end
	if unit == 'y' then
		return to_seconds(start:addyears(c))
	end
	return nil, 'Invalid duration'
end

function _M.duration_list(start_time, end_time, base, duration)
	local c, unit = string.match(duration, '^(%d+)(%w+)$')
	c = tonumber(c)
	unit = string.lower(unit)
	local list = {}
	local t = date(base):tolocal()
	local ts = date(start_time):tolocal()
	local te = date(end_time):tolocal()
	if unit == 'd' then
		while t <= te do
			if t > ts or t:copy():adddays(c) > ts then
				list[#list + 1] = to_seconds(t)
			end
			list[#list + 1] = t
			if t:adddays(c) > te then
				list[#list + 1] = to_seconds(t)
				break
			end
		end
	end
	if unit == 'm' then
		while t <= te do
			if t > ts or t:copy():addmonths(c) > ts then
				list[#list + 1] = to_seconds(t)
			end
			list[#list + 1] = t
			if t:adddays(1) > te then
				list[#list + 1] = to_seconds(t)
				break
			end
		end
	end
	if unit == 'y' then
		while t <= te do
			if t > ts or t:copy():adddays(1) > ts then
				list[#list + 1] = to_seconds(t)
			end
			list[#list + 1] = t
			if t:adddays(1) > te then
				list[#list + 1] = to_seconds(t)
				break
			end
		end
	end
	return list
end

return _M
