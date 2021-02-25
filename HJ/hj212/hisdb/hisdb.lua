local class = require 'middleclass'
local index = require 'hisdb.index'
local object = require 'hisdb.object'
local tag = require 'hisdb.tag'
local info = require 'hisdb.info'
--local treatment = require 'hisdb.treatment'

local hisdb = class('hisdb.hisdb')

function hisdb:initialize(folder, durations, default_duration)
	self._durations = durations
	self._index_db = index:new(folder, default_duration)
	self._objects = {}
	self._version_check = {}
end

function hisdb:open()
	return self._index_db:open()
end

function hisdb:close()
	return self._index_db:close()
end

function hisdb:index_db()
	return self._index_db
end

local function index_key(group, key, cate)
	return string.format('%s/%s/%s', group, key, cate)
end

function hisdb:create_object(group, key, cate, meta, version)
	assert(key ~= nil, "Key missing")
	assert(cate ~= nil, "Cate missing")
	assert(meta ~= nil, "Meta missing")
	local duration = self._durations[group]

	local ikey = index_key(group, key, cate)
	if not self._version_check[ikey] then
		self._version_check[ikey] = version
	else
		assert(self._version_check[ikey] == version)
	end

	local obj, err = object:new(self, group, key, cate, meta, version, duration)
	table.insert(self._objects, obj)
	return obj
end

function hisdb:create_store(obj, start_time)
	assert(obj, 'Object missing')
	assert(start_time, 'Start time missing')
	local start_time = start_time or os.time()
	local db = self._index_db
	return db:create(obj:group(), obj:key(), obj:duration(), start_time)
end

function hisdb:find_store(obj, timestamp)
	assert(obj and timestamp)
	local db = self._index_db
	return db:find(obj:group(), obj:key(), obj:duration(), timestamp)
end

function hisdb:list_store(obj, start_time, end_time)
	assert(obj and start_time and end_time)
	local db = self._index_db
	return db:list(obj:group(), obj:key(), obj:duration(), start_time, end_time)
end

function hisdb:retain_check()
	--- Purge db files each minute
	self._index_db:retain_check()
end

function hisdb:purge_all()
	return self._index_db:purge_all()
end

function hisdb:create_tag(...)
	return tag:new(self, ...)
end

function hisdb:create_info(...)
	return info:new(self, ...)
end

--[[
function hisdb:create_treatment(...)
	return treatment:new(self, ...)
end
]]--

return hisdb
