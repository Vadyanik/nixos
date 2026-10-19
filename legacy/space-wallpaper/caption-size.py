"""Measure the current caption using the wallpaper renderer's font and wrapping."""
import importlib.util
import json
import os
from pathlib import Path
import re

wrapper = Path('/run/current-system/sw/bin/wallpaper-next').read_text()
font = re.search(r"export SPACE_WALLPAPER_FONT='([^']+)'", wrapper).group(1)
source = re.search(r'(/nix/store/\S+/lib/space-wallpaper/wallpaper.py)', wrapper).group(1)
os.environ['SPACE_WALLPAPER_FONT'] = font
spec = importlib.util.spec_from_file_location('wallpaper', source)
w = importlib.util.module_from_spec(spec)
spec.loader.exec_module(w)
current = json.loads((w.STATE / 'shuffle.json').read_text())['current']
_, record = w.caption_record(w.CACHE / current)
c = w.SET['caption']
width, height = w.SET['desired_resolution']
font = w.ImageFont.truetype(str(w.FONT), c['title_size'])
credit_font = w.ImageFont.truetype(str(w.FONT), c['credit_size'])
draw = w.ImageDraw.Draw(w.Image.new('RGB', (1, 1)))
limit = int(width * c['max_width_fraction'])
title = '\n'.join(w.fit_lines(draw, record['title'], font, limit))
source_id, _ = w.caption_record(w.CACHE / current)
credit = w.ellipsize(draw, '  /  '.join(p for p in [record.get('credit'), source_id] if p), credit_font, limit)
t = draw.multiline_textbbox((0, 0), title, font=font, spacing=c['line_spacing'])
b = draw.textbbox((0, 0), credit, font=credit_font)
print(json.dumps({'width': max(t[2]-t[0], b[2]-b[0]), 'left': c['margin_x'], 'bottom': c['margin_bottom'] + b[3]-b[1] + c['title_credit_gap'] + t[3]-t[1], 'sourceWidth': width, 'title': record['title'], 'sourceId': source_id}))
