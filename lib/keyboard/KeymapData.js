.pragma library

const outputLimit = 1048576;
const cacheLimit = 8;

function requestFor(device, keymapFile) {
    if (!device || (!device.layout && !keymapFile)) return null;
    return { rules: String(device.rules || "evdev"), model: String(device.model || "pc105"),
        layouts: String(device.layout || ""), variants: String(device.variant || ""),
        options: String(device.options || ""), keymapFile: String(keymapFile || ""),
        group: Number(device.active_layout_index || 0) };
}

function signature(request, revision) {
    return request ? JSON.stringify(request) + ":" + revision : "";
}

function isObject(value) {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function isText(value) {
    return typeof value === "string" && value.length <= 512;
}

function parseDescription(text) {
    if (!text || text.length > outputLimit) return null;
    let data;
    try { data = JSON.parse(text); } catch (error) { return null; }
    if (!isObject(data) || data.schemaVersion !== 1 || !isObject(data.keys) || Object.keys(data.keys).length === 0
        || Object.keys(data.keys).length > 100
        || !isObject(data.compose) || !isObject(data.accents) || !isText(data.altGrKey)
        || !isText(data.layoutName) || !isObject(data.modifiers)
        || !["shift", "capsLock", "altGr"].every(function (name) { return typeof data.modifiers[name] === "boolean"; })
        || !Number.isInteger(data.group) || data.group < 0)
        return null;
    for (const keyId of Object.keys(data.keys)) {
        const key = data.keys[keyId];
        if (!/^[A-Z0-9]{2,8}$/.test(keyId) || !isObject(key) || !Array.isArray(key.states)
            || key.states.length !== 8) return null;
        for (const state of key.states) {
            if (state !== null && (!isObject(state) || !isText(state.keysym)
                || !isText(state.label) || !isText(state.text) || !isText(state.dead))) return null;
        }
    }
    if (Object.keys(data.compose).length > 100 || Object.keys(data.accents).length > 512) return null;
    let pairCount = 0;
    for (const prefix of Object.keys(data.compose)) {
        const pairs = data.compose[prefix];
        if (!isText(prefix) || !isObject(pairs)) return null;
        pairCount += Object.keys(pairs).length;
        if (pairCount > 4096) return null;
        for (const suffix of Object.keys(pairs))
            if (!isText(suffix) || !isText(pairs[suffix])) return null;
    }
    for (const letter of Object.keys(data.accents)) {
        const choices = data.accents[letter];
        if (!isText(letter) || !Array.isArray(choices) || choices.length > 12
            || !choices.every(isText)) return null;
    }
    return data;
}

function remember(cache, key, value) {
    const next = {};
    const recent = Object.keys(cache).filter(function (entry) { return entry !== key; })
        .slice(-(cacheLimit - 1));
    recent.forEach(function (entry) { next[entry] = cache[entry]; });
    next[key] = value;
    return next;
}
