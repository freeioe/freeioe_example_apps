local cjson = require 'cjson.safe'
local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local store = require 'hisdb.store'
local utils = require 'hisdb.utils'
local index_key = require 'hisdb.index_key'

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
	"duration"	TEXT NOT NULL	-- Duration time (seconds since EPOCH)
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

---
-- duration 1d 1m 1y
function index:initialize(folder, duration)
	self._folder = folder
	self._db = init_index_db(self._folder)
	self._db_map = {}
	self._duration = nil --- Default duration
	self._start = nil --- Start base
	self:load_meta()
end

function index:load_meta()
	local val = self:get_meta('duration')
	if not val then
		val = duration or '6m'
		self:set_meta('duration', val)
	end
	self._duration = val
	local val = self:get_meta('start')
	if not val then
		val = utils.duration_base(self._duration)
		self:set_meta('start', val)
	end
	self._start = val
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
local select_sql = "SELECT * FROM index WHERE key='%s' AND category='%s' ORDER BY creation ASC"
function index:purge(key, cate)
	local db = self._db
	local sql = string.format(select_sql, key, cate)
	local data = {}
	for row in db:rows(sql) do
		self._log:debug("INDEX", row.id, row.key, row.category, row.file, row.creation, row.duration)
		table.insert(data)
	end
	if #data == 0 then
		return
	end

	local cur = nil
	local now = os.time()
	for i, v in ipairs(data) do
		local diff = utils.duration_div(v.creation, now, v.duration)
		if diff >= 2 then
			-- Purge db
			local sql = 'DELETE FROM index WHERE id='..v.id
			db:exec(sql)
			table.remove(data, i)
			-- Remove db_map
			local key = index_key:new(key, cate, v.creation)
			self._db_map[key] = nil
		else
			if diff < 1 then
				cur = v
			end
		end
	end
end

local insert_sql = [[
INSERT INTO index (key, category, file, meta, creation, duration) VALUES('%s', '%s', '%s', '%s', %d, '%s')
]]
function index:create(key, cate, meta, creation)
	local creation = utils.duration_base(duration, creation)
	local file = string.format('%s/%s_%d_%s.sqlite3.db', key, cate, creation, self._duration)
	local meta = meta or {}
	local sql = string.format(insert_sql, key, cate, file, cjson.encode(meta), creation, self._duration)

	self._db:exec(sql)

	local obj = store:new(meta, creation, self._duration, self._folder..'/'..file)
	local key = index_key:new(key, cate, creation)
	self._db_map[key] = obj
	return obj
end

--
local find_sql = "SELECT * FROM index WHERE key='%s' AND category='%s' AND creation=%d"
function index:find(key, cate, timestamp)
	local creation = utils.duration_base(timestamp)
	local key = index_key:new(key, cate, creation)

	local db = self._db
	if self._db_map[key] then
		return self._db_map[key]
	end

	local sql = string.format(select_sql, key, cate, creation)
	local cur = nil
	for row in db:rows(sql) do
		if row.creation == creation then
			cur = row
			break
		end
	end

	if not cur then
		return nil, "Store not found for time "..creation
	end

	local meta = cjson.decode(meta) or {}
	return store:new(meta, creation, duration, self._folder..'/'..file)
end

function index:list(key, cate, start_time, end_time)
	local db = self._db
	local sql = string.format(select_sql, key, cate)
	local data = {}
	for row in db:rows(sql) do
		self._log:debug("INDEX", row.id, row.key, row.category, row.file, row.creation, row.duration)
		table.insert(data)
	end
	if #data == 0 then
		return {}
	end

	local list = {}
	local now = os.time()
	for i, v in ipairs(data) do
		local key = index_key:new(key, cate, v.creation)
		local obj = self._db_map[key]
		if not obj then
			local meta = cjson.decode(meta) or {}
			obj = store:new(meta, creation, duration, self._folder..'/'..file)
		end
		self._db_map[key] = obj
		list[#list + 1] = obj
	end

	return list
end

return index
