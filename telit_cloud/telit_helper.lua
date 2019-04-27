local _M = {}

function _M.escape_key(text)
   return text:gsub("[^a-zA-Z0-9-.]",
                    function(character) 
                       return string.format("_%02x", string.byte(character))
                    end)
end

function _M.unescape_key(text)
	return (string.gsub(text, "_(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end))
end

return _M
