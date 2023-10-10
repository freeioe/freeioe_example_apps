local cjson = require 'cjson.safe'

local file_url = 'uploads/file/202310/10093621_s2cjmC.gz'
local file_md5 = '02f5ee6506a9f2f0f5e9b77e267d9ab9'

print(cjson.encode( {
	url = "http://iot.kooiot.cn/" .. file_url,
	md5 = file_md5
}))
