local lfs = require 'lfs'
local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local store = require 'hisdb.store'
local utils = require 'hisdb.utils'
local meta = require 'hisdb.meta'

local index = class('hisdb.index')

index.static.DEFAULT_DURATION = '6m'
index.static.VERSION = 6

local db_create_sql = [[
CREATE TABLE "index" (
	"id"		INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"grp"		TEXT NOT NULL,		-- Saving group
	"key"		TEXT NOT NULL,		-- Saving key
	"duration"	TEXT NOT NULL,		-- Duration time string
	"creation"	INTEGER NOT NULL,	-- Db file creation time (seconds since EPOCH)
	"file"		TEXT NOT NULL		-- File path
)
]]

local function init_index_db(folder)
	if not lfs.attributes(folder, 'mode') then
		lfs.mkdir(folder)
	end

	local path = folder..'/index.db'
	local db = assert(sqlite3.open(path))
	local r, err = db:first_row([[SELECT name FROM sqlite_master WHERE type='table' AND name='index']])
	if not r then
		assert(db:exec(db_create_sql))
	end
	return db
end

local function clean_index_db(folder)
	local path = folder..'/index.db'
	os.execute('rm -f '..path)
	if not lfs.attributes(folder, 'mode') then
		return false, "Delete failed"
	end
	return true
end

local function index_key(group, key, creation)
	return string.format('%s/%s/%d', group or 'GRP', key or 'KEY', creation or 0)
end

---
-- default_duration 1d 1m 1y
--
function index:initialize(folder, default_duration)
	self._folder = folder
	self._store_map = {}
	self._default_duration = default_duration or index.static.DEFAULT_DURATION
	self._start = utils.duration_base(self._default_duration, os.time())
	self._version = index.static.VERSION
end

function index:open()
	local db, err = init_index_db(self._folder)
	if not db then
		return nil, err
	end
	self._db = db
	self._meta = meta:new(db)
	self:_load_meta()

	if self._version ~= index.static.VERSION then
		print('Clean db as version diff', self._version, index.static.VERSION)
		self:purge_all()
		self:close()
		local r, err = clean_index_db(self._folder)
		if not r then
			return nil, err
		end
		self._version = index.static.VERSION
		return self:open()
	end

	return true
end

function index:close()
	for key, store in pairs(self._store_map) do
		store:close()
	end
	self._store_map = {}
	self._db:close()
	self._db = nil
	self._meta = nil
end

function index:backup()
	self:close()
	local cmd = string.format('cp %s %s_%d', self._folder, self._folder, os.time())
	os.execute(cmd)
	return self:open()
end

function index:meta()
	return self._meta
end

function index:_load_meta()
	local meta = self._meta
	local val = meta:get('start')
	if not val then
		assert(meta:set('start', self._start))
		assert(meta:set('version', self._version))
		assert(meta:set('default_duration', self._default_duration))
	else
		self._start = tonumber(val)
		local val = meta:get('version')
		if not val then
			self._version = 0
		end
	end

	local val = meta:get('default_duration')
	if val then
		self._default_duration = val
	end
	local val = meta:get('version')
	if val then
		self._version = tonumber(val)
	end
end

function index:db_file(group, key, duration, creation)
	local time_str = os.date('%FT%H%M%S')
	return string.format('%s/%s_%s.%s.sqlite3.db', group, key, duration, time_str)
end

function index:retain_check()
	local db = self._db
	local now = os.time()
	local sql = [[SELECT * FROM 'index' ORDER BY creation ASC]]
	for row in db:rows(sql) do
		--print("INDEX.PURGE", row.id, row.key, row.grp, row.file, row.creation, row.duration)
		local diff = utils.duration_div(row.creation, now, row.duration)
		if diff > 2 then
			self:delete_db_row(row)
		end
	end
end

--- Purge all databases
function index:purge_all()
	for row in self._db:rows("SELECT * FROM 'index'") do
		self:delete_db_row(row)
	end
end

--- Returns Database Objects if exists
--
local purge_select_sql = "SELECT * FROM 'index' WHERE grp='%s' AND key='%s'"
function index:purge(group, key)
	local sql = string.format(purge_select_sql, group, key)
	for row in self._db:rows(sql) do
		self:delete_db_row(row)
	end
end

--- Internal
function index:delete_db_row(row)
	-- Remove db_map
	local key = index_key(row.grp, row.key, row.creation)
	local store = self._store_map[key]
	if store then
		self._store_map[key] = nil
		store:close()
	end

	-- Delete file
	local cmd = string.format('rm -f %s/%s', self._folder, row.file)
	os.execute(cmd)

	-- Purge db
	local sql = "DELETE FROM 'index' WHERE id="..row.id
	self._db:exec(sql)
end

local insert_sql = [[
INSERT INTO 'index' (grp, key, duration, creation, file) VALUES('%s', '%s', '%s', %d, '%s')
]]
function index:create(group, key, duration, timestamp)
	assert(self._db)
	local duration = duration or self._default_duration
	local creation = utils.duration_base(duration, timestamp)

	local obj, err = self:find(group, key, duration, timestamp)
	if obj then
		return obj
	end

	--- Create new database store file
	-- Make sure the sub folder exits
	local sub_folder = string.format('%s/%s', self._folder, group)
	if not lfs.attributes(sub_folder, 'mode') then
		lfs.mkdir(sub_folder)
	end

	--- Insert new now
	local ikey = index_key(group, key, creation)
	local file = self:db_file(group, key, duration, creation)
	local sql = string.format(insert_sql, group, key, duration, creation, file)

	local r, err = self._db:exec(sql)
	if not r then
		return nil, err
	end

	--- Create Store object
	obj = store:new(duration, creation, self._folder..'/'..file, function()
		self._store_map[ikey] = nil
	end)
	-- Open store
	local r, err = obj:_open()
	if not r then
		return nil, err
	end

	--- Set the database map
	self._store_map[ikey] = obj
	return obj
end

--
local find_sql = "SELECT * FROM 'index' WHERE grp='%s' AND key='%s' AND creation=%d"
function index:find(group, key, duration, timestamp)
	assert(group, "Group missing")
	assert(key, "Key missing")
	local duration = duration or self._default_duration
	local creation = utils.duration_base(duration, timestamp)
	local ikey = index_key(group, key, creation)

	local db = self._db
	assert(db)
	if self._store_map[ikey] then
		return self._store_map[ikey]
	end

	for k, v in pairs(self._store_map) do
		assert(tostring(k) ~= tostring(ikey))
	end

	local sql = string.format(find_sql, group, key, creation)

	local row, err = db:first_row(sql)
	if not row then
		return nil, err
	end
	local store = store:new(duration, creation, self._folder..'/'..row.file, function()
		self._store_map[ikey] = nil
	end)
	local r, err = store:_open()
	if not r then
		return nil, err
	end
	self._store_map[ikey] = store
	return store
end

local select_sql = "SELECT * FROM 'index' WHERE grp='%s' AND key='%s' AND creation>=%d AND creation<=%d"
function index:list(group, key, duration, start_time, end_time)
	local duration = duration or self._default_duration
	local stime = utils.duration_base(duration, start_time)
	local etime = utils.duration_base(duration, end_time)

	local db = self._db
	assert(db)
	local sql = string.format(select_sql, group, key, stime, etime)

	local list = {}
	for row in db:rows(sql) do
		--print("INDEX.LIST", row.id, row.key, row.grp, row.file, row.creation, row.duration)

		local ikey = index_key(row.grp, row.key, row.creation)
		local obj = self._store_map[ikey]
		if not obj then
			obj = store:new(row.duration, row.creation, self._folder..'/'..row.file, function()
				self._store_map[ikey] = nil
			end)
			if not obj:_open() then
				obj = nil
				print('INDEX.LIST', 'Store open failed')
			end
		end
		if obj then
			self._store_map[ikey] = obj
			list[#list + 1] = obj
		end
	end

	return list
end

return index
