local class = require 'middleclass'
local sysinfo = require 'utils.sysinfo'
local cjson = require 'cjson.safe'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("Cloud_Proxy")
--- 设定应用最小运行接口版本(最新版本为2,为了以后的接口兼容性)
app.API_VER = 2


---
-- 应用对象初始化函数
-- @param name: 应用本地安装名称。 如modbus_com_1
-- @param sys: 系统sys接口对象。参考API文档中的sys接口说明
-- @param conf: 应用配置参数。由安装配置中的json数据转换出来的数据对象
function app:initialize(name, sys, conf)
	self._name = name
	self._sys = sys
	self._conf = conf
	--- 获取数据接口
	self._api = self._sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	--- 设备实例
	self._devs = {}
	self._interfaces = nil
    self._proxyInfo = nil
    self._brlan = nil
	self._log:debug("Cloud_Proxy Application initlized")
end


function app:enable_proxy()
    local dev = self.net_info_dev
    if self._brlan and self._proxyInfo then
        local cmds = self._proxyInfo
    	self._log:debug("sshIP:", cmds.sshIP, cmds.sshUser, cmds.sshPwd)
    	local cmd_delhost = "sshpass -p \"" .. cmds.sshPwd .. "\" ssh -y " ..cmds.sshUser .. "@" .. cmds.sshIP .." \"sed -i '/ioe.thingsroot.com.*/d' /etc/hosts\""
    	local cmd_addhost = "sshpass -p \"" .. cmds.sshPwd .. "\" ssh -y " ..cmds.sshUser .. "@" .. cmds.sshIP .." \"sed -i '/127.0.0.1 localhos/a\\47.93.253.160 ioe.thingsroot.com' /etc/hosts\""
    	local cmd_addroute = "sshpass -p \"" .. cmds.sshPwd .. "\" ssh -y " ..cmds.sshUser .. "@" .. cmds.sshIP .." \"ip route add 47.93.253.160/32 via " .. self._brlan .. "\""
    
    	local info, err = sysinfo.exec(cmd_delhost)
    		if not info then
    		return nil, err
    	end
    	local info, err = sysinfo.exec(cmd_addhost)
    		if not info then
    		return nil, err
    	end
    	local info, err = sysinfo.exec(cmd_addroute)
    		if not info then
    		return nil, err
    	end
    	self._log:debug(cmds.sshIP .. " add Cloud_Proxy successful!")
    	dev:set_input_prop('guest_ipaddr', "value", cmds.sshIP)
    	dev:set_input_prop('proxy_status', "value", "enable_proxy")
        return true, "add Cloud_Proxy successful!"
    else
        return false, "lan_ipaddr or proxyInfo is nil"
    end
end

function app:disable_proxy()
    local dev = self.net_info_dev
    if self._brlan and self._proxyInfo then
        local cmds = self._proxyInfo
    	self._log:debug("sshIP:", cmds.sshIP, cmds.sshUser, cmds.sshPwd)
    	local cmd_delhost = "sshpass -p \"" .. cmds.sshPwd .. "\" ssh -y " ..cmds.sshUser .. "@" .. cmds.sshIP .." \"sed -i '/ioe.thingsroot.com.*/d' /etc/hosts\""
    	local cmd_delroute = "sshpass -p \"" .. cmds.sshPwd .. "\" ssh -y " ..cmds.sshUser .. "@" .. cmds.sshIP .." \"ip route del 47.93.253.160/32 via " .. self._brlan .. "\""
    	local info, err = sysinfo.exec(cmd_delhost)
    		if not info then
    		return nil, err
    	end
    	local info, err = sysinfo.exec(cmd_delroute)
    		if not info then
    		return nil, err
    	end
    	self._log:debug(cmds.sshIP .. " del Cloud_Proxy successful!")
    	dev:set_input_prop('guest_ipaddr', "value", "--")
    	dev:set_input_prop('proxy_status', "value", "disable_proxy")
    	dev:set_input_prop('guest_alive', "value", "")
    	self._proxyInfo = nil
        return true, "del Cloud_Proxy successful!"
    else
        return false, "lan_ipaddr or proxyInfo is nil"
    end
end


function app:check_alive(destip)
    local dev = self.net_info_dev
	local cmd = "ping -c 3  -W 2 " .. destip .. " > /dev/nul && echo true ||echo false"
	local info, err = sysinfo.exec(cmd)
	if not info then
		return nil, err
	end
	dev:set_input_prop('guest_alive', "value", info)
	if string.find(info, "true") then
	    self._log:debug("guest alive")
    else
	    self._log:debug("guest down")
	    dev:set_input_prop('proxy_status', "value", "")
	end

end

function app:show_interfaces()
	local cmd = "ubus call network.interface dump"
	local info, err = sysinfo.exec(cmd)
	if not info then
		return nil, err
	end
    local interfaces, err = cjson.decode(info)
    if not interfaces then
		self._log:debug("cjson decode error::", err)
	end
    self._interfaces = interfaces.interface
end

function app:refresh_interfaces()
    local dev = self.net_info_dev
	self:show_interfaces()
	for p, q in ipairs(self._interfaces) do
		-- self._log:debug(p, q)
		if (q.interface == 'lan') then

			if q.up then
			 --   self._log:debug("q value::", cjson.encode(q))
				if next(q['ipv4-address']) ~= nil then
				    self._brlan = q['ipv4-address'][1].address
				    dev:set_input_prop('lan_ipaddr', "value", q['ipv4-address'][1].address .. '/' ..q['ipv4-address'][1].mask)

				    -- self._log:debug(q.interface, q.device, "ipaddr", q['ipv4-address'][1].address)
				else
				    self._brlan = nil
				    dev:set_input_prop('lan_ipaddr', "value", "--")

				end
    		end
        end
	end	
end


--- 应用启动函数
function app:start()
	self._api:set_handler({
		on_output = function(app, sn, output, prop, value)
		end,
		on_command = function(app, sn, command, param)
			self._log:debug("on_command", app, sn, command, param)
				
				local cmds = param
				
				if type(cmds) ~= 'table' then
					self._log:debug("command is not json, value::", cjson.encode(param))
					return nil
				end
				
				if next(cmds) == nil then
				    return nil, "param is nil"
				end
				
				if command == "enable_proxy" then
				    self._proxyInfo = cmds
					return self:enable_proxy()
				end
				if command == "disable_proxy" then
				    if not self._proxyInfo then
				        return false, "enable_proxy is first"
				    end
					return self:disable_proxy()
				end
		end,	
		on_ctrl = function(app, command, param, ...)
		end,
	})

	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name


	--- 增加设备实例
	local inputs = {
		{
			name = "lan_ipaddr",
			desc = "lan_ipaddr",
			vt = "string",
		},
		{
			name = "guest_ipaddr",
			desc = "guest_ipaddr",
			vt = "string",
		},
		{
			name = "guest_alive",
			desc = "guest_alive",
			vt = "string",
		},
		{
			name = "proxy_status",
			desc = "proxy_status",
			vt = "string",
		}
	}
	local cmds = {
		{
			name = "enable_proxy",
			desc = "enable_proxy",
		},
		{
			name = "disable_proxy",
			desc = "disable_proxy",
		},
	}
	local meta = self._api:default_meta()
	meta.name = "Cloud_Proxy"
	meta.description = "Cloud_Proxy Meta"
	local dev = self._api:add_device(sn, meta, inputs, {}, cmds)
	for _, v in ipairs(inputs) do
	    dev:set_input_prop(v.name, "value", "")
	end
	self.net_info_dev = dev
	return true
end

--- 应用退出函数
function app:close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function app:run(tms)
    self:refresh_interfaces()
    if self._brlan and self._proxyInfo then
        self:check_alive(self._brlan)
    end
-- 	self._log:debug("start:")
	return 5 * 1000 --下一采集周期为xx秒
end

--- 返回应用对象
return app
