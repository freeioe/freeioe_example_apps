--- 导入需求的模块
local app_base = require 'app.base'
local opcua = require 'opcua'
local csv_tpl = require 'csv_tpl'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

local default_modal = 'MengLiA'
--local default_modal = 'UN200A5'

function app:connected()
	return self._client ~= nil
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	local client = client

	--[[
	local function load_opcua_node(ns, i)
		if not client then
			self._log:warning('no client', ns, i)
			return nil
		end

		local id = opcua.NodeId.new(ns, i)
		local obj, err = client:getNode(id)
		if not obj then
			self._log:warning("Cannot get OPCUA node", ns, i, id)
		end
		self._sys:sleep(0)
		self._log:debug('got input node', obj, ns, i)
		return obj, err
	end


	--- 获取节点
	for _, input in ipairs(self._tpl.inputs) do
		input.node = input.node or load_opcua_node(input.ns, input.i)
	end

	for _, minput in ipairs(self._tpl.map_inputs) do
		for _, input in ipairs(minput.values) do
			input.node = input.node or load_opcua_node(input.ns, input.i)
		end
	end

	for _, alarm in ipairs(self._tpl.alarms) do
		alarm.node = alarm.node or load_opcua_node(alarm.ns, alarm.i)
	end
	]]--

	for _, input in ipairs(self._tpl.calc_inputs) do
		local m = require('calc_func.'..input.func)
		input.calc_func = m:new(self, input, load_opcua_node)
	end

	-- Set client object
	self._client = client
end

---
-- 连接断开后的处理函数
function app:on_disconnect()
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

	--local ep = conf.endpoint or "opc.tcp://127.0.0.1:4840"
	local ep = conf.endpoint or "opc.tcp://172.30.0.187:55623"
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
function app:on_start()
	local sys = self._sys
	local conf = self._conf
	--conf.modal = conf.modal or default_modal
	self._connect_retry = 1000

	local tpl_id = conf.tpl or 'TPL000000178'
	local tpl_ver = conf.ver or '3'

	local capi = sys:conf_api(tpl_id)
	local data, err = capi:data(tpl_ver)
	if not data then
		self._log:error("Failed loading template from cloud!!!", err)
		return false
	end

	--- 生成OpcUa客户端对象
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
	local tpl = csv_tpl.load_tpl(tpl_id..'_'..tpl_ver)

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = tpl.meta.name
	meta.manufacturer = tpl.meta.manufacturer
	meta.description = tpl.meta.desc
	meta.series = tpl.meta.series

	local inputs = {}
	for _, v in ipairs(tpl.inputs) do
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc or v.name,
			vt = v.vt
		}
	end

	for _, v in ipairs(tpl.map_inputs) do
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc or v.name,
			vt = v.vt
		}
	end

	for _, v in ipairs(tpl.calc_inputs) do
		inputs[#inputs + 1] = {
			name = v.name,
			desc = v.desc or v.name,
			vt = v.vt
		}
	end

	self._tpl = tpl
	--print(cjson.encode(inputs))

	self._dev = self._api:add_device(sys_id..'.'..meta.name, meta, inputs)

	--- 发起OpcUa连接
	self._sys:fork(function() self:connect_proc() end)

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	--- 清理OpcUa客户端连接
	self._client = nil
	if self._client_obj then
		self._client_obj:disconnect()
		self._client_obj = nil
	end
end

--- 应用运行入口
function app:on_run(tms)
	local begin_time = self._sys:time()

	if not self._client then
		return 1000
	end

	local dev = self._dev

	self._log:debug('Start', os.date())

	local function load_opcua_node(ns, i)
		local client = self._client
		if not client then
			self._log:warning('no client', ns, i)
			return nil
		end

		local id = opcua.NodeId.new(ns, i)
		local obj, err = client:getNode(id)
		if not obj then
			self._log:warning("Cannot get OPCUA node", ns, i, id)
		end
		self._sys:sleep(0)
		self._log:debug('got input node', obj, ns, i)
		return obj, err
	end

	local read_val = function(node, vt)
		self._log:debug('reading node', node, vt, node.id)
		if not node then
			return nil
		end
		self._sys:sleep(0)
		local dv = node.dataValue
		local value = tonumber(dv.value:asString())
		if vt == 'int' then
			return math.floor(value)
		end
		return value
	end

	--- 获取节点当前值数据
	for _, input in ipairs(self._tpl.inputs) do
		input.node = input.node or load_opcua_node(input.ns, input.i)
		local node = input.node
		if node then
			local dv = node.dataValue
			--local ts = opcua.DateTime.toUnixTime(dv.sourceTimestamp or dv.serverTimestamp)
			--- 设定当前值
			local value = tonumber(dv.value:asString()) --- The data type always String -_-!
			local now = self._sys:time()
			if value then
				dev:set_input_prop(input.name, "value", value, now, 0)
			else
				self._log:warning("Read "..input.name.." failed!!")
				dev:set_input_prop(input.name, "value", 0, now, 1)
			end
		else
			local now = self._sys:time()
			-- TODO:
			-- dev:set_input_prop(k, "value", 0, now, 1)
		end
	end

	for _, alarm in ipairs(self._tpl.alarms) do
		local alarms = {}
		alarm.node = alarm.node or load_opcua_node(alarm.ns, alarm.i)
		local val = read_val(alarm.node, alarm.vt)
		if val and val > 0 then
			table.insert(alarms, {
				desc = alarm.desc,
				val = val,
				errno = alarm.errno,
			})
		end
		if #alarms > 0 then
			--- TODO: Fire alarm
			local state = 2
			for _, alarm in ipairs(alarms) do
				if alarm.is_error then
					state = 3
				end
			end
			self._err_state = state
		else
			-- TODO: Fire alaram clear
			self._err_state = nil
		end
	end

	for _, minput in ipairs(self._tpl.map_inputs) do
		local val = nil
		for _, input in ipairs(minput.values) do
			intput.node = input.node or load_opcua_node(input.ns, input.i)
			if input.node then
				local v = read_val(input.node, 'int')
				if v == 1 and (not val or val < v) then
					val = v
				end
			end
		end

		local now = self._sys:time()
		if val then
			dev:set_input_prop(minput.name, "value", val, now, 0)
		else
			dev:set_input_prop(minput.name, "value", 0, now, 1)
		end
	end

	for _, input in ipairs(self._tpl.calc_inputs) do
		input.calc_func:run(dev)
	end

	self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app

