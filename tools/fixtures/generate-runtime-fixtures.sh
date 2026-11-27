#!/usr/bin/env bash
# Regenerates the original (synthetic) runtime test fixtures in tests/fixtures/runtime.
# Requires ffmpeg and python3 with Pillow. Output is deterministic apart from encoder build differences.
set -euo pipefail
OUT="$(cd "$(dirname "$0")/../.." && pwd)/tests/fixtures/runtime"
mkdir -p "$OUT"

# 6 s 1280x720 30 fps H.264 test pattern with a quiet 440 Hz tone (for playback, pause and volume tests).
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc2=size=1280x720:rate=30:duration=6" \
  -f lavfi -i "sine=frequency=440:sample_rate=48000:duration=6" \
  -filter:a "volume=0.15" \
  -c:v libx264 -preset veryfast -profile:v high -pix_fmt yuv420p -crf 30 -g 30 \
  -c:a aac -b:a 64k -movflags +faststart -map_metadata -1 -fflags +bitexact -flags:v +bitexact -flags:a +bitexact \
  "$OUT/vibeloop-test-video.mp4"

# 3 s animated GIF (GIF player path).
ffmpeg -hide_banner -loglevel error -y \
  -f lavfi -i "testsrc=size=480x270:rate=12:duration=3" \
  -vf "split[a][b];[a]palettegen=max_colors=64[p];[b][p]paletteuse" \
  "$OUT/vibeloop-test-animation.gif"

# Static picture (picture player path).
ffmpeg -hide_banner -loglevel error -y -f lavfi -i "smptehdbars=size=1920x1080" -frames:v 1 -q:v 3 \
  "$OUT/vibeloop-test-picture.jpg"

# Web wallpaper package (Lively format: LivelyInfo.json + LivelyProperties.json), zipped for the import test.
python3 - "$OUT" <<'PY'
import json, os, sys, zipfile
from PIL import Image, ImageDraw
out = sys.argv[1]
src = os.path.join(out, "vibeloop-test-web")
os.makedirs(src, exist_ok=True)
# Thumbnail
img = Image.new("RGB", (480, 270))
d = ImageDraw.Draw(img)
for x in range(480):
    r = int(255 * x / 479); d.line([(x, 0), (x, 270)], fill=(r, 64, 255 - r))
d.text((20, 120), "Vibe Loop test web wallpaper", fill=(255, 255, 255))
img.save(os.path.join(src, "thumbnail.jpg"), quality=85)
info = {
    "AppVersion": "2.2.1.5", "Title": "Vibe Loop test - web", "Thumbnail": "thumbnail.jpg", "Preview": None,
    "Desc": "Synthetic WebView2/CEF test wallpaper: animated gradient, clock, and property listener echo.",
    "Author": "Vibe Loop test fixtures", "License": "GPL-3.0 (same as Vibe Loop)", "Contact": None,
    "Type": 1, "FileName": "index.html", "Arguments": None, "IsAbsolutePath": False, "Id": None,
    "Tags": ["test"], "Version": 0,
}
props = {
    "speed": {"type": "slider", "value": 8, "text": "Animation period (s)", "min": 2, "max": 30, "step": 1},
    "accent": {"type": "color", "value": "#FF3CAC", "text": "Accent color"},
    "showClock": {"type": "checkbox", "value": True, "text": "Show clock"},
}
html = """<!DOCTYPE html>
<html lang="en"><head><meta charset="utf-8"><title>Vibe Loop test web wallpaper</title>
<style>
  html,body{margin:0;height:100%;overflow:hidden;font-family:Segoe UI,Arial,sans-serif;color:#fff}
  #bg{position:fixed;inset:0;background:linear-gradient(120deg,#FF3CAC,#784BA0,#2B86C5,#2BD2C5);
      background-size:400% 400%;animation:shift var(--speed,8s) ease-in-out infinite}
  @keyframes shift{0%{background-position:0% 50%}50%{background-position:100% 50%}100%{background-position:0% 50%}}
  #panel{position:fixed;left:4vw;bottom:6vh;padding:16px 22px;border-radius:14px;background:rgba(0,0,0,.28)}
  #clock{font-size:6vh;font-weight:600}
  #log{font:12px Consolas,monospace;opacity:.85;white-space:pre}
</style></head>
<body><div id="bg"></div>
<div id="panel"><div id="clock"></div><div>Vibe Loop runtime test &middot; web</div><div id="log">waiting for property events...</div></div>
<script>
  const log = document.getElementById('log');
  function tick(){ document.getElementById('clock').textContent = new Date().toLocaleTimeString(); }
  setInterval(tick, 1000); tick();
  // Lively-format property API (kept for compatibility in Vibe Loop).
  function livelyPropertyListener(name, val){
    log.textContent = 'property ' + name + ' = ' + JSON.stringify(val);
    if (name === 'speed') document.getElementById('bg').style.setProperty('--speed', val + 's');
    if (name === 'accent') document.getElementById('panel').style.borderLeft = '6px solid ' + val;
    if (name === 'showClock') document.getElementById('clock').style.display = val ? 'block' : 'none';
  }
  function livelyWallpaperPlaybackChanged(data){ log.textContent = 'playback ' + data; }
</script></body></html>
"""
with open(os.path.join(src, "index.html"), "w", encoding="utf-8", newline="\n") as f: f.write(html)
with open(os.path.join(src, "LivelyInfo.json"), "w", encoding="utf-8", newline="\n") as f: json.dump(info, f, indent=2)
with open(os.path.join(src, "LivelyProperties.json"), "w", encoding="utf-8", newline="\n") as f: json.dump(props, f, indent=2)
zpath = os.path.join(out, "vibeloop-test-web.zip")
with zipfile.ZipFile(zpath, "w", zipfile.ZIP_DEFLATED) as z:
    for name in ["LivelyInfo.json", "LivelyProperties.json", "index.html", "thumbnail.jpg"]:
        zi = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0)); zi.compress_type = zipfile.ZIP_DEFLATED
        with open(os.path.join(src, name), "rb") as fh: z.writestr(zi, fh.read())
PY
( cd "$OUT" && sha256sum vibeloop-test-video.mp4 vibeloop-test-animation.gif vibeloop-test-picture.jpg vibeloop-test-web.zip > SHA256SUMS )
echo "fixtures written to $OUT"
