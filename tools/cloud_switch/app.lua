local base_app = require 'app.base'
local cjson = require 'cjson.safe'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.CLOUD_SWTICH")

my_app.static.API_VER = 14

local switch_file = '/root/.freeioe_cloud_switch'
local preset = {
	thingsroot = {
		host = 'ioe.thingsroot.com',
		pkg = 'ioe.thingsroot.com',
		cnf = 'ioe.thingsroot.com'
	},
	kooiot = {
		host = 'iot.kooiot.in',
		pkg = 'iot.kooiot.in:81',
		cnf = 'iot.kooiot.in:81'
	}
}

--- 应用初始化
function my_app:on_init()
	self._devs = {}
	if ioe.developer_mode() then
		switch_file = '/tmp/freeioe_cloud_switch'
	end
end

function my_app:switch_to(new_cloud, rollback)
	local log = self:log_api()
	if not rollback then
		log:warning('Switch to cloud: ', new_cloud.host, new_cloud.pkg, new_cloud.cnf)
		local sw_data = {
			old = {
				host = self._cloud,
				pkg = self._pkg_url,
				cnf = self._cnf_url
			},
			new = new_cloud
		}

		local f, err = io.open(switch_file, 'w+')
		if f then
			f:write(cjson.encode(sw_data))
			f:close()
		else
			log:error('Cannot write to disk about switched cloud', err)
			log:error('So we cannot switch back if new cloud is unreachable')
		end
	else
		log:warning('Rollback to cloud: ', new_cloud.host, new_cloud.pkg, new_cloud.cnf)
	end

	if string.len(new_cloud.host) == 0 then
		new_cloud.host = nil
	end
	if string.len(new_cloud.pkg) == 0 then
		new_cloud.pkg = nil
	end
	if string.len(new_cloud.cnf) == 0 then
		new_cloud.cnf = nil
	end
	ioe.set_cloud_host(new_cloud.host)
	ioe.set_pkg_host_url(new_cloud.pkg)
	ioe.set_cnf_host_url(new_cloud.cnf)

	local sys = self:sys_api()
	sys:cfg_call('SAVE') -- save configuration
	--- abort process
	ioe.abort()

	return true
end

function my_app:switch_reset()
	local log = self:log_api()
	log:info('Reset cloud to default')
	ioe.set_cloud_host(nil)
	ioe.set_pkg_host_url(nil)
	ioe.set_cnf_host_url(nil)

	local sys = self:sys_api()
	sys:cfg_call('SAVE') -- save configuration
	--- abort process
	ioe.abort()

	return true
end

function my_app:on_command(app, sn, command, params)
	local log = self:log_api()
	if command == 'switch' then
		if type(params.cloud) == 'string' then
			local pre = preset[params.cloud]
			if pre then
				return self:switch_to(pre)
			else
				return false, "not supported cloud"
			end
		else
			if params.cloud.host and params.cloud.pkg and params.cloud.cnf then
				return self:switch_to(params.cloud)
			end
		end
	end

	if command == 'reset' then
		return self:switch_reset()
	end

	return false, "Command is unknown"
end

---
-- 设备指令结果回调（当本应用向其他应用设备发送设备指令，并需要处理反馈时使用此函数)
-- function my_app:on_command_result(app, priv, result, info)
-- end

---
-- 应用启动函数
-- Application start callback
function my_app:on_start()
	--- Log interface
	local log = self:log_api()
	local sys = self:sys_api()

	--- 生成设备唯一序列号
	local sn = sys:id()..'.CLOUD_SWITCH'

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

	self._cloud = nil
	self._pkg_url = nil
	self._cnf_url = nil

	local f, err = io.open(switch_file, 'r')
	if f then
		local str = f:read('*a')
		f:close()
		local data, err = cjson.decode(str)
		if not data then
			log:error("Cannot parse the saved switch_file")
			os.execute('rm -f '..switch_file)
		else
			self._switch_info = data
			self._switch_timeout = ioe.now() + 60 * 1000 -- timeout in one minute
		end
	end

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
		self._cloud = cloud
		self._pkg_url = pkg_url
		self._cnf_url = cnf_url
		self._dev:set_input_prop('cloud', 'value', cloud)
		self._dev:set_input_prop('pkg_url', 'value', pkg_url)
		self._dev:set_input_prop('cnf_url', 'value', cnf_url)
	end

	if self._switch_info then
		local log = self:log_api()
		local online, last, msg = ioe.cloud_status()
		if online then
			os.execute('rm -f '..switch_file)
			self._switch_info = nil
			self._switch_timeout = nil
		else
			if self._switch_timeout < ioe.now() then
				-- timeout
				log:error("New cloud is not reachable, rollback!!!")
				self:switch_to(self._switch_info.old)

				self._switch_info = nil
				self._switch_timeout = nil
				os.execute('rm -f '..switch_file)
			else
				log:info('Wait for cloud be connected....', self._switch_timeout - ioe.now())
			end
		end
	end

	return 3000 --下一采集周期为3秒
end

--- 返回应用类
return my_app

