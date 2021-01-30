local class = require 'middleclass'
local client = require 'db.siridb.client'
local database = require 'db.siridb.database'

local hisdb = class('hisdb.hisdb')

hisdb.static.DEFAULT_DURATION = '10w' -- ten weeks

function hisdb:initialize(dbname, durations, default_duration, db_options)
	local def_duration = default_duration or hisdb.static.DEFAULT_DURATION
	local db_list = {
		DEFAULT = { name = dbname, duration = def_duration}
	}
	for cate, duration in pairs(durations) do
		db_list[cate] = { name = dbname..'_'..cate, duration = duration }
	end
	self._db_list = db_list
	self._db_options = db_options or {}
	self._client = client:new(self._db_options)
end

function hisdb:open()
	local list = self._client:get_databases()
	local list_map = {}
	for _, v in ipairs(list) do
		list_map[v] = v
	end

	for cate, db in pairs(self._db_list) do
		if not list_map[db.name] then
			local r, err = self._client:new_database(db.name, 'ms', 1024, db.duration)
			if not r then
				return nil, err
			end
			db.db = database:new(self._db_options, db.name)
		else
			db.db = database:new(self._db_options, db.name)
			db.db:exec('alter database set expiration_num '..db.duration..' set ignore_threshold true')
		end
	end

	return true
end

function hisdb:client()
	return assert(self._client)
end

function hisdb:db(cate)
	assert(cate)
	local db = assert(self._db_list[cate] or self._db_list.DEFAULT)
	return db.db
end

function hisdb:retain_check()
end

return hisdb
