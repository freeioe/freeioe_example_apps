local base_app = require 'app.base'
local ioe = require 'ioe'

local my_app = base_app:subclass("FREEIOE.APP.TOOLS.PING_CHECK")
my_app.static.API_VER = 14

function my_app:on_command(app, sn, command, params)
	if command == 'restart' then
		local skynet = require 'skynet.manager'
		skynet.abort()
	elseif command == 'reboot' then
		os.execute('sync && reboot')
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

