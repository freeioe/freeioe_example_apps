var msg = JSON.parse(msgStr);
var isForOneDevice = true;
var deviceId = undefined;
var timestamp = msg.ts || msg.timestamp;
if (msg.eid === undefined && msg.deviceid === undefined) {
    isForOneDevice = false;
} else {
    if (msg.eid !== undefined) {
        deviceId = msg.eid;
    } else if (msg.deviceid !== undefined) {
        deviceId = msg.deviceid;
    }
}
if (msg.data !== undefined) {
    var data_list = msg.data
    var myArray = [];
    var i = 0;
    var dMsg = {};
    dMsg.msg = {};
    dMsg.msg.data = {}
    if (isForOneDevice) {
        dMsg.eid = deviceId;
    }

    for (i = 0; i <data_list.length; i++) {
        var new_devid = undefined;
        if ( isForOneDevice ) {
        } else {
            if (data_list[i].eid !== undefined) {
                new_devid = data_list[i].eid;
            } else if (data_list[i].deviceid !== undefined) {
                new_devid = data_list[i].deviceid;
            } else {
                continue;
            }
            if (dMsg.eid && new_devid !== dMsg.eid) {
                myArray.push(dMsg);
                dMsg = {};
                dMsg.msg = {};
                dMsg.msg.data = {};
                dMsg.eid = new_devid;
            } else {
                dMsg.eid = new_devid || deviceId;
            }
        }
        var new_timestamp = undefined;
        if (data_list[i].ts !== undefined) {
            new_timestamp = data_list[i].ts;
        } else {
            new_timestamp = timestamp;
        }
        if (dMsg.ts && dMsg.ts !== new_timestamp) {
            myArray.push(dMsg);
            dMsg = {};
            dMsg.msg = {};
            dMsg.msg.data = {};
            dMsg.eid = new_devid || deviceId;
            dMsg.ts = new_timestamp || timestamp;
        } else {
            dMsg.ts = new_timestamp || timestamp;
        }
        dMsg.topic = topicStr;
        dMsg.msg.data[data_list[i].key] = data_list[i].value;
    }
    myArray.push(dMsg);
    return myArray;
} else {
    return;
}