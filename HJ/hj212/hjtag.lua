local calc_parser = require 'calc.parser'

local base = require 'hj212.client.tag'

local tag = base:subclass('HJ212_HJTAG')

local function load_hj212_calc(tag, tag_name, name)
	assert(tag and tag_name)
	local calc_name = name
	if not calc_name then
		if string.sub(tag_name, 1, 1) == 'w' then
			calc_name = 'water'
		elseif string.sub(tag_name, 1, 1) == 'a' then
			calc_name = 'air'
		else
			calc_name = 'simple'
		end
	end

	local m = assert(require('hj212.calc.'..calc_name))

	return m:new(function(typ, val)
		tag:on_sum_value(typ, val)
	end)
end

function tag:initialize(station, name, min, max, sum, calc)
	local sum_calc = load_hj212_calc(self, name, sum)
	base.initialize(self, name, min, max, sum_calc)
	if calc then
		self._calc = calc_parser(station, calc)
	else
		self._calc = nil
	end
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
	local value = self._calc and self._calc(value) or value
	base.set_value(self, value, timestamp)
	if self._value_callback then
		self._value_callback(self._value, timestamp)
	end
end

function tag:on_sum_value(typ, val)
	local cjson = require 'cjson'
	print('on_sum_value', self._name, typ, cjson.encode(val))
end

return tag
