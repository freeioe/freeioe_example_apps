local base = require 'hj212.calc.db'

local tag = base:subclass("HJ212_APP_TAG_DB_DB")

local sum_attrs = {
	{ name = 'cou', type = 'DOUBLE', not_null = true },
	{ name = 'avg', type = 'DOUBLE', not_null = true },
	{ name = 'min', type = 'DOUBLE', not_null = true },
	{ name = 'max', type = 'DOUBLE', not_null = true },
	{ name = 'stime', type = 'INTEGER', not_null = true },
	{ name = 'etime', type = 'INTEGER', not_null = true },
	{ name = 'flag', type = 'INTEGER', not_null = true },
}

local rdata_attrs = {
	{ name = 'value', type = 'DOUBLE', not_null = true },
	{ name = 'flag', type = 'INTEGER', not_null = true },
}

local db_version = 1

function tag:initialize(hisdb, tag_name, sample_attrs, sample_version, no_db)
	self._hisdb = hisdb
	self._tag_name = tag_name
	self._samples = {}
	self._attrs = sample_attrs
	self._version = sample_version or db_version
	self._no_db = no_db
	self._db_map = {}
end

function tag:init()
	if self._no_db then
		return true
	end

	local hisdb = self._hisdb
	local db_map = {
		SAMPLE = hisdb:create_object('SAMPLE', 'SAMPLE', self._tag_name, self._version, self._attrs),
		RDATA = hisdb:create_object('HISDB', self._tag_name, 'RDATA', db_version, rdata_attrs),
		MIN = hisdb:create_object('HISDB', self._tag_name, 'MIN', db_version, sum_attrs),
		HOUR = hisdb:create_object('HISDB', self._tag_name, 'HOUR', db_version, sum_attrs),
		DAY = hisdb:create_object('HISDB', self._tag_name, 'DAY', db_version, sum_attrs),
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
	if self._no_db then
		return true
	end

	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end

	return db:insert(data, is_array)
end

return tag
