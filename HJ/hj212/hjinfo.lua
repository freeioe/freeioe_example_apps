local cjson = require 'cjson.safe'
local tbl_equals = require 'utils.table.equals'
local calc_parser = require 'calc.parser'

local logger = require 'hj212.logger'
local base = require 'hj212.client.info'

local info = base:subclass('HJ212_HJ_INFO')

function info:initialize(hisdb, tag, props, no_hisdb)
	--- Base initialize
	base.initialize(self, tag)
	self._no_hisdb = no_hisdb

	--- Member objects
	self._hisdb = hisdb
	self._info_props = {}

	local station = tag:station()

	for _, prop in ipairs(props) do
		local p = {
			fmt = prop.fmt
		}

		local calc = prop.calc
		if calc then
			--- Value calc
			p.calc = calc_parser(station, calc)
		end

		self._info_props[prop.name] = p
	end

	self._value_callback = nil
end

function info:set_value_callback(callback)
	self._value_callback = callback
end

function info:init_db()
	local tag_name = self:tag():tag_name()

	local db = self._hisdb:create_info(tag_name, self._no_hisdb)
	local r, err = db:init()
	if not r then
		return nil, err
	end
	self._db = db
	return true
end

function info:init()
	return self:init_db()
end

function info:save_samples()
	if not self._db then
		return nil, "Database is not loaded correctly"
	end
	return self._db:save()
end

function info:get_format(info_name)
	local p = self._info_props[info_name]
	if not p then
		return nil
	end

	return p.fmt
end

function info:set_value(value, timestamp, quality)
	assert(value ~= nil)
	assert(timestamp ~= nil)

	local new_value = {}
	for info, val in pairs(value) do
		local val = quality == 0 and val or 0
		local p = self._info_props[info]

		if p and p.calc then
			val = p.calc(val, timestamp)
			val = math.floor(val * 100000) / 100000
		end

		-- TODO:
		new_value[info] = val
	end

	if self._db then
		self._db:push(new_value, timestamp, quality)
	end
	if self._value_callback then
		local org_value, org_tm, org_q = self:get_value()
		if not tbl_equals(org_value, value, true) then
			self._value_callback(new_value, timestamp, quality)
		end
	end

	return base.set_value(self, new_value, timestamp, quality)
end

return info
