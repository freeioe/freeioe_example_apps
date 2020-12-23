local base = require 'hj212.calc.db'

local db = base:subclass("HJ212_APP_TAG_DB_DB")

local sum_attrs = {
	{ name = 'total', type = 'DOUBLE', not_null = true },
	{ name = 'avg', type = 'DOUBLE', not_null = true },
	{ name = 'min', type = 'DOUBLE', not_null = true },
	{ name = 'max', type = 'DOUBLE', not_null = true },
	{ name = 'stime', type = 'INTEGER', not_null = true },
	{ name = 'etime', type = 'INTEGER', not_null = true },
}

local rdata_attrs = {
	{ name = 'value', type = 'DOUBLE', not_null = true },
	{ name = 'flag', type = 'INTEGER', not_null = true },
}

function base:initialize(hisdb, tag_name, sample_attrs)
	self._hisdb = hisdb
	self._tag_name = tag_name
	self._samples = {}
	self._attrs = sample_attrs
	self._db_map = {}
	self._attrs_map = {}
	for i, v in ipairs(sample_attrs) do
		self._attrs_map[v.name] = i
	end
end

function base:init()
	local hisdb = self._hisdb
	local db_map = {
		SAMPLE = hisdb:create_object(self._tag_name, 'SAMPLE', self._attrs),
		RDATA = hisdb:create_object(self._tag_name, 'RDATA', rdata_attrs),
		MIN = hisdb:create_object(self._tag_name, 'MIN', sum_attrs),
		HOUR = hisdb:create_object(self._tag_name, 'HOUR', sum_attrs),
		DAY = hisdb:create_object(self._tag_name, 'DAY', sum_attrs),
	}
	for k,v in pairs(db_map) do
		local r, err = v:init()
		if not r then
			return nil, err
		end
	end
	self._db_map = db_map
	return true
end

function base:push_sample(data)
	local val = {}
	for i, v in ipairs(self._attrs) do
		val[v.name] = data[i]
	end

	table.insert(self._samples, val)
end

function base:save_samples()
	local list = self._samples
	self._samples = {}
	return self:write('SAMPLE', list, true)
end

function base:read_samples(start_time, end_time)
	local data, err = self:read('SAMPLE', start_time, end_time)
	if not data then
		return nil, err
	end
	local list = {}
	local attrs_map = self._attrs_map
	for _, d in ipairs(data) do
		local val = {}
		for k, v in pairs(d) do
			if k ~= 'id' then	
				val[attrs_map[k]] = v
			end
		end
		list[#list + 1] = val
	end

	return list
end

function base:read(cate, start_time, end_time)
	assert(cate and start_time and end_time)
	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end

	return db:query(start_time, end_time)
end

function base:write(cate, data, is_array)
	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end

	if is_array then
		for _, v in ipairs(data) do
			assert(db:insert(v))
		end
	else
		assert(db:insert(data))
	end

	return true
end

return base
