local class = require 'middleclass'
local lcurl = require 'lcurl'
local cjson = require 'cjson.safe'
local sha1 = require 'hashings.sha1'
local md5 = require 'hashings.md5'
local hmac = require 'hashings.hmac'

local api = class("GRID_BJ_HTTP_API")

function api:initialize(sys, host)
	self._sys = sys
	self._host = host
	self._value = {}
end

function api:auth(gw_sn, manufacturer, model, name, desc)
	local result = {}
	local headers = {}
	local body = cjson.encode({
		gatewaySN = gw_sn,
		algId = 0,
		checkID = gw_sn,
		devInfo = {
			name = name or "Gateway",
			description = desc or "Gateway details",
			manufacturerId = manufacturer,
			model = model
		}
	})
	-- print(body)
	-- print(self._host)

	local easy_handle = lcurl.easy()
		:setopt_url("http://"..self._host.."/iot/devices/auth/gateway")
		:setopt_httpheader({"Content-Type: application/json"})
		:setopt_postfields(body)
		:setopt_writefunction(function(str) 
			--print("R:", str)
			result[#result + 1] = str
		end)
		:setopt_headerfunction(function(str)
			--print("H:", str)
			headers[#headers + 1] = str
		end)
	
	local m = lcurl.multi():add_handle(easy_handle)

	while m:perform() > 0 do
		self._sys:sleep(0)
		m:wait()
	end

	local h, r = m:info_read()
	easy_handle:close()
	if h ~= easy_handle or not r then
		return nil, "Failed to perform request"
	end

	local hstr = table.concat(headers)
	local str = table.concat(result)

	local code = string.match(hstr, "^HTTP/1.1 (%d+)")
	if tonumber(code) ~= 200 then
		return nil, hstr..str
	end

	local r, err = cjson.decode(str)
	if not r then
		return nil, err
	end

	if r.code == 200 then
		self._value = value
		return r.value
	end
	return nil, r.errMsg
end

function api:get_channel(chn_name, value)
	local val = value or self._value
	local chn_list = val.channelList
	for _, chn in ipairs(chn_list or {}) do
		if string.lower(chn.channelId) == string.lower(chn_name) then
			return chn
		end
	end
	return nil, 'Channel not found'
end

function api:find_topic_id(mqtt_topic)
	for _, t in ipairs(topic_list or {}) do
		if string.lower(t.topic) == string.lower(mqtt_topic) then
			return string.upper(t.topicId)
		end
	end
	return nil, 'Not found'
end

function api:get_topic(topic, value)
	local val = value or self._value
	local topic_list = val.topicList
	for _, t in ipairs(topic_list or {}) do
		if string.lower(t.topicId) == string.lower(topic) then
			return t
		end
	end
	return nil, 'Topic not found'
end

function api:get_gateway_id(value)
	local val = value or self._value
	return val.gatewayId
end

function api:get_tenancy(value)
	local val = value or self._value
	return val.tenancy
end

return api
