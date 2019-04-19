local restful = require 'restful'
local cjson = require 'cjson.safe'
--[[
* Guangzhou: 1809858
* Beijing: 1816670
* Shanghai: 1796236
	https://openweathermap.org/data/2.5/weather/?appid=b6907d289e10d714a6e88b30761fae22&id=1809858&units=metric
]]--


local _M = {}
local _restapi = restful:new('https://openweathermap.org')

function _M.get_temp(city_code)
	local status, body = _restapi:get('/data/2.5/weather/?appid=b6907d289e10d714a6e88b30761fae22&id='..city_code..'&units=metric')
	print(status, body)

	if status and status == 200 then
		local data = cjson.decode(body)
	end
	return nil, body
end

return _M
