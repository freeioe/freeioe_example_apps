local class = require 'middleclass'
local skynet = require 'skynet'
local cjson = require 'cjson.safe'
local basexx = require 'basexx'
local md5 = require 'md5'
local sc = require 'socketchannel'
local crypt = require 'welink.crypt'

local client = class('welink.client')

function client:initialize(host, port, pid, crypt)
	self._host = assert(host)
	self._port = assert(port)
	self._pid = pid
	self._crypt = crypt
end

function client:connect()
	self._sock = sc.channel({
		host = self._host,
		port = self._port,
		nodelay = true
	})
	return true
end

function client:close()
	if not self._sock then
		return true
	end
	self._sock:close()
	self._sock = nil
end

function client:crypto()
	return self._crypt
end

function client:register(sn)
	local pid = assert(self._pid)
	local lic = assert(self._crypt:sm2_sign(sn))
	local lic_hex = basexx.to_hex(lic)
	local reg_data = cjson.encode({
		sn = sn,
		lic = lic_hex,
		ts = skynet.time() * 1000
	})
	print(reg_data)
	
	local reg_encrypt = self._crypt:sm2_encrypt(reg_data)
	local reg_encrypt_hex = basexx.to_hex(reg_encrypt)

	local md5sum = md5.sumhexa(reg_encrypt_hex)

	local msg = cjson.encode({
		v = 2,
		pid = pid,
		data = reg_encrypt_hex,
		mac = md5sum
	})
	print('sending', msg)

	local raw = string.pack('>I2I4', 0x000d, string.len(msg))..msg

	local resp, err = self._sock:request(raw, function(sock)
		local head, err = sock:read(6)
		if not head then
			print('head', err)
			return nil, err
		end
		local cmd, len = string.unpack('>I2I4', head)
		print(cmd, len)
		local data, err = sock:read(len)
		if not data then
			print('data', err)
			return nil, err
		end
		print('RECV', data)

		return true, data
	end)

	if not resp then
		return nil, err
	end

	local data, err = cjson.decode(resp)
	if not data then
		return nil, err
	end

	if data.code ~= 0 then
		return data.msg
	end

	-- check md5
	local md5sum = md5.sumhexa(data.data)
	if md5sum ~= data.mac then
		return nil, "MD5 check failed"
	end

	local raw_data = basexx.from_hex(data.data)

	local dresp, err = self._crypt:sm2_decrypt(raw_data)
	if not dresp then
		return nil, err
	end
	print('DECRYPTED', dresp)

	return cjson.decode(dresp)
end

function client:challenge()
	local raw = string.pack('>I2I4I1', 0x000b, 1, 0x01)

	local resp, err = self._sock:request(raw, function(sock)
		local head, err = sock:read(6)
		if not head then
			return nil, err
		end
		local cmd, len = string.unpack('>I2I4', head)
		local data, err = sock:read(len)
		if not data then
			return nil, err
		end

		return true, data
	end)

	if not resp then
		return nil, err
	end

	local data, err = cjson.decode(resp)
	if not data then
		return nil, err
	end

	if data.code ~= 0 then
		return data.msg
	end

	return data.data --- challenge number
end

function client:login(sn, wid, challenge_ran, ran)
	local pid = assert(self._pid)
	local lic = assert(self._crypt:sm2_sign(sn))
	local lic_hex = basexx.to_hex(lic)
	local login_data = cjson.encode({
		wId = wid,
		lic = lic_hex,
		ran = ran,
		chanllenge_ran = challenge_ran
	})
	print(login_data)
	
	local data_en = self._crypt:sm2_encrypt(login_data)
	local data_en_hex = basexx.to_hex(data_en)

	local md5sum = md5.sumhexa(data_en_hex)

	local msg = cjson.encode({
		v = 2,
		pid = pid,
		data = data_en_hex,
		mac = md5sum
	})
	print('sending', msg)

	local raw = string.pack('>I2I4', 0x000e, string.len(msg))..msg

	local resp, err = self._sock:request(raw, function(sock)
		local head, err = sock:read(6)
		if not head then
			print('head', err)
			return nil, err
		end
		local cmd, len = string.unpack('>I2I4', head)
		print(cmd, len)
		local data, err = sock:read(len)
		if not data then
			print('data', err)
			return nil, err
		end
		print('RECV', data)

		return true, data
	end)

	if not resp then
		return nil, err
	end

	local data, err = cjson.decode(resp)
	if not data then
		return nil, err
	end

	if data.code ~= 0 then
		return data.msg
	end

	-- check md5
	local md5sum = md5.sumhexa(data.data)
	if md5sum ~= data.mac then
		return nil, "MD5 check failed"
	end

	local raw_data = basexx.from_hex(data.data)

	local dresp, err = self._crypt:sm2_decrypt(raw_data)
	if not dresp then
		return nil, err
	end
	print('DECRYPTED', dresp)

	return cjson.decode(dresp)
end

return client
