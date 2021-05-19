local wclient = require 'welink.client'
local wcrypt = require 'welink.crypt'
local cjson = require 'cjson.safe'
local base = require 'app.base.mqtt'
local basexx = require 'basexx'

local app = base:subclass("WELINK_CLOUD")
app.static.API_VER = 9

function test()
	local sm = require('crypt.sm')({})

	print(sm.sm2keygen('/tmp/sm2.pri.pem', '/tmp/sm2.pub.pem'))

	local pri_key = '269D0736F3464E16B1E692E6FCDFD57DB2EFF5A9C01F01B72A69DBBE87A5207E'
	local pub_key = 'ADD3C87A7380313971C44B18C31A13B2697FC93E562CA7C5A66863AAC3046E8CC71BF53F16EA2DA6E0ECA08E4AFA702F942ACE1FC110BBE3DCB73BE248F97A53'

	local keyx = string.sub(pub_key, 1, 64)
	local keyy = string.sub(pub_key, 65)

	--[[
	print(sm.sm2key_export(pri_key, keyx, keyy,
	'/tmp/sm2_export.pri.pem', '/tmp/sm2_export.pub.pem'))

	print(sm.sm2pubkey_write(pub_key, '/tmp/sm2_pub_write.pub.pem'))

	print(sm.sm2prikey_write(pri_key, '/tmp/sm2_pri_export.pri.pem'))
	]]--

	print(sm.sm2key_write(pub_key, '/tmp/sm2_write.pub.pem',
	pri_key, '/tmp/sm2_write.pri.pem'))

	local srv_key = '99213644F0F7EB64992DAD9AFF59A1215CDFC00F7C620D08646C7537962F8D1A8A1CE9C04F435E5ACF36893BC5BEB81E22A83894847052BD8832EB02A89161BB'
	print(sm.sm2key_write(srv_key, '/tmp/sm2_srv.pub.pem'))
end

function app:on_init()
	--test()
	local conf = self:app_conf()

	--- Client Configruation
	local opt = conf or {}
	local host = opt.host or "iot.weiling.qq.com"
	local port = opt.port or 18831
	local pid = opt.pid or '1701001132'
	local srv_pub_key = opt.srv_pub_key or '99213644F0F7EB64992DAD9AFF59A1215CDFC00F7C620D08646C7537962F8D1A8A1CE9C04F435E5ACF36893BC5BEB81E22A83894847052BD8832EB02A89161BB'
	local dev_pub_key = opt.dev_pub_key or 'ADD3C87A7380313971C44B18C31A13B2697FC93E562CA7C5A66863AAC3046E8CC71BF53F16EA2DA6E0ECA08E4AFA702F942ACE1FC110BBE3DCB73BE248F97A53'
	local dev_pri_key = opt.dev_pri_key or '269D0736F3464E16B1E692E6FCDFD57DB2EFF5A9C01F01B72A69DBBE87A5207E'

	self._crypt = wcrypt:new(opt.pname, pid, srv_pub_key, dev_pub_key, dev_pri_key)
	self._pid = pid
	self._sm4iv = conf.sm4iv or '9G44eKBX76pXXsl0'
	self._proj_id = conf.proj_id
	self._client = wclient:new(host, port, pid, self._crypt)
	self._seq = 1
end

function app:on_start()
	local r, err = self._client:connect()
	if not r then
		return nil, err
	end

	return base.on_start(self)	
end

--- Auth mqtt
function app:mqtt_auth()
	--local reg_data, err = self._client:register('TRTX011902000001')
	local sys = self:sys_api()
	local sn = sys:id()

	local reg, err = self._client:register(sn)
	if not reg then
		return nil, err
	end

	local wid = assert(reg.wId)
	local proj_id = assert(reg.projId)
	local proj_access_addr = assert(reg.projAccessAddr)
	local sslType = assert(reg.sslType)
	local din = assert(reg.din)

	if self._proj_id and self._proj_id ~= proj_id then
		return nil, "Gateway project ID incorrect, please bind gateway correct"
	end

	if sslType ~= 'none' then
		return nil, "Currently only none tls MQTT supported"
	end

	local mqtt_client_id = assert(reg.mqttClientId)
	local mqtt_server = assert(reg.mqttServer)
	local mqtt_user = assert(reg.mqttUser)
	local mqtt_password = assert(reg.mqttPassword)
	local mqtt_recv_topic = assert(reg.mqttReciveTopic)
	local mqtt_push_topic = assert(reg.mqttPushTopic)

	local inner_url = assert(reg.innerUrl)
	local http_domain = assert(reg.httpDomain)

	local proto, host, port = string.match(mqtt_server, '^([^:]+)://([^:]+):(%d+)$')
	if proto ~= 'tcp' then
		return nil, "MQTT server incorrect"
	end

	self._sn = sn
	self._wid = wid
	self._proj_access_addr = proj_access_addr

	self._mqtt_sub = '/welink/msg/receive/v2/'..wid
	self._mqtt_pub = '/welink/msg/push/v2/'..wid

	local r, err = self:refresh_token()
	if not r then
		return nil, err
	end

	-- Close channel
	self._client:close()

	return {
		client_id = mqtt_client_id,
		username = mqtt_user,
		password = mqtt_password,
		clean_session = true,
		host = host,
		port = port,
	}
end

function app:on_mqtt_connect_ok()
	self:subscribe(self._mqtt_sub, 1)
	return self:fire_heartbeat()
end

function app:fire_heartbeat()
	return self:send_message(30001, 'welink')
end

function app:send_message(dp, value, sub_wid)
	local sys = self:sys_api()
	local rand = math.random(1, 0xFFFFFFFF)
	local seq = self._seq
	local msg = {
		timeStamp = sys:time() * 1000,
		random = rand,
		seq = seq,
		datapoint = dp,
		msgType = 'report',
		wId = self._wid,
		value = value,
		subwId = sub_wid
	}

	self._seq = self._seq + 1

	local data = self:encrypt(msg)

	return self:publish(self._mqtt_pub, data, 1, true)
end

function app:encrypt(data)
	local crypt = self._crypt

	local msg, err = cjson.encode(data)
	if not msg then
		return nil, err
	end
	print('SM4 iv:', self._sm4iv, 'key:', self._sm4key)
	print('SM4.Encrypt:', msg)

	local r, err = crypt:sm4_encrypt_with_cipher(msg, self._sm4key, self._sm4iv)
	if not r then
		return nil, err
	end

	print('SM4.Encrypt:', basexx.to_hex(r))

	return r
end

function app:decrypt(data)
	local crypt = self._crypt

	local msg = crypt:sm4_decrypt_with_cipher(data, self._sm4key, self._sm4iv)

	return cjson.decode(msg)
end

function app:create_event_msg(app, sn, level, type_, info, data, timestamp)
	return {
		header = {
			eventType = "event",
			from = "/devices/"..self._device_id.."/services/"..sn,
			to = "/event/v1.1.0/devices/"..self._device_id.."/services/"..sn,
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			app = app,
			sn = sn,
			level = level,
			['type'] = type_,
			info = info,
			data = data,
			timestamp = timestamp
		},
	}
end

function app:create_data_msg(sn, input, prop, value, timestamp, quality)
	return {
		header = {
			method = "PUT",
			from = "/device/"..sn,
			to = "/data/v1.1.0/devices/"..sn.."/services/data",
			access_token = self._refresh_token,
			timestamp = huawei_timestamp(timestamp),
			eventTime = huawei_timestamp(timestamp),
		},
		body = {
			sn = sn,
			input = input,
			prop = prop,
			value = value,
			timestamp = timestamp,
			quality = quality
		}
	}
end

function app:on_publish_data(key, value, timestamp, quality)
	return true
--[[
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	assert(sn and input and prop)
	local msg = self:create_data_msg(sn, input, prop, value, timestamp, quality)
	return self:publish(".cloud.signaltrans.v2.categories.data", cjson.encode(msg), 1, false)
	]]--
end

function app:on_publish_data_list(val_list)
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
	return true
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	return true
	--[[
	local msg = self:create_event_msg("event", app, sn, level, type_, info, data, timestamp)
	return self:publish(".cloud.signaltrans.v2.categories.event", cjson.encode(msg), 1, false)
	]]--
end

function app:on_stat(app, sn, stat, prop, value, timestamp)
end

function app:on_publish_devices(devices)
	-- TODO: added devices
	--[[
	local r, err = self._huawei_http:sync_devices(devs)
	if not r then
		self._log:error("Sync device failed", err)
		return nil, err
	end
	self._log:debug("Sync device return", cjson.encode(r))
	return true
	]]
end

function app:refresh_token()
	local sys = self:sys_api()
	local conf = self:app_conf()

	if not self._proj_access_addr then
		return nil, "Project Access Address not exists"
	end
	local addr = self._proj_access_addr[1]
	if not addr then
		return nil, "Project Access Address not exists"
	end

	local host, port = string.match(addr, '^([^:]+):(%d+)$')
	if not host or not port then
		return nil, "Invalid Project Access Address"
	end

	self._log:info("Connect to Access server", host, port)

	local client = wclient:new(host, port, self._pid, self._crypt)

	if not client:connect() then
		return nil, "Cannot connect to Project Accsss Server"
	end

	local challenge_ran, err = client:challenge()
	if not challenge_ran then
		return nil, err
	end

	local ran = self._sm4iv

	local login, err = client:login(self._sn, self._wid, challenge_ran, ran)

	self._sm4key = assert(login.ran)
	self._http_token = assert(login.httpToken)

	local key_userful_time = assert(tonumber(login.keyUsefulTime)) -- seconds
	self._refresh_token_timeout = sys:now() + (key_userful_time or 86400) * 100

	return true
end

--- 应用运行入口
function app:on_run(tms)
	local sys = self:sys_api()
	if self._refresh_token_timeout and self._refresh_token_timeout - sys:now() < 60 * 100  then
		assert(self:refresh_token())
	end

	return 1000  -- one second
end

--- 返回应用对象
return app

