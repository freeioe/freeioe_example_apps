local calc_parser = require 'calc.parser'

local base = require 'hj212.client.tag'
local hisdb_tag = require 'hisdb.tag'

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

	--- TODO: Mask and Upper Tag
	local calc = m:new(function(typ, val)
		tag:on_sum_value(typ, val)
	end, mask, upper_tag)

	local db = hisdb_tag:new(hisdb, name)
	calc:set_db(db)

	return calc
end

function tag:initialize(hisdb, station, name, min, max, sum, calc)
	--- Sumation calculation
	local sum_calc = load_hj212_calc(self, name, sum)

	--- Base initialize
	base.initialize(self, name, min, max, sum_calc)

	--- Member objects
	self._hisdb = hisdb
	self._station = station
	if calc then
		--- Value calc
		self._calc = calc_parser(station, calc)
	else
		self._calc = nil
	end
	self._value_callback = nil
	self._sum_callback = nil
end

function tag:set_value_callback(cb)
	self._value_callback = cb
end

function tag:set_sum_callback(cb)
	self._sum_callback = cb
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
	self._sum_callback(typ, val)
end

return tag
