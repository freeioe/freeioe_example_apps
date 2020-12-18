local class = require 'middleclass'

local db = class('tag_db.store')

function db:initialize(index, key, last_per_file, max_file_count)
	self._index = index
end

function db:save()
end

function db:write()
end

function db:get_db(type_name)
end

function db:purge(etime)
end
