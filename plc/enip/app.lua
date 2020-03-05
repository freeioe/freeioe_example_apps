--- 导入需求的模块
local app_base = require 'app.base'
local client = require 'client_sc'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = app_base:subclass("FREEIOE_PLC_AB_PLCTAG_APP")
--- 设定应用最小运行接口版本(目前版本为4,为了以后的接口兼容性)
app.static.API_VER = 4

--- 应用启动函数
function app:on_start()
	local sys = self._sys
	local conf = self._conf
	conf.host = '192.168.250.1'
	conf.port = 0xAF12

	self._log:info("Ethernet IP/CIP: Host:"..conf.host..' Port:'..conf.port)
	local conn_path = conf.host..':'..conf.port

	--- 创建设备对象实例
	local sys_id = self._sys:id()
	local meta = self._api:default_meta()
	meta.name = 'PLC' 
	meta.manufacturer = "FreeIOE.org"
	meta.description = 'PLC via ENIP/CIP' 
	meta.series = 'N/A'

	local inputs = {
		{ name = 'tag1', vt='int', desc = 'tag1', dt='UINT'},
		{ name = 'tag2', vt='int', desc = 'tag2', dt='UINT'},
		{ name = 'tag3', vt='int', desc = 'tag3', dt='UINT'},
	}

	local dev_sn = conf.device_sn
	if dev_sn == nil or string.len(conf.device_sn) == 0 then
		--dev_sn = sys_id..'.'..self._name..'.'..meta.name
		dev_sn = sys_id..'.'..meta.name
	end
	self._dev_sn = dev_sn
	self._dev = self._api:add_device(dev_sn, meta, inputs)
	self._inputs = inputs

	self._client = client:new(conn_path)

	local r, err = self._client:connect()
	if not r then
		self._log:error(tostring(err))
	end
	
	return r, err
end

--- 应用退出函数
function app:on_close(reason)
	self._log:warning('Application closing', reason)
	self._closing = {}
	self._sys:sleep(5000, self._closing)
end

function app:on_run(tms)

	for _, v in ipairs(self._inputs) do
		local r, err = self._client:read_tag(v.name, v.dt, function(val, err)
			self._log:debug('Value from PLC', val, err)
		end)
	end

	return 10000
end

--- 返回应用对象
return app

