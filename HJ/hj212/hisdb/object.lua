local class = require 'middleclass'

local object = class('hisdb.object')

local attrs_example = {
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

function object:initialize(hisdb, key, cate, attrs)
	self._hisdb = hisdb
	self._attrs = attrs
	self._db_map = {}
end

--[[
function object:create_sql(db_name)
	local sql = 'CREATE TABLE "'..db_name'" (\n\t"id"\tINTERGER UNIQUE,\n'
	for k, v in pairs(self._cols) do
		local col = string.format('\t"%s"\t%s', v.name, v.col_type)
		if v.not_null then
			col = col..' NOT NULL'
		end
		if v.unique then
			col = col..' UNIQUE'
		end
		sql = sql..col..'\n'
	end
	return sql..'\tPRIMARY KEY("id" AUTOINCREMENT)\n);'
end
]]--

function object:insert(val)
end

function object:query(start_time, end_time)
end

return object
