---
-- Package finder utility
--

return function(types, base_pn)
	assert(types ~= nil and type(types) == 'table')
	assert(base_pn ~= nil and type(base_pn) == 'string')
	local codes = {}
	for k,v in pairs(types) do
		codes[v] = string.lower(k)
	end
	local p_map = {}

	return function(code, appendix)
		local p_m = p_map[code]
		if p_m then
			return p_m[1], p_m[2]
		end

		local key = codes[code]
		if not key then
			return nil, "No package found:"..code
		end

		local p_name = base_pn..'.'..key
		p_name = appendix and p_name..'.'..appendix or p_name
		local r, p = pcall(require, p_name)
		if not r then
			return nil, p
		end

		p_map[code] = {p, p_name}

		return p, p_name
	end
end
