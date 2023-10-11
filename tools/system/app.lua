local skynet = require 'skynet.manager'
local base_app = require 'app.base'
local sysinfo = require 'utils.sysinfo'
local curl_down = require 'curl_download'
local lfs = require 'lfs'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.PING_CHECK")
my_app.static.API_VER = 14

local function fs_access(file)
	local mode = lfs.attributes(file, 'access')
	return mode
end

function my_app:on_command(app, sn, command, params)
	if command == 'restart' then
		self._sys:timeout(1000, function()
			skynet.abort()
		end)
		return true
	elseif command == 'reboot' then
		self._sys:timeout(1000, function()
			sysinfo.exec('sync && reboot')
		end)
		return true
	elseif command == 'force_upgrade' then
		local filepath = '/tmp/freeioe.force.upgrade.tar.gz'
		local down = curl_down:new()
		local r, err = down:download(params.url, params.md5, filepath, function(total, downloaded)
			self._log:trace('Download totol:'..total..' downloaed:'..downloaded)
		end)

		if r then
			self._log:notice('Downloaed completed, now abort after one second')
			sysinfo.exec('cp -f '..self._sys:app_dir()..'/upgrade.sh /usr/ioe/ipt/upgrade')
			self._sys:timeout(1000, function()
				skynet.abort()
			end)
		else
			return false, err
		end
	elseif command == 'exec' then
		sysinfo.exec(params.cmd)
		return true
	end

	return false, "Command is unknown"
end

function my_app:on_start()
	local sys = self:sys_api()
	--- 生成设备唯一序列号
	local sn = sys:id()..'.SYSTEM'

	--- 增加设备实例
	local commands = {
		{name="restart", desc="Restart FreeIOE"},
		{name="reboot", desc="Reboot FreeIOE gateway device"},
		{name="force_upgrade", desc="Force upgrade FreeIOE from url"},
		{name="exec", desc="Execute shell command"},
	}

	local meta = self._api:default_meta()
	meta.name = "SystemHelper"
	meta.description = "System Helper Utility"
	local dev = self._api:add_device(sn, meta, inputs, nil, commands)
	self._dev = dev

	return true
end

--- 应用退出函数
function my_app:on_close(reason)
	local log = self:log_api()
	log:info("App close "..reason)
end

--- 返回应用类
return my_app

