local base = require 'hj212.calc.db'

local poll = base:subclass("HJ212_APP_TAG_DB_DB")

function poll:initialize(hisdb, poll_id, no_db)
	self._hisdb = hisdb
	self._poll_id = poll_id
	self._samples = {}
	self._no_db = no_db
	self._db_map = {}
end

function poll:init()
	if self._no_db then
		return true
	end

	local sample_meta, sample_ver = self:sample_meta()
	local rdata_meta, rdata_ver = self:rdata_meta()
	local cou_meta, cou_ver = self:cou_meta()

	local hisdb = self._hisdb
	local db_map = {
		SAMPLE = hisdb:create_object('SAMPLE', 'SAMPLE', self._poll_id, sample_meta, sample_ver),
		RDATA = hisdb:create_object('HISDB', self._poll_id, 'RDATA', rdata_meta, rdata_ver),
		MIN = hisdb:create_object('HISDB', self._poll_id, 'MIN', cou_meta, cou_ver),
		HOUR = hisdb:create_object('HISDB', self._poll_id, 'HOUR', cou_meta, cou_ver),
		DAY = hisdb:create_object('HISDB', self._poll_id, 'DAY', cou_meta, cou_ver),
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

function poll:push_sample(data)
	table.insert(self._samples, data)
	if #self._samples > 3600 then
		assert(nil, 'Tag Id:'..self._poll_id..'\t reach max sample data unsaving')
		self._samples = {}
	end
end

function poll:save_samples()
	local list = self._samples
	if #list == 0 then
		return true
	end
	self._samples = {}
	return self:write('SAMPLE', list, true)
end

function poll:read_samples(start_time, end_time)
	return self:read('SAMPLE', start_time, end_time)
end

function poll:read(cate, start_time, end_time)
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

function poll:write(cate, data, is_array)
	if self._no_db then
		return true
	end

	local db = self._db_map[cate]
	if not db then
		return nil, "Not found db for "..cate
	end

	return db:insert(data, is_array)
end

return poll
