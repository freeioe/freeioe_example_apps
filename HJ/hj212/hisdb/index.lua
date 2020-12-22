local cjson = require 'cjson.safe'
local lfs = require 'lfs'
local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local store = require 'hisdb.store'
local utils = require 'hisdb.utils'

local index = class('hisdb.index')

local info_create_sql = [[
CREATE TABLE "meta" (
	"key"		TEXT PRIMARY KEY UNIQUE,
	"value"		TEXT NOT NULL
);
]]

local db_create_sql = [[
CREATE TABLE "index" (
	"id"		INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"key"		TEXT NOT NULL,		-- Saving key
	"category"	TEXT NOT NULL,		-- Saving Category
	"file"		TEXT NOT NULL,		-- File path
	"meta"		TEXT NOT NULL,		-- Meta information
	"creation"	INTEGER NOT NULL,	-- Db file creation time (seconds since EPOCH)
	"duration"	TEXT NOT NULL		-- Duration time string
);
]]

local function init_index_db(folder)
	local path = folder..'/index.db'
	local db = assert(sqlite3.open(path))
	local r, err = db:first_row([[SELECT name FROM sqlite_master WHERE type='table' AND name='meta';]])
	if not r then
		assert(db:exec(info_create_sql))
	end
	local r, err = db:first_row([[SELECT name FROM sqlite_master WHERE type='table' AND name='index';]])
	if not r then
		assert(db:exec(db_create_sql))
	end
	return db
end

index.static.DEFAULT_DURATION = '6m'

local function index_key(key, cate, creation)
	return string.format('%s-%s-%d', key, cate, creation)
end

---
-- duration 1d 1m 1y default duration
--
function index:initialize(folder, durations)
	self._folder = folder
	self._db_map = {}
	self._duration = index.static.DEFAULT_DURATION
	self._durations = durations or {}
	self._start = nil --- Start base
end

function index:open()
	local db, err = init_index_db(self._folder)
	if not db then
		return nil, err
	end
	self._db = db
	self:load_meta()
	return true
end

function index:load_meta(default_durations)
	local val = self:get_meta('start')
	if not val then
		val = utils.duration_base(self._duration)
		self:set_meta('start', val)
	end
	self._start = val

	local val = self:get_meta('duration')
	if not val then
		val = duration or index.static.DEFAULT_DURATION
		self:set_meta('duration', val)
	end
	self._duration = val

	for k, v in pairs(self._durations) do
		self:set_meta('duration.'..k, v)
	end
end

function index:get_meta(key)
	assert(self._db)
	assert(key)
	for now in self._db:rows('SELECT * FROM meta WHERE key=\''..key..'\'') do
		return now.value
	end
	return nil, 'Not found'
end

function index:set_meta(key, value)
	local sql = [[INSERT INTO meta (key, value) VALUES('%s', '%s')]]
	return self._db:exec(string.format(sql, key, value))
end

--- Returns Database Objects if exists
--
local select_sql = "SELECT * FROM 'index' WHERE key='%s' AND category='%s' ORDER BY creation ASC"
function index:purge(key, cate)
	local db = self._db
	local sql = string.format(select_sql, key, cate)

	local now = os.time()
	for row in db:rows(sql) do
		--print("INDEX.PURGE", row.id, row.key, row.category, row.file, row.creation, row.duration)
		local diff = utils.duration_div(row.creation, now, row.duration)
		if diff >= 2 then
			-- Purge db
			local sql = 'DELETE FROM index WHERE id='..row.id
			assert(db:exec(sql))
			-- Remove db_map
			local key = index_key(key, cate, row.creation)
			self._db_map[key] = nil
		end
	end
end

local insert_sql = [[
INSERT INTO 'index' (key, category, file, meta, creation, duration) VALUES('%s', '%s', '%s', '%s', %d, '%s')
]]
function index:create(key, cate, meta, creation)
	assert(self._db)

	local obj, err = self:find(key, cate, creation)
	if obj then
		--- TODO: Check meta
		return obj
	end

	local duration = self._durations[cate] or self._duration
	local creation = utils.duration_base(duration, creation)

	local sub_folder = string.format('%s/%s', self._folder, cate)
	if not lfs.attributes(sub_folder, 'mode') then
		lfs.mkdir(sub_folder)
	end

	local file = string.format('%s/%s_%d_%s.sqlite3.db', cate, key, creation, duration)
	local meta = meta or {}
	local sql = string.format(insert_sql, key, cate, file, cjson.encode(meta), creation, duration)

	local r, err = self._db:exec(sql)
	if not r then
		return nil, err
	end

	local obj = store:new(meta, creation, duration, self._folder..'/'..file)
	local r, err = obj:open()
	if not r then
		return nil, err
	end

	local key = index_key(key, cate, creation)

	self._db_map[key] = obj
	return obj
end

--
local find_sql = "SELECT * FROM 'index' WHERE key='%s' AND category='%s' AND creation=%d"
function index:find(key, cate, timestamp)
	local duration = self._durations[cate] or self._duration
	local creation = utils.duration_base(duration, timestamp)
	local ikey = index_key(key, cate, creation)

	local db = self._db
	if self._db_map[ikey] then
		return self._db_map[ikey]
	end

	for k, v in pairs(self._db_map) do
		assert(tostring(k) ~= tostring(ikey))
	end

	local sql = string.format(select_sql, key, cate, creation)

	local row, err = db:first_row(sql)
	if not row then
		return nil, err
	end

	local meta = cjson.decode(row.meta) or {}
	local store = store:new(meta, creation, duration, self._folder..'/'..row.file)
	local r, err = store:open()
	if not r then
		return nil, err
	end
	self._db_map[ikey] = store
	return store
end

function index:list(key, cate, start_time, end_time)
	local db = self._db
	assert(db)
	local sql = string.format(select_sql, key, cate)

	local list = {}
	local now = os.time()

	--print(sql)
	for row in db:rows(sql) do
		--print("INDEX.LIST", row.id, row.key, row.category, row.file, row.creation, row.duration)

		local duration = self._durations[cate] or self._duration
		local key = index_key(key, cate, row.creation)
		local obj = self._db_map[key]
		if not obj then
			local meta = cjson.decode(row.meta) or {}
			obj = store:new(meta, creation, duration, self._folder..'/'..file)
			if not obj:open() then
				obj = nil
				print('Store open failed')
			end
		end
		if obj then
			self._db_map[key] = obj
			list[#list + 1] = obj
		end
	end

	return list
end

return index
