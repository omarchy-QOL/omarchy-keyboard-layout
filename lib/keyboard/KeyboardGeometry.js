.pragma library

const rowWidthUnits = 15;
const functionRowHeightUnits = 0.75;

function keySpec(keyId, widthUnits) {
    return { keyId: keyId, widthUnits: widthUnits || 1 };
}

function keyRow(names) {
    return names.split(" ").map(function (keyId) { return keySpec(keyId); });
}

const functionRow = [keySpec("ESC", 1.5)].concat(
    keyRow("FK01 FK02 FK03 FK04 FK05 FK06 FK07 FK08 FK09 FK10 FK11 FK12")
        .map(function (key) { return keySpec(key.keyId, 1.125); }));
const numberKeys = keyRow("TLDE AE01 AE02 AE03 AE04 AE05 AE06 AE07 AE08 AE09 AE10 AE11 AE12");
const topLetterKeys = keyRow("AD01 AD02 AD03 AD04 AD05 AD06 AD07 AD08 AD09 AD10 AD11 AD12");
const homeLetterKeys = keyRow("AC01 AC02 AC03 AC04 AC05 AC06 AC07 AC08 AC09 AC10 AC11");
const bottomLetterKeys = keyRow("AB01 AB02 AB03 AB04 AB05 AB06 AB07 AB08 AB09 AB10");
const bottomRow = [keySpec("LCTL", 1.25), keySpec("LWIN", 1.25), keySpec("LALT", 1.25),
    keySpec("SPCE", 6), keySpec("RALT", 1.25), keySpec("RCTL"), keySpec("ARROWS", 3)];

const keyboardShapes = {
    ansi: [functionRow, numberKeys.concat([keySpec("BKSP", 2)]),
        [keySpec("TAB", 1.5)].concat(topLetterKeys, [keySpec("BKSL", 1.5)]),
        [keySpec("CAPS", 1.75)].concat(homeLetterKeys, [keySpec("RTRN", 2.25)]),
        [keySpec("LFSH", 2.25)].concat(bottomLetterKeys, [keySpec("RTSH", 2.75)]), bottomRow],
    iso: [functionRow, numberKeys.concat([keySpec("BKSP", 2)]),
        [keySpec("TAB", 1.5)].concat(topLetterKeys, [keySpec("RTRN", 1.5)]),
        [keySpec("CAPS", 1.75)].concat(homeLetterKeys, [keySpec("BKSL"), keySpec("RTRN", 1.25)]),
        [keySpec("LFSH", 1.25), keySpec("LSGT")].concat(bottomLetterKeys, [keySpec("RTSH", 2.75)]), bottomRow],
    abnt: [functionRow, numberKeys.concat([keySpec("BKSP", 2)]),
        [keySpec("TAB", 1.5)].concat(topLetterKeys, [keySpec("RTRN", 1.5)]),
        [keySpec("CAPS", 1.75)].concat(homeLetterKeys, [keySpec("BKSL"), keySpec("RTRN", 1.25)]),
        [keySpec("LFSH", 1.25), keySpec("LSGT")].concat(bottomLetterKeys,
            [keySpec("AB11"), keySpec("RTSH", 1.75)]), bottomRow],
    jis: [functionRow, numberKeys.concat([keySpec("AE13"), keySpec("BKSP")]),
        [keySpec("TAB", 1.5)].concat(topLetterKeys, [keySpec("RTRN", 1.5)]),
        [keySpec("CAPS", 1.75)].concat(homeLetterKeys, [keySpec("BKSL"), keySpec("RTRN", 1.25)]),
        [keySpec("LFSH", 2.25)].concat(bottomLetterKeys,
            [keySpec("AB11"), keySpec("RTSH", 1.75)]), bottomRow]
};

function shapeFor(setting, layout, model) {
    if (keyboardShapes[setting]) return setting;
    if (layout === "jp") return "jis";
    if (layout === "br") return "abnt";
    return layout === "us" || /(^|[^0-9])104/.test(String(model || "")) ? "ansi" : "iso";
}

function widthInUnits(row) {
    return row.reduce(function (width, key) { return width + key.widthUnits; }, 0);
}

function extendEnterKey(key, columnX, rowY, keyHeight) {
    const rightEdge = key.x + key.width;
    key.notchY = key.height;
    key.notchWidth = columnX - key.x;
    key.height = rowY + keyHeight - key.y;
    key.hitRectangles = [{ x: 0, y: 0, width: key.width, height: key.notchY },
        { x: key.notchWidth, y: 0, width: rightEdge - columnX, height: key.height }];
}

function arrowKeys(originX, originY, keyPitch, rowHeight, keyGap) {
    const halfHeight = (rowHeight - keyGap) / 2;
    function arrow(keyId, columnOffset, upperRow) {
        const width = keyPitch - keyGap;
        return { keyId: keyId, x: originX + columnOffset * keyPitch,
            y: upperRow ? originY : originY + halfHeight + keyGap,
            width: width, height: halfHeight, notchWidth: 0, notchY: 0,
            hitRectangles: [{ x: 0, y: 0, width: width, height: halfHeight }] };
    }
    return [arrow("LEFT", 0, false), arrow("UP", 1, true),
        arrow("DOWN", 1, false), arrow("RGHT", 2, false)];
}

function placeKeys(shapeName, keyPitch, keyGap) {
    const rows = keyboardShapes[shapeName] || keyboardShapes.iso;
    const keys = [];
    const keysByName = {};
    let rowY = 0;
    rows.forEach(function (row, rowIndex) {
        const keyHeight = (rowIndex === 0 ? functionRowHeightUnits : 1) * keyPitch - keyGap;
        let columnX = 0;
        row.forEach(function (spec) {
            const keyWidth = spec.widthUnits * keyPitch - keyGap;
            if (spec.keyId === "ARROWS") {
                arrowKeys(columnX, rowY, keyPitch, keyHeight, keyGap).forEach(function (key) { keys.push(key); });
            } else if (keysByName[spec.keyId]) {
                extendEnterKey(keysByName[spec.keyId], columnX, rowY, keyHeight);
            } else {
                const key = { keyId: spec.keyId, x: columnX, y: rowY, width: keyWidth,
                    height: keyHeight, notchWidth: 0, notchY: 0,
                    hitRectangles: [{ x: 0, y: 0, width: keyWidth, height: keyHeight }] };
                keysByName[spec.keyId] = key;
                keys.push(key);
            }
            columnX += spec.widthUnits * keyPitch;
        });
        rowY += keyHeight + keyGap;
    });
    return { keys: keys, width: rowWidthUnits * keyPitch - keyGap, height: rowY - keyGap };
}
