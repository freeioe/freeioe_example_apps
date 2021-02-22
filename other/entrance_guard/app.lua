local base = require 'app.base'
local socket = require 'skynet.socket'
local sockethelper = require 'http.sockethelper'
local urllib = require 'http.url'
local restful = require 'eg_http.restful'
local httpd = require 'eg_http.httpd'

local app = base:subclass("FREEIOE.APP.OTHER.ENTRANCE_GUARD")
app.static.API_VER = 9

function app:on_init()
	self._devs = {}
end

function app:on_start()
	local sys = self:sys_api()
	local log = self:log_api()
	local conf = self:app_conf()
	conf.devs = conf.devs or {}

	--- Default is with gateway sn prefix
	local with_prefix = conf.dev_sn_prefix ~= nil and conf.dev_sn_prefix or true
	local dev_sn = with_prefix and sys:id()..'.'..(conf.sn or self:app_name())

	self:create_device(dev_sn)

	self._cycle = tonumber(conf.cycle) or 5000 -- ms
	if self._cycle < 100 then
		self._cycle = 5000
	end

	return self:start_httpd(conf.port)
end

function app:create_device(dev_sn)
	local api = self:data_api()
	local meta = api:default_meta()
	meta.name = 'EntranceGuard'
	meta.description = "Entrance Guard device"
	meta.series = 'X'
	meta.inst = self:app_name()

	local inputs = {
		{ name = 'id', desc = 'Device ID', vt='string'},
		{ name = 'verify_status', desc = 'Verify Status', vt='int'},
		{ name = 'verify_type', desc = 'Verify Type', vt='int'},
		{ name = 'person_type', desc = 'Person Type', vt='int'},
		{ name = 'verify_code', desc = 'Face, Card, token code', vt='string'},
		{ name = 'open_time', desc = 'Door open time', vt='string'},
		{ name = 'door_status', desc = 'Door status', vt='int'},
		{ name = 'card_no', desc = 'Dorr status', vt='string'},
		{ name = 'persion_id', desc = 'Persion ID', vt='string'},
		{ name = 'persion_image', desc = 'Persion Image URL', vt='string'},
		{ name = 'persion_name', desc = 'Persion Name', vt='string'},
	}
	local commands = {
		{ name = 'open_door', desc = 'Open door with access token' }
	}

	local dev = api:add_device(dev_sn, meta, inputs, {}, commands)

	self._dev = dev
	self._stat = dev:stat('port')
end

function app:start_httpd(port, ip)
	assert(port, "Port missing")
	if self._httpd_socket then
		return true
	end
	local id, err = socket.listen(ip or "0.0.0.0", port)
	if not id then
		return nil, err
	end

	self._httpd_socket = id
	socket.start(id, function(cid, addr)
		self:process_http('http', cid, addr)
	end)

	return true
end

local function response(id, write, ...)
	local ok, err = httpd.write_response(write, ...)
	if not ok then
		-- if err == sockethelper.socket_error , that means socket closed.
		skynet.error(string.format("fd = %d, %s", id, err))
	end
end


local SSLCTX_SERVER = nil
local function gen_interface(protocol, fd)
	if protocol == "http" then
		return {
			init = nil,
			close = nil,
			read = sockethelper.readfunc(fd),
			write = sockethelper.writefunc(fd),
		}
	elseif protocol == "https" then
		local tls = require "http.tlshelper"
		if not SSLCTX_SERVER then
			SSLCTX_SERVER = tls.newctx()
			-- gen cert and key
			-- openssl req -x509 -newkey rsa:2048 -days 3650 -nodes -keyout server-key.pem -out server-cert.pem
			local certfile = skynet.getenv("certfile") or "./server-cert.pem"
			local keyfile = skynet.getenv("keyfile") or "./server-key.pem"
			print(certfile, keyfile)
			SSLCTX_SERVER:set_cert(certfile, keyfile)
		end
		local tls_ctx = tls.newtls("server", SSLCTX_SERVER)
		return {
			init = tls.init_responsefunc(fd, tls_ctx),
			close = tls.closefunc(tls_ctx),
			read = tls.readfunc(fd, tls_ctx),
			write = tls.writefunc(fd, tls_ctx),
		}
	else
		error(string.format("Invalid protocol: %s", protocol))
	end
end

function app:process_http(protocol, id, addr)
	socket.start(id)
	local interface = gen_interface(protocol, id)
	if interface.init then
		interface.init()
	end
	-- limit request body size to 8192 (you can pass nil to unlimit)
	local code, url, method, header, body = httpd.read_request(interface.read, 8192)
	if code then
		if code ~= 200 then
			response(id, interface.write, code)
		else
			local tmp = {}
			if header.host then
				table.insert(tmp, string.format("host: %s", header.host))
			end
			local path, query = urllib.parse(url)
			table.insert(tmp, string.format("path: %s", path))
			if query then
				local q = urllib.parse_query(query)
				for k, v in pairs(q) do
					table.insert(tmp, string.format("query: %s= %s", k,v))
				end
			end
			table.insert(tmp, "-----header----")
			for k,v in pairs(header) do
				table.insert(tmp, string.format("%s = %s",k,v))
			end
			table.insert(tmp, "-----body----\n" .. body)
			response(id, interface.write, code, table.concat(tmp,"\n"))
		end
	else
		if url == sockethelper.socket_error then
			skynet.error("socket closed")
		else
			skynet.error(url)
		end
	end
	socket.close(id)
	if interface.close then
		interface.close()
	end
end

function app:on_run(tms)
	if not self._subscribed then
		self:subscribe()
		return
	end

	return self._cycle
end

function app:subscribe()
end

return app
