local class = require 'middleclass'
local prom_db = require 'db.prometheus.database'
local prom_data = require 'db.prometheus.data'
local prom_metric = require 'db.prometheus.metric'

local db = class('tsdb.prometheus')

function db:initialize(db_name)
	self._dbname = assert(db_name)
end

function db:init()
	self._db = prom_db:new({
		host = '127.0.0.1',
		port = 8428,
		url = '/api/v1/import/prometheus'
	})
	return true
end

function db:insert(name, vt, value, timestamp)
	if vt == 'string' then
		return --- float cannot be used in prometheus
	end

	local metric = prom_metric:new(name)
	metric:push_value(value, assert(timestamp))
	return self._db:insert_metric(metric)
end

return db
