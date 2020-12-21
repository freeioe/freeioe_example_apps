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

function base:initialize(hisdb, tag_name, sample_attrs)
	self._hisdb = hisdb
	self._tag_name = tag_name
	self._samples = {}
	self._attrs = sample_attrs

	local db_map = {
		SIMPLE = hisdb:create_object(tag_name, 'SAMPLE', sample_attrs),
		MIN = hisdb:create_object(tag_name, 'MIN', sum_attrs),
		HOUR = hisdb:create_object(tag_name, 'HOUR', sum_attrs),
		DAY = hisdb:create_object(tag_name, 'DAY', sum_attrs),
	}
	self._db_map = db_map
end

function base:push_sample(...)
	local vals = {...}
	local val = {}
	for i, v in ipairs(self._attrs) do
		val[v.name] = vals[i]
	end

	table.insert(self._samples, val)
end

function base:save_samples()
	local list = self._samples
	self:write('SIMPLE', list)
	self._samples = {}
end

function base:read(cate, start_time, end_time)
	assert(nil, "Not implemented")
end

function base:write(cate, data_list)
	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end
	for _, v in ipairs(data_list) do
		db:insert(v)
	end
	return true
end

return base
