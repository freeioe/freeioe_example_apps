local cjson = require 'cjson.safe'
local calc_parser = require 'calc.parser'

local base = require 'hj212.client.tag'
local hisdb_tag = require 'hisdb.tag'

local tag = base:subclass('HJ212_HJTAG')

function tag:initialize(hisdb, station, name, min, max, calc, cou)
	--- Base initialize
	base.initialize(self, station, name, min, max, cou, cou)

	--- Member objects
	self._hisdb = hisdb
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

function tag:init(calc_mgr)
	base.init(self, calc_mgr)
	if not self._tagdb then
		self:init_db()
	end
end

function tag:save_samples()
	if not self._tagdb then
		return nil, "Database is not loaded correctly"
	end
	return self._tagdb:save_samples()
end

function tag:set_value_callback(cb)
	self._value_callback = cb
end

function tag:set_value(value, timestamp)
	local value = value 
	if self._calc then
		value = self._calc(value, timestamp)
		value = math.floor(value * 100000) * 100000
	end
	base.set_value(self, value, timestamp)
	if self._value_callback then
		self._value_callback('value', self._value, timestamp)
	end
end

--- Forward to MQTT application
function tag:on_calc_value(type_name, val, timestamp)
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
	--print('on_calc_value', self._name, type_name, cjson.encode(val))
	if self._value_callback then
		self._value_callback(type_name, val_str, timestamp)
	end
end

return tag
