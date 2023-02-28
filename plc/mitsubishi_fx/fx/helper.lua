local _M = {}

_M.convert_addr = function(name, index)
	if string.upper(name) == 'X' then
		return tonumber(index, 8)
	elseif string.upper(name) == 'Y' then
		return tonumber(index, 8)
	else
		return tonumber(index)
	end
end

_M.cmd_addr_len = function(name)
	if cmd == 'QR' or cmd == 'QW' or cmd == 'QT' then
		return 7
	else
		return 5
	end
end

_M.make_addr = function(name, index, addr_len)
	local len = addr_len - string.len(name)
	if string.upper(name) == 'X' then
		return name..string.format('%0'..len..'o', index)	
	elseif string.upper(name) == 'Y' then
		return name..string.format('%0'..len..'o', index)	
	else
		return name..string.format('%0'..len..'d', index)	
	end
end

return _M
