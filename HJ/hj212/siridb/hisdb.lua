local class = require 'middleclass'
local client = require 'db.siridb.client'
local database = require 'db.siridb.database'
local tag = require 'siridb.tag'
local utils = require 'siridb.utils'

local hisdb = class('siridb.hisdb')

hisdb.static.DEFAULT_DURATION = '10w' -- ten weeks

function hisdb:initialize(dbname, durations, default_duration, db_options)
	local def_duration = utils.duration(default_duration or hisdb.static.DEFAULT_DURATION)
	local db_list = {
		DEFAULT = { name = dbname, expiration = def_duration * 1000}
	}
	--local default_expiration = utils.duration('1m')
	for cate, duration in pairs(durations) do
		local duration = utils.duration(duration)
		db_list[cate] = {
			name = dbname..'_'..cate,
			--duration = duration > default_expiration * 2 and default_expiration or math.ceil(duration / 2),
			duration = 0, -- auto duration is enabled in siridb configuration
			expiration = duration * 1000,
		}
	end
	self._db_list = db_list
	self._db_options = db_options or {}
	self._client = client:new(self._db_options)
end

function hisdb:open()
	local list, err = self._client:get_databases()
	if not list then
		return nil, err
	end
	local list_map = {}
	for _, v in ipairs(list) do
		list_map[v] = v
	end

	for cate, db in pairs(self._db_list) do
		--print(db.name, db.expiration, db.duration)
		if not list_map[db.name] then
			local r, err = self._client:new_database(db.name, 'ms', 1024, db.duration)
			if not r then
				return nil, err
			end
			db.db = assert(database:new(self._db_options, db.name))
		else
			local dbi = database:new(self._db_options, db.name)

			local data, err = dbi:exec('show time_precision')
			if not data then
				return nil, err
			end
			if data.data[1].value ~= 'ms' then
				return nil, "time_precision is not ms"
			end

			--Check expiration
			local data, err = dbi:exec('show expiration_num')
			if not data then
				return nil, err
			end

			local num = tonumber(data.data and data.data[1] and data.data[1].value or 0) or 0
			if num ~= db.expiration then
				--print('Correct expriation:', num, db.expiration)
				dbi:exec('alter database set expiration_num '..db.expiration..' set ignore_threshold true')
			end
			db.db = assert(dbi)
		end
	end

	return true
end

function hisdb:close()
	return true
end

function hisdb:client()
	return assert(self._client)
end

function hisdb:db(cate)
	assert(cate)
	local db = assert(self._db_list[cate] or self._db_list.DEFAULT)
	return assert(db.db)
end

function hisdb:retain_check()
end

function hisdb:purge_all()
	-- TODO:
end

function hisdb:create_tag(...)
	return tag:new(self, ...)
end

return hisdb
