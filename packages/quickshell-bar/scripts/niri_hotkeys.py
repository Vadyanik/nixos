#!/usr/bin/env python3
"""Build the complete searchable hotkey index from the installed KDL source."""
import json
import re
import sys
from pathlib import Path

actions = {
    'close-window': 'Close window', 'quit': 'Exit Niri',
    'toggle-window-floating': 'Toggle floating window',
    'focus-column-left': 'Focus column to the left', 'focus-column-right': 'Focus column to the right',
    'focus-window-up': 'Focus window above in column', 'focus-window-down': 'Focus window below in column',
    'focus-workspace-up': 'Switch to workspace above', 'focus-workspace-down': 'Switch to workspace below',
    'move-column-left': 'Move column left', 'move-column-right': 'Move column right',
    'move-window-up': 'Move window up in column', 'move-window-down': 'Move window down in column',
    'move-window-to-workspace-up': 'Move window to workspace above and follow',
    'move-window-to-workspace-down': 'Move window to workspace below and follow',
    'fullscreen-window': 'Toggle fullscreen', 'toggle-overview': 'Workspace overview',
    'toggle-column-tabbed-display': 'Toggle column tabs',
    'switch-focus-between-floating-and-tiling': 'Switch focus between floating and tiled windows',
    'maximize-column': 'Maximize column',
    'expand-column-to-available-width': 'Expand column to available width',
    'center-column': 'Center column',
    'switch-preset-column-width': 'Next column width preset',
    'switch-preset-window-height': 'Next window height preset',
    'consume-or-expel-window-left': 'Move window into or out of the column on the left',
    'consume-or-expel-window-right': 'Move window into or out of the column on the right',
    'consume-window-into-column': 'Move next window into column',
    'expel-window-from-column': 'Move bottom window out of column',
    'focus-column-first': 'Focus first column', 'focus-column-last': 'Focus last column',
    'move-workspace-up': 'Move workspace up', 'move-workspace-down': 'Move workspace down',
    'show-hotkey-overlay': 'Niri shortcut overlay',
    'toggle-keyboard-shortcuts-inhibit': 'Toggle application shortcut capture',
    'power-off-monitors': 'Turn off monitors; any input wakes them',
    'screenshot-screen': 'Screenshot screen to clipboard', 'screenshot-window': 'Screenshot window to clipboard',
    'next-window': 'Next recent window', 'previous-window': 'Previous recent window',
}
spawn = {
    'ghostty': 'Ghostty', 'chromium': 'Chromium', 'dolphin': 'Dolphin',
    'desktop-force-close': 'Force close window', 'rofi-launcher': 'Rofi: apps / search / calculator',
    'stt-toggle': 'Dictation: complete text', 'desktop-poltertype': 'Toggle PolterType exclusion for current app',
    'desktop-mru': 'Previous keyboard layout; double press for third language',
    'desktop-focus': 'Codex: focus / launch', 'sh': 'Clipboard history',
}
def describe(body):
    action = body.split()[0].rstrip(';')
    quoted = re.findall(r'"([^"\\]*(?:\\.[^"\\]*)*)"', body)
    if action == 'spawn':
        command = quoted[0]
        if command == 'quickshell':
            return {'toggleControlCenter': 'Control Center', 'openNotifications': 'Notification Center',
                    'toggleHotkeys': 'Toggle shortcut guide', 'volumeUp': 'Volume +2%',
                    'volumeDown': 'Volume −2%'}.get(quoted[-1], quoted[-1])
        if command == 'desktop-screenshot':
            return 'Screenshot region → editor' if quoted[-1] == 'edit' else 'Screenshot region → clipboard'
        if command == 'desktop-scratchpad':
            return 'Move window to Magic' if quoted[-1] == 'move' else 'Magic: open / return'
        if command == 'wpctl':
            mic = '@DEFAULT_AUDIO_SOURCE@' in body
            if 'set-mute' in body: return 'Toggle microphone mute' if mic else 'Toggle audio mute'
            return 'Volume +5%' if '5%+' in body else 'Volume −5%'
        if command == 'brightnessctl': return 'Brightness +5%' if '5%+' in body else 'Brightness −5%'
        if command == 'playerctl': return {'next': 'Next track', 'previous': 'Previous track', 'play-pause': 'Play / pause'}[quoted[-1]]
        return spawn.get(command, ' '.join(quoted))
    if action == 'focus-workspace': return 'Switch to workspace ' + quoted[0]
    if action == 'move-window-to-workspace': return 'Move window to workspace ' + quoted[0] + ' and follow'
    if action == 'switch-layout': return {'0': 'English keyboard layout', '2': 'Russian keyboard layout'}.get(quoted[0], 'Keyboard layout ' + quoted[0])
    if action in ('set-column-width', 'set-window-height'):
        return ('Column width ' if action == 'set-column-width' else 'Window height ') + quoted[0]
    for prefix, label in [('focus-monitor-', 'Focus monitor '), ('move-window-to-monitor-', 'Move window to monitor ')]:
        if action.startswith(prefix): return label + {'left': 'on the left', 'right': 'on the right', 'up': 'above', 'down': 'below'}[action.removeprefix(prefix)]
    if action in ('next-window', 'previous-window') and 'filter=' in body:
        return ('Next' if action == 'next-window' else 'Previous') + ' window of the same app'
    return actions.get(action, body.strip(' ;'))

rows = []
for line in Path(sys.argv[1]).read_text().splitlines():
    match = re.match(r'^\s*([\w+]+)\s+[^{}]*\{\s*(.*?)\s*\}\s*$', line)
    if not match: continue
    key, body = match.groups()
    if '+' not in key and not key.startswith(('Print', 'XF86')): continue
    readable = key.replace('Mod+', 'Super+').replace('Page_Up', 'PgUp').replace('Page_Down', 'PgDn')
    readable = {'XF86AudioRaiseVolume': 'Volume +', 'XF86AudioLowerVolume': 'Volume −',
                'XF86AudioMute': 'Mute', 'XF86AudioMicMute': 'Mic mute',
                'XF86MonBrightnessUp': 'Brightness +', 'XF86MonBrightnessDown': 'Brightness −',
                'XF86AudioNext': 'Media next', 'XF86AudioPrev': 'Media previous',
                'XF86AudioPlay': 'Media play', 'XF86AudioPause': 'Media pause'}.get(readable, readable)
    for name, symbol in [('BracketLeft','['),('BracketRight',']'),('Comma',','),('Period','.'),('Minus','−'),('Equal','='),('Slash','/'),('grave','`'),('Left','←'),('Right','→'),('Up','↑'),('Down','↓')]:
        readable = readable.replace(name, symbol)
    rows.append({'shortcut': readable, 'description': describe(body)})
rows += [
    {'shortcut': 'Super+Left mouse · drag', 'description': 'Move window with mouse'},
    {'shortcut': 'Super+Right mouse · drag', 'description': 'Resize window with mouse'},
    {'shortcut': 'Caps Lock ↔ Esc', 'description': 'Keys are swapped'},
]
print(json.dumps(rows, ensure_ascii=False, indent=2))
