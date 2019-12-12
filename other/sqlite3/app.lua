local app_base = require 'app.base'
local ioe = require 'ioe'
local sqlite3 = require 'sqlite3'
local sysinfo = require 'utils.sysinfo'

--- 注册应用对象
local app = app_base:subclass("FREEIOE_SQLITE3_EXAMPLE_APP")
app.static.API_VER = 6 -- require app.conf module


--- 应用初始化回调函数
function app:on_init()
	--- 计算帮助类初始化
	local calc = self:create_calc()
	--- calc对象为计算帮助类对象，creaet_calc也会将calc对象赋值给 self._calc变量
end

function app:on_start()

	local db, err = self:init_db_file()
	if not db then
		return false, err
	end
	self._db = db

	db:exec([[ 
CREATE TABLE "cpu_temp" (
	"id"	INTEGER PRIMARY KEY AUTOINCREMENT UNIQUE,
	"timestamp"	DOUBLE NOT NULL,
	"value"	DOUBLE NOT NULL
);]])

	self:start_record()

	return true
end

function app:init_db_file()
	local path = sysinfo.data_dir() .. "/sqlite3_" .. self._name .. "_db_file.sqlite3"
	return sqlite3.open(path)
end

function app:start_record()
	--- 关注设备cpu温度
	local dsn = self._sys:id()
	local db = self._db

	self._calc:add('cpu_temp', {
		{ sn = dsn, input = 'cpu_temp', prop='value' }
	}, function(cpu_temp)
		print(cpu_temp)
		-- 保存数据
		local stmt, err = db:prepare([[ INSERT INTO cpu_temp (timestamp, value) VALUES (:timestamp, :value)]])
		if not stmt then
			self._log:error(err)
			return
		end
		self._log:debug("Insert", cpu_temp)

		stmt:bind( {timestamp=ioe.time(), value=cpu_temp} ):exec()
	end)
end

function app:on_run(tms)
	local db = self._db
	if not db then
		return
	end
	for row in db:rows("SELECT * FROM cpu_temp ORDER BY timestamp DESC LIMIT 1") do
		self._log:debug("CPU_TEMP", row.id, row.timestamp, row.value)
	end
end

function app:on_close(reason)
	if self._db then
		self._db:close()
		self._db = nil
	end
end

--- 返回应用对象
return app

