--- 导入需求的模块
local app_base = require 'app.base'
local opcua_client = require 'base.client'
local csv_tpl = require 'csv_tpl'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为5,为了以后的接口兼容性)
app.static.API_VER = 5

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

function app:on_init()
	local conf = self._conf
	if conf.encryption then
		conf.encryption.cert = self:text2file(conf.encryption.cert, '.ca.der')
		conf.encryption.key = self:text2file(conf.encryption.key, '.key.der')
	end
end

function app:connected()
	return self._client ~= nil and self._client:connected()
end

---
-- 连接成功后的处理函数
function app:on_connected(client)
	if client ~= self._client then
		return false, "Not this client"
	end

	self._log:info("OPCUA Client connected")
	local enable_sub = self._conf.enable_sub

	if not enable_sub then
		local function get_opcua_node(ns, i, itype)
			return client:get_node(ns, i, itype)
		end

		--- 获取节点
		for _, input in ipairs(self._tpl.inputs) do
			input.node = input.node or get_opcua_node(input.ns, input.i, input.itype)
		end
	else
		local r, err = client:create_subscription(self._tpl.inputs, function(input, data_value)
			local dev = self._dev
			local value = client:parse_value(data_value, input.vt)
			--self._log:debug('Sub recv', input.name, value)
			if value then
				if input.vt ~= 'string' and input.rate ~= 1 then
					value = value * input.rate
				end
				dev:set_input_prop(input.name, "value", value, nil, 0)
			else
				dev:set_input_prop(input.name, "value", 0, nil, -1)
			end
		end)
		if not r then
			self._log:error("failed to subscribe nodes", err)
			return false, "Subscribe failed"
		else
			self._log:notice("Subscribe nodes finished!!")
		end
	end

	self._ready_to_run = true
	return true
end

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf

	conf.endpoint = conf.endpoint or 'opc.tcp://localhost:4840'
	if conf.enable_sub == nil then
		conf.enable_sub = true
	end

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver
	local tpl_file = 'example'

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			self._log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end

	-- 加载模板
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

	local outputs = {}
	for _, v in ipairs(tpl.outputs) do
		outputs[#outputs + 1] = {
			name = v.name,
			desc = v.desc or v.name,
			vt = v.vt
		}
	end

	self._tpl = tpl
	local dev_sn = conf.device_sn
	if dev_sn == nil or string.len(conf.device_sn) == 0 then
		dev_sn = sys_id..'.'..meta.name
	end
	self._dev_sn = dev_sn
	self._dev = self._api:add_device(dev_sn, meta, inputs, outputs)

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
				if input.vt ~= 'string' and input.rate ~= 1 then
					value = value * input.rate
				end
				dev:set_input_prop(input.name, "value", value, now, 0)
			else
				self._log:warning("Read "..input.name.." failed!!")
				dev:set_input_prop(input.name, "value", 0, now, 1)
			end
		else
			--local now = self._sys:time()
			-- TODO:
			-- dev:set_input_prop(k, "value", 0, now, 1)
		end
	end

	self._log:debug('End', os.date())

	local next_tms = (self._conf.loop_gap or 1000) - ((self._sys:time() - begin_time) * 1000)
	return next_tms > 0 and next_tms or 0
end

function app:on_output(app_src, sn, output, prop, value, timestamp)
	if not self:connected() then
		return nil, "OPCUA not connected to server!"
	end
	if sn ~= self._dev_sn then
		return nil, "Device Serial Number incorrect!"
	end

	for _, v in ipairs(self._tpl.outputs) do
		if v.name == output then
			local node, err = self._client:get_node(v.ns, v.i, v.itype)
			if not node then
				return nil, err
			end
			local val = v.rate == 1 and value or (value / v.rate)
			local r, err = self._client:write_value(node, v.vt, val)
			if not r then
				return nil, err
			end
			return true, "Write value done!"
		end
	end

	return nil, "Output not found!"
end

--- 返回应用对象
return app

