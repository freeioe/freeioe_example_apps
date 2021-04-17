local verify = require 'verify'
local cjson = require 'cjson.safe'
local ioe = require 'ioe'
local base = require 'app.base'
local socket = require 'skynet.socket'
local sockethelper = require 'http.sockethelper'
local urllib = require 'http.url'
local restful = require 'http.restful'
local httpd = require 'http.httpd'

local app = base:subclass("FREEIOE.APP.SIM.FACE_ENTRANCE")
app.static.API_VER = 9

function app:on_init()
	self._devs = {}
	self._subscribe = false
end

function app:on_start()
	local sys = self:sys_api()
	local conf = self:app_conf()

	verify.init(sys:app_dir()..'/images/')

	return self:start_httpd(conf.port)
end

function app:on_run(tms)
	local log = self:log_api()

	if self._subscribe then
		self:fire_heartbeat()
		self:fire_verify()
		return 5000 -- five seconds
	end

	return 100
end

function app:on_close(reason)
	self:stop_httpd()
	return true
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

function app:stop_httpd()
	if self._httpd_socket then
		socket.close(self._httpd_socket)
	end
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
	local log = self:log_api()

	socket.start(id)
	local interface = gen_interface(protocol, id)
	if interface.init then
		interface.init()
	end
	-- limit request body size to 8192K (you can pass nil to unlimit)
	local code, url, method, header, body = httpd.read_request(interface.read, 8192 * 1024)
	if code then
		if code ~= 200 then
			response(id, interface.write, code)
		else
			local path, query = urllib.parse(url)
			if query then
				query = urllib.parse_query(query)
			end
			path = string.lower(path)

			self:handle_http_req(method, path, header, query, body, function(code, body)
				if type(body) == 'table' then
					--content = table.concat(tmp,"\n")
					local content, err = cjson.encode(body)
					return response(id, interface.write, code, content or err)
				else
					return response(id, interface.write, code, body)
				end
			end)
		end
	else
		if url == sockethelper.socket_error then
			log:error("socket closed")
		else
			log:error(url)
		end
	end
	socket.close(id)
	if interface.close then
		interface.close()
	end
end

local function convert_type(verfy_type)
	local typ = tonumber(verfy_type) or 1
	if typ == 1 then
		return 1
	end
	if typ == 27 then
		return 4
	end

	-- Others are 2
	return 2
end

function app:handle_http_req(method, path, header, query, body, response)
	local log = self:log_api()
	log:trace(path, body)

	local path = string.lower(path)

	if path == '/action/subscribe' then
		local data, err = cjson.decode(body)
		if not data then
			return response(403, {code=403, desc="Decode JSON failure"})
		end

		self._subscribe = data.info

		self._api = restful:new(data.info.SubscribeAddr, 1000, nil, {'admin', 'admin'})

		return response(200, {
			operator = 'Subscribe',
			code = 200,
			info = {
				Result="OK"
			}
		})
	end
	if path == '/action/addperson' then
		local data, err = cjson.decode(body)

		return response(200, {
			operator = 'AddPerson',
			code = 200,
			info = {
				Result="OK"
			}
		})
	end

	if path == '/action/deleteperson' then
		local data, err = cjson.decode(body)

		return response(200, {
			operator = 'DeletePerson',
			code = 200,
			info = {
				Result="OK"
			}
		})
	end

	if path == '/action/opendoor' then
		local data, err = cjson.decode(body)

		return response(200, {
			operator = 'OpenDoor',
			code = 200,
			info = {
				Result="OK"
			}
		})
	end

	return response(403, "Not implemented such request handling")
end

function app:fire_heartbeat()
	local sub = self._subscribe
	local p = {
		operator = 'HeartBeat',
		info = {
			DeviceID = sub.DeviceID,
			Time = os.date('%FT%T')
		}
	}
	--- Hacks about the \/ escape
	local content = string.gsub(cjson.encode(p), '\\/', '/')

	local status, body = self._api:post('/Subscribe/heartbeat', {}, content, 'application/json')
	if not status or status ~= 200 then
		self._subscribe = nil
		self._api = nil
		return nil, body
	end
	self._last_hearbeat = ioe.now()
	return true
end

function app:fire_verify()
	local sub = self._subscribe
	local content = {
		operator = 'VerifyPush',
		info = {
			DeviceID = sub.DeviceID,
			PersonID = 1,
			CreateTime = os.date('%FT%T'),
			Similarity1 = 95.123,
			Similarity2 = 0,
			VerifyStation = 1,
			VerifyType = 1,
			PersonType = 0,
			Name = '门禁1',
			Gender = 0,
			Nation = 1,
			CardType = 0,
			IdCard = "",
			Birthday = os.date('%F', 0),
			Telnum = '',
			Native = '',
			Address = '',
			Notes = '13810955224',
			MjCardFrom = '',
			MjCardNo = 1,
			Tempvalid = 0,
			CustomizeID = 0,
			PersonUUID = '11000000-0000-0000-0000-013810955224',
			ValidBegin = '0000-00-00T00:00:00',
			ValidEnd = '0000-00-00T00:00:00',
			RFIDCard = '',
			Sendintime = 1,
		},
		SnapPic = 'data:image/jpeg;base64,QUFBCg==',
	}
	local status, body = self._api:post('/Subscribe/Verify', {}, content, 'application/json')
	if not status or status ~= 200 then
		return nil, body
	end

	local ret = cjson.decode(body)
	if tonumber(ret.code or '') ~= 200 then
		local err = ret.desc and ret.desc or 'Error status code:'..ret.code
		return nil, err
	end

	return true
end

return app
