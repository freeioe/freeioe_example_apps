local cjson = require 'cjson.safe'
local tbl_equals = require 'utils.table.equals'
local calc_parser = require 'calc.parser'

local logger = require 'hj212.logger'
local base = require 'hj212.client.info'

local info = base:subclass('HJ212_HJ_INFO')

function info:initialize(hisdb, poll, props, no_hisdb)
	--- Base initialize
	base.initialize(self, poll)
	self._no_hisdb = no_hisdb

	--- Member objects
	self._hisdb = hisdb
	self._info_props = {}

	local station = poll:station()

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
	local poll_id = self:poll():id()

	local db = self._hisdb:create_info(poll_id, self._no_hisdb)
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

	local org_value, org_tm, org_q = self:get_value()
	local eq = tbl_equals(org_value, value, true)

	if not eq or (self._db and self._db:samples_size() == 0) then
		self._db:push(new_value, timestamp, quality)
	end

	assert( base.set_value(self, new_value, timestamp, quality) )

	if not eq and self._value_callback then
		self._value_callback(base.get_value(self))
	end

	return true
end

return info
