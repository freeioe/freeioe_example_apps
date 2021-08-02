local class = require 'middleclass'
local lcurl = require 'lcurl'
local cjson = require 'cjson.safe'
local hmac = require 'hashings.hmac'
local sha256 = require 'hashings.sha256'
local basexx = require 'basexx'

local api = class("BAIDU_IOT_HTTP_API")

function api:initialize(sys, instance, addr, product_key, device_name, device_secret)
	assert(instance)
	assert(addr)
	assert(product_key)
	assert(device_name)
	assert(device_secret)
	self._sys = sys
	self._instance = instance
	self._addr = addr
	self._product_key = product_key
	self._device_name = device_name
	self._device_secret = device_secret
end

function api:post(url, body, sign_s, expire_time)
	local result = {}
	local header = {
		"Content-Type: application/json",
		"expiryTime: "..expire_time
	}
	if sign_s then
		header[#header + 1] = "signature: "..sign_s
	end

	local easy_handle = lcurl.easy()
		:setopt_url(url)
		:setopt_writefunction(function(str) 
			--print("R:", str)
			result[#result + 1] = str
		end)
		:setopt_httpheader(header)
		:setopt_postfields(body)
		:setopt_ssl_verifyhost(0)
		:setopt_ssl_verifypeer(0)

	--easy_handle:perform()

	local m = lcurl.multi():add_handle(easy_handle)

	while m:perform() > 0 do
		self._sys:sleep(0)
		m:wait()
	end

	local h, r = m:info_read()
	easy_handle:close()
	if h ~= easy_handle or not r then
		return nil, "Failed to call login api"
	end

	local str = table.concat(result)
	print(str)
	return cjson.decode(str)
end

function api:sign(path, expire_time, body)
	local auth_str = path.."\n"..expire_time.."\n"..body
	local sign_hex = hmac:new(sha256, self._device_secret, auth_str):digest()
	local sign_b64 = basexx.to_base64(sign_hex)

	local c = lcurl.easy()

	local sign_u = c:escape(sign_b64)

	c:close()

	return sign_u
end

function api:auth()
	local expire_time = os.time() // 60 -- minutes
	local body = {
		resourceType =  "MQTT"
	}
	local path = "/v1/devices/"..self._instance.."/"..self._product_key.."/"..self._device_name.."/resources"
	local body_str = cjson.encode(body)

	local sign_s = self:sign(path, expire_time, body_str)
	local url = self._addr..path	

	return self:post(url, body_str, sign_s, expire_time)
end

return api
