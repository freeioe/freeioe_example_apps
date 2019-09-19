local _M = {}

function _M.escape_key(text)
   return string.gsub(text, "%.", "__")
end

function _M.unescape_key(text)
	return string.gsub(text, "__", ".")
end

return _M
