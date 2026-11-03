.pragma library

function typingDevices(devices) {
    const physical = devices.filter(function (device) {
        const name = String(device.name);
        return name === "keyd-virtual-keyboard" || !name.includes("virtual-keyboard");
    });
    const typing = physical.filter(function (device) {
        const name = String(device.name);
        return !name.endsWith("-system-control") && !name.endsWith("-consumer-control")
            && name !== "video-bus" && !name.startsWith("power-button")
            && !name.endsWith("-extra-buttons") && !name.endsWith("-wmi-hotkeys");
    });
    return typing.length ? typing : physical;
}

function selectDevice(devices, preferredName) {
    const typing = typingDevices(devices);
    return typing.find(function (device) { return device.name === preferredName; })
        || typing.find(function (device) { return device.main; }) || typing[0];
}
