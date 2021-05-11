local class = require 'middleclass'
local utils = require 'hisdb.utils'

local object = class('hisdb.object')

function object:initialize(hisdb, group, key, cate, meta, version, duration)
	self._hisdb = hisdb
	self._group = group
	self._key = key
	self._cate = cate
	self._meta = meta
	self._version = version
	self._duration = duration
	self._store = nil
end

function object:key()
	return self._key
end

function object:group()
	return self._group
end

function object:cate()
	return self._cate
end

function object:version()
	return self._version
end

function object:duration()
	return self._duration
end

function object:meta()
	return self._meta
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
	local r, err = self:get_store(os.time())
	if r then
		return true
	end
	return nil, err
end

function object:set_store(store)
	if self._store then
		self._store:remove_watch(self)
	end
	assert(store:init(self._cate, self._meta, self._version))
	store:add_watch(self, function(store)
		if store == self._store then
			self._store = nil
		end
	end)
	self._store = store
end

function object:get_store(timestamp)
	local store = self._store
	if store then
		if store:in_time(timestamp) then
			return store
		end
	end

	--- Switch to correct store (normally it is an new created)
	local store, err = self._hisdb:create_store(self, os.time())
	if not store then
		return nil, err
	end

	self:set_store(store)

	return store
end

function object:insert(val, is_array)
	assert(is_array and #val > 0 or true)

	local v = is_array and val[1] or val

	local store, err = self:get_store(v.timestamp)
	if not store then
		return nil, err
	end

	if not is_array then
		return store:insert(self._cate, v)
	else
		local last = val[#val]
		--- All data in current store then insert them
		if store:in_time(last.timestamp) then
			return store:insert(self._cate, val, true)
		else
			local val_list = {}
			local left = {}
			for _, v in ipairs(val) do
				if store:in_time(v.timestamp) then
					val_list[#val_list + 1] = v
				else
					left[#left + 1] = v
				end
			end
			--- Insert current
			local r, err = store:insert(self._cate, val_list, true)
			if not r then
				return nil, err
			end
			--- Insert left
			return self:insert(left, true)
		end
	end
end

function object:query(start_time, end_time)
	assert(start_time and end_time)
	local stores = self._hisdb:list_store(self, start_time, end_time)

	local data = {}
	for _, v in ipairs(stores) do
		local list = v:query(self._cate, start_time, end_time)
		if list and #list > 0 then
			table.move(list, 1, #list, #data + 1, data)
		end
		v:done()
	end

	return data
end

return object
