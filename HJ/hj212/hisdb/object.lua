local class = require 'middleclass'

local object = class('hisdb.object')

function object:initialize(hisdb, key, cate)
	self._hisdb = hisdb
	self._key = key
	self._cate = cate
	self._store = nil
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
	local r, err = self:get_store()
	if r then
		return true
	end
	return nil, err
end

function object:set_store(store)
	if self._store then
		self._store:set_watch(nil)
	end
	store:set_watch(function(store)
		if store == self._store then
			self._store = nil
		end
	end)
	self._store = store
end

function object:get_store()
	if self._store then
		return self._store
	end

	local store, err = self._hisdb:create_store(self)
	if not store then
		return nil, err
	end

	self:set_store(store)

	return self._store
end

function object:insert(val)
	local store = self:get_store()
	if not store:in_time(val.timestamp) then
		store, err = self._hisdb:find_store(self, val.timestamp)
		if not store then
			return nil, err
		end
		self:set_store(store)
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
