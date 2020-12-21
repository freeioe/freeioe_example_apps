local sqlite3 = require 'sqlite3'
local class = require 'middleclass'
local utils = require 'hisdb'

local store = class('hisdb.store')

function store:initialize(meta, creation, duration, file)
	self._meta = meta
	self._creation = creation
	self._duration = utils.duration_calc(creation, duration)
	self._file = file
	self._pre = nil
	self._nex = nil
	self:open()
end

function store:set_chain(pre, nex)
	self._pre = pre
	self._nex = nex
end

function store:switch(file)
	self._file = file
	self:close()
	self:open()
end

local his_create_sql = [[
CREATE TABLE "his" (
	"id"	INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"timestamp"	DOUBLE NOT NULL,
	%s
);
]]
function store:open()
	if self._db then
		return
	end
	local db = sqlite3.open(self._file)

	local sql_data = {}
	for _, v in ipairs(self._meta) do
		local col = string.format('\t"%s"\t%', v.name, v.type)
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
		table.insert(sql_data, col)
	end

	local sql = string.format(his_create_sql, table.concat(sql_dta, '\n'))
	print(sql)

	db:exec(sql)
	self._db = db
end

function store:close()
	if self._db then
		self._db:close()
		self._db = nil
	end
end

local function check_meta(val, meta)
	local cols = {}
	for _, v in ipairs(self._meta) do
		if not val[v.name] and v.default == nil then
			return nil, "Missing column value "..v.name
		end
		cols[#cols + 1] = v.name
	end
	return val, cols
end

local his_insert_sql = [[
INSERT INTO his (%s) VALUES (%s)
]]
function store:insert(val)
	if not val.timestamp then
		return nil, "Timestamp missing"
	end
	if val.timestamp < self._creation then
		assert(self._pre, 'Value timestamp earlier than creation')
		return self._pre:insert(val)
	end
	if val.timestamp > self._duration then
		assert(self._pre, 'Value timestamp later than duration')
		return self._nex:insert(val)
	end

	local val, cols = check_meta(val, meta)
	if not val then
		return nil, cols
	end

	--- Insert timestmap column
	table.insert(cols, 'timestamp')

	local cols_str = table.concat(cols, ',')
	local fmt_str = ':'..table.concat(cols, ', :')
	local stmt, err = self._db:prepare(string.format(his_insert_sql, cols_str, fmt_str))

	return stmt:bind(val):exec()
end

local his_query_sql = [[
SELECT * FROM his WHERE timestamp >= %d AND timestamp <= %d %s
]]
function store:query(start_time, end_time, order_by, limit)
	local more = (order_by or 'DESC')..(limit and ' '..limit or '')
	local data = {}
	for row in db:rows(string.format(his_query_sql, start_time, end_time, more)) do
		data[#data + 1] = row
	end

	return data
end

return store
