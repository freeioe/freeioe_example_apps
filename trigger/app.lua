local class = require 'middleclass'
local openweathermap = require 'openweathermap'

--- 注册对象(请尽量使用唯一的标识字符串)
local app = class("FREEIOE_EXAMPLE_TRIGGER_APP")
--- 设定应用最小运行接口版本(目前版本为1,为了以后的接口兼容性)
app.API_VER = 1

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
	self._api = sys:data_api()
	--- 获取日志接口
	self._log = sys:logger()
	self._nodes = {}
end

--- 设定变量的默认值
local default_vals = {
	int = 0,
	string = '',
}

--- 创建数据回调对象
-- @param app: 应用实例对象
local function create_handler(app)
	local api = app._api
	local server = app._server
	local log = app._log
	local idx = app._idx
	local nodes = app._nodes
	return {
		--- 处理设备对象添加消息
		on_add_device = function(app, sn, props)
			--- 获取对象目录
		end,
		--- 处理设备对象删除消息
		on_del_device = function(app, sn)
		end,
		--- 处理设备对象修改消息
		on_mod_device = function(app, sn, props)
		end,
		--- 处理设备输入项数值变更消息
		on_input = function(app, sn, input, prop, value, timestamp, quality)
		end,
	}
end

--- 应用启动函数
function app:start()
	local temp = openweathermap.get_temp(1809858)

	self._log:notice("Started!!!!")
	return true
end

--- 应用退出函数
function app:close(reason)
end

--- 应用运行入口
function app:run(tms)

	return 1000
end

--- 返回应用对象
return app

