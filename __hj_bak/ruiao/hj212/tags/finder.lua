local TAGS = require 'hj212.tags.info'

local TAG_INFO = {}

return function(name)
	local info = TAG_INFO[name]
	if info then
		return info
	end

	local tag = nil
	for _, v in ipairs(TAGS) do
		local v_name = v.name
		if v_name == name then
			tag = v
			break
		end
		if v.org_name and v.org_name == name then
			tag = v
			break
		end
		if string.len(v_name) == string.len(name) then
			local km = nil
			if string.sub(v_name, -2) == 'xx' then
				km = string.sub(v_name, 1, -3)..'(%d%d)'
			else
				if string.sub(v_name, -1) == 'x' then
					km = string.sub(v_name, 1, -2)..'(%d)'
				end
			end
			if km then
				if string.match(name, km) then
					tag = v
					break
				end
			end
		end
	end

	if tag then
		TAG_INFO[name] = tag
		return tag
	end

	return nil
end

