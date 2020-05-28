--- 导入需求的模块
local app_base = require 'app.base'
local opcua_client = require 'base.client'
local csv_tpl = require 'csv_tpl'
local cjson = require 'cjson.safe'
local calc_map_input = require 'calc_func.map_input'
local calc_alarm = require 'calc_func.alarm'
local opcua = require 'opcua'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("YIZUMI_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为5,为了以后的接口兼容性)
app.static.API_VER = 5

local alarm_state_input = 'AlarmState'

function app:connected()
	return self._client ~= nil and self._client:connected()
end

function app:on_disconnected(client)
	if self._client ~= client then
		return
	end
	self._ready_to_read = false

	for _, input in ipairs(self._tpl.calc_inputs) do
		if input.calc_func then
			input.calc_func:stop()
			input.calc_func = nil
		end
	end

	for k, input in pairs(self._tpl.map_inputs) do
		if input.calc_func then
			input.calc_func:stop()
			input.calc_func = nil
		end
	end

	for _, input in ipairs(self._tpl.inputs) do
		input.node = nil
	end


	if self._calc_alarm then
		self._calc_alarm:stop()
		self._calc_alarm = nil
	end
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	if client ~= self._client then
		return false
	end

	self._log:info("OPCUA Client connected")
	local enable_sub = self._conf.enable_sub

	for _, input in ipairs(self._tpl.calc_inputs) do
		local m = require('calc_func.'..input.func)
		input.calc_func = m:new(self, self._dev, input, enable_sub)
		input.calc_func:start(client)
	end

	for k, input in pairs(self._tpl.map_inputs) do
		input.calc_func = calc_map_input:new(self, self._dev, input, enable_sub)
		input.calc_func:start(client)
	end

	if not enable_sub then
		local function get_opcua_node(ns, i)
			return client:get_node(ns, i)
		end

		--- 获取节点
		for _, input in ipairs(self._tpl.inputs) do
			input.node = input.node or get_opcua_node(input.ns, input.i)
		end
	else
		self._log:info("Create Subscription for INPUTS")
		local r, err = client:create_subscription(self._tpl.inputs, function(input, data_value)
			local dev = self._dev
			local value = client:parse_value(data_value, input.vt)
			self._log:debug('INPUT Sub recv', input.name, input.vt, value, data_value.value:asString())
			--[[
			local st = opcua.DateTime.toUnixTime(data_value.sourceTimestamp)
			self._log:debug('INPUT Sub recv', input.name, os.date(), os.date('%c', st))
			]]--
			--assert(tostring(value) == data_value.value:asString())
			if value then
				dev:set_input_prop(input.name, "value", value, now, 0)
			else
				dev:set_input_prop(input.name, "value", 0, now, -1)
			end
		end)

		if not r then
			self._log:error("failed to subscribe nodes", err)
			return false
		else
			self._log:notice("Subscribe nodes finished!!")
		end
	end

	if #self._tpl.alarms > 0 then
		self._calc_alarm = calc_alarm:new(self, self._dev, self._tpl.alarms, alarm_state_input, enable_sub)
		self._calc_alarm:start(client)
	end

	self._ready_to_read = true
	return true
end

--- 应用启动函数
function app:on_start()
	self._watches = {}
	local sys = self._sys
	local conf = self._conf

	conf.endpoint = conf.endpoint or 'opc.tcp://172.30.0.187:47055'
	--conf.endpoint = conf.endpoint or 'opc.tcp://192.168.0.100:4840'
	conf.enable_sub = conf.enable_sub ~= nil and conf.enable_sub or true

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example'

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			self._log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	---获取设备序列号和应用配置
	local sys_id = self._sys:id()
	local device_sn = conf.device_sn
	if conf.with_ioe_sn then
		device_sn = sys_id..'.'..device_sn
	end

	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file)

	--- 创建设备对象实例
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

	for k, v in pairs(tpl.map_inputs) do
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
	if #tpl.alarms > 0 then
		inputs[#inputs + 1] = {
			name = alarm_state_input,
			desc = '报警状态',
			vt = 'string',
		}
	end

	--print(cjson.encode(tpl.map_inputs))
	self._tpl = tpl

	self._dev = self._api:add_device(device_sn, meta, inputs)
	local org_set_input_prop = self._dev.set_input_prop
	self._dev.set_input_prop = function(dev, input, prop, value, timestamp, quality)
		--print(dev, input, prop, value, timestamp, quality)
		org_set_input_prop(dev, input, prop, value, timestamp, quality)
		local cb_list = self._watches[input]
		if cb_list then
			for _, v in pairs(cb_list) do
				v(input, prop, value, timestamp, quality)
			end
		end
	end

	self._client = opcua_client:new(self, conf)
	self._client.on_connected = function(client)
		return self:on_connected(client)
	end
	self._client.on_disconnected = function(client)
		return self:on_disconnected(client)
	end
	self._client:connect()

	return true
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	--- 清理OpcUa客户端连接
	if self._client then
		self._client:disconnect()
	end
	self._client = nil
end

function app:read_all_inputs()
	local read_val = function(node, vt)
		local value, source_ts, server_ts = client:read_value(node, vt)
		-- skip source/server timestamp
		return value
	end

	--- 获取节点当前值数据
	for _, input in ipairs(self._tpl.inputs) do
		local node = input.node
		if node then
			--- 设定当前值
			local value = read_val(node, input.vt)
			local now = self._sys:time()
			if value then
				dev:set_input_prop(input.name, "value", value, now, 0)
			else
				self._log:warning("Read "..input.name.." failed!!")
				dev:set_input_prop(input.name, "value", 0, now, -1)
			end
		else
			local now = self._sys:time()
			-- TODO:
			-- dev:set_input_prop(k, "value", 0, now, -1)
		end
	end
end

function app:watch_input(key, input, cb)
	local cb_list = self._watches[input] or {}
	cb_list[key] = cb
	self._watches[input] = cb_list
end

--- 应用运行入口
function app:on_run(tms)
	local begin_time = self._sys:time()
	if not self._client then
		return 1000
	end

	if not self._ready_to_read then
		return 1000
	end

	local dev = self._dev
	local client = self._client
	local enable_sub = self._conf.enable_sub

	--self._log:debug('Start', os.date())

	if not enable_sub then
		self:read_all_inputs()
	end

	for k, input in pairs(self._tpl.map_inputs) do
		input.calc_func:run()
	end

	if self._calc_alarm then
		self._calc_alarm:run()
	end

	for _, input in ipairs(self._tpl.calc_inputs) do
		input.calc_func:run()
	end

	--self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app

