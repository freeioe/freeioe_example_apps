local class = require 'middleclass'
local basexx = require 'basexx'
local b64 = require 'crypt.b64'
local sm = require 'crypt.sm'

local crypt = class('welink.crypt')

function crypt:initialize(pname, pid, srv_pub_key, dev_pub_key, dev_pri_key)
	local base_dir = '/tmp/welink_keys_'..pid
	os.execute('mkdir -p '..base_dir)
	local srv_pub_path = base_dir..'/srv_pub.pem'
	local dev_pub_path = base_dir..'/dev_pub.pem'
	local dev_pri_path = base_dir..'/dev_pri.pem'

	self._sm = sm({})
	self._b64 = b64({})

	self._sm.sm2key_write(srv_pub_key, srv_pub_path)
	self._sm.sm2key_write(dev_pub_key, dev_pub_path, dev_pri_key, dev_pri_path)

	self._srv_pub_path = srv_pub_path
	self._dev_pub_path = dev_pub_path
	self._dev_pri_path = dev_pri_path
	self._pname = pname
	self._pid = pid
end

function crypt:sm2_sign(sn)
	print(self._pid)
	print(self._pid..sn)
	return self._sm.sm2sign(self._dev_pri_path, self._pid, self._pid..sn)
end

function crypt:sm2_encrypt(data)
	return self._sm.sm2encrypt(self._srv_pub_path, data)
end

function crypt:sm2_decrypt(data)
	return self._sm.sm2decrypt(self._dev_pri_path, data)
end

function crypt:sm4_encrypt_with_cipher(data, key, iv)
	return self._sm.sm4_cbc_encrypt(key, data, iv)
end

function crypt:sm4_decrypt_with_cipher(data, key, iv)
	return self._sm.sm4_cbc_decrypt(key, data, iv)
end

return crypt
