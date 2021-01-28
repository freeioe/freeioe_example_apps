local base = require 'hj212.calc.db'
local siri_data = require 'db.siridb.data'
local siri_series = require 'db.siridb.series'

local tag = base:subclass('hisdb.tag')

function tag:initialize(hisdb, tag_name)
	self._hisdb = hisdb
	self._db = hisdb:db()
	self._tag_name = tag_name
	self._samples = {}
	self._value_type_map = {}
end

local function map_value_type(v_type)
	if v_type == 'DOUBLE' then
		return 'float'
	elseif v_type == 'INTEGER' then
		return 'int'
	else
		return 'string'
	end
end

function tag:init()
	local meta = self:sample_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['SAMPLE.'..v.name] = map_value_type(v.type)
	end
	meta = self:rdata_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['RDATA.'..v.name] = map_value_type(v.type)
	end
	meta = self:cou_meta()
	for _, v in ipairs(meta) do
		self._value_type_map['MIN.'..v.name] = map_value_type(v.type)
		self._value_type_map['HOUR.'..v.name] = map_value_type(v.type)
		self._value_type_map['DAY.'..v.name] = map_value_type(v.type)
	end

	return true
end

function tag:get_value_type(cate, prop)
	local k = cate..'.'..prop
	local vt = self._value_type_map[k]
	if vt then
		return vt
	end
	return 'string'
end

function tag:push_sample(data)
	table.insert(self._samples, data)
	if #self._samples > 3600 then
		assert(nil, 'Tag Name:'..self._tag_name..'\t reach max sample data unsaving')
		self._samples = {}
	end
end

function tag:save_samples()
	local list = self._samples
	if #list == 0 then
		return true
	end
	self._samples = {}
	return self:write('SAMPLE', list, true)
end

function tag:read_samples(start_time, end_time)
	return self:read('SAMPLE', start_time, end_time)
end

function tag:read(cate, start_time, end_time)
	assert(cate and start_time and end_time)
	if self._no_db then
		return {}
	end

	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end

	return db:query(start_time, end_time)
end

function tag:write(cate, data, is_array)
	local db_data = siri_data:new()

	if not is_array then
		data = {data}
	end

	local series_map = {}
	for _, d in ipairs(data) do
		for k, v in pairs(d) do
			local series = series_map[k]
			if not series and k ~= 'timestamp' then
				local vt = self:get_value_type(cate, k)
				local name = cate..'.'..self._tag_name..'.'..k..'.'..vt
				--print(name, vt)
				series = siri_series:new(name, vt)
				series_map[k] = series
				db_data:add_series(name, series)
			end
			if series then
				series:push_value(v, assert(d.timestamp))
			end
		end
	end

	return self._db:insert(db_data)
end

return tag
