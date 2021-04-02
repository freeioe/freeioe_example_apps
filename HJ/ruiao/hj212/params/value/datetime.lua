local base = require 'hj212.params.value.base'
local date = require 'date'

local param = base:subclass('hj212.params.value.datetime')

local date_fmt = '%Y%m%d%H%M%S'

function param:encode()
	return date(self._value):tolocal():fmt(date_fmt)
end

function param:decode(raw)
	local time_raw = string.sub(raw, 1, 14)
	self._value = math.floor(date.diff(date(time_raw):toutc(), date(0)):spanseconds())
	return 14
end

return param
