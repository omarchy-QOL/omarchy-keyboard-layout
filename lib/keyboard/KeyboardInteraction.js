.pragma library

const latched = 1;
const locked = 2;
const doubleClickInterval = 400;
const modifierNames = ["shift", "altGr", "control", "alt", "superKey"];
const commandModifiers = [
    ["control", "ctrl"], ["alt", "alt"], ["superKey", "logo"], ["altGr", "altgr"], ["shift", "shift"]
];
const modifierSymbols = {
    Shift_L: "shift", Shift_R: "shift", Control_L: "control", Control_R: "control",
    Alt_L: "alt", Alt_R: "alt", Super_L: "superKey", Super_R: "superKey",
    ISO_Level3_Shift: "altGr"
};
const specialLabels = {
    Escape: "Esc", BackSpace: "Back", Return: "Enter", Tab: "Tab", space: "Space",
    Caps_Lock: "Caps", Shift_L: "Shift", Shift_R: "Shift", Control_L: "Ctrl",
    Control_R: "Ctrl", Alt_L: "Alt", Alt_R: "Alt", Super_L: "Super", Super_R: "Super",
    ISO_Level3_Shift: "AltGr", Menu: "Menu", Left: "Left", Right: "Right", Up: "Up", Down: "Down",
    ISO_Left_Tab: "Backtab", Multi_key: "Compose", Shift_Lock: "Shift lock",
    ISO_Level3_Latch: "AltGr", ISO_Level3_Lock: "AltGr lock",
    ISO_Level5_Shift: "Level 5", ISO_Level5_Latch: "Level 5", ISO_Level5_Lock: "Level 5 lock",
    ISO_Next_Group: "Next group", ISO_Prev_Group: "Prev group",
    Zenkaku_Hankaku: "Zenkaku", Eisu_toggle: "Eisu", Hangul_Hanja: "Hanja"
};
const spacingAccents = {
    dead_acute: "´", dead_grave: "`", dead_circumflex: "^", dead_tilde: "~",
    dead_diaeresis: "¨", dead_cedilla: "¸", dead_caron: "ˇ", dead_breve: "˘",
    dead_abovering: "˚", dead_macron: "¯", dead_doubleacute: "˝", dead_ogonek: "˛", dead_abovedot: "˙"
};

function initialState(capsLock) {
    return { shift: 0, altGr: 0, control: 0, alt: 0, superKey: 0, capsLock: !!capsLock,
        pendingDeadKey: "", pendingDeadKeyId: "", lastModifier: "", lastModifierClick: 0 };
}

function stateIndex(state) {
    return (state.shift ? 1 : 0) | (state.capsLock ? 2 : 0) | (state.altGr ? 4 : 0);
}

function entryFor(keymap, keyId, state) {
    const key = keymap && keymap.keys ? keymap.keys[keyId] : null;
    const entry = key ? key.states[stateIndex(state)] || null : null;
    return entry && entry.keysym !== "VoidSymbol" && entry.keysym !== "NoSymbol" ? entry : null;
}

function baseEntry(keymap, keyId) {
    return entryFor(keymap, keyId, initialState(false));
}

function modifierFor(keymap, keyId) {
    const entry = baseEntry(keymap, keyId);
    return entry ? modifierSymbols[entry.keysym] || "" : "";
}

function hasShortcutModifiers(state) {
    return !!(state.control || state.alt || state.superKey);
}

function releaseOneShot(state) {
    const next = Object.assign({}, state);
    modifierNames.forEach(function (name) { if (next[name] === latched) next[name] = 0; });
    return next;
}

function clearDeadKey(state) {
    return Object.assign({}, state, { pendingDeadKey: "", pendingDeadKeyId: "" });
}

function toggleModifier(state, name, timestamp) {
    const next = Object.assign({}, state);
    if (!state[name]) {
        next[name] = latched;
        next.lastModifier = name;
        next.lastModifierClick = timestamp;
    } else if (state[name] === latched && state.lastModifier === name
        && timestamp - state.lastModifierClick < doubleClickInterval) {
        next[name] = locked;
    } else {
        next[name] = 0;
    }
    return next;
}

function textCommand(text) { return { command: ["wtype", "-"], input: text }; }

function keyCommand(state, keysym) {
    const modifiers = commandModifiers.filter(function (pair) { return !!state[pair[0]]; })
        .map(function (pair) { return pair[1]; });
    const command = ["wtype"];
    modifiers.forEach(function (name) { command.push("-M", name); });
    command.push("-k", keysym);
    modifiers.slice().reverse().forEach(function (name) { command.push("-m", name); });
    return { command: command };
}

function composedText(keymap, prefix, suffix) {
    const pairs = keymap && keymap.compose ? keymap.compose[prefix] : null;
    return pairs && pairs[suffix] ? pairs[suffix] : "";
}

function spacingAccent(keymap, prefix) {
    return composedText(keymap, prefix, "space") || spacingAccents[prefix] || "";
}

function pressKey(keymap, state, keyId, timestamp) {
    const base = baseEntry(keymap, keyId);
    if (!base) return { state: state, commands: [] };
    const modifier = modifierFor(keymap, keyId);
    if (modifier)
        return { state: toggleModifier(state, modifier, timestamp || 0), commands: [] };
    if (base.keysym === "Caps_Lock")
        return { state: Object.assign({}, state, { capsLock: !state.capsLock }), commands: [] };
    const commands = [];
    const next = releaseOneShot(clearDeadKey(state));
    if (state.pendingDeadKey && (base.keysym === "Escape" || base.keysym === "BackSpace"))
        return { state: clearDeadKey(state), commands: commands };
    if (hasShortcutModifiers(state)) {
        commands.push(keyCommand(state, base.keysym));
        return { state: next, commands: commands };
    }
    const current = entryFor(keymap, keyId, state);
    if (!current) return { state: state, commands: [] };
    if (current.dead) {
        if (state.pendingDeadKey) {
            const combined = composedText(keymap, state.pendingDeadKey, current.keysym);
            if (combined) return { state: next, commands: [textCommand(combined)] };
            const previous = spacingAccent(keymap, state.pendingDeadKey);
            if (previous) commands.push(textCommand(previous));
        }
        next.pendingDeadKey = current.dead;
        next.pendingDeadKeyId = keyId;
    } else if (state.pendingDeadKey) {
        const combined = composedText(keymap, state.pendingDeadKey, current.keysym);
        const accent = spacingAccent(keymap, state.pendingDeadKey);
        if (combined) commands.push(textCommand(combined));
        else if (current.text) commands.push(textCommand(accent + current.text));
        else {
            if (accent) commands.push(textCommand(accent));
            commands.push(keyCommand(state, current.keysym));
        }
    } else if (current.text) {
        commands.push(textCommand(current.text));
    } else {
        commands.push(keyCommand(state, current.keysym));
    }
    return { state: next, commands: commands };
}

function chooseAccent(state, text) {
    return { state: releaseOneShot(clearDeadKey(state)), commands: [textCommand(text)] };
}

function shownState(state) {
    return state.superKey ? Object.assign({}, state, { shift: 0, altGr: 0, capsLock: false }) : state;
}

function displayEntry(keymap, keyId, state) {
    const base = baseEntry(keymap, keyId);
    if (modifierFor(keymap, keyId) || (base && base.keysym === "Caps_Lock")) return base;
    return entryFor(keymap, keyId, shownState(state))
        || (hasShortcutModifiers(state) ? baseEntry(keymap, keyId) : null);
}

function labelFor(keymap, keyId, state) {
    const entry = displayEntry(keymap, keyId, state);
    if (!entry) return "";
    return specialLabels[entry.keysym] || entry.label
        || entry.dead.replace(/^dead_/, "").replace(/_/g, " ") || entry.keysym;
}

function alternateLabel(keymap, keyId, state) {
    if (state.shift || state.superKey) return "";
    const current = entryFor(keymap, keyId, state);
    const shifted = entryFor(keymap, keyId, Object.assign({}, state, { shift: latched }));
    // secondary legends show characters, not internal XKB action names
    if (shifted && !shifted.text && !shifted.dead) return "";
    if (!current || !shifted || !current.label || !shifted.label || current.label === shifted.label)
        return "";
    if (current.label.toUpperCase() === shifted.label.toUpperCase()
        && current.label.toLowerCase() !== current.label.toUpperCase()) return "";
    return shifted.label;
}

function accentChoices(keymap, keyId, state) {
    if (hasShortcutModifiers(state) || state.pendingDeadKey || !keymap || !keymap.accents) return [];
    const entry = entryFor(keymap, keyId, state);
    return entry ? keymap.accents[entry.text] || [] : [];
}

function latchFor(keymap, keyId, state) {
    const entry = baseEntry(keymap, keyId);
    if (entry && entry.keysym === "Caps_Lock") return state.capsLock ? locked : 0;
    const modifier = modifierFor(keymap, keyId);
    return modifier ? state[modifier] : 0;
}

function repeats(keymap, keyId) {
    const entry = baseEntry(keymap, keyId);
    return !!entry && ["BackSpace", "space", "Left", "Right", "Up", "Down"].includes(entry.keysym);
}
