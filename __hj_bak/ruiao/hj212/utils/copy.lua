---- Table copy helper.
-- The helper functions for you to copy table easily.
-- @author Dirk Chang
-- @copyright SymTech Inc 2014

local _M = {}

--- Create copy deeply, thus each key, value is been copied.
-- @tparam table orig	the original source table
-- @treturn table  the copied table
_M.deep = function (orig)
	local orig_type = type(orig)
	local copy
	if orig_type == 'table' then
		copy = {}
		for orig_key, orig_value in next, orig, nil do
			copy[_M.deep(orig_key)] = _M.deep(orig_value)
		end
		setmetatable(copy, _M.deep(getmetatable(orig)))
	else -- number, string, boolean, etc
		copy = orig
	end
	return copy
end

--- Copy the table to destination table, but not create a new table for destination
-- @tparam table from the source table
-- @tparam table to destination table
--
_M.inplace = function(from, to)
	if type(from) == 'table' then
		for k, v in pairs(to) do
			to[k] = nil
		end

		for k, v in pairs(from) do
			to[k] = v
		end
	else
		to = from 
	end
end

return _M
