# TeslaCam 4‑Up Composer

Compose Tesla Sentry/Dashcam minutes into a single 2×2 “CCTV” stream per minute, then concatenate to one file. Native resolution preserved. Missing angles auto‑black.

## Features
- 2×2 grid: **Front | Back / Left | Right**
- Native tile **1280×960** (HW3) or **2896×1876** (HW4) ⇒ frame doubles accordingly, fps preserved (~36.027), SAR 1:1
- Hardware HEVC on Apple Silicon; optional DNxHR, ProRes, or x265 lossless
- Resume‑safe, continues after errors, keeps temp parts for inspection
- No upscaling; optional 4K pad for delivery
- Works from a flat folder of TeslaCam MP4s

## Input
- Filenames: `YYYY-MM-DD_HH-MM-SS-front.mp4`, `…-back.mp4`, `…-left_repeater.mp4`, `…-right_repeater.mp4`.
- Put all minute files into one directory (e.g. `~/Downloads/TeslaCam/`). Missing angles are filled with black.

## Output
Default single file next to your chosen output name:
```
cctv_4up_all_hevc_max.mp4
codec=HEVC (hvc1), 8‑bit yuv420p, 2560×1920, ~36.027 fps, faststart, silent
duration ≈ N_minutes × 60 s
```

## Requirements
- macOS 12+ on Apple Silicon
- `ffmpeg`, `ffprobe` (Homebrew: `brew install ffmpeg`)
- Shell: `zsh`

## Install
Create a project and save the script:
```zsh
mkdir -p ~/code/teslacam-4up && cd ~/code/teslacam-4up
curl -L -o teslacam_4up_all_max.sh https://example.invalid/replace-with-your-repo/teslacam_4up_all_max.sh
chmod +x teslacam_4up_all_max.sh
```

## Quick start
```zsh
# Put TeslaCam minutes here:
mkdir -p ~/Downloads/TeslaCam && cd ~/Downloads/TeslaCam
# …move all *.mp4 here …

# Run max practical quality (hardware HEVC 8‑bit):
cd ~/code/teslacam-4up
env PRESET=HEVC_MAX VT_Q=16 GOP=36 FFLOGLEVEL=info LIMIT_SETS=0 \
  caffeinate -dimsu \
  ./teslacam_4up_all_max.sh ~/Downloads/TeslaCam cctv_4up_all_hevc_max.mp4
```

## Hardware generations
- The script now asks whether the footage comes from **HW3** or **HW4** Teslas.
- You can skip the prompt by exporting `HARDWARE=HW3` or `HARDWARE=HW4` before running the script.
- HW3 minute files are already 1280×960 per camera.
- HW4 minutes keep the native 2896×1876 fronts/backs, while the 1448×938 repeaters are doubled with high-quality scaling so that all four tiles align cleanly in the 2×2 grid.

## Presets
| PRESET         | Codec            | Bit depth | Use case                         |
|----------------|------------------|-----------|----------------------------------|
| `HEVC_MAX`     | hevc_videotoolbox| 8‑bit 4:2:0 | Fast, high‑quality distribution |
| `DNXHR_HQ`     | DNxHR HQ         | 8‑bit 4:2:2 | Editing mezzanine in NLEs       |
| `PRORES_HQ`    | ProRes 422 HQ    | 10‑bit 4:2:2| Apple‑native mezzanine          |
| `X265_LOSSLESS`| libx265 lossless | 8‑bit 4:2:0 | True lossless archive           |

Quality knobs:
- `VT_Q` for `HEVC_MAX` (lower = better). Typical 14–20.
- `GOP` for `HEVC_MAX` (e.g. 36 ≈ 1 s). Lower for scrub‑friendly.

## Options (env vars)
```zsh
PRESET=HEVC_MAX     # or X265_LOSSLESS, DNXHR_HQ, PRORES_HQ
VT_Q=16             # HEVC quality (lower is better)
GOP=36              # HEVC GOP length
FFLOGLEVEL=info     # info|warning|error|debug
LIMIT_SETS=0        # 0=all minutes; N=first N only
WORKDIR=/path/parts # keep parts in a fixed folder (resume across runs)
HARDWARE=HW3        # HW3 (1280×960) or HW4 (2896×1876 + scaled repeaters)
```

## Verify
```zsh
ffprobe -v error -select_streams v:0 \
  -show_entries stream=codec_name,pix_fmt,width,height,avg_frame_rate \
  -of default=nk=1:nw=1 ~/Downloads/TeslaCam/cctv_4up_all_hevc_max.mp4
# expect: hevc / yuv420p / 2560 / 1920 / 36027/1000
```

## Optional: deliver as 4K without scaling (pad only)
```zsh
PAD='pad=3840:2160:(ow-iw)/2:(oh-ih)/2'
env PRESET=HEVC_MAX VT_Q=16 GOP=36 \
  ffmpeg -r 36.027 -i cctv_4up_all_hevc_max.mp4 \
  -vf "setsar=1,${PAD}" -c:v hevc_videotoolbox -tag:v hvc1 -q:v 16 -movflags +faststart \
  -an cctv_4up_all_2160p.mp4
```

## Troubleshooting
- Stops mid‑run → wrap with `caffeinate -dimsu`.
- Bad minute → script logs `WARN: failed … → continuing` and moves on.
- Resume after crash → rerun with same `WORKDIR` to skip existing parts.
- Performance → close heavy apps; keep sources on internal SSD.

Live progress without `watch`:
```zsh
PARTDIR=$(grep -m1 PARTDIR encode.log | awk -F= '{print $2}')
TOTAL=$(grep -m1 '4-cam sets:' encode.log | awk '{print $3}')
while :; do C=$(ls "$PARTDIR"/*.mp4 2>/dev/null | wc -l | tr -d ' ');
printf "%s parts=%d/%d (%.1f%%)\r" "$(date '+%H:%M:%S')" "$C" "$TOTAL" "$(awk -v c=$C -v t=$TOTAL 'BEGIN{if(t>0) printf 100*c/t; else print 0}')"; sleep 5; done
```

## License
MIT. See `LICENSE`.
