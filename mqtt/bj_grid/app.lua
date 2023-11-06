local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local ioe = require 'ioe'

local http_auth = require 'http_auth'
local csv_tpl = require 'csv_tpl'

local app = mqtt_app:subclass("GRID_BJ_PD_MQTT_APP")
app.static.API_VER = 15 -- Require API_VER 15

function app:on_init()
	local sys = self:sys_api()
	local conf = self:app_conf()

	if ioe.developer_mode() then
		--conf.host = '10.121.0.15'
		conf.host = '10.131.0.25'
		conf.port = 23106
		conf.sn = 'FHETN12344000002'
		conf.period = 1
	end

	local host = conf.host
	if conf.port then
		host = host .. ':' .. conf.port
	end

	self._http_auth = http_auth:new(sys, host)

	local dev_sn = string.upper(conf.sn or ioe.id())
	if string.len(dev_sn) < 16 then
		dev_sn = string.rep('0', 16 - string.len(dev_sn))..dev_sn
	elseif string.len(dev_sn) > 16 then
		dev_sn = string.sub(dev_sn, -16) -- last 16 chars
	end
	self._gateway_sn = dev_sn

	self._data_fire_period = (conf.period or 15) * 60 * 1000 -- 分钟
	self._dev_map = {}

	self._mid = 0
	self._changed_data = {}

	csv_tpl.init(sys:app_dir())

	--
	--disable period buffer and cov ttl
	conf.period = 0
	conf.ttl = 0
end

function app:get_mid()
	if self._mid == 0xFFFFFFFF then
		self._mid = 1
	else
		self._mid = self._mid + 1
	end
	return self._mid
end

function app:on_start()
	local log = self:log_api()
	local sys = self:sys_api()
	local conf = self:app_conf()

	---获取设备序列号和应用配置
	local sys_id = sys:id()
	--- Mapping
	local function map_dev_sn(sn)
		sn = sn or 'GW'
		if sn == 'GW' then
			return sys_id
		end
		sn = string.gsub(sn, '^GW(%..*)$', sys_id..'%1')
		return sn
	end
	local function map_node_id(node_id)
		-- 15: 展示传感器 1: 485 1: 485-I
		return '1511'..node_id..self._gateway_sn
	end
	local function map_dev_name(name)
		return name .. self._gateway_sn
	end

	local tpl_file = 'test'
	local tpl_id = conf.tpl
	local tpl_ver = conf.ver

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	log:info("Loading template", tpl_file)
	local tpl, err = csv_tpl.load_tpl(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end

	-- 映射ID
	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
		v.node_id = map_node_id(v.node_id)
	end
	for _, v in ipairs(tpl.devs) do
		v.node_id = map_node_id(v.node_id)
		if v.name and string.len(v.name) > 0 then
			v.name = map_dev_name(v.name)
		else
			v.name = v.node_id
		end
	end

	self._tpl = tpl

	self._last_data_fire = ioe.now()
	return mqtt_app.on_start(self)
end

function app:mqtt_auth()
	local meta = self._tpl.meta
	local gw_name = meta.name..self._gateway_sn
	local r, err = self._http_auth:auth(self._gateway_sn, meta.manufacturer, meta.model, gw_name, meta.desc)
	if r then
		local chn, err = self._http_auth:get_channel('channel_mqtt_main')
		if not chn then
			return nil, err
		end

		local addr = assert(chn.addr)
		local mqtt_host, mqtt_port = string.match(addr, '^([^:]+):(%d+)$')


		self._mqtt_id = self._http_auth:get_gateway_id()
		-- local conf = self:app_conf()
		-- local username = conf.username
		-- local password = conf.password

		return {
			client_id = self._mqtt_id,
			-- username = username,
			-- password = password, -- not required username/password
			clean_session = true,
			host = mqtt_host,
			port = mqtt_port,
		}
	else
		return nil, err or "Cannot auth with http server"
	end
end

function app:pack_key(src_app, sn, input, prop)
	if prop ~= 'value' then
		return
	end
	if not self._tpl then
		-- Not started!!
		return
	end

	local props = self._tpl.props or {}
	for _, p in ipairs(props) do
		if p.sn == sn and p.name == input then
			return string.format("%s/%s", sn, input)
		end
	end
	return
end

function app:on_publish_data(key, value, timestamp, quality)
	local sn, input = string.match(key, '^([^/]+)/(.+)$')

	local props = self._tpl.props or {}
	for _, prop in ipairs(props) do
		if prop.sn == sn and prop.name == input then
			if prop.dt == 'DI' then
				-- buffer this
				self._has_data_update = true
				self._changed_data[key] = {value, timestamp, quality}
			end
		end
	end

	return true -- do nothing
end

function app:on_publish_data_list(val_list)
	assert(false) -- should not be here
	return true
end


--[[
function app:on_event(app, sn, level, type_, info, data, timestamp)
	return self:publish(self._mqtt_topic_prefix.."/events", cjson.encode(msg), 1, false)
end
]]--

function app:on_add_device(src_app, sn, props)
	--- TODO: for device online?
end

function app:on_mode_device(src_app, sn, props)
	--- TODO: for device online?
end

function app:on_del_device(src_app, sn)
	--- TODO: for device offline?
end

function app:on_publish_cached_data_list(val_list)
	return true
end

function app:on_publish_devices(devices)
	return true
	--return self:publish(self._mqtt_topic_prefix.."/devices", cjson.encode(devices), 1, true)
end

function app:on_mqtt_connect_ok()
	local conf = self:app_conf()
	local log = self:log_api()
	local topic = assert(self._http_auth:get_topic('DEVICE_ADD_RESP'))
	log:info('MQTT subscribe', topic.topic, topic.qos)
	self:subscribe(topic.topic, topic.qos)
	topic = assert(self._http_auth:get_topic('DEVICE_UPDATE_RESP'))
	log:info('MQTT subscribe', topic.topic, topic.qos)
	self:subscribe(topic.topic, topic.qos)
	topic = assert(self._http_auth:get_topic('CMD_BASE'))
	log:info('MQTT subscribe', topic.topic, topic.qos)
	self:subscribe(topic.topic, topic.qos)

	return self:sub_dev_reg()
end

function app:on_mqtt_disconnect()
	self._connection_ready = nil
end

function app:on_mqtt_message(mid, topic, data, qos, retained)
	local log = self:log_api()
	log:debug(topic, data)
	local msg, err = cjson.decode(data)
	if not msg then
		log:error('MQTT recv data has JSON error', err)
		return
	end
	--[[
	local gw_id, topic = string.match(topic, '/v1/devices/([^/]+)/(.+)$')
	if gw_id ~= self._mqtt_id then
		log:error('Recevied incorrect topic', topic)
		return
	end
	if topic == 'topo/addResponse' then
	end
	]]--
	local topic_id = self._http_auth:find_topic_id(topic)
	if topic_id == 'DEVICE_ADD_RESP' then
		self._dev_map = {}
		if msg.statusCode ~= 0 then
			log:error('Device add response error code', msg.statusDesc, data)
		end
		for _, v in ipairs(msg.data or {}) do
			if (v.statusCode ~= 0) then
				log:error('Sub device add error', v.statusDesc, cjson.encode(v.deviceInfo))
			else
				local info = v.deviceInfo
				log:info('Got device add info', cjson.encode(info))
				self._dev_map[info.nodeId] = info.deviceId
			end
		end

		local sys = self:sys_api()
		self._first_login = true
		sys:timeout(100, function()
			self:sub_dev_online()
		end)
	end
	if topic_id == 'DEVICE_UPDATE_RESP' then
		if msg.statusCode ~= 0 then
			log:error('Device update response error code', msg.statusDesc, data)
		end
		for _, v in ipairs(msg.data or {}) do
			if (v.statusCode ~= 0) then
				log:error('Sub device update error', v.statusDesc, cjson.encode(v.deviceInfo))
			else
				log:info('Got device update info', v.deviceId)
			end
		end
	end
end

function app:sub_dev_online()
	local log = self:log_api()
	local sts = {}
	for _, v in pairs(self._dev_map) do
		table.insert(sts, {
			deviceId = v,
			status = 'online'
		})
	end

	local topic = self._http_auth:get_topic('DEVICE_UPDATE')
	if not topic then
		log:error('topic not found!')
		return
	end

	local payload, err = cjson.encode({ mid = self:get_mid(), deviceStatuses = sts })
	if not payload then
		log:error(err)
		return
	end

	log:info('Online all sub devices')

	return self:publish(topic.topic, payload, topic.qos, false)
end

function app:sub_dev_reg()
	local log = self:log_api()
	-- 子设备注册
	--return self:publish(self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
	local props = self._tpl.props or {}
	local tpl_devs = self._tpl.devs or {}
	local devs = {}
	for _, prop in ipairs(props) do
		if not devs[prop.node_id] then
			for _, v in ipairs(tpl_devs) do
				if v.node_id == prop.node_id then
					devs[prop.node_id] = v
				end
			end
		end
	end

	local deviceInfo = {}

	for _, v in ipairs(tpl_devs) do
		table.insert(deviceInfo, {
			nodeId = v.node_id,
			name = v.name,
			desc = v.desc,
			manufacturerId = v.manufacturer,
			model = v.model
		})
	end

	local topic = self._http_auth:get_topic('DEVICE_ADD')
	if not topic then
		log:error('topic not found!')
		return
	end

	local payload, err = cjson.encode({ mid = self:get_mid(), deviceInfo = deviceInfo })
	if not payload then
		log:error(err)
		return
	end
	log:info('Register all sub devices', payload)

	return self:publish(topic.topic, payload, topic.qos, false)
end

function app:fire_snapshot_data()
	local log = self:log_api()
	-- Set the last data fire timestamp
	self._last_data_fire = self._last_data_fire + self._data_fire_period

	local snapshot1 = self._cov:snapshot()
	-- print('fire_snapshot_data', cjson.encode(snapshot1))
	local topic, err = self._http_auth:get_topic('DATA_BASE')
	if not topic then
		self._log:error('topic not found!', err)
		return nil, err
	end

	local cov = self._cov

	local snapshot = cov:snapshot()
	local now = os.date('%Y%m%dT%H%M%SZ')

	local ai_datas = {}
	local di_datas = {}
	local props = self._tpl.props or {}
	for _, prop in ipairs(props) do
		local key = string.format("%s/%s", prop.sn, prop.name)
		local val = snapshot[key]
		if val then
			local datas = prop.dt == 'DI' and di_datas or ai_datas
			-- value, timestamp, qualit
			local dev_id = self._dev_map[prop.node_id]
			if dev_id then
				local d = datas[dev_id] or {
					deviceId = dev_id,
					serviceId = prop.dt == 'DI' and 'discrete' or 'analog',
					eventTime = now,
					data = {{}}
				}

				d.data[1][prop.srv_name] = val[1]

				datas[dev_id] = d
			else
				self._log:error('deviceId not found for '..prop.node_id)
			end
		end
	end

	local devs = {}
	for _, v in pairs(di_datas) do
		devs[#devs + 1] = v
	end
	for _, v in pairs(ai_datas) do
		devs[#devs + 1] = v
	end
	local payload, err = cjson.encode({ devices = devs })
	if not payload then
		self._log:error(err)
		return nil, err
	end
	log:debug('fire snapshot data', payload)

	return self:publish(topic.topic, payload, topic.qos, false)
end

function app:fire_di_data(data_list)
	local log = self:log_api()
	local topic = self._http_auth:get_topic('DATA_BASE')
	if not topic then
		self._log:error('topic not found!')
		return
	end

	local now = os.date('%Y%m%dT%H%M%SZ')

	local datas = {}
	local props = self._tpl.props or {}
	for _, prop in ipairs(props) do
		local key = string.format("%s/%s", prop.sn, prop.name)
		local val = data_list[key]
		if val and prop.dt == 'DI' then
			-- value, timestamp, qualit
			local dev_id = self._dev_map[prop.node_id]
			if dev_id then
				local d = datas[dev_id] or {
					deviceId = dev_id,
					serviceId = 'discrete_change',
					eventTime = now,
					data = {{}}
				}

				d.data[1][prop.srv_name] = val[1]

				datas[dev_id] = d
			end
		end
	end

	local devs = {}
	for _, v in pairs(datas) do
		devs[#devs + 1] = v
	end
	local payload, err = cjson.encode({ devices = devs })
	if not payload then
		self._log:error(err)
		return nil, err
	end
	log:debug('fire discrete change data', payload)

	return self:publish(topic.topic, payload, topic.qos, false)
end

--[[
function app:mqtt_will()
	return self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true
end
]]--

function app:on_run(tms)
	if self._first_login then
		-- print('first_login')
		self._last_data_fire = ioe.now() - self._data_fire_period
		self:fire_snapshot_data()
		-- Clear changed data
		self._changed_data = {}
		self._has_data_update = false
		self._first_login = nil
		self._connection_ready = true
		return 1000
	end
	if not self._connection_ready then
		self._changed_data = {}
		self._has_data_update = false
		return 1000
	end

	if self._has_data_update then
		self._has_data_update = false
		local data = self._changed_data
		self._changed_data = {}
		-- print(cjson.encode(data))
		self:fire_di_data(data)
	end

	local diff = ioe.now() - self._last_data_fire
	-- print('diff', diff, self._data_fire_period)

	if diff > self._data_fire_period then
		self:fire_snapshot_data()
	end

	return 1000 -- ASAP
end

--- 返回应用对象
return app


