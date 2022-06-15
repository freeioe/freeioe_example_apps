local base_app = require 'app.base'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.CLOUD_SWTICH")

my_app.static.API_VER = 14

--- 应用初始化
function my_app:on_init()
	self._devs = {}
end

function my_app:on_command(app, sn, command, params)
	local log = self:log_api()
	if command == 'switch' then
		if type(params.cloud) == 'string' then
			if params.cloud == 'thingsroot' then
				log:info('Switch to thingsroot cloud')
				ioe.set_cloud_host('ioe.thingsroot.com')
				ioe.set_pkg_host_url('ioe.thingsroot.com')
				ioe.set_cnf_host_url('ioe.thingsroot.com')
			elseif params.cloud == 'kooiot' then
				log:info('Switch to kooiot cloud')
				ioe.set_cloud_host('iot.kooiot.in')
				ioe.set_pkg_host_url('iot.kooiot.in:81')
				ioe.set_cnf_host_url('iot.kooiot.in:81')
			else
				return false, "not supported cloud"
			end
		else
			local cld = params.cloud
			if cld.host and cld.pkg and cld.cnf then
				log:info('Switch to cloud: ', cld.host, cld.pkg, cld.cnf)
				ioe.set_cloud_host(cld.host)
				ioe.set_pkg_host_url(cld.pkg)
				ioe.set_cnf_host_url(cld.cnf)
			end
		end

		local sys = self:sys_api()
		sys:cfg_call('SAVE') -- save configuration
		--- abort process
		ioe.abort()
	end

	if command == 'reset' then
		log:info('Reset cloud to default')
		ioe.set_cloud_host(nil)
		ioe.set_pkg_host_url(nil)
		ioe.set_cnf_host_url(nil)

		local sys = self:sys_api()
		sys:cfg_call('SAVE') -- save configuration
		--- abort process
		ioe.abort()
	end

	return false, "There is no output handler"
end

---
-- 设备指令结果回调（当本应用向其他应用设备发送设备指令，并需要处理反馈时使用此函数)
-- function my_app:on_command_result(app, priv, result, info)
-- end

---
-- 应用启动函数
-- Application start callback
function my_app:on_start()
	--- 生成设备唯一序列号
	local sn = 'CLOUD_SWITCH'

	--- 增加设备实例
	local inputs = {
		{name="cloud", desc="Cloud host address", vt="string"},
		{name="pkg_url", desc="Cloud pkg url", vt="string"},
		{name="cnf_url", desc="Cloud cnf url", vt="string"}
	}
	local commands = {
		{name="switch", desc="Switch cloud(thingsroot, kooiot)"},
		{name="reset", desc="Reset cloud settings to default"}
	}

	local meta = self._api:default_meta()
	meta.name = "CloudSwitcher"
	meta.description = "Switch Cloud Utility"
	local dev = self._api:add_device(sn, meta, inputs, nil, commands)
	self._dev = dev

	self._cloud = ''
	self._pkg_url = ''
	self._cnf_url = ''

	return true
end

--- 应用退出函数
function my_app:on_close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function my_app:on_run(tms)
	local cloud = ioe.cloud_host()
	local pkg_url = ioe.pkg_host_url()
	local cnf_url = ioe.cnf_host_url()

	if cnf_url ~= self._cnf_url or pkg_url ~= self._pkg_url or cloud ~= self._cloud then
		self._dev:set_input_prop('cloud', 'value', cloud)
		self._dev:set_input_prop('pkg_url', 'value', pkg_url)
		self._dev:set_input_prop('cnf_url', 'value', cnf_url)
	end

	return 3000 --下一采集周期为3秒
end

--- 返回应用类
return my_app

