local telit = require 'telit_helper'


local function test(key)
	local ekey = telit.escape_key(key)
	print(key, ekey)

	assert(key == telit.unescape_key(ekey))
end

local keys = {
	'2-30002-011212-121211',
	'2_30002_011212-121211',
	'2.30002,011212.121211',
}

for _, key in ipairs(keys) do
	test(key)
end

