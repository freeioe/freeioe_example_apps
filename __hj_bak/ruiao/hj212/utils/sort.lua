local _M = {}

function _M.string_compare(a, b)
	local i = 1
	while i <= string.len(a) and i <= string.len(b) do
		if string.sub(a, i, i) < string.sub(b, i, i) then
			return true
		end
		if string.sub(a, i, i) > string.sub(b, i, i) then
			return false
		end
		i = i + 1
	end
	return string.len(a) > string.len(b)
end

function _M.for_each_sorted_key(tab, func)
	local keys = {}
	for k, v in pairs(tab) do
		keys[#keys + 1] = k
	end
	table.sort(keys, _M.string_compare)

	for _, key in ipairs(keys) do
		func(tab[key])
	end
end

return _M
