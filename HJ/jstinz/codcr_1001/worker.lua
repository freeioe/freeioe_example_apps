local class = require 'middleclass'
local pdu = require 'modbus.pdu.init'
local data_pack = require 'modbus.data.pack'
local data_unpack = require 'modbus.data.unpack'
local date = require 'date'
local ioe = require 'ioe'
local retry = require 'utils.retry'

local worker = class("CODcr_1001.worker")

local SF = string.format


--[[
0：待机状态  2：水样加入  3：试剂B加入  4：试剂A加入
5：试剂C加入  6：正在加热  7：正在冷却  8：预冲洗 
9：正在排液   13：设备异常 13：测量完清洗
]]--
--[[
i12101:
0=空闲  1=做样  2=清洗  3=维护  4=故障 5=校准 6=标样核查
--]]
--[[
HJ212 Flag:
N-正常
F-停运
M-维护
S-手工输入
D-故障
C-校准
T-超限
B-通讯异常
]]--
--[[
0-关闭 1-运行 2-校准 3-维护 4-报警 5-反吹
]]--
local function convert_status(status)
	if status == 0 then
		return 0, 'N', 1
	elseif status >= 2 and status <= 9 then
		return 1, 'N', 1
	elseif status <= 12 then
		return 4, 'D', 4
	elseif status >= 13 then
		return 2, 'N', 1
	end
	return 4, 'B', 0
end

--[[
1：热电偶异常 2：加热器异常  3：未采到试剂A  4:未采到试剂B
5:计量信号错误  6：未采到试剂C   8：冷凝异常  10：停电异常
11：开机    12：光电异常  13：未采到标1   14：未采到标2   
15：未采到水样  0：无异常
]]--

--[[
i12103:
0=正常  1=缺试剂  2=缺蒸馏水  3=缺标液  4=缺水样  5=加热故障  6=光源异常  7=测量超上限  8=测量超下限 9=排残液故障  10=采样故障
]]--

local function convert_alarm(alarm)
	if alarm == 0 then
		return 0
	elseif alarm == 1 or alarm == 2 then
		return 5
	elseif alarm == 3 or alarm == 4 or alarm == 6 then
		return 1
	elseif alarm == 5 or alarm == 12 then
		return 6
	elseif alarm == 8 or alarm == 10 or alarm == 11 then
		return 10
	elseif alarm == 13 or alarm == 14 then
		return 3
	elseif alarm == 15 then
		return 4
	end
	return 10
end

local function convert_datetime(d, pdu_data, index)
	local year = d:uint16(pdu_data, index)
	local mon = d:uint16(pdu_data, index + 2)
	local day = d:uint16(pdu_data, index + 4)
	local hour = d:uint16(pdu_data, index + 6)
	local min = d:uint16(pdu_data, index + 8)

	year = year % 100
	mon = mon % 12
	day = day % 31
	hour = hour % 60
	min = min % 60

	--[[
	local dt_str = string.format('20%02d-%02d-%02dT%02d:%02d:00', year, mon, day, hour, min)
	print(dt_str, year, mon, day, hour, min)
	]]--

	local t = os.time({
		year = 2000 + year,
		month = mon,
		day = day,
		hour = hour,
		min = min,
	})
	--print(os.date('%FT%T', t))

	return t
end

local function convert_range(r)
	if r == 0 then
		return 5, 500
	elseif r == 1 then
		return 100, 5000
	elseif r == 2 then
		return 300, 10000
	end
	return 0, 0
end


function worker:initialize(app, unit, dev, conf)
	self._log = app:log_api()
	self._unit = unit
	self._dev = dev
	self._conf = conf
	self._pdu = pdu:new()
	self._data_pack = data_pack:new()
	self._data_unpack = data_unpack:new()
end

function worker:run(modbus)
	local r, err = self:read_val(modbus)
	if not r then
		self:invalid_dev()
		return nil, err
	end

	return true
end

function worker:invalid_dev()
	local now = ioe.time()

	self._dev:set_input_prop('status', 'value', -1, now, -1)
	self._dev:set_input_prop('alarm', 'value', -1, now, -1)
	self._dev:set_input_prop('RS', 'value', 0, now, -1)

	self._dev:set_input_prop('w01018', 'value', 0, now, -1)
	self._dev:set_input_prop('w01018_raw', 'value', 0, now, -1)
	self._dev:set_input_prop('w01018', 'RDATA', {
		value = 0,
		value_src = 0,
		flag = 'B',
		timestamp = now
	}, now, -1)
end

function worker:read_val(modbus)
	local func = 0x03
	local addr = 0
	local dlen = 34
	local req, err = self._pdu:make_request(func, addr, dlen)
	if not req then
		return nil, err
	end
	local pdu, err = retry(3, modbus.request, modbus, self._unit, req, 1000)
	if not pdu then
		return nil, err
	end

	--- 解析数据
	local d = self._data_unpack
	if d:uint8(pdu, 1) == (0x80 + func) then
		local basexx = require 'basexx'
		self._log:warning("read package failed 0x"..basexx.to_hex(string.sub(pdu, 1, 1)))
		return nil, 'Modbus error'..d:uint8(pdu, 1)
	end

	local len = d:uint8(pdu, 2)
	if len < dlen * 2 then
		return SF("length issue :%d - %d", len, dlen * 2)
	end

	local pdu_data = string.sub(pdu, 3)

	local cod_val = d:float(pdu_data, 1)
	local cod_raw = d:float(pdu_data, 5)

	local water_tm = convert_datetime(d, pdu_data, 9)

	local status = d:uint16(pdu_data, 19)
	local i12101, flag, rs = convert_status(status)

	local alarm = d:uint16(pdu_data, 21)
	local i12103 = convert_alarm(alarm)
	local i12102 = i12103 == 0 and 0 or 1

	local offset = d:float(pdu_data, 23)
	local offset_r = d:float(pdu_data, 27)

	local calib_tm = convert_datetime(d, pdu_data, 31)

	local i13105 = d:uint16(pdu_data, 41)
	local i13110 = d:uint16(pdu_data, 43)

	local dtemp = d:uint16(pdu_data, 45)
	local dtime = d:uint16(pdu_data, 47)

	local up_tm = convert_datetime(d, pdu_data, 49)
	local min, max = convert_range(d:uint16(pdu_data, 59))
	local i13104 = d:float(pdu_data, 61)
	local i13108 = d:float(pdu_data, 65)

	local now = ioe.time()

	self._dev:set_input_prop('sample_time', 'value', os.date('%FT%T', water_tm), now)
	self._dev:set_input_prop('calib_time', 'value', os.date('%FT%T', calib_tm), now)
	self._dev:set_input_prop('uptime', 'value', os.date('%FT%T', up_tm), now)

	self._dev:set_input_prop('RS', 'value', rs, now)
	self._dev:set_input_prop('status', 'value', status, now)
	self._dev:set_input_prop('alarm', 'value', alarm, now)
	self._dev:set_input_prop('w01018_raw', 'value', cod_raw, now)

	self._dev:set_input_prop('w01018', 'value', cod_val, now)
	self._dev:set_input_prop('w01018', 'RDATA', {
		value = cod_val,
		value_src = cod_raw,
		timestamp = now,
		flag = flag
	}, now)

	local info = {
		i12101 = i12101,
		i12102 = i12102,
		i12103 = i12103,

		-- Zero
		i13101 = calib_tm,
		i13104 = i13104,
		i13105 = i13105,
		-- Max
		i13107 = calib_tm,
		i13108 = i13108,
		i13110 = i13110,

		i13116 = max, -- 当前量程
		i13119 = offset_r,
		i13120 = offset,
		i13121 = dtemp,
		i13122 = dtime / 60,
	}
	for k, v in pairs(info) do
		self._dev:set_input_prop(k, 'value', v, now)
	end

	self._dev:set_input_prop('w01018', 'INFO', info, now)

	return true
end

return worker
