import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import vm from 'node:vm';

const source = readFileSync(new URL('../KeyboardLayout.qml', import.meta.url), 'utf8');
const functions = source.slice(
    source.indexOf('    function typingKeyboards('),
    source.indexOf('    function refresh('),
);
const settingsFunctions = source.slice(
    source.indexOf('    function storeSettings('),
    source.indexOf('    function setPulseColor('),
);
const labelBindings = Object.fromEntries(['maxLayoutLabelLength', 'layoutLabels', 'layouts', 'layoutLabel'].map(name => {
    const value = source.match(new RegExp(
        `^    readonly property \\w+ ${name}: ([\\s\\S]*?)(?=\\n    (?:readonly )?property |\\n\\n)`, 'm',
    ))[1];
    return [name, new vm.Script(value.startsWith('{') ? `(function() ${value})()` : `(${value})`)];
}));
const eventHandler = source.match(/        function onRawEvent\(event\) \{[\s\S]*?\n        \}/)[0];

const queryHandler = new vm.Script('(function() ' + source.match(
    /            onStreamFinished: (\{[\s\S]*?\n            \})/,
)[1] + ')()');

function widget(settings = {}) {
    const root = {
        settings,
        layoutKeys: [],
        layoutFull: '',
        setting: (name, fallback) => root.settings[name] ?? fallback,
        bar: { shell: { updateEntryInline: () => { calls.saves++; return true; } } },
        keyboardName: '',
        layoutConfig: '',
        activeLayoutIndex: -1,
        automaticRestoreLayout: -1,
        animationEnabled: true,
    };
    const calls = { pulses: 0, resets: 0, timerStops: 0, refreshes: 0, saves: 0 };
    const context = vm.createContext({
        root,
        pulseAnimation: { restart: () => calls.pulses++ },
        automaticRestoreTimer: { stop: () => calls.timerStops++ },
        resetPulse: () => calls.resets++,
    });
    vm.runInContext(settingsFunctions, context);
    vm.runInContext(functions, context);
    vm.runInContext(eventHandler, context);
    Object.assign(root, {
        storeSettings: context.storeSettings,
        layoutDisplayName: context.layoutDisplayName,
        typingKeyboards: context.typingKeyboards,
        selectKeyboard: context.selectKeyboard,
        updateKeyboards: context.updateKeyboards,
        refresh: () => calls.refreshes++,
    });
    for (const [name, binding] of Object.entries(labelBindings))
        Object.defineProperty(root, name, { get: () => binding.runInContext(context) });
    return {
        root,
        calls,
        update: (...keyboards) => context.updateKeyboards(keyboards),
        event: context.onRawEvent,
        labels: () => Array.from(root.layouts),
        rename: context.setLayoutDisplayName,
        query: raw => { context.text = raw; queryHandler.runInContext(context); },
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

test('aliases distinguish variants and retain automatic labels elsewhere', () => {
    const w = widget({ layoutLabels: { 'US(intl)': 'International' } });
    w.update(keyboard(1));
    assert.deepEqual(w.labels(), ['US', 'International']);
    assert.equal(w.root.layoutLabel, 'International');
    w.update(keyboard(0));
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 1);
});

test('renaming preserves other preferences and resetting restores the XKB name', () => {
    const w = widget({ pulseColor: '#a77bd8', animation: false, layoutLabels: { DE: 'German' } });
    w.update(keyboard());
    w.rename('US', '  English  ');
    assert.equal(w.root.layoutLabel, 'English');
    assert.equal(w.root.settings.layoutLabels.US, 'English');
    assert.equal(w.root.settings.layoutLabels.DE, 'German');
    assert.equal(w.root.settings.pulseColor, '#a77bd8');
    assert.equal(w.root.settings.animation, false);
    assert.equal(w.calls.pulses, 0);
    w.rename('US', 'English');
    assert.equal(w.calls.saves, 1);
    w.rename('US', '   ');
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(Object.hasOwn(w.root.settings.layoutLabels, 'US'), false);
    assert.equal(w.root.settings.layoutLabels.DE, 'German');
    assert.equal(w.calls.saves, 2);
});

test('aliases apply to duplicate keys without changing index-based pulses', () => {
    const w = widget();
    w.update(keyboard(0, { variant: '' }));
    w.rename('US', 'English');
    assert.deepEqual(w.labels(), ['English', 'English']);
    assert.equal(w.calls.pulses, 0);
    w.update(keyboard(1, { variant: '' }));
    assert.equal(w.root.layoutLabel, 'English');
    assert.equal(w.calls.pulses, 1);
});

test('keyboard refreshes retain the alias editor model until layouts change', () => {
    const w = widget();
    w.update(keyboard());
    const keys = w.root.layoutKeys;
    w.update(keyboard(1));
    assert.equal(w.root.layoutKeys, keys);
    w.rename('US(intl)', 'International');
    w.update(keyboard(1));
    assert.equal(w.root.layoutKeys, keys);
    assert.equal(w.root.layoutLabel, 'International');
    w.update(keyboard(0, { layout: 'de,us', variant: '' }));
    assert.notEqual(w.root.layoutKeys, keys);
    assert.deepEqual(Array.from(w.root.layoutKeys), ['DE', 'US']);
    const saves = w.calls.saves;
    w.rename('US(intl)', 'Stale edit');
    assert.equal(w.calls.saves, saves);
    assert.equal(w.root.settings.layoutLabels['US(intl)'], 'International');
});

test('settings updates change labels without a keyboard event or pulse', () => {
    const w = widget();
    w.update(keyboard());
    w.root.settings = { layoutLabels: { US: 'English' } };
    assert.equal(w.root.layoutLabel, 'English');
    w.root.settings = {};
    assert.equal(w.root.layoutLabel, 'US');
    assert.equal(w.calls.pulses, 0);
});

test('invalid alias settings keep automatic labels', () => {
    for (const layoutLabels of [null, 7, 'English', [], { US: 42, 'US(intl)': '  ' }]) {
        const w = widget({ layoutLabels });
        w.update(keyboard());
        assert.deepEqual(w.labels(), ['US', 'US(intl)']);
    }
});

test('saving an automatic label removes a redundant alias', () => {
    const w = widget({ layoutLabels: { US: 'English' } });
    w.update(keyboard());
    w.rename('US', 'US');
    assert.deepEqual(Object.keys(w.root.settings.layoutLabels), []);
    assert.equal(w.root.layoutLabel, 'US');
});

test('Unicode glyphs and punctuation survive label persistence unchanged', () => {
    const w = widget();
    w.update(keyboard());
    for (const name of ['日本語', 'العربية', 'Клавиатура', 'é e\u0301', '👩🏽‍💻 🇩🇪', '󰌌', '<b>US</b>', '<img src="https://example.invalid/test.png">', '$(`echo test`) \\ "quoted" &']) {
        w.rename('US', name);
        assert.equal(w.root.layoutLabel, name);
        const serialized = JSON.stringify(w.root.settings);
        assert.equal(JSON.parse(serialized).layoutLabels.US, name);
    }
});

test('oversized and non-printing labels cannot replace the saved label', () => {
    const w = widget();
    w.update(keyboard());
    w.rename('US', 'English');
    const saves = w.calls.saves;
    for (const name of ['x'.repeat(257), 'US\nDE', 'US\tDE', 'US\u0000', 'US\u001b', 'US\u0085', 'US\u2028DE', '\ud800', '\udc00', null, {}]) {
        w.rename('US', name);
        assert.equal(w.root.layoutLabel, 'English');
        assert.equal(w.calls.saves, saves);
        w.root.settings = {layoutLabels:{US:name}};
        assert.equal(w.root.layoutLabel, 'US');
        w.root.settings = {layoutLabels:{US:'English'}};
    }
    w.rename('US', 'x'.repeat(256));
    assert.equal(w.root.layoutLabel.length, 256);
    w.rename('US', '😀'.repeat(128));
    assert.equal(w.root.layoutLabel, '😀'.repeat(128));
});

test('invalid keyboard query hides the label and a later query recovers', () => {
    const w = widget({ layoutLabels: { US: 'English' } });
    w.update(keyboard());
    assert.equal(w.root.layoutLabel, 'English');
    w.query('{ invalid JSON');
    assert.equal(w.root.layoutLabel, '');
    w.query(JSON.stringify({keyboards:[keyboard()]}));
    assert.equal(w.root.layoutLabel, 'English');
    assert.equal(w.calls.pulses, 0);
});
