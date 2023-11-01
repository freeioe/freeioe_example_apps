local cjson = require 'cjson.safe'
local mqtt_app = require 'app.base.mqtt'
local uuid = require 'uuid'
local ioe = require 'ioe'

local http_auth = require 'http_auth'
local csv_tpl = require 'csv_tpl'

local app = mqtt_app:subclass("GRID_BJ_PD_MQTT_APP")
app.static.API_VER = 14

function app:on_init()
	local sys = self:sys_api()
	local conf = self:app_conf()
	local host = conf.host
	if conf.port then
		host = host .. ':' .. conf.port
	end
	self._http_auth = http_auth:new(sys, host)
	self._gateway_sn = conf.sn or ioe.id()
	self._data_fire_period = conf.period or 5000

	csv_tpl.init(sys:app_dir())

	--
	--disable period buffer and cov ttl
	conf.period = 0
	conf.ttl = 0
end

function app:on_start()
	local log = self:log_api()
	local sys = self:sys_api()
	local conf = self:app_conf()

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

	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
	end
	self._tpl = tpl

	self._last_data_fire = ioe.now()
	return mqtt_app.on_start(self)
end

function app:mqtt_auth()
	local r, err = self._http_auth:auth()
	if r and r.content then
		local conf = self:app_conf()

		local chn = self._http_auth:get_channel('mqtt')
		local addr = chn.addr
		local mqtt_host, mqtt_port = string.match('^([^:]+):(%d+)$')


		self._mqtt_id = self._http_auth:get_gateway_id()
		local username = conf.username
		local password = conf.password

		return {
			client_id = self._mqtt_id,
			username = username,
			password = password,
			clean_session = true,
			host = mqtt_host,
			port = mqtt_port,
		}
	else
		return nil, err or "Cannot auth with http server"
	end
end

function app:fire_data()
	local topic = self._http_auth:get_topic('DATA_BASE')
	if not topic then
		self._log:error('topic not found!')
		return
	end

	local cov = self._cov

	local snapshot = cov:snapshot()
	local now = os.date('%Y%m%dT%H%M%S')

	local datas = {}
	local props = self._tpl.props or {}
	for _, prop in ipairs(props) do
		local key = string.format("%s/%s", prop.sn, prop.name)
		local val = snapshot[key]
		if val then
			-- value, timestamp, qualit
			local dev = self._dev_map[prop.node_id]
			if dev then
				local d = datas[dev.deviceId] or {
					deviceId = dev.deviceId,
					serviceId = dev.serviceId,
					eventTime = now,
					data = {{}}
				}

				d.data[1][prop.srv_name] = val[1]

				datas[dev.deviceId] = d
			end
		end
	end

	local devs = {}
	for k, v in pairs(datas) do
		devs[#devs + 1] = v
	end
	local payload, err = cjson.encode({ devices = devs })
	if not payload then
		self._log:error(err)
		return
	end

	return self:publish(topic.topic, payload, topic.qos, false)
end

function app:pack_key(app, sn, input, prop)
	if prop ~= 'value' then
		return
	end

	local props = self._tpl.props or {}
	for _, prop in ipairs(props) do
		if prop.sn == sn and prop.name == input then
			return string.format("%s/%s", sn, input)
		end
	end
	return
end

function app:on_publish_data(key, value, timestamp, quality)
	self._has_data_update = true
	return true -- do nothing
	--[[
	local sn, input, prop = string.match(key, '^([^/]+)/([^/]+)/(.+)$')
	local msg = {
		reqId = uuid.new(),
		method = "thing.property.post",
		version = "1.0",
		timestamp = (timestamp * 1000) // 1,
		properties = {
			[input] = value
		}
	}
	return self:publish(self._mqtt_topic_prefix.."/property/post", cjson.encode(msg), 1, false)
	]]--
end

function app:on_publish_data_list(val_list)
	self._has_data_update = true
	return true
	--[[
	for _, v in ipairs(val_list) do
		self:on_publish_data(table.unpack(v))
	end
	return true
	]]--
end


--[[
function app:on_event(app, sn, level, type_, info, data, timestamp)
	return self:publish(self._mqtt_topic_prefix.."/events", cjson.encode(msg), 1, false)

end
]]--

function app:on_publish_cached_data_list(val_list)
	return true
end

function app:on_publish_devices(devices)
	return true
	--return self:publish(self._mqtt_topic_prefix.."/devices", cjson.encode(devices), 1, true)
end

function app:on_mqtt_connect_ok()
	local c = self:app_conf()
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/property/invoke', 1) -- 可写属性更新
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/command/invoke', 1) -- 可写属性更新
	self:subscribe('thing.'..c.product_key..'/'..c.device_name..'/response/c2d', 1) -- 云端调用响应

	--return self:publish(self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="ONLINE"}), 1, true)
end

function app:on_mqtt_message(mid, data, qos, retained)
	--print(...)
	-- invodke 
	local property_example = [[
{
	"reqId":<uuid>,
	"method":"thing.property.invoke",
	"version":"1.0",
	"timestamp":1610212132010, --ms
	"properties":{
		"log_url":"http://xxx.xxx.xx.xx"
	}
}
]]
	local command_example = [[
{
	"reqId":<uuid>,
	"method":"thing.command.invoke",
	"version":"1.0",
	"timestamp":1610212132010, --ms
	"params":{
		"test":"hello world",
		"format":"plain text"
	}
}
]]

	local response_example = [[
{
	"reqId":<uuid>,
	"method":"thing.property.post",
	"code":200,
	"description":"The property 'sn' has been updated successfully."
}
]]
end

--[[
function app:mqtt_will()
	return self._mqtt_topic_prefix.."/status", cjson.encode({device=mqtt_id, status="OFFLINE"}), 1, true
end
]]--

function app:on_run(tms)
	if self._has_data_update then
		self._has_data_update = false
		self:fire_data()
	else
		local diff = ioe.now() - self._last_data_fire
		if diff > self._data_fire_period then
			self:fire_data()
		end
	end
	return 1000
end

--- 返回应用对象
return app


