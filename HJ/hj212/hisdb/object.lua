local class = require 'middleclass'

local object = class('hisdb.object')

function object:initialize(hisdb, key, cate)
	self._hisdb = hisdb
	self._key = key
	self._cate = cate
	self._store = nil
	self._store_map = {}
end

function object:key()
	return self._key
end

function object:cate()
	return self._cate
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

function object:init()
	local store, err = self._hisdb:create_store(self)
	if not store then
		return nil, err
	end

	self._store_map = {store}
	self._store = store
	return true
end

function object:insert(val)
	assert(self._store)
	local store = self._store
	if not store:in_time(val.timestamp) then
		store = nil
		for _, v in ipairs(self._store_map) do
			if v:in_time(val.timestamp) then
				store = v
			end
		end
	end

	if not store then
		store, err = self._hisdb:find_store(self, val.timestamp)
		if not store then
			return nil, err
		end

		table.insert(self._store_map, store)
		table.sort(self._store_map, function(a, b)
			return a:start_time() < b:start_time()
		end)
	end
	return store:insert(val)
end

function object:query(start_time, end_time)
	assert(start_time and end_time)
	local stores = self._hisdb:list_store(self, start_time, end_time)

	local data = nil
	for _, v in ipairs(stores) do
		local list = v:query(start_time, end_time)
		if not data then
			data = list
		else
			table.move(list, 1, #list, #data + 1, data)
		end
	end

	return data
end

return object
