local class = require 'middleclass'
local index = require 'hisdb.index'
local object = require 'hisdb.object'

local hisdb = class('hisdb.hisdb')

function hisdb:initialize(folder, durations)
	self._durations = durations
	self._index_db = index:new(folder)
	self._objects = {}
	self._group_version = {}
end

function hisdb:open()
	return self._index_db:open()
end

function hisdb:index_db()
	return self._index_db
end

local function index_key(group, key)
	return string.format('%s/%s/%s', group, key)
end

function hisdb:create_object(group, key, cate, version, meta)
	assert(key ~= nil, "Key missing")
	assert(cate ~= nil, "Cate missing")
	assert(meta ~= nil, "Meta missing")
	local duration = self._durations[group]

	self._group_version[group] = self._group_version[group] or {}
	if not self._group_version[group][key] then
		self._group_version[group][key] = version
	else
		assert(self._group_version[group][key] == version)
	end

	local obj, err = object:new(self, group, key, cate, version, meta, duration)
	table.insert(self._objects, obj)
	return obj
end

function hisdb:create_store(obj, start_time)
	assert(obj)
	local start_time = start_time or os.time()
	local db = self._index_db
	return db:create(obj:group(), obj:key(), obj:version(), obj:duration(), start_time)
end

function hisdb:find_store(obj, timestamp)
	assert(obj and timestamp)
	local db = self._index_db
	return db:find(obj:group(), obj:key(), obj:version(), obj:duration(), timestamp)
end

function hisdb:list_store(obj, start_time, end_time)
	assert(obj and start_time and end_time)
	local db = self._index_db
	return db:list(obj:group(), obj:key(), obj:version(), obj:duration(), start_time, end_time)
end

function hisdb:cleanup(now)
	--- Purge db files each minute
	if (now % 60) == 9 then
		self._index_db:retain_check()
	end
end

function hisdb:clean_all()
	return self._index_db:purge_all()
end

return hisdb
