local class = require 'middleclass'
local cjson = require 'cjson.safe'

local info = class("HJ212_APP_HISDB_INFO_DB")

--[[ FIXME:

local DB_VER = 1 -- version

function info:initialize(hisdb, info_name, vt, no_db)
	self._hisdb = hisdb
	self._info_name = info_name
	self._vt = vt -- vt is not used in sqlite
	self._samples = {}
	self._no_db = no_db
	self._db = nil
end

function info:sample_meta()
	return {
		{ name = 'timestamp', type = 'DOUBLE', not_null = true },
		-- Values
		{ name = 'value', type = 'TEXT', not_null = true },
	}, DB_VER
end

function info:init()
	if self._no_db then
		return true
	end

	local sample_meta, sample_ver = self:sample_meta()

	local hisdb = self._hisdb
	self._db = hisdb:create_object('INFO', 'INFO', self._info_name, sample_meta, sample_ver)
	return self._db:init()
end

function info:push(value, timestamp, quality)
	local val = type(value) ~= 'table' and value or cjson.encode(value)
	table.insert(self._samples, {value = val, timestamp = timestamp, quality = quality})
	if #self._samples > 3600 then
		assert(nil, 'Info Name:'..self._info_name..'\t reach max sample data unsaving')
		self._samples = {}
	end
end

function info:save()
	local list = self._samples
	if #list == 0 then
		return true
	end
	self._samples = {}
	if not self._db then
		return nil, "Not found db for info"
	end
	return self._db:insert(list, true)
end

function info:read(start_time, end_time)
	if not self._db then
		return nil, "Not found db for info"
	end
	return self._db:query(start_time, end_time)
end

return info
]]--
