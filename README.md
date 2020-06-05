FreeIOE 示例应用
=============================

# 什么是 FreeIOE

[FreeIOE](http://github.com/freeioe/freeioe)

# 应用分类


## Modbus 应用

### Modbus 数据采集

Modbus 数据采集应用 (Master 模式）, 从Modbus设备(Slave)读写寄存器

### Modbus 网关

Modbus TCP/RTU 网关

### Modbus 数据发布

Modbus 数据发布应用（Slave模式), 将FreeIOE网关设备数据通过Modbus协议进行发布，方便其他应用或设备通过Modbus协议获取数据


## OPCUA 应用

### OPCUA 服务器

应用创建OPCUA服务器，将设备数据发布到OPCUA服务器

### OPCUA 客户端

应用连接到其他OPCUA服务器程序/设备，将数据发布到OPCUA服务器

### OPCUA 数据采集应用

应用连接到OPCUA设备/软件(服务器)，从OPCUA设备/软件读取数据


## MQTT 应用

连接MQTT服务器，将网关中的设备数据上传至服务器

### Aliyun

### Baidu Yun

### Citic Cloud

### Inspur Cloud

### Telit Cloud

### Huawei Cloud


## CNC

### 发那科机床数据采集(Fanuc Focas协议)


## DLT645

通过DLT 645协议读取电表数据

## PLC

### AB

AB PLC 设备数据采集应用，依赖于libplctag通讯库

### ENIP

Ethernet IP/CIP 协议通讯方式获取 PLC数据 (如AB PLC, OMRON PLC)

### MELSEC

三菱MC协议，支持三菱PLC, 基恩士PLC

### OMRON

Hostlink协议（未完善，不可用)


