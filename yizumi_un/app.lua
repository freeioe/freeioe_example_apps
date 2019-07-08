--- 导入需求的模块
local class = require 'middleclass'
local opcua = require 'opcua'
local conf_helper = require 'app.conf_helper'
local csv_tpl = require 'csv_tpl'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("FREEIOE_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--local default_modal = 'UN200A5_s'
local default_modal = 'UN200A5'

---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如app1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._connect_retry = 1000

	--- Set default
	conf.modal = conf.modal or default_modal
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	-- Cleanup nodes buffer
	self._nodes = {}

	--- 获取节点
	for _, input in pairs(self._inputs) do
		local prop = self._input_props[input.name]
		if not self._nodes[input.name] then
			local id =  opcua.NodeId.new(prop.ns, prop.i)
			local obj, err = client:getNode(id)
			if obj then
				self._nodes[input.name] = obj

				if not prop.desc then
					prop.desc = obj.displayName.text
					self._log:debug("Read displayName", prop.desc)
				end
			else
				self._log:warning("Cannot get OPCUA node", id)
			end

			self._sys:sleep(0)
		end
	end
	
	-- Set client object
	self._client = client

	self:save_input_desc(self._input_props)
end

function app:save_input_desc(inputs)
	local conf = self._conf
	local desc_map = {}
	for k, v in pairs(inputs) do
		desc_map[k] = v.desc
	end
	local str, err = cjson.encode(desc_map)
	if not str then
		self._log:warning("JSON Encode error", err)
		return
	end

	local desc_file = self._sys:app_dir() ..'/'..conf.modal..'.txt'
	local f, err = io.open(desc_file, 'w+')
	if not f then
		self._log:warning("Failed to open description file", err)
		return
	end
	f:write(str)
	f:close()
end

function app:load_input_desc()
	local conf = self._conf
	local desc_file = self._sys:app_dir() ..'/'..conf.modal..'.txt'
	local f, err = io.open(desc_file, 'r')
	local input_desc = {}
	if f then
		local str = f:read('*a')
		local desc_map, err = cjson.decode(str)
		if desc_map then
			input_desc = desc_map
		end
		f:close()
	end
	return input_desc
end

---
-- 连接断开后的处理函数
function app:on_disconnect()
	self._nodes = {}
	self._client = nil
	self._sys:timeout(self._connect_retry, function() self:connect_proc() end)
	self._connect_retry = self._connect_retry * 2
	if self._connect_retry > 2000 * 64 then
		self._connect_retry = 2000
	end
end

---
-- 连接处理函数
function app:connect_proc()
	self._log:notice("OPC Client start connection!")
	local client = self._client_obj
	local conf = self._conf

	local ep = conf.endpoint or "opc.tcp://172.30.0.187:4840"
	self._log:info("Client connect endpoint", ep)

	local r, err
	if conf.auth then
		self._log:info("Client connect with username&password")
		r, err = client:connect_username(ep, conf.auth.username, conf.auth.password)
	else
		self._log:info("Client connect without username&password")
		r, err = client:connect(ep)
	end

	if r and r == 0 then
		self._log:notice("OPC Client connect successfully!")
		self._connect_retry = 2000
		self:on_connected(client)
	else
		local err = err or opcua.getStatusCodeName(r)
		self._log:error("OPC Client connect failure!", err)
		self:on_disconnect()
	end
end

function app:load_encryption(conf)
	local sys = self._sys

	local securityMode = nil
	if (conf.encryption.mode) then
		if mode == 'SignAndEncrypt' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGNANDENCRYPT
		end
		if mode == 'Sign' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_SIGN
		end
		if mode == 'None' then
			securityMode = opcua.UA_MessageSecurityMode.UA_MESSAGESECURITYMODE_NONE
		end
	end

	local cert_file = sys:app_dir()..(conf.encryption.cert or "certs/cert.der")
	local key_file = sys:app_dir()..(conf.encryption.key or "certs/key.der")

	local cert_fn = "certs/certt.der"
	if conf.encryption.cert and string.len(conf.encryption.cert) > 0 then
		cert_fn = conf.encryption.cert
	end
	local cert_file = sys:app_dir()..cert_fn

	local key_fn = "certs/key.der"
	if conf.encryption.key and string.len(conf.encryption.key) > 0 then
		key_fn = conf.encryption.key
	end

	local key_file = sys:app_dir()..key_fn

	return {
		cert = cert_file,
		key = key_file,
		mode = securityMode,
	}
end

--- 应用启动函数
function app:start()
	--- 设定接口处理函数
	self._api:set_handler({
		on_output = function(...)
			print(...)
		end,
		on_ctrl = function(...)
			print(...)
		end
	})

	self._nodes = {}

	--- 生成OpcUa客户端对象
	local conf = self._conf
	local sys = self._sys
	local client = nil

	if conf.encryption then
		local cp = self:load_encryption(conf)
		self._log:info("Create client with entryption", cp.mode, cp.cert, cp.key)
		client = opcua.Client.new(cp.mode, cp.cert, cp.key)
	else
		self._log:info("Create client without entryption.")
		client = opcua.Client.new()
	end

	local config = client.config
	config:setTimeout(5000)
	config:setSecureChannelLifeTime(10 * 60 * 1000)

	local app_uri = conf.app_uri or "urn:freeioe:opcuaclient"
	config:setApplicationURI(app_uri)

	self._client_obj = client

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()

	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(conf.modal)

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = tpl.meta.name
	meta.manufacturer = tpl.meta.manufacturer
	meta.description = tpl.meta.desc
	meta.series = tpl.meta.series

	local input_desc = self:load_input_desc()
	local inputs = {}
	self._input_props = {}
	for _, v in ipairs(tpl.inputs) do
		v.desc = v.desc or input_desc[v.name]
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc or v.name,
			vt = v.vt
		}
		self._input_props[v.name] = v 
	end

	self._inputs = inputs
	print(cjson.encode(inputs))
	self._dev = self._api:add_device(sys_id..'.'..meta.name, meta, inputs)

	--- 发起OpcUa连接
	self._sys:fork(function() self:connect_proc() end)

	return true
end

--- 应用退出函数
function app:close(reason)
	print('close', self._name, reason)
	--- 清理OpcUa客户端连接
	self._client = nil
	if self._client_obj then
		self._nodes = {}
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

--- 应用运行入口
function app:run(tms)
	local begin_time = self._sys:time()

	if not self._client then
		return 1000
	end

	local dev = self._dev

	--- 获取节点当前值数据
	for _, input in pairs(self._inputs) do
		local prop = self._input_props[input.name]
		local node = self._nodes[input.name]

		local now = self._sys:time()
		if node then
			local dv = node.dataValue
			local ts = opcua.DateTime.toUnixTime(dv.sourceTimestamp or dv.serverTimestamp)
			--- 设定当前值
			local value = tonumber(dv.value:asString()) --- The data type always String -_-!
			if value then
				dev:set_input_prop(input.name, "value", value, ts or now, 0)
			else
				self._log:warning("Read "..input.name.." failed!!")
			end
		else
			-- TODO:
			-- dev:set_input_prop(k, "value", 0, now, 1)
		end
	end

	local next_tms = (self._conf.loop_gap or 1000) - (self._sys:time() - begin_time)

	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app

