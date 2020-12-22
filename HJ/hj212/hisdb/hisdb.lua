local class = require 'middleclass'
local index = require 'hisdb.index'
local object = require 'hisdb.object'

local hisdb = class('hisdb.hisdb')

function hisdb:initialize(folder, durations)
	self._index_db = index:new(folder, durations)
	self._meta_map = {}
	self._objects = {}
end

function hisdb:open()
	return self._index_db:open()
end

function hisdb:index_db()
	return self._index_db
end

function hisdb:create_object(key, cate, meta)
	assert(key ~= nil, "Key missing")
	assert(cate ~= nil, "Cate missing")
	assert(meta ~= nil, "Meta missing")

	self._objects[key] = self._objects[key] or {}
	local obj = self._objects[key][cate] 

	if not obj then
		self._meta_map[key] = self._meta_map[key] or {}
		self._meta_map[key][cate] = meta
		obj = object:new(self, key, cate)
		self._objects[key][cate] = obj
	end

	return obj
end

local function key_and_cate(obj)
	return obj:key(), obj:cate()
end

function hisdb:create_store(obj, start_time)
	assert(obj)
	local start_time = start_time or os.time()
	local key, cate = key_and_cate(obj)
	local meta = self._meta_map[key][cate]
	assert(meta)
	return self._index_db:create(key, cate, meta, start_time)
end

function hisdb:find_store(obj, timestamp)
	assert(obj and timestamp)
	local key, cate = key_and_cate(obj)
	return self._index_db:find(key, cate, timestamp)
end

function hisdb:list_store(obj, start_time, end_time)
	assert(obj and start_time and end_time)
	local key, cate = key_and_cate(obj)
	return self._index_db:list(key, cate, start_time, end_time)
end

function hisdb:cleanup(now)
	--- Purge db files each minute
	if (now % 60) == 3 then
		for key, v in pairs(self._objects) do
			for cate, obj in pairs(v) do
				self._index_db:purge(key, cate)
			end
		end
	end
end

return hisdb
