local class = require 'middleclass'

local key = class('hisdb.index_key')

function key:initialize(key, cate, creation)
	self._key = key
	self._cate = cate
	self._creation = creation
end

function key:__eq(a, b)
	return a._key == b._key and a._cate == b._cate and self._creation == self._creation
end

function key:__lt(a, b)
	if a._key < b._key then
		return true
	end
	if a._key == b._key and a._cate < b._cate then
		return true
	end
	if a._key == b._key and a._cate == a._cate and a._creation < b._creation then
		return true
	end
	return false
end

return key
