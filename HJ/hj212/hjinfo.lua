local cjson = require 'cjson.safe'
local calc_parser = require 'calc.parser'

local logger = require 'hj212.logger'
local base = require 'hj212.client.info'

local info = base:subclass('HJ212_HJ_INFO')

local function prop2options(prop)
	return {
		fmt = prop.fmt,
	}
end

function info:initialize(hisdb, station, prop)
	--- Base initialize
	base.initialize(self, station, prop.name, prop2options(prop))
	self._upload = prop.upload
	self._no_hisdb = prop.no_hisdb
	self._hj2005 = prop.hj2005
	self._vt = prop.vt

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

function info:upload()
	return self._upload
end

function info:set_value_callback(callback)
	self._value_callback = callback
end

function info:hj2005_name()
	if not self._hj2005 then
		local finder = require 'hj212.infos.finder'
		local info = finder(self:info_name())
		if info then
			self._hj2005 = info.org_name
		end
	end
	return self._hj2005
end

function info:init_db()
	local db = self._hisdb:create_info(self:info_name(), self._vt, self._no_hisdb)
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

function info:set_value(value, timestamp, quality)
	assert(value ~= nil)
	assert(timestamp ~= nil)

	local value = quality == 0 and value or 0

	if self._calc then
		value = self._calc(value, timestamp)
		value = math.floor(value * 100000) / 100000
	end
	if self._db then
		self._db:push(value, timestamp, quality)
	end
	if self._value_callback then
		self._value_callback(value, timestamp, quality)
	end

	return base.set_value(self, value, timestamp, quality)
end

return info
