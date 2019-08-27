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
		--username = sys_id,
		--password = '',
		server = conf.server or '117.73.3.68',
		port = conf.port or 31183,
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
	local f = assert(io.open(full_path, 'w+'))
	f:write(text)
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
	self._sys = sys

	conf.tls_cert = self:text2file(conf.tls_cert, 'ca.crt')
	conf.client_cert = self:text2file(conf.client_cert, 'client_cert.crt')
	conf.client_key = self:text2file(conf.client_key, 'client_key.crt')

	conf.tls_cert = conf.tls_cert or 'certs/IoTRootCA.crt'
	conf.client_cert = conf.client_cert or 'certs/iotmpsp3i1t-qxcf6rtc-IDIDIDIDID.crt'
	conf.client_key = conf.client_key or 'certs/iotmpsp3i1t-qxcf6rtc-IDIDIDIDID.key'
	conf.project_code = conf.project_code or 'iotmpsp3i1t'
	conf.product_code = conf.product_code or 'qxcf6rtc'

	local sys_id = sys:id()
	local mqtt_conf = self:to_mqtt_app_conf(conf, sys_id)
	mqtt_conf.period = mqtt_conf.period or 1

	--- 基础类初始化
	mqtt_app.initialize(self, name, sys, mqtt_conf)

	self._device_map = {}
	for _, v in ipairs(conf.devs or {}) do
		if v.sn and string.len(v.sn) > 0 then
			self._log:info("Device mapping", v.sn, v.model, v.device)
			self._device_map[v.sn] = {
				model = v.model,
				device = v.device,
				topic = string.format('iot/%s/%s/%s', conf.project_code, v.model, v.device)
			}
		else
			self._log:warning("Device missing sn in conf.devs item")
		end
	end

	self._device_map[sys_id] = self._device_map[sys_id] or {
		model = conf.product_code, 
		device = sys_id,
		topic = string.format('iot/%s/%s/%s', conf.project_code, conf.product_code, sys_id)
	}
	--[[
	local gl_product_code = 'yxzt3yaf'
	self._device_map[sys_id..'.GL'] = {
		model = gl_product_code,
		device = sys_id..'GL',
		topic = string.format('iot/%s/%s/%s', conf.project_code, gl_product_code, sys_id..'GL')
	}
	]]--
	self._sys_id = sys_id
end

function app:pack_key(app_src, device_sn, input, prop)
	-- if data upload disabled
	if self._disable_data then
		return
	end

	if prop ~= 'value' then
		return
	end

	local dev = self._device_map[device_sn]
	--- if deivce not in allowed list
	if not dev then
		return
	end

	return device_sn .. '/' .. input .. '/' .. prop
end

function app:escape_input_name(input)
	return string.gsub(input, '_', '-')
end

function app:shadow_update(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	input = self:escape_input_name(input)

	local reported = {}
	reported[input] = value
	local data = {
		state = {
			reported = reported
		}
	}
	local dev = self._device_map[sn]

	--print('shadow_update', sn, dev.topic..'/shadow/update', cjson.encode(data))
	return mqtt_app.publish(self, dev.topic..'/shadow/update', cjson.encode(data), 0, false)
end

function app:shadow_update_dev(dev, data)
	local data = {
		state = {
			reported = data
		}
	}
	--print('shadow_update', dev.topic..'/shadow/update', cjson.encode(data))
	return mqtt_app.publish(self, dev.topic..'/shadow/update', cjson.encode(data), 0, false)

end

function app:shadow_update_list(val_list)
	local devs = {}
	for _, v in ipairs(val_list) do
		local key, value, timestamp, quality = table.unpack(v)
		local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
		input = self:escape_input_name(input)

		if prop == 'value' then
			devs[sn] = devs[sn] or {}
			if devs[sn][input] then
				self:shadow_update_dev(self._device_map[sn], devs[sn])
				devs[sn] = {}
			end
			devs[sn][input] = value
		end
	end
	for k, v in pairs(devs) do
		local dev = self._device_map[k]

		local r, err = self:shadow_update_dev(dev, v)
		if not r then
			return false, err
		end
	end
	return true
end

function app:publish(topic, data)
	local dev = self._device_map[self._sys_id]
	if true then
		return true
	end

	return mqtt_app.publish(self, dev.topic..'/'..topic, cjson.encode({topic=topic,data=data}), 0, false)
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {key, value, timestamp, quality}
	return self:shadow_update(key, value, timestamp, quality) and self:publish("data", msg)
end

function app:on_publish_data_em(key, value, timestamp, quality)
	if self._disable_data_em then
		return
	end

	return self:on_publish_data(key, value, timestamp, quality)
end

function app:on_publish_data_list(val_list)
	return self:shadow_update_list(val_list) and self:publish("data_list", val_list)
	--[[
	data = self:compress(data)
	return self:publish("data_gz", data, 0, false)
	]]--
end

function app:on_publish_cached_data_list(val_list)
	return self:publish("cached_data", val_list)
	--[[
	data = self:compress(data)
	return self:publish("cached_data_gz", data, 0, false)
	]]--
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
	return self:publish("event", {sn, event, timestamp} )
end

function app:on_mqtt_connect_ok()
	local sub_topics = {
		'/control',
		'/shadow/get/accepted',
		'/shadow/update/rejected',
		'/shadow/update/documents',
		'/thing/topo/get_reply'
	}
	local sys_id = self._sys:id()
	local conf = self._conf
	local topic_base = string.format('iot/%s/%s/%s', conf.project_code, conf.product_code, sys_id)
	for _, v in ipairs(sub_topics) do
		self:subscribe(topic_base..v, 1)
	end

	---[[sub devices online]]--
	-- TODO:
	for k, v in pairs(self._device_map) do
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
	end
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

	self._log:info("Recevied", mid, topic, payload)
	return
end
--- 返回应用对象
return app
