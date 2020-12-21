local cjson = require 'cjson.safe'
local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local store = require 'hisdb.store'
local utils = require 'hisdb.utils'

local index = class('hisdb.index')

local db_create_sql = [[
CREATE TABLE "index" (
	"id"		INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"key"		TEXT NOT NULL,		-- Saving key
	"category"	INTEGER NOT NULL,	-- Saving Category
	"file"		TEXT NOT NULL,		-- File path
	"meta"		TEXT NOT NULL,		-- Meta information
	"creation"	INTEGER NOT NULL,	-- Db file creation time (seconds since EPOCH)
	"duration"	TEXT NOT NULL,	-- Duration time (seconds since EPOCH)
);
]]

local function init_index_db(folder)
	local path = self._folder..'/index.db'
	local db = sqlite3.open(path)
	db:exec(db_create_sql)
	return db
end

---
-- duration 1d 1m 1y
function index:initialize(folder, duration)
	self._folder = folder
	self._duration = duration or '6m'
	self._db = init_index_db(self._folder)
	self._db_map = {}
	self._meta = {}
end

function index:set_key_meta(key, meta)
	self._meta[key] = meta
end

--- Returns Database Objects if exists
--
local select_sql = "SELECT * FROM index WHERE key='%s' category='%d' ORDER BY creation DESC"
function index:open(key, cate)
	local db = self._db
	local ind = string.format('%s[%d]', key, cate or 0)
	if self._db_map[ind] then
		return self._db_map[ind]
	end

	local sql = string.format(select_sql, key, cate)
	local data = {}
	for row in db:rows(sql) do
		self._log:debug("INDEX", row.id, row.key, row.category, row.file, row.creation, row.duration)
		table.insert(data)
	end
	if #data == 0 then
		-- Create entry
		return self:create(key, cate)
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
		else
			if diff < 1 then
				cur = v
			end
		end
	end
	if not cur then
		return self:create(key, cate)
	end

	return self:load(cur.meta, cur.creation, cur.duration, cur.file)
end

local insert_sql = 'INSERT INTO index (key, category, file, meta, creation, duration) VALUES(%s, %d, %s, %s, %d, %s)'
function index:create(key, cate)
	local now = os.time()
	local file = string.format('%s/%d_%d_%s.sqlite3.db', key, cate, now, self._duration)
	local meta = self._meta[key] or {}
	local sql = string.format(insert_sql, key, cate, file, cjson.encode(meta), now, self._duration)

	return store:new(meta, now, self._duration, self._folder..'/'..file)
end

function index:load(meta, creation, duration, file)
	local meta = cjson.decode(meta) or self._meta[key] or {}
	return store:new(meta, creation, duration, self._folder..'/'..file)
end

return index
