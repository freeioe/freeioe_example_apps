RELEASE_SCRIPT=$1

RELEASE_APP (){
	$RELEASE_SCRIPT $1
}

# Release ioe
RELEASE_APP ioe

# modbus
RELEASE_APP modbus/master
RELEASE_APP modbus/slave
RELEASE_APP modbus/gateway
RELEASE_APP modbus/smc

# Hardware test
RELEASE_APP hw_test/reboot 
RELEASE_APP hw_test/serial_socket

# HJ212
RELEASE_APP HJ/hj212
RELEASE_APP HJ/hj212_screen
RELEASE_APP HJ/hj212_server
RELEASE_APP HJ/ai_ex
RELEASE_APP HJ/ruiao
RELEASE_APP HJ/hebei
RELEASE_APP HJ/jbsd
RELEASE_APP HJ/chsdl
RELEASE_APP HJ/treeland
RELEASE_APP HJ/face_gate

RELEASE_APP tools/frpc
RELEASE_APP tools/network_uci
RELEASE_APP tools/dns_hosts
RELEASE_APP tools/local_proxy

# OPCUA apps
RELEASE_APP opcua/server_pub
RELEASE_APP opcua/client_pub
RELEASE_APP opcua/client_simple
RELEASE_APP opcua/client_tpl
RELEASE_APP opcua/yizumi
RELEASE_APP opcua/symlink

# MQTT Cloud connectors
RELEASE_APP mqtt/thingsroot
RELEASE_APP mqtt/aliyun
RELEASE_APP mqtt/baidu
RELEASE_APP mqtt/huawei
RELEASE_APP mqtt/telit
RELEASE_APP mqtt/citic
RELEASE_APP mqtt/inspur

# PLC
RELEASE_APP plc/ab
RELEASE_APP plc/enip
RELEASE_APP plc/melsec

# CNC
RELEASE_APP cnc/focas

# Edge Computing
RELEASE_APP computing/showbox 
RELEASE_APP computing/oee 
RELEASE_APP computing/oee_pp

# TSDB
RELEASE_APP tsdb/bench

# Others
RELEASE_APP dlt645
RELEASE_APP other/dtu 
RELEASE_APP other/oliver_355_monitor
RELEASE_APP other/logger

RELEASE_APP sim/sim
RELEASE_APP sim/sim_tpl
RELEASE_APP sim/tank
RELEASE_APP sim/mp1_cems
RELEASE_APP sim/ruiao_cems
RELEASE_APP sim/event
