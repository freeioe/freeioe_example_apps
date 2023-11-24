local cjson = require 'cjson.safe'
local app_base = require 'app.base'
local ioe = require 'ioe'
local mqtt_client = require 'mqtt.skynet.client'
local crypt = require "lcrypt"

local app = app_base:subclass("MQTT_BXVPN_APP")
app.static.API_VER = 15 -- Require API_VER 15

function app:on_init()
	local conf = self:app_conf()

	self._connecting = nil
	self._mqtt_reconnect_timeout = 1000
	self._max_mqtt_reconnect_timeout = 512 * 1000 -- about 8.5 minutes

	self._safe_call = function(f, ...)
		local r, er, err = xpcall(f, debug.traceback, ...)
		if not r then
			self._log:warning('Code bug', er, err)
			return nil, er and tostring(er) or nil
		end
		return er, er and tostring(err) or nil
	end

	if ioe.developer_mode() then
		conf.sn = '1213132356134354'
		conf.host = '113.57.212.64'
		conf.port = 41801
		conf.user = 'iBaoXin@@@202305'
		conf.passwd = 'iBaoXin@@@202305'
		conf.aes_iv = 'iBaoXin@@@202305'
		conf.aes_key = 'iBaoXin@@@202305'
	end

	local host = conf.host
	if conf.port then
		host = host .. ':' .. conf.port
	end

	local mqtt_host, mqtt_port = string.match(host, '^([^:]+):(%d+)$')

	local dev_sn = string.upper(conf.sn or ioe.id())
	if string.len(dev_sn) < 16 then
		dev_sn = string.rep('0', 16 - string.len(dev_sn))..dev_sn
	elseif string.len(dev_sn) > 16 then
		dev_sn = string.sub(dev_sn, -16) -- last 16 chars
	end
	self._gateway_sn = dev_sn

	local aes_sn, err = crypt.aes_cbc_encrypt(16, conf.aes_key, self._gateway_sn..'=json', conf.aes_iv, 1)
	if not aes_sn then
		self._log:error(err)
	end
	--local aes_sn = crypt.aes_cbc_encrypt(16, conf.aes_key, self._gateway_sn, conf.aes_iv, 5)
	local aes_sn_b = crypt.base64encode(aes_sn)
	self._log:trace("Client ID", aes_sn_b)

	self._mqtt_opt = {
		client_id = aes_sn_b,
		clean_session = true,
		username = conf.user,
		password = conf.passwd,
		host = mqtt_host,
		port = mqtt_port,
		keep_alive = 60,
	}
end

function app:connected()
	return self._mqtt_client ~= nil and self._mqtt_client:connected()
end

function app:publish(topic, data, qos, retained)
	if not self._mqtt_client then
		self._log:trace("MQTT not connected!")
		return nil, "MQTT not connected!"
	end

	return self._mqtt_client:publish(topic, data, qos, retained)
end

function app:subscribe(topic, qos)
	if not self._mqtt_client then
		return nil, "MQTT not connected!"
	end
	return self._mqtt_client:subscribe(topic, qos or 1)
end

function app:unsubscribe(topic)
	return self._mqtt_client:unsubscribe(topic)
end

function app:connect()
	if not self._mqtt_client then
		return self:_connect_proc()
	end
	return nil, "Already connected"
end

function app:disconnect()
	if self._mqtt_client then
		self._mqtt_client:disconnect()
		self._mqtt_client = nil
	end
	return true
end


function app:_start_reconnect()
	local client = self._mqtt_client
	self._mqtt_client = nil

	self._sys:timeout(self._mqtt_reconnect_timeout, function()
		if client then
			client:disconnect()
		end

		-- If this is connecting
		if self._connecting then
			self._log:error("There is one more reconnecting???")
			return
		end

		self._connecting = true
		self:_connect_proc()
		self._connecting = false
	end)

	self._mqtt_reconnect_timeout = self._mqtt_reconnect_timeout * 2
	if self._mqtt_reconnect_timeout > self._max_mqtt_reconnect_timeout then
		self._mqtt_reconnect_timeout = 1000
	end
end


function app:_connect_proc()
	local log = self._log
	local sys = self._sys

	local option = self._mqtt_opt

	-- 创建MQTT客户端实例
	log:info("MQTT Connect:", option.client_id, option.host, option.port, option.username, option.password)

	local cli = mqtt_client:new(option, self._log)

	-- 注册回调函数
	cli.on_mqtt_connect = function(client, success, rc, msg)
		if success then
			log:notice("ON_CONNECT", success, rc, msg)
			if self._mqtt_client ~= client then
				self._log:warning("There is one client already connected!")
				self._mqtt_client:disconnect()
				self._mqtt_client = client
			end
			self._mqtt_client_last = sys:time()
			self._mqtt_reconnect_timeout = 1000

			if self.on_mqtt_connect_ok then
				self._sys:fork(function()
					self._safe_call(self.on_mqtt_connect_ok, self)
				end)
			end

			self:_fire_devices(1000)
		end
	end

	cli.on_mqtt_disconnect = function(client, msg)
		log:warning("ON_DISCONNECT", msg)
		if not self._mqtt_client or self._mqtt_client == client then
			self._mqtt_client_last = sys:time()

			if self.on_mqtt_disconnect then
				self._sys:fork(function()
					self._safe_call(self.on_mqtt_disconnect, self)
				end)
			end
		end
	end

	if self.on_mqtt_publish then
		cli.on_mqtt_publish = function(client, packet_id)
			self._safe_call(self.on_mqtt_publish, self, packet_id)
		end
	end

	if self.on_mqtt_message then
		cli.on_mqtt_message = function(client, packet_id, topic, data, qos, retained)
			--print(packet_id, topic, data, qos, retained)
			if self.on_mqtt_message then
				self._safe_call(self.on_mqtt_message, self, packet_id, topic, data, qos, retained)
			end
		end
	end

	self._mqtt_client = cli

	return cli:connect()
end


function app:on_start()
	local log = self:log_api()

	self:connect()

	log:debug("MQTT Connector Started!")

	return true
end

function app:on_mqtt_connect_ok()
	local conf = self:app_conf()
	local log = self:log_api()
	local topic = string.format('/DS/%s/property/GET', self._gateway_sn)
	log:info('MQTT subscribe', topic)
	self:subscribe(topic, 0)
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
end

function app:on_run(tms)
	if self._first_login then
		-- print('first_login')
		self._connection_ready = true
		return 1000
	end
	if not self._connection_ready then
		return 1000
	end
	return 1000 -- ASAP
end

--- 应用退出函数
function app:on_close(reason)
	if self._online_check_host then
		ioe.set_online_check_host(nil) -- clear online host check
	end

	self:disconnect()
	return true
end

--- 返回应用对象
return app


