local ioe = require 'ioe'
local base = require 'app.base'
local serial = require 'serialdriver'

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
		data = '##0236ST=31;CN=2011;PW=123456;MN=MP1;CP=&&DataTime=20210129152246;01-Rtd=8.764,01-ZsRtd=14.387;02-Rtd=9.933,02-ZsRtd=16.307;03-Rtd=86.131,03-ZsRtd=141.392;B02-Rtd=6015.213;S01-Rtd=13.893;S02-Rtd=2.491;S03-Rtd=44.586;S05-Rtd=0;S08-Rtd=53.796&&524F' + '\r\n'
		self._serial_sent = self._serial_sent + string.len(data)
		self._dev:dump_comm('SERIAL-OUT', data)
		self._port:write(data)
	end

	self._dev:set_input_prop('serial_sent', 'value', self._serial_sent)
	self._dev:set_input_prop('serial_recv', 'value', self._serial_recv)

	return 5000
end

return app
