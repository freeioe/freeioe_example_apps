local restful = require 'http.restful'
local cjson = require 'cjson.safe'
--[[
* Guangzhou: 1809858
* Beijing: 1816670
* Shanghai: 1796236
	https://openweathermap.org/data/2.5/weather/?appid=b6907d289e10d714a6e88b30761fae22&id=1809858&units=metric

[Response]:
{
	"coord": {
		"lon": 113.25,
		"lat": 23.12
	},
	"weather": [{
		"id": 502,
		"main": "Rain",
		"description": "heavy intensity rain",
		"icon": "10d"
	}, {
		"id": 202,
		"main": "Thunderstorm",
		"description": "thunderstorm with heavy rain",
		"icon": "11d"
	}],
	"base": "stations",
	"main": {
		"temp": 22.39,
		"pressure": 1009,
		"humidity": 94,
		"temp_min": 21,
		"temp_max": 26.67
	},
	"visibility": 1200,
	"wind": {
		"speed": 1
	},
	"rain": {
		"1h": 8.13
	},
	"clouds": {
		"all": 75
	},
	"dt": 1555644364,
	"sys": {
		"type": 1,
		"id": 9620,
		"message": 0.0045,
		"country": "CN",
		"sunrise": 1555625003,
		"sunset": 1555670924
	},
	"id": 1809858,
	"name": "Guangzhou",
	"cod": 200
}
]]--


local _M = {}
local _restapi = restful:new('https://openweathermap.org')

function _M.get_temp(city_code)
	local status, body = _restapi:get('/data/2.5/weather/?appid=b6907d289e10d714a6e88b30761fae22&id='..city_code..'&units=metric')

	if not status or status ~= 200 then
		return nil, body
	end
	local data, err = cjson.decode(body)
	if not data then
		return nil, err
	end
	local main = data.main
	if not main then
		return nil, "Data has no main attribute"
	end
	local temp = main.temp
	if not temp then
		return nil, "Main node has no temp attribute"
	end

	return tonumber(temp), data.name or "UNKNOWN"
end

return _M
