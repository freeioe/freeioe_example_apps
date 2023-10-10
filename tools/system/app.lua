local base_app = require 'app.base'
local sysinfo = require 'utils.sysinfo'
local helper = require 'utils.helper'
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
			local skynet = require 'skynet.manager'
			skynet.abort()
		end)
		return true
	elseif command == 'reboot' then
		self._sys:timeout(1000, function()
			sysinfo.exec('sync && reboot')
		end)
		return true
	elseif command == 'force_upgrade' then
		if fs_access('/usr/bin/wget') then
			sysinfo.exec('wget -O /tmp/freeioe.force.upgrade.tar.gz '..params.url)
			if fs_access('/tmp/freeioe.force.upgrade.tar.gz') then
				local sum, err = helper.md5sum(path)
				if not sum then
					return nil, "Cannot caculate md5"
				end
				if string.lower(sum) ~= string.lower(params.md5) then
					return nil, "md5sum check failed"
				end
				sysinfo.exec('cp -f '..self._sys:app_dir()..'/upgrade.sh /usr/ioe/ipt/')
				self._sys:timeout(1000, function()
					skynet.abort()
				end)
				return true
			else
				return false, 'Download file missing'
			end
		else
			return false, 'wget command not found'
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

