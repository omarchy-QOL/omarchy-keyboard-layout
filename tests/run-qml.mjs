import assert from 'node:assert/strict';
import { mkdtempSync, symlinkSync, copyFileSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { dirname, join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

const project = resolve(dirname(fileURLToPath(import.meta.url)), '..');
const shell = join(process.env.OMARCHY_PATH || '/usr/share/omarchy', 'shell');
const temporary = mkdtempSync(join(tmpdir(), 'keyboard-viewer-qml-'));
try {
    symlinkSync(join(project, 'ui'), join(temporary, 'ui'));
    symlinkSync(join(project, 'lib'), join(temporary, 'lib'));
    symlinkSync(join(shell, 'Ui'), join(temporary, 'Ui'));
    symlinkSync(join(shell, 'Commons'), join(temporary, 'Commons'));
    mkdirSync(join(temporary, 'tests/qml'), {recursive:true});
    copyFileSync(join(project, 'tests/qml/KeyboardViewerTests.qml'), join(temporary, 'tests/qml/KeyboardViewerTests.qml'));
    writeFileSync(join(temporary, 'shell.qml'), `import QtQuick
import Quickshell
import "tests/qml" as Tests
ShellRoot {
    Window {
        width:900
        height:700
        visible:true
        Tests.KeyboardViewerTests {}
    }
}
`);
    mkdirSync(join(temporary, 'bin'));
    writeFileSync(join(temporary, 'bin/hyprctl'), String.raw`#!/bin/sh
printf '%s\n' '{"str":"[[EMPTY]]","set":false}'
`, {mode:0o755});
    writeFileSync(join(temporary, 'bin/keymap-helper'), String.raw`#!/usr/bin/env node
const fs = require('node:fs');
const {spawnSync} = require('node:child_process');
const request = JSON.parse(fs.readFileSync(0,'utf8'));
const delay = request.options === 'test:slow' ? 200 : 0;
if (delay) request.options = '';
setTimeout(() => {
    const result = spawnSync(process.env.TEST_NATIVE_HELPER,['--describe-keymap'],{input:JSON.stringify(request),encoding:'utf8'});
    if (result.stdout) process.stdout.write(result.stdout);
    process.exitCode = result.status || 0;
}, delay);
`, {mode:0o755});
    writeFileSync(join(temporary, 'bin/wtype'), String.raw`#!/usr/bin/env node
const fs = require('node:fs');
const command = process.argv.slice(2);
const input = command[0] === '-' ? fs.readFileSync(0,'utf8') : '';
if (command.includes('TestFailure')) process.exit(1);
fs.appendFileSync(process.env.TEST_ACTION_LOG,JSON.stringify({command,input})+String.fromCharCode(10));
`, {mode:0o755});
    const environment = {...process.env, QT_QPA_PLATFORM:'offscreen', QT_ASSUME_STDERR_HAS_CONSOLE:'1',
        TEST_NATIVE_HELPER:join(project,'native/keyboard-layoutd'), TEST_HELPER:join(temporary,'bin/keymap-helper'),
        TEST_ACTION_LOG:join(temporary,'actions.jsonl'), PATH:join(temporary,'bin')+':'+process.env.PATH};
    delete environment.WAYLAND_DISPLAY;
    const result = spawnSync('quickshell',['-p',temporary],{env:environment,encoding:'utf8',timeout:20000});
    const output = (result.stdout || '') + (result.stderr || '');
    process.stdout.write(output);
    const report = output.match(/KEYBOARD_QML_RESULT (\{[^\n]+\})/);
    assert.equal(result.status,0,result.error || output);
    assert.ok(report,'QML tests did not finish');
    assert.equal(JSON.parse(report[1]).failed,0,output);
    assert.ok(!/TypeError|ReferenceError|Binding loop detected|Failed to load configuration/.test(output),output);
} finally {
    if (process.env.KEEP_QML_TEST) console.log("QML test directory:", temporary);
    else rmSync(temporary,{recursive:true,force:true});
}
