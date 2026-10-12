#!/usr/bin/env python3
"""Use the launcher's wallpaper theme for other existing Rofi menus."""
import os
import sys
from pathlib import Path
from launcher import dynamic_theme

config_dir = os.environ.get('ROFI_CONFIG_DIR', str(Path(__file__).resolve().parent.parent))
os.execvp('rofi', ['rofi', '-config', str(Path(config_dir) / 'config.rasi'), '-theme-str', dynamic_theme(), *sys.argv[1:]])
