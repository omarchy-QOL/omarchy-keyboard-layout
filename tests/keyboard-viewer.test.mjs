import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

function library(name, exports) {
    const source = readFileSync(new URL('../lib/keyboard/' + name, import.meta.url), 'utf8');
    return vm.runInNewContext(source.replace('.pragma library', '') + '; ({' + exports.join(',') + '})');
}
const Geometry = library('KeyboardGeometry.js', ['keyboardShapes', 'rowWidthUnits', 'widthInUnits', 'shapeFor', 'placeKeys']);
const Interaction = library('KeyboardInteraction.js', ['initialState', 'pressKey', 'chooseAccent', 'labelFor',
    'modifierFor', 'accentChoices', 'repeats', 'alternateLabel', 'latchFor']);
const Data = library('KeymapData.js', ['requestFor', 'signature', 'parseDescription', 'remember', 'cacheLimit']);
const keymap = JSON.parse(readFileSync(new URL('fixtures/viewer-us-intl.json', import.meta.url), 'utf8'));
const json = value => JSON.parse(JSON.stringify(value));
function press(state, keyId, timestamp = 100) {
    return Interaction.pressKey(keymap, state, keyId, timestamp);
}

test('all keyboard shapes have aligned rows and non-overlapping key identities', () => {
    for (const [name, rows] of Object.entries(Geometry.keyboardShapes)) {
        for (const row of rows) assert.equal(Geometry.widthInUnits(row), Geometry.rowWidthUnits, name);
        const geometry = Geometry.placeKeys(name, 40, 3);
        assert.equal(geometry.width, 597);
        assert.equal(new Set(geometry.keys.map(key => key.keyId)).size, geometry.keys.length);
        const enter = geometry.keys.find(key => key.keyId === 'RTRN');
        assert.equal(enter.notchWidth > 0, name !== 'ansi');
        for (const key of geometry.keys) {
            assert.ok(key.width > 0 && key.height > 0 && key.x >= 0 && key.y >= 0);
            assert.ok(key.x + key.width <= geometry.width + 0.001);
            assert.ok(key.y + key.height <= geometry.height + 0.001);
            for (const rectangle of key.hitRectangles) {
                assert.ok(rectangle.x + rectangle.width <= key.width + 0.001);
                assert.ok(rectangle.y + rectangle.height <= key.height + 0.001);
            }
        }
    }
    assert.equal(Geometry.shapeFor('auto', 'jp', 'pc105'), 'jis');
    assert.equal(Geometry.shapeFor('auto', 'br', 'pc105'), 'abnt');
    assert.equal(Geometry.shapeFor('auto', 'us', 'pc105'), 'ansi');
    assert.equal(Geometry.shapeFor('auto', 'de', 'pc105'), 'iso');
    assert.equal(Geometry.shapeFor('ansi', 'de', 'pc105'), 'ansi');
});

test('printable input is passed privately over stdin', () => {
    const action = press(Interaction.initialState(false), 'AD03');
    assert.deepEqual(json(action.commands), [{command:['wtype','-'],input:'e'}]);
    assert.equal(action.commands[0].command.includes('e'), false);
});

test('one-shot and double-click locked Shift have separate lifetimes', () => {
    let state = press(Interaction.initialState(false), 'LFSH', 100).state;
    assert.equal(state.shift, 1);
    const once = press(state, 'AD03');
    assert.equal(once.commands[0].input, 'E');
    assert.equal(once.state.shift, 0);
    state = press(state, 'LFSH', 200).state;
    assert.equal(state.shift, 2);
    const repeated = press(state, 'AD03');
    assert.equal(repeated.commands[0].input, 'E');
    assert.equal(repeated.state.shift, 2);
    assert.equal(press(state, 'LFSH', 250).state.shift, 0);
});

test('right Control and remapped modifier keys use resolved symbols', () => {
    const control = press(Interaction.initialState(false), 'RCTL').state;
    const action = press(control, 'AB03');
    assert.deepEqual(json(action.commands), [{command:['wtype','-M','ctrl','-k','c','-m','ctrl']}]);
    assert.equal(action.state.control, 0);
    const remapped = JSON.parse(readFileSync(new URL('fixtures/viewer-caps-altgr.json', import.meta.url), 'utf8'));
    assert.equal(Interaction.modifierFor(remapped, 'CAPS'), 'altGr');
    assert.equal(Interaction.labelFor(remapped, 'CAPS', Interaction.initialState(false)), 'AltGr');
    const escaped = JSON.parse(readFileSync(new URL('fixtures/viewer-caps-escape.json', import.meta.url), 'utf8'));
    const escape = Interaction.pressKey(escaped, Interaction.initialState(false), 'CAPS', 100);
    assert.deepEqual(json(escape.commands), [{command:['wtype','-k','Escape']}]);
    assert.equal(escape.state.capsLock, false);
});

test('dead keys compose, cancel, and preserve locked modifiers', () => {
    let action = press(Interaction.initialState(false), 'AC11');
    assert.equal(action.state.pendingDeadKey, 'dead_acute');
    assert.equal(action.commands.length, 0);
    const composed = press(action.state, 'AD03');
    assert.equal(composed.commands[0].input, 'é');
    assert.equal(composed.state.pendingDeadKey, '');
    assert.equal(press(action.state, 'BKSP').commands.length, 0);
    assert.equal(press(action.state, 'ESC').state.pendingDeadKey, '');
    const space = press(action.state, 'SPCE');
    assert.equal(space.commands[0].input, keymap.compose.dead_acute.space);
    const choices = Interaction.accentChoices(keymap, 'AD03', Interaction.initialState(false));
    assert.deepEqual(Array.from(choices).slice(0, 4), ['è','é','ê','ë']);
    const chosen = Interaction.chooseAccent(Interaction.initialState(false), '😀');
    assert.deepEqual(json(chosen.commands), [{command:['wtype','-'],input:'😀'}]);
});

test('missing keys never produce commands and repeat follows the mapped key', () => {
    assert.equal(press(Interaction.initialState(false), 'MISSING').commands.length, 0);
    assert.equal(Interaction.repeats(keymap, 'BKSP'), true);
    assert.equal(Interaction.repeats(keymap, 'AD03'), false);
    const escaped = JSON.parse(readFileSync(new URL('fixtures/viewer-caps-escape.json', import.meta.url), 'utf8'));
    assert.equal(Interaction.labelFor(escaped, 'CAPS', Interaction.initialState(false)), 'Esc');
});

test('secondary legends omit XKB actions while retaining printable symbols and accents', () => {
    const german = json(keymap);
    german.keys.TAB.states[1] = {keysym:'ISO_Left_Tab',label:'ISO_Left_Tab',text:'',dead:''};
    german.keys.LFSH.states[1] = {keysym:'ISO_Prev_Group',label:'ISO_Prev_Group',text:'',dead:''};
    const state = Interaction.initialState(false);
    assert.equal(Interaction.alternateLabel(german, 'TAB', state), '');
    assert.equal(Interaction.alternateLabel(german, 'LFSH', state), '');
    assert.equal(Interaction.labelFor(german, 'TAB', {...state,shift:1}), 'Backtab');
    assert.equal(Interaction.alternateLabel(german, 'AE01', state), '!');
    assert.equal(Interaction.alternateLabel(german, 'AC11', state), '¨');
});

test('unassigned XKB symbols have no legend or typing action', () => {
    const custom = json(keymap);
    custom.keys.AD01.states[0] = {keysym:'VoidSymbol',label:'VoidSymbol',text:'',dead:''};
    const state = Interaction.initialState(false);
    assert.equal(Interaction.labelFor(custom, 'AD01', state), '');
    assert.equal(Interaction.pressKey(custom, state, 'AD01', 100).commands.length, 0);
});

test('modifier legends keep their toggle identity when a shifted group action is absent', () => {
    const grouped = json(keymap);
    grouped.keys.RTSH.states[1] = {keysym:'VoidSymbol',label:'VoidSymbol',text:'',dead:''};
    grouped.keys.RALT.states[1] = {keysym:'ISO_Next_Group',label:'ISO_Next_Group',text:'',dead:''};
    const state = {...Interaction.initialState(false),shift:1};
    assert.equal(Interaction.labelFor(grouped, 'RTSH', state), 'Shift');
    assert.equal(Interaction.labelFor(grouped, 'RALT', state), 'AltGr');
});

test('wide ligatures retain their original text for typing', () => {
    const custom = json(keymap);
    custom.keys.AD01.states[0] = {keysym:'UFDFD',label:'﷽',text:'﷽',dead:''};
    const result = Interaction.pressKey(custom, Interaction.initialState(false), 'AD01', 100);
    assert.equal(result.commands[0].input, '﷽');
});

test('keymap requests preserve empty variants, active groups and all compiler inputs', () => {
    const device = {rules:'evdev',model:'pc105',layout:'us,us',variant:',intl',options:'caps:escape',active_layout_index:1};
    const request = Data.requestFor(device, '/tmp/custom map.xkb');
    assert.deepEqual(json(request), {rules:'evdev',model:'pc105',layouts:'us,us',variants:',intl',
        options:'caps:escape',keymapFile:'/tmp/custom map.xkb',group:1});
    assert.notEqual(Data.signature(request, 0), Data.signature({...request,group:0}, 0));
    assert.notEqual(Data.signature(request, 0), Data.signature(request, 1));
    assert.equal(Data.requestFor(null, ''), null);
    assert.equal(Data.requestFor({layout:'',active_layout_index:1}, '/tmp/map.xkb').group, 1);
});

test('keymap response validation bounds structured data and cache growth', () => {
    assert.ok(Data.parseDescription(JSON.stringify(keymap)));
    assert.equal(Data.parseDescription('x'.repeat(1048577)), null);
    for (const invalid of [null, [], {...keymap,group:-1}, {...keymap,keys:[]},
        {...keymap,modifiers:{}}, {...keymap,keys:{AD01:{states:[]}}}, {...keymap,schemaVersion:2}]) {
        assert.equal(Data.parseDescription(JSON.stringify(invalid)), null);
    }
    let cache = {};
    for (let index=0;index<20;index++) cache=Data.remember(cache,'key'+index,index);
    assert.equal(Object.keys(cache).length, Data.cacheLimit);
    assert.equal(cache.key19,19);
    assert.equal(cache.key0,undefined);
});

test('shortcuts use the base key even when its modified symbol is absent', () => {
    const custom = json(keymap);
    custom.keys.AB03.states[1] = null;
    const state = {...Interaction.initialState(false), control:1, shift:1};
    const action = Interaction.pressKey(custom,state,'AB03',100);
    assert.deepEqual(json(action.commands), [{command:['wtype','-M','ctrl','-M','shift','-k','c','-m','shift','-m','ctrl']}]);
    assert.equal(Interaction.labelFor(custom,'AB03',state), 'c');
});
