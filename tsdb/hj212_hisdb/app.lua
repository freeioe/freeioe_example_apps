local base_app = require 'app.base'
local ioe = require 'ioe'
local cjson = require 'cjson.safe'
local hisdb = require 'hisdb.hisdb'
local hisdb_tag = require 'hisdb.tag'

--- 创建自己应用的子类
--- create your own application subclass
local my_app = base_app:subclass("DB_TEST_APP")

-- Version 9 has db interfaces
my_app.static.API_VER = 9

--- 应用初始化
function my_app:on_init()
	local conf = self:app_conf()
	local sys = self:sys_api()
	self._watch_dsn = sys:id()..'.'..(conf.device or 'HJ212')
	self._db_map = {}
end

---
-- 处理设备数据
-- Handle device real time data
-- app: 数据来源应用名称（实例名）[Source application instance name]
-- sn: 数据源设备的序列号 [Device serial number e.g XXX.PLC1]
-- input: 数据源名称 [Device input name. e.g temperature]
-- prop: 数据源属性 [Device input property. e.g. value]
-- value: 数据值 [Device input property value.  e.g 20]
-- timestamp: 时间戳 [Data timestamp]
-- quality: 质量戳 [Data quality 0 means good]
function my_app:on_input(app, sn, input, prop, value, timestamp, quality)
	if sn ~= self._watch_dsn then
		return
	end
	local tagdb = self._db_map[input]
	if not tagdb then
		tagdb = hisdb_tag:new(self._hisdb, input)
		tagdb:init()
		self._db_map[input] = tagdb
	end
	if prop == 'value' then
		tagdb:push_sample({value=value, flag='N', timestamp=timestamp, cou=value})
	else
		local val, err = cjson.decode(value)
		if not val then
			return
		end
		tagdb:write(prop, val)
	end
	return
end

---
-- 应用启动函数
-- Application start callback
function my_app:on_start()
	self._start = ioe.time()
	self._hisdb = hisdb:new('HJ212', {})
	return self._hisdb:init()
end

--- 应用退出函数
function my_app:on_close(reason)
	--print(self._name, reason)
end

--- 应用运行入口
function my_app:on_run(tms)
	if ioe.time() - self._start > 60 then
		for k, v in pairs(self._db_map) do
			v:save_samples()
		end
	end

	return 10000 --下一采集周期为10秒
end

--- 返回应用类
return my_app

