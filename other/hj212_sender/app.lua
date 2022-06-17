local ioe = require 'ioe'
local base = require 'app.base'
local serial = require 'serialdriver'
local cjson = require 'cjson.safe'
local date = require 'date'
local crc16 = require 'utils.crc'
local sort = require 'utils.sort'

local csv_tpl = require 'csv_tpl'

local app = base:subclass("FREEIOE.APP.OTHER.HJ212_SENDER")
app.static.API_VER = 9

function app:on_init()
	self._serial_sent = 0
	self._serial_recv = 0
	self._value_map = {}
end

function app:on_start()
	local sys = self:sys_api()
	local log = self:log_api()

	csv_tpl.init(sys:app_dir())

	--- Mapping 
	local sys_id = sys:id()
	local function map_dev_sn(sn)
		local sn = sn or 'GW'
		if sn == 'GW' then
			return sys_id
		end
		sn = string.gsub(sn, '^GW(%..*)$', sys_id..'%1')
		return sn
	end

	local conf = self:app_conf() or {}

	local tpl_id = conf.tpl
	local tpl_ver = conf.ver

	if conf.tpls and #conf.tpls >= 1 then
		tpl_id = conf.tpls[1].id
		tpl_ver = conf.tpls[1].ver
	end

	local tpl_file = '___NO_SUCH_TEMPLATE.csv'
	if tpl_id and tpl_ver then
		local capi = sys:conf_api(tpl_id)
		local data, err = capi:data(tpl_ver)
		if not data then
			log:error("Failed loading template from cloud!!!", err)
			return false
		end
		tpl_file = tpl_id..'_'..tpl_ver
	end
	if ioe.developer_mode() then
		tpl_file = 'test'
	end

	log:info("Loading template", tpl_file)
	local tpl, err = csv_tpl.load_tpl(tpl_file, function(...)
		log:error(...)
	end)
	if not tpl then
		return nil, err
	end

	for _, v in ipairs(tpl.props) do
		v.sn = map_dev_sn(v.sn)
	end
	self._tpl = tpl

	--- 增加设备实例
	local inputs = {
		{name="serial_sent", desc="Serial sent bytes", vt="int", unit="bytes"},
		{name="serial_recv", desc="Serial received bytes", vt="int", unit="bytes"},
	}

	local meta = self._api:default_meta()
	meta.name = "HJ212 Sender"
	meta.inst = self._name
	meta.description = "HJ212 Sender"

	--- 生成设备唯一序列号
	local sn = sys_id.."."..self._name
	self._dev = self._api:add_device(sn, meta, inputs)

	local opt = conf.serial or {
		port = '/dev/ttyS2',
		baudrate = 9600,
		data_bits = 8,
		parity = 'NONE',
		stop_bits = 1,
		flow_control = 'OFF'
	}
	if ioe.developer_mode() then
		opt.port = '/tmp/ttyS10'
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

	sys:timeout(10, function()
		self:read_tags()
	end)

	return true
end

local function n_val_fmt(fmt, val)
	local i, f = string.match(fmt, 'N(%d*)%.?(%d*)')
	i = tonumber(i)
	f = tonumber(f)
	assert(i)
	assert(val)
	if f then
		local ffmt = '%.'..f..'f'
		return string.format(ffmt, val)
	else
		return string.format('%.0f', val)
	end
end

function app:set_input_value_map(hj212_name, fmt, rate, key, value, quality)
	print(hj212_name, fmt, rate, key, value, quality)
	local val = value
	if rate then
		val = val * rate
	end

	if string.sub(fmt, 1, 1) == 'N' then
		val = n_val_fmt(fmt, val)
	else
		val = tostring(val)
	end

	if self._value_map[hj212_name] == nil then
		self._value_map[hj212_name] = {
			[key] = val
		}
	end

	if quality == 0 then
		self._value_map[hj212_name]._flag = 'N'
		self._value_map[hj212_name][key] = val
	else
		self._value_map[hj212_name]._flag = 'D'
	end
end

function app:read_tags()
	local api = self:data_api()
	local props = self._tpl.props
	local devs = {}
	for _, v in pairs(props) do
		local dev_api = devs[v.sn]
		if not dev_api then
			dev_api = api:get_device(v.sn)
			devs[v.sn] = dev_api
		end

		if dev_api then
			local value, timestamp, quality = dev_api:get_input_prop(v.name, 'value')
			if value ~= nil then
				self:set_input_value_map(v.hj212, v.fmt, v.rate, v.key, value, quality)
			end
		else
			self._log:error("Failed to find device", v.sn)
		end
	end
end

function app:on_input(app_src, sn, input, prop, value, timestamp, quality)
	-- Skip quality not good value
	if prop ~= 'value' then
		return
	end

	-- avoid nil ipairs
	local props = self._tpl and self._tpl.props or {}

	for _, v in ipairs(props) do
		if v.sn == sn and v.name == input then
			self:set_input_value_map(v.hj212, v.fmt, v.rate, v.key, value, quality)
		end
	end
end

local function encode_datetime(now)
	return date(now):tolocal():fmt('%Y%m%d%H%M%S')
end

function app:on_run(tms)
	if self._port then
		local t = {}
		t[#t + 1] = string.format('ST=%02d;CN=2011;PW=123456;MN=%s;CP=&&', self._conf.st, self._conf.mn)
		t[#t + 1] = 'DataTime='..encode_datetime(ioe.time())
		sort.for_each_sorted_kv(self._value_map, function(k, v)
			local tt = {}
			for kk, vv in pairs(v) do
				if kk ~= '_flag' then
					table.insert(tt, string.format('%s-%s=%s', k, kk, vv))
				end
			end
			table.insert(tt, string.format('%s-Flag=%s', k, v._flag or 'D'))
			t[#t + 1] = string.format(';%s', table.concat(tt, ','))
		end)
		local body_str = table.concat(t)..'&&'
		local body_len = string.len(body_str)
		local crc_str = string.format('%04X', crc16(body_str))
		local data = string.format('##%04d%s%s\r\n', body_len, body_str, crc_str)

		self._serial_sent = self._serial_sent + string.len(data)
		self._dev:dump_comm('SERIAL-OUT', data)
		self._port:write(data)
	end

	self._dev:set_input_prop('serial_sent', 'value', self._serial_sent)
	self._dev:set_input_prop('serial_recv', 'value', self._serial_recv)

	return (self._conf.interval or 5) * 1000
end

return app
