local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local utils = require 'hisdb.utils'

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

function store:initialize(meta, creation, duration, file)
	assert(meta, "Meta missing")
	assert(creation, "Creation missing")
	assert(duration, "Duration missing")
	assert(file, "File missing")
	self._meta = meta
	self._start_time = creation
	self._end_time = utils.duration_calc(creation, duration)
	self._file = file
end

function store:start_time()
	return self._start_time
end

function store:end_time()
	return self._end_time
end

function store:in_time(timestamp)
	assert(timestamp)
	return timestamp >= self._start_time and timestamp < self._end_time
end

local data_create_sql = [[
CREATE TABLE "data" (
	"id"	INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"timestamp"	DOUBLE NOT NULL,
%s
);
]]
function store:open()
	if self._db then
		return
	end
	local db, err = sqlite3.open(self._file)
	if not db then
		return nil, err
	end

	local sql_data = {}
	for _, v in ipairs(self._meta) do
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

	local r, err = db:first_row([[SELECT name FROM sqlite_master WHERE type='table' AND name='data';]])
	if not r then
		local sql = string.format(data_create_sql, table.concat(sql_data, ',\n'))
		print(sql)

		r, err = db:exec(sql)
	else
		print('TABLE "store" already exists')
	end

	if r then
		self._db = db
	end
	return r, err
end

function store:close()
	if self._db then
		self._db:close()
		self._db = nil
	end
end

local function check_meta(val, meta)
	local cols = {}
	for _, v in ipairs(meta) do
		if not val[v.name] and v.default == nil then
			return nil, "Missing column value "..v.name
		end
		if v.name ~= 'timestamp' then
			cols[#cols + 1] = v.name
		end
	end
	return val, cols
end

local data_insert_sql = [[
INSERT INTO data (%s) VALUES (%s)
]]
function store:insert(val)
	assert(self._db)

	if not val.timestamp then
		return nil, "Timestamp missing"
	end
	assert(val.timestamp >= self._start_time and val.timestamp < self._end_time)

	local val, cols = check_meta(val, self._meta)
	if not val then
		return nil, cols
	end

	--- Insert timestmap column
	table.insert(cols, 'timestamp')

	local cols_str = table.concat(cols, ',')
	local fmt_str = ':'..table.concat(cols, ', :')
	local sql_str = string.format(data_insert_sql, cols_str, fmt_str)
	local stmt, err = self._db:prepare(sql_str)

	return stmt:bind(val):exec()
end

local data_query_sql = [[
SELECT * FROM data WHERE timestamp >= %d AND timestamp <= %d %s
]]
function store:query(start_time, end_time, order_by, limit)
	assert(self._db)

	local more = 'ORDER BY '..(order_by or 'timestamp ASC')..(limit and ' '..limit or '')
	local data = {}
	local sql = string.format(data_query_sql, start_time, end_time, more)
	for row in self._db:rows(sql) do
		data[#data + 1] = row
	end

	return data
end

return store
