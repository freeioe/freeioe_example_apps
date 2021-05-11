local class = require 'middleclass'

local meta = class('hisdb.meta')

local create_sql = [[
CREATE TABLE "meta" (
	"key"		TEXT PRIMARY KEY UNIQUE,
	"value"		TEXT NOT NULL
);
]]

function meta:initialize(db)
	assert(db, "Database missing")
	self._db = db
	self._meta = {}

	local r, err = self._db:first_row([[SELECT name FROM sqlite_master WHERE type='table' AND name='meta';]])
	if not r then
		assert(self._db:exec(create_sql))
	else
		self:_load_vals()
	end
end

function meta:_load_vals()
	for row in self._db:rows('SELECT * FROM meta') do
		self._meta[row.key] = row.value
	end
end

function meta:get(key)
	return self._meta[key]
end

function meta:set(key, value)
	if value == nil then
		local sql = [[DELETE FROM meta WHERE key='%s']]
		local r, err = self._db:exec(string.format(sql, key))
		if not r then
			return nil, err
		end
		self._meta[key] = nil
		return true
	end

	if not self._meta[key] then
		local sql = [[INSERT INTO meta (key, value) VALUES('%s', '%s')]]
		local r, err = self._db:exec(string.format(sql, key, value))
		if not r then
			return nil, err
		end
	else
		local sql = [[UPDATE meta SET value='%s' WHERE key='%s']]
		local r, err = self._db:exec(string.format(sql, value, key))
		if not r then
			return nil, err
		end
	end
	self._meta[key] = value
	return true
end

return meta
