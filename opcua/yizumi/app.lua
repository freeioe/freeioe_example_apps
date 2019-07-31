--- 导入需求的模块
local app_base = require 'app.base'
local opcua_client = require 'base.client'
local csv_tpl = require 'csv_tpl'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("YIZUMI_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

function app:connected()
	return self._client ~= nil and self._client:connected()
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	if client ~= self._client then
		return
	end

	self._log:info("OPCUA Client connected")
	local enable_sub = self._conf.enable_sub

	if not enable_sub then
		local function get_opcua_node(ns, i)
			return client:get_node(ns, i)
		end

		--- 获取节点
		for _, input in ipairs(self._tpl.inputs) do
			input.node = input.node or get_opcua_node(input.ns, input.i)
		end

		for _, minput in ipairs(self._tpl.map_inputs) do
			for _, input in ipairs(minput.values) do
				input.node = input.node or get_opcua_node(input.ns, input.i)
			end
		end

		for _, alarm in ipairs(self._tpl.alarms) do
			alarm.node = alarm.node or get_opcua_node(alarm.ns, alarm.i)
		end
	else
		local r, err = client:createSubscription(self._tpl.inputs, function(input, data_value)
			local dev = self._dev
			local value = client:parse_value(data_value, input.vt)
			--self._log:debug('Sub recv', input.name, value)
			if value then
				dev:set_input_prop(input.name, "value", value, now, 0)
			else
				dev:set_input_prop(input.name, "value", 0, now, -1)
			end
		end)
		if not r then
			self._log:error("failed to subscribe nodes", err)
		else
			self._log:notice("Subscribe nodes finished!!")
		end

		for _, minput in ipairs(self._tpl.map_inputs) do
			local m_value = {}
			--[[
			client:createSubsciption(minput.values, function(input, data_value)
				for _, input in ipairs(minput.values) do
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
			end)
			]]--
		end
	end

	--- TODO:
	for _, input in ipairs(self._tpl.calc_inputs) do
		local m = require('calc_func.'..input.func)
		input.calc_func = m:new(self, self._dev, input, enable_sub)
		input.calc_func:start(client)
	end

	self._ready_to_run = true
end

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf

	--conf.endpoint = conf.endpoint or 'opc.tcp://172.30.0.187:38133'
	conf.enable_sub = true

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example_test'

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

	csv_tpl.init(self._sys:app_dir())
	local tpl = csv_tpl.load_tpl(tpl_file)

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

	--print(cjson.encode(inputs))
	self._tpl = tpl

	self._dev = self._api:add_device(sys_id..'.'..meta.name, meta, inputs)

	self._client = opcua_client:new(self, conf)
	self._client.on_connected = function(client)
		self:on_connected(client)
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

--- 应用运行入口
function app:on_run(tms)
	local begin_time = self._sys:time()
	if not self._client or self._conf.enable_sub then
		return 1000
	end

	if not self._ready_to_run then
		return 1000
	end

	local dev = self._dev
	local client = self._client

	self._log:debug('Start', os.date())

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
		input.calc_func:run()
	end

	self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

--- 返回应用对象
return app

