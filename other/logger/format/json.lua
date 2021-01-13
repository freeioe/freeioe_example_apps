local date = require 'date'
local cjson = require 'cjson.safe'
local basexx = require 'basexx'

return function(app)
	assert(app, "App missing")
	local sys = app:sys_api()
	local host_name = sys:id()

	return {
		log = function(app, procid, lvl, timestamp, content)
			local content = content:gsub('\n', '\\\\n')
			return cjson.encode({
				host = host_name,
				app = 'FREEIOE.'..app,
				procid = procid,
				level = lvl,
				timestamp = timestamp,
				content = content
			})
		end,
		comm = function(app, sn, dir, timestamp, base64, ...)
			local lvl = Log.LVL.TRACE
			local args = {
			}
			local data = {}
			for _, v in ipairs({...}) do
				if base64 then
					data[#data + 1] = basexx.to_base64(v)
				else
					data[#data + 1] = v:gsub('\n', '\\\\n')
				end
			end
			local content = table.concat(data, '\t')

			return cjson.encode({
				host = host_name,
				app = 'FREEIOE.'..app,
				format = base64 and 'BASE64' or 'PLAIN',
				sn = sn,
				dir = dir
				timestamp = timestamp,
				content = content
			})
		end,
	}
end
