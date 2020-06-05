FreeIOE Example Applications
=============================

# What is FreeIOE

[FreeIOE](http://github.com/freeioe/freeioe)

# Application Categories


## Modbus Applications

### Modbus Data Collection Application

Modbus Master mode application, which can access modbus slave(device) registers

### Modbus Gateway

Modbus TCP/RTU gateway

### Modbus Data Provider Application

Modbus Slave mode application, which provide the data to other software via modbus protocol


## OPCUA Applications

### OPCUA Server

This application creates an opcua server, which offer all devices data from FreeIOE

### OPCUA Client

This application connect to an exists opcua server, then create device nodes and provide data from FreeIOE

### OPCUA Client data collection

This application connect to an device/software which is opcua server, reads the selected node's data value to FreeIOE


## MQTT Applications

Those application are MQTT client application

### Aliyun

### Baidu Yun

### Citic Cloud

### Inspur Cloud

### Telit Cloud

### Huawei Cloud


## CNC

### Fanuc Focas application


## DLT645

Reading Meter devices data via dlt645 protocol

## PLC

### AB

AB PLC device data collection

### ENIP

PLCs which supports Ethernet IP/CIP protocol.

### MELSEC

PLCs which support MITSUBISHI MELSEC protocol

### OMRON

Hostlink protocol (not implemented yet)