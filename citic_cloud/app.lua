local ioe = require 'ioe'
local cjson = require 'cjson.safe'
local base_mqtt = require 'app.base.mqtt'

--- 创建应用（名称，最小API版本)
local app = base_mqtt:subclass("_CITIC_CLOUD_MQTT")
app.static.API_VER = 4

function app:initialize(name, sys, conf)
	--conf.ttl = nil --- 禁止TTL
	conf.period = 1
	--conf.period = 0 --- 数据不打包
	conf.enable_data_cache = nil --- 不开启短线缓存
	conf.up_topic = conf.up_topic or "6pmux/p_6pmv9"
	conf.down_topic = conf.down_topic or "6pmux/s_6pmv8"

	base_mqtt.initialize(self, name, sys, conf)
	self._log:debug("Citic cloud app intialize!!!")

	self._def_keys = conf.def_keys or {
		test = '779f5e21ca394b5da34ef95bc3a89c8b'
	}
	self._def_key_default = string.lower(conf.def_key_default or '7f9bc4f9986d422ab76268b6d94ed41e')

	self._devid_to_sn = {}
	self._devid_to_sn[self._def_key_default] = self._sys:id()
	for k, eid in pairs(self._def_keys) do
		self._devid_to_sn[eid] = self._sys:id()..'.'..k
	end
end

function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id..".test"

	--- 增加设备实例
	local inputs = {
		{name="tag1", desc="tag1 desc"}
	}

	local meta = self._api:default_meta()
	meta.name = "Example Device"
	meta.description = "Example Device Meta"

	self._dev = self._api:add_device(sn, meta, inputs)

	return base_mqtt.on_start(self)
end

function app:mqtt_auth()
	local conf = self._conf
	return {
		client_id = self._sys:id(),
		username = conf.user or '6pmv7',
		password = conf.password or "a1b3a8616a8c4fbaaac830cc4558e9c7",
		host = conf.server or "iothub.c.citic",
		port = conf.port or "8883",
		clean_session = true,
		enable_tls = true,
		tls_cert = "ca.crt",
	}
end

function app:on_add_device(src_app, sn, props)
	self._log:debug("Citic cloud on_add_device", src_app, sn)
	return true
end

function app:on_del_device(src_app, sn)
	self._log:debug("Citic cloud on_del_device")
	return true
end

function app:on_mod_device(src_app, sn, props)
	self._log:debug("Citic cloud on_mod_device")
	return true
end

function app:pack_key(src_app, sn, input, prop)
	if prop ~= 'value' then
		return nil
	end

	return sn..'/'..input
end

function app:on_publish_devices(devices)
	for sn, props in pairs(devices) do
		self:on_add_device('__fake_name', sn, props)
	end
end

function app:get_device_id(sn)
	local devid = self._def_key_default
	if sn ~= self._sys:id() then
		local ssn, sub = string.match(sn, '^([^.]+)%.(.+)')
		if ssn == self._sys:id() then
			devid = self._def_keys[sub]
		else
			devid = self._def_keys[sn]
		end
	end
	return devid
end

function app:on_publish_data(key, value, timestamp, quality)
	if not self:connected() then
		return nil, "MQTT connection lost!"
	end

	local sn, input = string.match(key, '^([^/]+)/(.+)$')
	assert(key and sn and input)

	local devid = self:get_device_id(sn)
	if not devid then
		self._log:trace("Skip device", sn)
		return true
	end

    local msg = {
		eid = devid,
		data = {{
			key = input,
			value = value,
			ts = math.floor(timestamp * 1000),
		}}
	}
	local val, err = cjson.encode(msg)
	if not val then
		self._log:warning('cjson encode failure. error: ', err)
		return true -- skip this data
	end
	self._log:trace("fire topic", val)

	return self:publish(self._conf.up_topic, val, 1, false)
end

--- The implementation for publish data in list (zip compressing required)
function app:on_publish_data_list(val_list)
	assert(val_list)

	local val_count = #val_list
	self._log:trace('publish_data_list begin',  #val_list)

	if val_count == 0 then
		return true
	end

	if not self:connected() then
		self._log:trace('publish_data_list connection not ready!')
		return nil, "MQTT connection lost!"
	end

--[[ property.batch.json ]]--
	local data_list = {}
	for _, v in ipairs(val_list) do
		local sn, input = string.match(v[1], '^([^/]+)/(.+)$')

		local devid = self:get_device_id(sn)
		if devid then
			if not data_list[devid] then
				data_list[devid] = {}
			end
			table.insert(data_list[devid], {
				key = input,
				value = v[2],
				ts = math.floor(v[3] * 1000)
			})
		end
	end

	for devid, data in pairs(data_list) do
		local msg = {
			eid = devid,
			data = data
		}

		local val, err = cjson.encode(msg)
		--print(val)
		if not val then
			self._log:warning('cjson encode failure. error: ', err)
			return true -- skip current datas
		end

		local deflated = self:compress(val)
		--local r, err = self:publish(self._conf.up_topic, deflated, 1, false)
		self._log:trace("compress data from: ", string.len(val), "to:", string.len(deflated))
		self._log:trace("fire topic", val)
		local r, err = self:publish(self._conf.up_topic, val, 1, false)

		if not r then
			return nil, err
		end
	end

	self._log:trace('publish_data_list end!')
	return true
end

function app:on_publish_cached_data_list(val_list)
	local r, err = self:on_publish_data_list(val_list)
	if r then
		return #val_list
	end
	return nil, err
end

-- no return
function app:on_mqtt_connect_ok()
	self._log:debug("Citic cloud on_connect_ok")
	--- 
	self._log:trace("Subscribe", self._conf.down_topic)
	self:subscribe(self._conf.down_topic, 1)
	--self:subscribe('+/#', 1)
end

function app:send_heartbeat()
	for k, v in pairs(self._devid_to_sn) do
		self._log:debug("Fire heartbeat for device", k)
		local hb = {
			deviceid = k,
			ts = math.floor(self._sys:time() * 1000),
			hb = 300
		}
		local val, err = cjson.encode(hb)
		if val then
			self:publish(self._conf.up_topic, val, 1, false)
		end
	end
end

function app:on_mqtt_message(packet_id, topic, payload, qos, retained)
	self._log:trace('MQTT Message', topic, qos, retained, payload)
	local data = cjson.decode(payload)
	local devid = data.eid or data.deviceid
	if not devid then
		self._log:warning('Device id is missing!')
		return
	end

	if data.output then
		local dev_sn = self._devid_to_sn[devid]
		local device, err = self._api:get_device(dev_sn)
		if not device then
			self._log:error('Cannot parse payload!')
			return
		end
		local r, err = device:set_output_prop(data.output, 'value', data.value)
		if not r then
			self._log:error('Set output prop', err)
		end
	end
end

function app:on_toedge_result(id, dev_sn, input, result, err)
end

function app:on_output_result(app_src, priv, result, err)
	if result then
		return self:on_toedge_result(priv.id, priv.dev_sn, priv.input, 0, "done")
	else
		return self:on_toedge_result(priv.id, priv.dev_sn, priv.input, -99, err)
	end
end

function app:on_run(tms)
	if not self._hb_last or (self._sys:time() - self._hb_last >= 60) then
		self._hb_last = self._sys:time()
		self:send_heartbeat()
	end

	self._dev:set_input_prop('tag1', 'value', math.random(1, 1000))

	return 1000
end

--- 返回应用类对象
return app

