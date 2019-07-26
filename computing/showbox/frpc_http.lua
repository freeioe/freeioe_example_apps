local restful = require 'restful'
local cjson = require 'cjson.safe'

local _M = {}
--local _restapi = restful:new('http://127.0.0.1:7413')
local _restapi = restful:new('http://172.30.11.139:7413')

function _M.get_status(city_code)
	local status, body = _restapi:get('/api/status')
	print(status, body)

	if not status or status ~= 200 then
		return nil, body
	end
	local data, err = cjson.decode(body)
	if not data then
		return nil, err
	end
	return data
end

return _M
