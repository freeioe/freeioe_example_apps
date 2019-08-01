--- 导入需求的模块
local app_base require 'app.base'
local opcua_client = require 'base.client'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_OPCUA_CLIENT_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.static.API_VER = 4

---
-- 检测连接可用性
function app:is_connected()
	return self._client ~= nil and self._client:connected()
end

---
-- 获取设备的OpcUa节点
function app:get_device_node(namespace, obj_name)
	if not self:is_connected() then
		self._log:warning("Client is not connected!")
		return
	end

	local client = self._client
	local nodes = self._nodes

	--- 获取Objects节点
	local objects = client:get_objects_node()
	--- 获取名字空间的id号
	local idx, err = client:get_namespace_index(namespace)
	if not idx then
		self._log:warning("Cannot find namespace", err)
		return
	end
	--- 获取设备节点
	local devobj, err = client:get_child(objects, idx..":"..obj_name)
	if not devobj then
		self._log:error('Device object not found', err)
		return
	else
		self._log:debug("Device object found", devobj)
	end

	--- 返回节点对象
	return {
		idx = idx,
		name = obj_name,
		device = device,
		devobj = devobj,
		vars = {}
	}
end

---
-- 定义需要获取数据的输入项
local inputs = {
	{ name = "Counter1", desc = "Counter1"},
	{ name = "s1", desc = "Simulation 1"},
}

---
-- 连接成功后的处理函数
function app:on_connected(client)
	if client ~= self._client then
		return false
	end

	-- Cleanup nodes buffer
	self._nodes = {}

	--- Get opcua object instance by namespace and browse name
	-- 根据名字空间和节点名称获取OpcUa对象实体
	local namespace = self._conf.namespace or "http://www.prosysopc.com/OPCUA/SimulationNodes"
	local obj_name = "Simulation"
	local node, err = self:get_device_node(namespace, obj_name)
	---
	-- 获取设备对象节点下的变量节点
	if node then
		for _,v in ipairs(inputs) do
			local var, err = node.devobj:getChild(v.name)
			--print(_,v.name,var)
			if not var then
				self._log:error('Variable not found', err)
				return false, err
			else
				node.vars[v.name] = var
			end
		end
		local sn = namespace..'/'..obj_name
		self._nodes[sn] = node
	end
	return true
end

--- 应用启动函数
function app:on_start()
	self._nodes = {}
	self._devs = {}

	--- 生成OpcUa客户端对象
	local conf = self._conf
	local sys = self._sys


	--- 设定接口处理函数
	self._api:set_handler({
		on_output = function(...)
			print(...)
		end,
		on_ctrl = function(...)
			print(...)
		end
	})

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = "OPCUA"
	meta.description = "Unknown OPCUA Device"
	meta.series = "XXX"
	local dev = self._api:add_device(sys_id..'.OPCUA_TEST', meta, inputs)
	self._devs['Simulation'] = dev

	self._client = opcua_client:new(self, conf)
	self._client.on_connected = function(client)
		return self:on_connected(client)
	end
	self._client:connect()

	return true
end

--- 应用退出函数
function app:close(reason)
	print('close', self._name, reason)
	--- 清理OpcUa客户端连接
	if self._client then
		self._nodes = {}
		self._client:disconnect()
	end
	self._client = nil
end

--- 应用运行入口
function app:on_run(tms)
	if not self._client then
		return 1000
	end

	--- 获取节点当前值数据
	for sn, node in pairs(self._nodes) do
		local dev = self._devs[node.name]
		assert(dev)
		for k, v in pairs(node.vars) do
			local dv = v.value
			--[[
			print(dv, dv:isEmpty(), dv:isScalar())
			print(dv:asLong(), dv:asDouble(), dv:asString())
			]]--
			local now = self._sys:time()
			--- 设定当前值
			dev:set_input_prop(k, "value", dv:asDouble(), now, 0)
		end
	end

	--- 返回下一次调用run函数的间隔
	return 2000
end

--- 返回应用对象
return app

