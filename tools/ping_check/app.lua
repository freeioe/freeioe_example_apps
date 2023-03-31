local base_app = require 'app.base'
local sysinfo = require 'utils.sysinfo'
local lfs = require 'lfs'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.PING_CHECK")
my_app.static.API_VER = 14

function my_app:on_init()
	local conf = self:app_conf()

	self._cloud = conf.cloud or 'ioe.thingsroot.com' -- host address
	self._iface = conf.iface or '4g_wan'
	self._ping_cycle = conf.cycle or 60 -- in seconds
	self._timeout = conf.timeout or 300 -- in seconds
	self._reset_count = 0

	self._last = ioe.time()
	--- 设备实例
	self._devs = {}
end

local function fs_access(file)
	local mode = lfs.attributes(file, 'access')
	return mode
end

function my_app:reset_wwan_module(iface_name)
	local log = self:log_api()
	local sys = self:sys_api()
	log:info(iface_name..' reset module')
	local pcie_reset_path = '/sys/class/gpio/pcie_reset/value'
	local pcie_reset = fs_access(pcie_reset_path)
	local pcie_on_off_path = '/sys/class/gpio/pcie_on_off/value'
	local pcie_on_off = fs_access(pcie_on_off_path)

	sysinfo.exec("ifdown "..iface_name)
	if pcie_on_off then
		log:info(iface_name..' module reset on(soft)')
		sysinfo.exec("echo 0 > "..pcie_on_off_path)
		sys:sleep(3000)
	end
	if pcie_reset then
		sysinfo.exec("echo 1 > "..pcie_reset_path)
	end
	sysinfo.exec("killall -9 uqmi")
	sys:sleep(1000)
	if pcie_on_off then
		log:info(iface_name..' module reset off(soft)')
		sysinfo.exec("echo 1 > "..pcie_on_off_path)
	end
	if pcie_reset then
		sysinfo.exec("echo 0 > "..pcie_reset_path)
	end
	sys:sleep(10000)
	sysinfo.exec("ifup "..iface_name)
end

function my_app:repower_wwan_module(iface_name)
	local log = self:log_api()
	local sys = self:sys_api()
	log:info(iface_name..' re-power module')

	local pcie_power_path = '/sys/class/gpio/pcie_power/value'
	local pcie_power = fs_access(pcie_power_path)
	local pcie_on_off_path = '/sys/class/gpio/pcie_on_off/value'
	local pcie_on_off = fs_access(pcie_on_off_path)

	sysinfo.exec("ifdown "..iface_name)
	if pcie_on_off then
		log:info(iface_name..' module power off(soft)')
		sysinfo.exec("echo 0 > "..pcie_on_off_path)
		sys:sleep(3000)
	end
	if pcie_power then
		log:info(iface_name..' module power off')
		sysinfo.exec("echo 0 > "..pcie_power_path)
	end
	sysinfo.exec("killall -9 uqmi")
	sys:sleep(1000)
	if pcie_on_off then
		log:info(iface_name..' module power on(soft)')
		sysinfo.exec("echo 1 > "..pcie_on_off_path)
	end
	if pcie_power then
		log:info(iface_name..' module power on')
		sysinfo.exec("echo 1 > "..pcie_power_path)
	end
	sys:sleep(10000)
	sysinfo.exec("ifup "..iface_name)
end


function my_app:on_command(app, sn, command, params)
	if command == 'reset' then
		self:reset_wwan_module(self._iface)
	elseif command == 'repower' then
		self:repower_wwan_module(self._iface)
	end

	return false, "Command is unknown"
end

function my_app:check_alive(destip)
    local dev = self.net_info_dev
	local cmd = "ping -c 3  -W 2 " .. destip .. " > /dev/null && echo true ||echo false"
	local info, err = sysinfo.exec(cmd)
	if not info then
		return nil, err
	end
	if string.find(info, "true") then
		return true
    else
		return false, info
	end
end

function my_app:on_start()
	local sys = self:sys_api()
	--- 生成设备唯一序列号
	local sn = sys:id()..'.CLOUD_SWITCH'

	--- 增加设备实例
	local inputs = {
		{name="host", desc="Host address used for ping check", vt="string"},
		{name="last", desc="Last ping valid time", vt="int"},
	}
	local commands = {
		{name="reset", desc="Reset 4G module"},
		{name="repower", desc="Repower 4G module"}
	}

	local meta = self._api:default_meta()
	meta.name = "PingCheck"
	meta.description = "Ping Check Utility"
	local dev = self._api:add_device(sn, meta, inputs, nil, commands)
	self._dev = dev

	return true
end

--- 应用退出函数
function my_app:on_close(reason)
	local log = self:log_api()
	log:info("App close "..reason)
end

--- 应用运行入口
function my_app:run(tms)
	local log = self:log_api()
	log:debug("Ping host "..self._cloud.."...")
	local r = self:check_alive(self._cloud)
    if r then
		self._reset_count = 0
		self._last = ioe.time()
		return self._ping_cycle * 1000
	else
		log:warning("Ping host "..self._cloud.." failed!")
		self._dev:set_input_prop('last', 'value', self._last)
		if (ioe.time() - self._last) > (self._timeout * (self._reset_count + 1)) then
			self._reset_count = self._reset_count + 1
			if self._reset_count > 3 then
				self._reset_count = 0
				self:repower_wwan_module(self._iface)
			else
				self:reset_wwan_module(self._iface)
			end
		end
		return 3000 -- 3秒
    end
end

--- 返回应用类
return my_app

