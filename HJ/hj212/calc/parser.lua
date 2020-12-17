
return function(station, calc_str)
	local calc = nil
	for name, param in string.gmatch(calc_str, '([^>:]+)([^>]*)>?') do
		param = param and param:sub(2)

		local r, m = pcall(require, 'calc.'..name)
		if not r then
			return nil, m
		end
		calc = m:new(station, calc, param)
	end

	return calc
end
