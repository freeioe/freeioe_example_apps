local class = require 'middleclass'
local client = require 'db.siridb.client'
local siri_db = require 'db.siridb.database'
local siri_data = require 'db.siridb.data'
local siri_series = require 'db.siridb.series'

local db = class('tsdb.siridb')

function db:initialize(db_name)
	self._dbname = assert(db_name)
	self._client = client:new({})
end

function db:init()
	local list = self._client:get_databases()
	for _, v in ipairs(list) do
		if v == self._dbname then
			self._db = siri_db:new({}, self._dbname)
			return true
		end
	end
	local r, err = self._client:new_database(self._dbname, 'ms')

	if r then
		self._db = siri_db:new({}, self._dbname)
	end

	return r, err
end

function db:insert(name, vt, value, timestamp)
	local series = siri_series:new(name, vt)
	series:push_value(value, assert(timestamp))
	return self._db:insert_series(series)
end

function db:insert_list(data)
	local db_data = siri_data:new()
	local series_map = {}

	for _, v in ipairs(data) do
		local name, vt, value, timestamp = table.unpack(v)
		local series = series_map[name]
		if not series then
			--print(name, vt)
			series = siri_series:new(name, vt)
			series_map[name] = series
			db_data:add_series(name, series)
		end
		series:push_value(value, assert(timestamp))
	end

	return self._db:insert(db_data)
end

return db
