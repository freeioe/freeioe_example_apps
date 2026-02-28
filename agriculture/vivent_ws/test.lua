local vv_http = require 'vv_http'

local vvh = vv_http('192.168.88.128')

print(vvh.reboot())
