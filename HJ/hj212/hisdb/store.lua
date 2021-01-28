local sqlite3 = require 'sqlite3'
local cjson = require 'cjson.safe'
local class = require 'middleclass'
local utils = require 'hisdb.utils'
local meta = require 'hisdb.meta'

local store = class('hisdb.store')

local meta_example = {
	{
		name = 'timestamp',
		type = 'DOUBLE',
		not_null = true,
		unique = true
	},
	{
		name = 'value',
		type = 'DOUBLE',
		not_null = false
	},
	{
		name = 'value_str',
		type = 'TEXT',
		not_null = false
	}
}

local function meta_to_cols(meta)
	local cols = {'timestamp'}
	for _, v in ipairs(meta) do
		if v.name ~= 'timestamp' then
			cols[#cols + 1] = v.name
		end
	end
	return cols
end

local function check_db_meta(new, old)
	if #new ~= #old then
		return false
	end

	for i, v in ipairs(new) do
		local ov = old[i]
		for k, vv in pairs(v) do
			if vv ~= ov[k] then
				return false
			end
		end
		for k, vv in pairs(ov) do
			if vv ~= v[k] then
				return false
			end
		end
	end

	return true
end

function store:initialize(duration, creation, file, clean_cb)
	assert(creation, "Creation missing")
	assert(duration, "Duration missing")
	assert(file, "File missing")
	self._meta_map = {}
	self._stmts = {}
	self._db = nil
	self._meta = nil
	self._start_time = creation
	self._end_time = utils.duration_add(creation, duration)
	self._file = file
	self._watches = {}
	self._clean_cb = clean_cb
end

function store:start_time()
	return self._start_time
end

function store:end_time()
	return self._end_time
end

function store:in_time(timestamp)
	assert(timestamp)
	return timestamp > self._start_time and timestamp <= self._end_time
end

function store:_open()
	if self._db then
		return
	end
	local db, err = sqlite3.open(self._file)
	if not db then
		local er = string.format('Open db file:%s\terror:%s', self._file, err)
		return nil, er
	end
	self._db = db

	db:exec('PRAGMA journal_mode=wal;')
	--db:exec('PRAGMA temp_store=2;') --- MEMORY
	db:exec('PRAGMA locking_mode=EXCLUSIVE;')

	self._meta = meta:new(db)

	return true
end

function store:add_watch(obj, cb)
	table.insert(self._watches, {obj=obj, cb=cb})
end

function store:remove_watch(obj)
	for i, v in ipairs(self._watches) do
		if v.obj == obj then
			table.remove(self._watches, i)
		end
	end
	self:done()
end

function store:done()
	if #self._watches == 0 then
		self:close()
	end
end

function store:close()
	for k, stmt in pairs(self._stmts) do
		stmt:close()
	end
	self._stmts = {}
	if self._db then
		self._db:close()
		self._db = nil
	end
	for _, v in ipairs(self._watches) do
		v.cb(self)
	end
	self._watches = {}
	self._clean_cb()
end

local table_create_sql = [[
CREATE TABLE 'DATA_%s' (
	"id"	INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"timestamp"	DOUBLE NOT NULL,
%s
)
]]

local table_drop_sql = [[
DROP TABLE 'DATA_%s'
]]

local table_rename_sql = [[
ALTER TABLE 'DATA_%s' RENAME TO 'DATA_%s'
]]

local table_query = [[
SELECT name FROM sqlite_master WHERE type='table' AND name='DATA_%s'
]]

local insert_sql = [[
INSERT INTO 'DATA_%s' (%s) VALUES (%s)
]]

local insert_query = [[
SELECT * FROM 'DATA_%s' WHERE timestamp == %f
]]

local data_query_sql = [[
SELECT * FROM 'DATA_%s' WHERE timestamp >= %f AND timestamp <= %f %s
]]

function store:init(cate, meta, version)
	assert(cate, "Cate missing")
	assert(meta, "Meta missing")
	assert(version, "Meta version missing")

	local tkey = 'table_meta_'..cate

	if not self._meta_map[cate] then
		local old_meta = self._meta:get(tkey)
		local old_version = self._meta:get(tkey..'.ver') or 0
		if old_meta and tonumber(old_version) ~= version then
			self:rename(cate, '_backup_'..cate..'_'..old_version)
			self._meta:set(tkey..'.ver_'..old_version, old_meta)
		end
	else
		if not check_db_meta(meta, self._meta_map[cate]) then
			return nil, "Meta different for this store"
		end
		-- Already inited!
		return true
	end

	assert(self._stmts[cate] == nil)

	local sql_data = {}
	for _, v in ipairs(meta) do
		local col = string.format('\t"%s"\t%s', v.name, v.type)
		if v.default then
			if type(v.default) == 'string' then
				col = col .. string.format(" DEFAULT '%s'", v.default)
			else
				col = col .. string.format(' DEFAULT %s', tostring(v.default))
			end
		end
		if v.not_null then
			col = col .. ' NOT NULL'
		end
		if v.unique then
			col = col ..' UNIQUE'
		end
		--- Skip the timestamp meta
		if v.name ~= 'timestamp' then
			table.insert(sql_data, col)
		end
	end

	local db = self._db
	assert(db)
	local r, err = db:first_row(string.format(table_query, cate))
	if not r then
		local sql = string.format(table_create_sql, cate, table.concat(sql_data, ',\n'))
		--print(sql)

		r, err = db:exec(sql)
		if not r then
			return nil, err
		end
	end

	local cols = meta_to_cols(meta)
	local cols_str = table.concat(cols, ',')
	local fmt_str = ':'..table.concat(cols, ', :')
	local sql_str = string.format(insert_sql, cate, cols_str, fmt_str)
	local stmt, err = self._db:prepare(sql_str)
	if not stmt then
		return nil, err
	end

	self._stmts[cate] = stmt
	self._meta_map[cate] = meta

	self._meta:set(tkey, cjson.encode(meta))
	self._meta:set(tkey..'.ver', tostring(version))

	return true
end

function store:insert(cate, val, is_array)
	assert(cate)
	assert(self._db)

	local stmt = assert(self._stmts[cate])

	if not is_array then
		if not val.timestamp then
			return nil, "Timestamp missing"
		end
		assert(val.timestamp >= self._start_time and val.timestamp < self._end_time)

		local r, err = self._db:first_row(string.format(insert_query, cate, val.timestamp))
		if r then
			return nil, string.format("Duplicated data db:%s data:%s", cjson.encode(r), cjson.encode(val))
		end
		return stmt:bind(val):exec()
	else
		self._db:exec('BEGIN;')
		for _, v in ipairs(val) do
			local r, err = stmt:bind(v):exec()
			if not r then
				return nil, err
			end
		end
		self._db:exec('COMMIT;')
		return true
	end
end

function store:query(cate, start_time, end_time, order_by, limit)
	assert(cate)
	assert(self._db)

	local more = 'ORDER BY '..(order_by or 'timestamp ASC')..(limit and ' '..limit or '')
	local data = {}
	local sql = string.format(data_query_sql, cate, start_time, end_time, more)
	for row in self._db:rows(sql) do
		data[#data + 1] = row
	end

	return data
end

function store:drop(cate)
	assert(cate)
	assert(self._db)
	assert(self._db:exec(string.format(table_drop_sql, cate)))
end

function store:rename(cate, cate_re)
	assert(cate)
	assert(self._db)
	assert(self._db:exec(string.format(table_rename_sql, cate, cate_re)))
end

return store
