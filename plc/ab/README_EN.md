# AB PLC

## Supported Devices

This application builds on [libplctag](https://github.com/kyle-github/libplctag), you cloud remove more information about supported devices and registers, in libplctag's github introduction

## Template

### Meta Section

* name - Device name
* description - Device description
* series - Device series


### PROP Section

* name - Device property name
* desc - Property description
* unit - Property value unit
* RW - Property read-write attribute
* data_type - data value type in PLC. Supported: uint8/16/32/64 int8/16/32/64 float32/64
* vt - FreeIOE value type int/float/string
* elem_name - PLC Element Name
* offset - Element offset index
* rate - value rate that converts to true value
* path - the property path in device, default will be the path configured in application settings

