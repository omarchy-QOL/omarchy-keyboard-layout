import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../KeyboardLayout.qml', import.meta.url), 'utf8');
const functions = source.slice(
    source.indexOf('    function typingKeyboards('),
    source.indexOf('    function refresh('),
);
const eventHandler = source.match(/        function onRawEvent\(event\) \{[\s\S]*?\n        \}/)[0];

function widget() {
    const root = {
        keyboardName: '',
        layoutConfig: '',
        activeLayoutIndex: -1,
        automaticRestoreLayout: -1,
        animationEnabled: true,
    };
    const calls = { pulses: 0, resets: 0, timerStops: 0, refreshes: 0 };
    const context = vm.createContext({
        root,
        pulseAnimation: { restart: () => calls.pulses++ },
        automaticRestoreTimer: { stop: () => calls.timerStops++ },
        resetPulse: () => calls.resets++,
    });
    vm.runInContext(functions, context);
    vm.runInContext(eventHandler, context);
    Object.assign(root, {
        typingKeyboards: context.typingKeyboards,
        selectKeyboard: context.selectKeyboard,
        refresh: () => calls.refreshes++,
    });
    return {
        root,
        calls,
        update: (...keyboards) => context.updateKeyboards(keyboards),
        event: context.onRawEvent,
        labels: () => Array.from(root.layouts),
    };
}

function keyboard(index = 0, overrides = {}) {
    return {
        name: 'physical-keyboard',
        layout: 'us,us',
        variant: ',intl',
        active_layout_index: index,
        active_keymap: index === 0 ? 'English (US)' : 'English (US, intl., with dead keys)',
        ...overrides,
    };
}

test('bar and picker distinguish variants and pulse once per switch', () => {
    const w = widget();
    w.update(keyboard());
    assert.deepEqual(w.labels(), ['US', 'US(intl)']);
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 0);
    w.update(keyboard(1));
    assert.equal(w.root.layoutLabel, 'US(intl)');
    assert.equal(w.calls.pulses, 1);
    w.update(keyboard(1));
    assert.equal(w.calls.pulses, 1);
    w.update(keyboard(0));
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 2);
});

test('empty variants retain their positions and whitespace is trimmed', () => {
    const w = widget();
    w.update(keyboard(2, { layout: ' us, de, us ', variant: ', , dvorak ' }));
    assert.deepEqual(w.labels(), ['US', 'DE', 'US(dvorak)']);
    assert.equal(w.root.layoutLabel, 'US(dvorak)');
    w.update(keyboard(1, { layout: 'us,de', variant: undefined }));
    assert.deepEqual(w.labels(), ['US', 'DE']);
});

test('identical labels still pulse when the active index changes', () => {
    const w = widget();
    w.update(keyboard(0, { variant: '' }));
    w.update(keyboard(1, { variant: '' }));
    assert.deepEqual(w.labels(), ['US', 'US']);
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 1);
});

test('animation preference and automatic restores suppress pulses', () => {
    const w = widget();
    w.update(keyboard());
    w.root.animationEnabled = false;
    w.update(keyboard(1));
    assert.equal(w.root.layoutLabel, 'US(intl)');
    assert.equal(w.calls.pulses, 0);
    w.root.animationEnabled = true;
    w.root.automaticRestoreLayout = 0;
    w.update(keyboard(0));
    assert.equal(w.calls.pulses, 0);
    assert.equal(w.root.automaticRestoreLayout, -1);
    assert.equal(w.calls.timerStops, 2);
    w.update(keyboard(1));
    assert.equal(w.calls.pulses, 1);
});

test('an unchanged automatic restore is consumed before a manual switch', () => {
    const w = widget();
    w.update(keyboard());
    w.root.automaticRestoreLayout = 0;
    w.update(keyboard());
    assert.equal(w.root.automaticRestoreLayout, -1);
    w.update(keyboard(1));
    w.update(keyboard());
    assert.equal(w.calls.pulses, 2);
});

test('configuration changes establish a baseline without pulsing', () => {
    const w = widget();
    w.update(keyboard());
    w.update(keyboard(0, { variant: ',dvorak' }));
    assert.deepEqual(w.labels(), ['US', 'US(dvorak)']);
    assert.equal(w.calls.pulses, 0);
    w.update(keyboard(1, { variant: ',dvorak' }));
    assert.equal(w.calls.pulses, 1);
});

test('labels and variants belong to the selected physical keyboard', () => {
    const w = widget();
    w.update(
        keyboard(0, { name: 'hl-virtual-keyboard-fcitx5', main: true, layout: 'de' }),
        keyboard(1),
    );
    assert.equal(w.root.keyboardName, 'physical-keyboard');
    assert.equal(w.root.layoutLabel, 'US(intl)');
});

test('custom keymaps without layout metadata use the reported name', () => {
    const w = widget();
    w.update(keyboard(0, { layout: '', variant: '', active_keymap: 'Custom map' }));
    assert.equal(w.root.layoutLabel, 'Custom map');
    assert.equal(w.root.multipleLayouts, false);
});

for (const name of ['ideapad-extra-buttons', 'asus-wmi-hotkeys', 'dell-wmi-hotkeys']) {
    test(`laptop switches follow the typing keyboard instead of ${name}`, () => {
        const w = widget();
        const laptop = index => keyboard(index, {
            name: 'at-translated-set-2-keyboard',
            layout: 'us,br',
            variant: 'intl,',
            active_keymap: index === 0 ? 'English (US, intl., with dead keys)' : 'Portuguese (Brazil)',
        });
        const frozen = { ...laptop(1), name };
        const fcitx = { ...laptop(1), name: 'hl-virtual-keyboard-fcitx5', main: true };
        w.update(frozen, fcitx, laptop(0));
        assert.equal(w.root.keyboardName, laptop(0).name);
        assert.equal(w.root.layoutLabel, 'US(intl)');
        assert.deepEqual(Array.from(w.root.keyboardNames), [laptop(0).name]);
        for (const index of [1, 0]) {
            const device = laptop(index);
            w.event({ name: 'activelayout', data: `${device.name},${device.active_keymap}` });
            w.update(frozen, fcitx, device);
            assert.equal(w.root.keyboardName, device.name);
            assert.equal(w.root.layoutLabel, index === 0 ? 'US(intl)' : 'BR');
        }
        assert.equal(w.calls.pulses, 2);
        assert.equal(w.calls.refreshes, 2);
    });
}

test('the first layout switch on an attached keyboard updates the label and pulses', () => {
    const w = widget();
    const primary = keyboard(0, { main: true });
    const second = keyboard(1, { name: 'at-translated-set-2-keyboard' });
    w.update(primary);
    w.update(primary, { ...second, active_layout_index: 0, active_keymap: 'English (US)' });
    assert.equal(w.root.keyboardName, primary.name);
    assert.equal(w.calls.pulses, 0);
    w.event({ name: 'activelayout', data: `${second.name},${second.active_keymap}` });
    w.update(primary, second);
    assert.equal(w.root.keyboardName, second.name);
    assert.equal(w.root.layoutLabel, 'US(intl)');
    assert.equal(w.calls.pulses, 1);
    w.event({ name: 'activelayout', data: 'hl-virtual-keyboard-fcitx5,English (US)' });
    assert.equal(w.root.keyboardName, second.name);
    w.event({ name: 'activelayout', data: `${second.name},English (US)` });
    w.update(primary, { ...second, active_layout_index: 0, active_keymap: 'English (US)' });
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 2);
});

test('changing keyboards without changing the layout index does not pulse', () => {
    const w = widget();
    const primary = keyboard(0, { main: true });
    const second = keyboard(0, { name: 'external-keyboard' });
    w.update(primary, second);
    w.event({ name: 'activelayout', data: `${second.name},${second.active_keymap}` });
    w.update(primary, second);
    assert.equal(w.root.keyboardName, second.name);
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 0);
});
