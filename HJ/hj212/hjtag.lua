local cjson = require 'cjson.safe'
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
	local calc = m:new(function(type_name, val, timestamp)
		tag:on_sum_value(type_name, val, timestamp)
	end, mask, tag_name, upper_tag)

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

function tag:init_db()
	local sum_calc = self:his_calc()
	local db = hisdb_tag:new(self._hisdb, self:tag_name(), sum_calc:sample_meta())
	local r, err = db:init()
	if not r then
		return nil, err
	end
	sum_calc:set_db(db)
	self._tagdb = db
	return true
end

function tag:save_samples()
	return self._tagdb:save_samples()
end

function tag:set_value_callback(cb)
	self._value_callback = cb
end

function tag:set_value(value, timestamp)
	local value = value 
	if self._calc then
		value = self._calc(value)
		value = math.floor(value * 100000) * 100000
	end
	base.set_value(self, value, timestamp)
	if self._value_callback then
		self._value_callback('value', self._value, timestamp)
	end
end

--- Forward to MQTT application
function tag:on_sum_value(type_name, val, timestamp)
	assert(type_name ~= 'value')
	assert(val and type(val) == 'table')
	local val_str, err = cjson.encode(val)
	if not val_str then
		print(self:tag_name())
		print(val)
		print(type(val))
		for k,v in pairs(val) do
			print(k,v, type(v))
		end
		return
	end
	--print('on_sum_value', self._name, type_name, cjson.encode(val))
	if self._value_callback then
		self._value_callback(type_name, val_str, timestamp)
	end
end

return tag
