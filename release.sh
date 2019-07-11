RELEASE_SCRIPT=$1

RELEASE_APP (){
	$RELEASE_SCRIPT $1
}

# Release ioe
RELEASE_APP ioe
#RELEASE_APP bms
RELEASE_APP modbus_master
RELEASE_APP test_reboot 
#RELEASE_APP modbus_slave
RELEASE_APP frpc
RELEASE_APP opcua_server
RELEASE_APP opcua_client
RELEASE_APP opcua_collect_example
RELEASE_APP yizumi_un
RELEASE_APP symlink
RELEASE_APP network
# Cloud connectors
RELEASE_APP aliyun
RELEASE_APP baidu_cloud
RELEASE_APP huawei_cloud
RELEASE_APP telit_cloud
RELEASE_APP citic_cloud
# Others
RELEASE_APP dlt645
RELEASE_APP sim_tank
RELEASE_APP focas
RELEASE_APP showbox 
RELEASE_APP rtu 
RELEASE_APP sim
RELEASE_APP port_test
RELEASE_APP oliver_355_monitor
