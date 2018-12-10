#!/usr/bin/env lua

----
-- Run this on openwrt with lua5.1
--

require "ubus"
require "uloop"

uloop.init()

local conn = ubus.connect()
if not conn then
	error("Failed to connect to ubusd")
end

local function print_table(v)
	if type(v) ~= 'table' then
		print(v)
	end
	for k, v in pairs(v) do
		if type(v) == 'table' then
			print("key="..k.." value is:")
			print_table(v)
		else
			print("key=" .. k .. " value=" .. tostring(v))
		end
	end
end

local function conn_call(method, param)
	local status, err = conn:call("focas", method, param)
	print("Result of method:", method)
	if not status then
		print("ERROR", err)
		return nil
	end
	print_table(status)
--[[
	for k, v in pairs(status) do
		print("key=" .. k .. " value=" .. tostring(v))
	end
]]--
	return status
end

local ret = conn_call("connect", { ip = "192.168.0.200", port = 8193, timeout=5 })
local handle = ret.handle

conn_call("actf", {handle=handle})
conn_call("acts", {handle=handle})
conn_call("acts2", {handle=handle, index=-1})
conn_call("acts2", {handle=handle, index=1})
conn_call("axis", {handle=handle, ['function']="absolute", index=-1})
conn_call("axis", {handle=handle, ['function']="absolute", index=1})
conn_call("axis", {handle=handle, ['function']="machine2", index=-1})
conn_call("axis", {handle=handle, ['function']="machine2", index=1})
conn_call("rdsvmeter", {handle=handle})
conn_call("rdspmeter", {handle=handle, type=-1})
conn_call("rdspdlname", {handle=handle})
conn_call("alarm", {handle=handle})
conn_call("alarm2", {handle=handle})
conn_call("rdalminfo", {handle=handle, type=-1})
conn_call("rdalmmsg", {handle=handle, type=1})
conn_call("rdalmmsg2", {handle=handle, type=0})
conn_call("rdalmmsg2", {handle=handle, type=1})
conn_call("getdtailerr", {handle=handle})
conn_call("rdprgnum", {handle=handle})
conn_call("rdexecprog", {handle=handle, length=1000})
conn_call("rdpmcrng", {handle=handle, addr_type=1,data_type=1,start=100,length=4})

conn_call("disconnect", { handle=handle })


conn:close()
