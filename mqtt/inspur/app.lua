local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local ioe = require 'ioe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = mqtt_app:subclass("THINGSROOT_MQTT_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 5

function app:to_mqtt_app_conf(conf, sys_id)
	local client_id = conf.project_code..'@'..conf.product_code..'@'..sys_id
	local new_conf = {
		--- mqtt
		client_id = client_id,
		username = sys_id,
		password = '',
		server = conf.server or '117.73.3.68',
		port = conf.port,
		enable_tls = true,
		tls_cert = conf.tls_cert,
		client_cert = conf.client_cert,
		client_key = conf.client_key,
	}
	for k, v in pairs(conf.options or {}) do
		new_conf[k] = v
	end
	if conf.has_options_ex == 'yes' then
		self._disable_data = conf.options_ex.disable_data
		self._disable_event = conf.options_ex.disable_event
		self._disable_devices = conf.options_ex.disable_devices
		self._disable_data_em = conf.options_ex.disable_data_em
		self._disable_output = conf.options_ex.disable_output
		self._disable_command = conf.options_ex.disable_command
		self._disable_compress = conf.options_ex.disable_compress
	end
	self._disable_apps = true --- application list not supported!!!!
	self._disable_stat = true --- statiticsis not supported!!!

	return new_conf
end

function app:text2file(text, filename)
	if not text or string.len(text) == 0 then
		return nil
	end

	local full_path = self._sys:app_dir()..filename
	local f = assert(io.open(full_path), 'w+')
	f:write(text or '')
	f:close()
	return filename 
end

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._prv_conf = conf

	conf.tls_cert = self:text2file(conf.tls_cert, 'ca.crt')
	conf.client_cert = self:text2file(conf.client_cert, 'client_cert.crt')
	conf.client_key = self:text2file(conf.client_key, 'client_key.crt')

	conf.tls_cert = conf.tls_cert or 'certs/IoTRootCA.crt'
	conf.client_cert = conf.client_cert or 'certs/iotmpsp3i1t-qxcf6rtc-IDIDIDIDID.crt'
	conf.client_key = conf.client_key or 'certs/iotmpsp3i1t-qxcf6rtc-IDIDIDIDID.key'
	conf.project_code = conf.project_code or 'iotmpsp3i1t'
	conf.product_code = conf.product_code or 'qxcf6rtc'

	self._devices_map = {}
	for _, v in ipairs(conf.devs or {}) do
		if v.sn and string.len(v.sn) > 0 then
			self._devices_map[v.sn] = v.code
		else
			self._log:warning("Device missing sn in conf.devs item")
		end
	end

	local sys_id = sys:id()
	local mqtt_conf = self:to_mqtt_app_conf(conf, sys_id)

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, mqtt_conf)

	self._mqtt_id = mqtt_conf.client_id
end

function app:pack_key(app_src, device_sn, input, prop)
	-- if data upload disabled
	if self._disable_data then
		return
	end

	local dev_code = self._device_map[device_sn]
	--- if deivce not in allowed list
	if not dev_code then
		return
	end

	return dev_code .. '/' .. input .. '/' .. prop
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {
		sn = sn,
		input = input,
		prop = prop,
		value = value,
		timestamp = timestamp,
		quality = quality
	}
	return self:publish(self._mqtt_id.."/data", cjson.encode(msg), 0, false)
end

function app:on_publish_data_em(key, value, timestamp, quality)
	if self._disable_data_em then
		return
	end

	return self:on_publish_data(key, value, timestamp, quality)
end

function app:on_publish_data_list(val_list)
    local data=cjson.encode(val_list)
    if self._disable_compress then
		return self:publish(self._mqtt_id.."/data", data, 0, false)
	else
        data = self:compress(data)
		return self:publish(self._mqtt_id.."/data_gz", data, 0, false)
    end
end

function app:on_publish_cached_data_list(val_list)
	local data=cjson.encode(val_list)
    if not self._disable_compress then
		return self:publish(self._mqtt_id.."/cached_data", data, 0, false)
	else
        data = self:compress(data)
		return self:publish(self._mqtt_id.."/cached_data_gz", data, 0, false)
    end
end

function app:on_event(app, sn, level, type_, info, data, timestamp)
	if self._disable_event then
		return true
	end
	if not self._device_map[sn] then
		return true
	end

	local event = {
		level = level,
		['type'] = tyep_,
		info = info,
		data = data,
		app = app
	}
	return self:publish(self._mqtt_id.."/event", cjson.encode({sn, event, timestamp} ), 1, false)
end

--[[
function app:on_stat(app, sn, stat, prop, value, timestamp)
	if self._disable_stat then
		return true
	end

	local msg = {
		app = app,
		sn = sn,
		stat = stat,
		prop = prop,
		value = value,
		timestamp = timestamp,
	}
	return self:publish(self._mqtt_id.."/stat", cjson.encode(msg), 1, false)
end
]]--

function app:on_publish_devices(devices)
	if self._disable_devices then
		return true
	end
	local new_devices = {}
	for k, v in pairs(self._device_map) do
		if v then
			new_devices[k] = devices[k]
		end
	end

	local data, err = cjson.encode(new_devices)
	if not data then
		self._log:error("Devices data json encode failed", err)
		return false
	end

	if self._disable_compress then
		return self:publish(self._mqtt_id.."/devices", data, 1, true)
	else
		data = self:compress(data)
		return self:publish(self._mqtt_id.."/devices_gz", data, 1, true)
	end
end

function app:on_mqtt_connect_ok()
	local sub_topics = {
		'/shadow/get/accepted',
		'/shadow/update/rejected',
		'/thing/topo/get_reply'
	}
	if not self._disable_output or not self._disable_command then
		table.insert(sub_topics, '/control')
	end
	for _, v in ipairs(sub_topics) do
		self:subscribe(self._mqtt_id..v, 1)
	end
	---[[sub devices online]]--
	for k, v in pairs(self._devices_map) do
		local data = {
			id = os.time(),
			param = {
				IotModelCode = v.model,
				IotDeviceCode = v.device,
				clientId = v.device,
				timestamp = ioe.time(),
				signMethod
			}
		}
		return self:publish(self._mqtt_id.."/status", "ONLINE")
	end
end

function app:mqtt_will()
	return self._mqtt_id.."/status", "OFFLINE", 1, true
end

function app:on_mqtt_message(mid, topic, payload, qos, retained)
	local id, t, sub = topic:match('^([^/]+)/([^/]+)(.-)$')
	if id ~= self._mqtt_id and id ~= "ALL" then
		self._log:error("MQTT recevied incorrect topic message")
		return
	end
	local data, err = cjson.decode(payload)
	if not data then
		self._log:error("Decode JSON data failed", err)
		return
	end

	if t == 'output' then
		self:on_mqtt_output(string.sub(sub or '/', 2), data.id, data.data)
	elseif t == 'command' then
		self:on_mqtt_command(string.sub(sub or '/', 2), data.id, data.data)
	else
		self._log:error("MQTT recevied incorrect topic", t, sub)
	end
end

function app:on_mqtt_result(id, result, message)
	local data = {
		id = id,
		result = result,
		message = message,
		timestamp = ioe.time(),
		timestamp_str = os.date()
	}
	self:publish(self._mqtt_id..'/result/output', cjson.encode(data), 0, false)
end

function app:on_mqtt_output(topic, id, data)
	if self._disable_output then
		return self:on_mqtt_result(id, false, 'Device output disabled!')
	end
	if not self._device_map[data.device] then
		return self:on_mqtt_result(id, false, 'Device not allowed!')
	end

	local device, err = self._api:get_device(data.device)
	if not device then
		return self:on_mqtt_result(id, false, err or 'Device missing!')
	end

	local priv = {id = id, data = data}
	local r, err = device:set_output_prop(data.output, data.prop or 'value', data.value, ioe.time(), priv)
	if not r then
		self._log:error('Set output prop failed!', err)
		return self:on_mqtt_result(id, false, err or 'Set output prop failed')
	end
end

function app:on_output_result(app_src, priv, result, err)
	if not result then
		self._log:error('Set output prop failed!', err)
		return self:on_mqtt_result(priv.id, false, err or 'Set output prop failed')
	else
		return self:on_mqtt_result(priv.id, true, 'Set output prop done!!')
	end
end

function app:on_mqtt_command(topic, id, data)
	if self._disable_command then
		return self:on_mqtt_result(id, false, 'Device command disabled!')
	end
	if not self._device_map[data.device] then
		return self:on_mqtt_result(id, false, 'Device not allowed!')
	end

	local device, err = self._api:get_device(data.device)
	if not device then
		return self:on_mqtt_result(id, false, err or 'Device missing!')
	end

	local priv = {id = id, data = data}
	local r, err = device:send_command(data.cmd, data.param or {}, priv)
	if not r then
		self._log:error('Device command execute failed!', err)
		return self:on_mqtt_result(id, false, err or 'Device command execute failed!')
	end
end

function app:on_command_result(app_src, priv, result, err)
	if not result then
		self._log:error('Device command execute failed!', err)
		return self:on_mqtt_result(priv.id, false, err or 'Device command execute failed!')
	else
		return self:on_mqtt_result(priv.id, true, 'Device command execute done!!')
	end
end

--- 返回应用对象
return app
