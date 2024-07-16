local cjson = require 'cjson.safe'
local app_base = require 'app.base'
local ioe = require 'ioe'
local lfs = require 'lfs'
local mqtt_client = require 'mqtt.skynet.client'
local crypt = require "lcrypt"
local sysinfo = require 'utils.sysinfo'
local services = require 'utils.services'
local inspect = require 'inspect'
local curl_down = require 'curl_download'

local app = app_base:subclass("MQTT_BXVPN_APP")
app.static.API_VER = 15 -- Require API_VER 15

function app:on_init()
	local conf = self:app_conf()
	local sys = self:sys_api()

	self._connecting = nil
	self._mqtt_reconnect_timeout = 1000
	self._max_mqtt_reconnect_timeout = 512 * 1000 -- about 8.5 minutes

	self._cid = 0

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
		conf.host = '10.80.39.6'
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

	-- padding zeros
	local sn = self._gateway_sn..'=json'..string.rep('\0', 11)

	local aes_sn, err = crypt.aes_cbc_encrypt(16, conf.aes_key, sn, conf.aes_iv, 5)
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
	-- print(inspect(sysinfo.network()))
end

function app:connected()
	return self._mqtt_client ~= nil and self._mqtt_client:connected()
end

function app:publish(topic, data)
	if not self._mqtt_client then
		self._log:trace("MQTT not connected!")
		return nil, "MQTT not connected!"
	end
	local topic_full = string.format('/US/%s/%s', self._gateway_sn, topic)

	local qos = 0
	local retained = false
	self._log:debug("MQTT PUB", topic_full, data)
	return self._mqtt_client:publish(topic_full, data, qos, retained)
end

function app:subscribe(topic)
	if not self._mqtt_client then
		return nil, "MQTT not connected!"
	end
	local qos = 0
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

function app:start_vpn_service()
	local sys = self:sys_api()
	local conf_path = sys:app_dir()..'/client.conf'
	if self._service then
		self._service:stop()
		self._service:cleanup()
		self._service:remove()
	end
	self._service = services:new(self:app_name(), 'openvpn', {'--config', conf_path})
	local r, err = self._service:create()
	if not r then
		self._log:error('VPN services create error', err)
		return
	end
	r, err = self._service:start()
	if not r then
		self._log:error('VPN service start error', err)
	end
end

function app:stop_vpn_services()
	if self._services then
		self._service:stop()
		self._service:cleanup()
	end
end

function app:vpn_status()
	if self._services then
		return self._services:status()
	end
	return nil, "VPN services not created"
end

function app:on_start()
	local log = self:log_api()
	local sys = self:sys_api()

	self:connect()

	local config = self:get_vpn_config()
	if config.vpnShutdown == 'no shutdown' then
		local conf_path = sys:app_dir()..'/client.conf'
		local mode = lfs.attributes(conf_path, 'access')
		if mode then
			self:start_vpn_service()
		end
	end

	log:debug("MQTT Connector Started!")

	return true
end

function app:on_mqtt_connect_ok()
	local conf = self:app_conf()
	local log = self:log_api()
	local topic = string.format('/DS/%s/property/GET', self._gateway_sn)
	log:info('MQTT subscribe', topic)
	self:subscribe(topic)
	topic = string.format('/DS/%s/property/SET', self._gateway_sn)
	log:info('MQTT subscribe', topic)
	self:subscribe(topic)
end

function app:on_mqtt_disconnect()
	self._connection_ready = nil
end

function app:get_cid()
	local cid = self._cid
	self._cid = cid + 1
	return cid
end

function app:get_network_info()
	local net_info = sysinfo.network()
	local data = {}
	for name, info in pairs(net_info) do
		print(name)
		data[name..'IpAddress'] = info.ipv4
		data[name..'WorkMode'] = ""
	end
	return data
end

function app:get_lower_ip()
	local net_info = sysinfo.network()
	local data = {}
	for name, info in pairs(net_info) do
		table.insert(data, {
			ip = info.ipv4,
			mac = info.hwaddr,
		})
	end
	return data
end

function app:get_vpn_config()
	local sys = self:sys_api()
	local path = sys:app_dir()..'/client.conf.json'
	local f, err = io.open(path, 'r')
	if not f then
		self._log:error(err)
		return {}
	end

	local str = f:read('a')
	f:close()
	
	local conf, err = cjson.decode(str)
	if not conf then
		self._log:error(err)
		return {}
	end

	local update_network = true
	if update_network then
		for k, v in pairs(conf) do
			if string.match(k, '(.+)IpAddress') then
				conf[k] = nil
			end
			if string.match(k, '(.+)WorkMode') then
				conf[k] = nil
			end
		end
		local netinfo = self:get_network_info()
		for k, v in pairs(netinfo) do
			conf[k] = v
		end
	end

	return conf
end

function app:set_vpn_config(new_config)
	local config = self:get_vpn_config()
	for k, v in pairs(new_config) do
		config[k] = v
	end
	local sys = self:sys_api()
	local path = sys:app_dir()..'/client.conf.json'
	local f, err = io.open(path, 'w+')
	if not f then
		return nil, err
	end
	f:write(cjson.encode(config))
	f:close()
	-- Generate openvpn config file

	local data = {
		'#================= 动态参数配置 ================',
		config.vpnMode,
		config.vpnDev,
		'proto '..config.vpnProtocol,
		'remote '..config.vpnDestination..' '..config.vpnPort,
		config.vpnNoBind,
		'ca '..config.vpnCa,
		'cert '..config.vpnCert,
		'key '..config.vpnKey,
		config.vpnCompress and 'comp-lzo' or '#comp-lzo',
		'cipher '..config.vpnCipher,
		'keepalive 10 '..config.vpnKeepAlive,
		'ns-cert-type server',
		'resolv-retry infinite',
		'persist-key',
		'persist-tun',
		'verb 0'
	}
	local str = table.concat(data, '\n\n')
	local conf_path = sys:app_dir()..'/client.conf'
	local cf, err = io.open(conf_path, 'w+')
	if not cf then
		return nil, err
	end
	cf:write(str)
	cf:close()

	return true
end

function app:on_mqtt_message(mid, topic, data, qos, retained)
	local log = self:log_api()
	log:debug('MQTT RECV', topic, data)
	local msg, err = cjson.decode(data)
	if not msg then
		log:error('MQTT recv data has JSON error', err)
		return
	end
	local tp, sn, s_topic = string.match(topic, '^/([^/]+)/([^/]+)/(.+)$')
	if tp ~= 'DS' then
		log:error('Topic error', tp)
		return
	end

	if s_topic == 'property/GET' then
		local get = msg.GET or {}
		local data = {
			cid = self:get_cid(),
			code = 200,
			GET = {},
		}
		if get.lowerIp then
			local lower_ip = self:get_lower_ip()
			data.GET.lowerIp = lower_ip
		elseif get.config then
			local config = self:get_vpn_config()
			data.config = { json = config }
		else
			local config = self:get_vpn_config()
			local lower_ip = self:get_lower_ip()
			data.config = { json = config }
			data.lowerIp = lower_ip
		end
		return self:publish('property/GET', cjson.encode(data))
	elseif s_topic == 'property/SET' then
		local set = msg.SET or {}
		if set.config then
			local new_config = set.config.json or {}
			local cert_url = new_config.certUrl
			local url, param = string.match(cert_url, '^([^&]+)&(.+)&')
			if url and param == 'cert_id=9527' then
				-- download cert_file'
				local down = curl_down:new()
				local filepath = '/tmp/bxvpn.download.tar.gz'
				local r, err = down:download(url, nil, filepath) 
				if not r then
					self._log:error('download from '..url..' failed. err: '..err)
				end
				-- uncompress cert files
				sysinfo.exec('tar xzvf '..file_path)
			end
			self:set_vpn_config(new_config)
		end
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


