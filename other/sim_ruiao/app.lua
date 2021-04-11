local ioe = require 'ioe'
local base = require 'app.base'
local serial = require 'serialdriver'
local cjson = require 'cjson.safe'

local app = base:subclass("FREEIOE.APP.OTHER.SIM_MP1")
app.static.API_VER = 9

function app:on_init()
	self._serial_sent = 0
	self._serial_recv = 0
end

function app:on_start()
	--- 生成设备唯一序列号
	local sys_id = self._sys:id()
	local sn = sys_id.."."..self._name

	--- 增加设备实例
	local inputs = {
		{name="serial_sent", desc="Serial sent bytes", vt="int", unit="bytes"},
		{name="serial_recv", desc="Serial received bytes", vt="int", unit="bytes"},
	}

	local meta = self._api:default_meta()
	meta.name = "CEMS MP1"
	meta.inst = self._name
	meta.description = "CEMS MP1 Simulation"

	self._dev = self._api:add_device(sn, meta, inputs)

	local opt = {
		port = '/dev/ttyS2',
		baudrate = 9600,
		data_bits = 8,
		parity = 'NONE',
		stop_bits = 1,
		flow_control = 'OFF'
	}
	if ioe.developer_mode() then
		opt.port = '/tmp/ttyS2'
	end

	self._log:notice(string.format("Open serial %s", cjson.encode(opt)))
	local port = serial:new(opt.port, opt.baudrate or 9600, opt.data_bits or 8, opt.parity or 'NONE', opt.stop_bits or 1, opt.flow_control or "OFF")

	local r, err = port:open()
	if not r then
		self._log:warning("Failed open port, error: "..err)
		return nil, err
	end

	port:start(function(data, err)
		-- Recevied Data here
		if data then
			self._dev:dump_comm('SERIAL-IN', data)
			self._serial_recv = self._serial_recv + string.len(data)
		else
			self._log:error(err)
		end
	end)
	self._port = port

	return true
end

function app:on_run(tms)

	if self._port then
		local data = '##00010900ST=31;CN=1073;PW=123456;MN=88888880000001;CP=&&DataTime=20180102212551;02-CurrZero=-54.660,02-DemCoeff=1.109;03-CurrZero=153.371,03-DemCoeff=0.971;S01-CurrZero=0.000,S01-DemCoeff=0.980;ZeroDate=33811122235142;02-ScaleGasNd=1428.571,02-CailDate=20140101010101;03-ScaleGasNd=80.357,03-CailDate=33811122235251;S01-ScaleGasNd=19.500,S01-CailDate=33811122235107;02-ZeroRange=0,02-FullRange=857.14;03-ZeroRange=0,03-FullRange=401.79;S01-ZeroRange=0,S01-FullRange=25.00;CellPressure=101.3;CellTemp=30.5;SpecEnergy=40371.0;02-ZeroDev=-0.77,02-CailDev=0.00;03-ZeroDev=0.48,03-CailDev=0.00;S01-ZeroDev=0.00,S01-CailDev=4.30;03-Mol=30;02-ZeroCail=0,02-ZeroOrigin=-54.660,02-CailOrigin=0.000,02-RealOrigin=-54.653,02-Rtd=0.01;03-ZeroCail=0,03-ZeroOrigin=153.371,03-CailOrigin=0.000,03-RealOrigin=163.094,03-Rtd=9.444;S01-ZeroCail=0,S01-ZeroOrigin=0.000,S01-CailOrigin=19.893,S01-RealOrigin=20.067,S01-Rtd=19.7;&&6E2D\r\n'
		self._serial_sent = self._serial_sent + string.len(data)
		self._dev:dump_comm('SERIAL-OUT', data)
		self._port:write(data)

		-- local data = '##00010206ST=31;CN=2011;PW=123456;MN=88888880000001;CP=&&DataTime=20180102160917;02-Rtd=0.00,02-RealOrigin=-54.660;03-Rtd=6.444,03-RealOrigin=160.006;S01-Rtd=19.6,S01-RealOrigin=19.955;SB1-InstrState=0;SB1-Ala=0000&&5BF7\r\n'
		local data = '##00010105ST=31;CN=2021;PW=123456;MN=88888880000001;CP=&&DataTime=20150530191231;SB1-InstrState=0000;SB1-Ala=0000&&4188\r\n'
		self._serial_sent = self._serial_sent + string.len(data)
		self._dev:dump_comm('SERIAL-OUT', data)
		self._port:write(data)
	end

	self._dev:set_input_prop('serial_sent', 'value', self._serial_sent)
	self._dev:set_input_prop('serial_recv', 'value', self._serial_recv)

	return 5000
end

return app
