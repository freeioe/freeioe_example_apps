RELEASE_SCRIPT=$1
RELEASE_SUB=$2

RELEASE_APP (){
	$RELEASE_SCRIPT $RELEASE_SUB $1
}

# Release ioe
RELEASE_APP ioe

# modbus
RELEASE_APP modbus/master
RELEASE_APP modbus/slave
RELEASE_APP modbus/slave_one_unit
RELEASE_APP modbus/gateway
RELEASE_APP modbus/smc

# Hardware test
RELEASE_APP hw_test/reboot 
RELEASE_APP hw_test/serial_socket

RELEASE_APP tools/frpc
RELEASE_APP tools/freetun
RELEASE_APP tools/network_uci
RELEASE_APP tools/dns_hosts
RELEASE_APP tools/local_proxy
RELEASE_APP tools/cloud_switch
RELEASE_APP tools/ping_check
RELEASE_APP tools/system

# OPCUA apps
RELEASE_APP opcua/server_pub
RELEASE_APP opcua/client_pub
RELEASE_APP opcua/client_simple
RELEASE_APP opcua/client_tpl
RELEASE_APP opcua/yizumi
RELEASE_APP opcua/symlink

# MQTT Cloud connectors
RELEASE_APP mqtt/thingsroot
RELEASE_APP mqtt/mqtt_local
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
RELEASE_APP other/dtu_m
RELEASE_APP other/oliver_355_monitor
RELEASE_APP other/logger
RELEASE_APP other/hj212_sender

RELEASE_APP sim/sim
RELEASE_APP sim/sim_tpl
RELEASE_APP sim/tank
RELEASE_APP sim/mp1_cems
RELEASE_APP sim/ruiao_cems
RELEASE_APP sim/event
