local cjson = require 'cjson.safe'
local calc_parser = require 'calc.parser'

local logger = require 'hj212.logger'
local base = require 'hj212.client.poll'

local poll = base:subclass('HJ212_HJTAG')

local function prop2options(prop)
	if not prop.cou_calc then
		return {
			min = prop.min,
			max = prop.max,
			fmt = prop.fmt,
			cou = {
				cou = prop.cou,
			},
			zs_calc = prop.zs_calc
		}
	end

	local cou_calc, params = string.match(prop.cou_calc, '^(.+)({.+})')
	if cou_calc and params then
		params = cjson.decode(params)
	else
		cou_calc = prop.cou_calc
	end

	return {
		min = prop.min,
		max = prop.max,
		fmt = prop.fmt,
		cou = {
			calc = cou_calc,
			cou = prop.cou,
			params = params,
		},
		zs_calc = prop.zs_calc
	}
end

function poll:initialize(hisdb, station, prop, info_creator)
	--- Base initialize
	if prop.zs and string.upper(prop.zs) == 'SRC' then
		prop.zs_calc = true
	elseif prop.zs then
		prop.zs_calc = calc_parser(station, prop.zs)
	end
	base.initialize(self, station, prop.name, prop2options(prop), info_creator)
	self._upload = prop.upload
	self._no_hisdb = prop.no_hisdb
	self._hj2005 = prop.hj2005

	--- Member objects
	self._hisdb = hisdb
	local calc = prop.calc
	if calc then
		--- Value calc
		self._calc = calc_parser(station, calc)
	else
		self._calc = nil
	end
	self._value_callback = nil
end

function poll:upload()
	return self:inited() and self._upload
end

function poll:hj2005_id()
	if not self._hj2005 then
		local finder = require 'hj212.tags.finder'
		local poll = finder(self:id())
		if poll then
			self._hj2005 = poll.org_id
		end
	end
	return self._hj2005
end

function poll:init_db()
	local cou_calc = self:cou_calc()
	local db = self._hisdb:create_poll(self:id(), self._no_hisdb)
	local r, err = db:init()
	if not r then
		return nil, err
	end
	cou_calc:set_db(db)
	self._polldb = db
	return true
end

function poll:init(calc_mgr)
	base.init(self, calc_mgr)
	return self:init_db()
end

function poll:save_samples()
	if not self._polldb then
		return nil, "Database is not loaded correctly"
	end
	return self._polldb:save_samples()
end

function poll:set_value_callback(cb)
	self._value_callback = cb
end

function poll:set_value(value, timestamp, value_z, flag, quality, ex_vals)
	assert(value ~= nil)
	assert(timestamp ~= nil)
	local value = (quality or 0) == 0 and value or 0
	local value_z = value_z and ((quality or 0) == 0 and value_z or 0) or nil

	if self._calc then
		value = self._calc(value, timestamp)
		value = math.floor(value * 100000) / 100000
		if value_z ~= nil then
			value_z = self._calc(value_z, timestamp)
			value_z = math.floor(value_z * 100000) / 100000
		end
	end
	return base.set_value(self, value, timestamp, value_z, flag, quality, ex_vals)
end

--- Forward to MQTT application
function poll:on_calc_value(type_name, val, timestamp, quality)
	assert(type_name ~= 'value')
	assert(val and type(val) == 'table')
	--print('on_calc_value', self._name, type_name, timestamp, cjson.encode(val))
	if self._value_callback then
		self._value_callback(type_name, val, timestamp, quality)
	end
	return val
end

return poll
