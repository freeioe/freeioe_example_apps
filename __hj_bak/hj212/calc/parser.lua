
return function(station, calc_str)
	local calc = nil
	local list = {}
	for name, param in string.gmatch(calc_str, '([^>:]+)([^>]*)>?') do
		if string.len(param) <= 1 then
			param = nil
		else
			param = param:sub(2)
		end

		list[#list + 1] = {
			name = name,
			param = param,
		}
	end
	for i = #list, 1, -1 do
		local v = list[i]
		local r, m = pcall(require, 'calc.'..v.name)
		if not r then
			return nil, m
		end
		calc = m:new(station, calc, v.param)
	end

	return calc
end
