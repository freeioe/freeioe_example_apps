local base = require 'hj212.calc.db'

local db = base:subclass("HJ212_APP_TAG_DB_DB")

---
-- Database base class
-- Data Unit:
-- {
--   total = 
--   agv = 
--   min = 
--   max = 
--   stime = 
--   etime = 
-- }
--
function base:initialize(database, tag_name)
	self._tag_name = tag_name
	self._database = database
	self._samples = {}
end

function base:push_sample(timestamp, value, value2, value3)
	table.insert(self._samples, {timestamp, value, value2, value3})
end

function base:save_samples()
	assert(nil, "Not implemented")
end

function base:read(cate, start_time, end_time)
	assert(nil, "Not implemented")
end

function base:write(cate, data_list)
	assert(nil, "Not implemented")
end

return base
