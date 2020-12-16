local base = require 'hj212.client.tag'

local tag = base:subclass('HJ212TAG')

function tag:initialize(sn, name, calc, min, max)
	base.initialize(self, sn, name, calc, min, max)
	self._db = nil
	self._value_callback = nil
end

function tag:bind_db(db)
	self._db = db
end

function tag:set_value_callback(cb)
	self._value_callback = cb
end

function tag:set_value(value, timestamp)
	base.set_value(self, value, timestamp)
	if self._value_callback then
		self._value_callback(self._value, timestamp)
	end
end

function tag:on_calc_value(typ, val)
	-- TODO: save to db
end

function tag:query_min_data(start_time, end_time)
	-- Try calc then db
end

function tag:query_hour_data(start_time, end_time)
	-- Try calc then db
end

function tag:query_day_data(start_time, end_time)
	-- Try calc then db
end

return tag
