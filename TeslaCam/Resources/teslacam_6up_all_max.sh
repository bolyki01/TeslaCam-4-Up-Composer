#!/usr/bin/env zsh
emulate -L zsh
set -u
setopt PIPE_FAIL NONOMATCH
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${PATH:-}"

usage(){
  cat <<'USAGE' >&2
Usage:
  PRESET={HEVC_MAX|X265_LOSSLESS|DNXHR_HQ|PRORES_HQ} WORKDIR=<dir> \
    ./teslacam_6up_all_max.sh INPUT_DIR [OUTPUT_FILE]

Arguments:
  INPUT_DIR     Directory containing TeslaCam minute files (.mp4/.mov).
  OUTPUT_FILE   Optional output name (default: cctv_6up_all.mp4). The final
                extension is chosen by PRESET.

Options:
  -h, --help    Show this help and exit.

Environment:
  PRESET        Output codec preset (default: HEVC_MAX)
  VT_Q          HEVC_MAX quality (lower is higher quality, default: 16)
  GOP           HEVC_MAX GOP length (default: 36)
  FFLOGLEVEL    ffmpeg log level (default: info)
  LIMIT_SETS    Process only the first N 6-cam sets (default: 0 = all)
  WORKDIR       Directory to reuse intermediate parts (default: temporary)
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -h|--help)
      usage
      exit 0
      ;;
    --)
      shift
      break
      ;;
    -* )
      print -u2 "Unknown option: $1"
      usage
      exit 64
      ;;
    *)
      break
      ;;
  esac
done

[[ $# -ge 1 ]] || { print -u2 "ERROR: INPUT_DIR is required."; usage; exit 64; }
[[ $# -le 2 ]] || { print -u2 "ERROR: Too many arguments."; usage; exit 64; }

INDIR="${1:-}"
OUT="${2:-cctv_6up_all.mp4}"
PRESET="${PRESET:-HEVC_MAX}"
WORKDIR="${WORKDIR:-}"
FFLOGLEVEL="${FFLOGLEVEL:-info}"
LIMIT_SETS="${LIMIT_SETS:-0}"

validate_input_dir(){
  local dir="$1"
  if [[ ! -d "$dir" ]]; then
    print -u2 "ERROR: INPUT_DIR must be an existing directory: $dir"
    exit 1
  fi
  if ! find "$dir" -type f \( -iname '*.mp4' -o -iname '*.mov' \) -print -quit | grep -q .; then
    print -u2 "ERROR: INPUT_DIR contains no .mp4 or .mov files: $dir"
    exit 2
  fi
}

validate_output_path(){
  local path="$1" dir
  dir="${path:h}"
  if [[ ! -d "$dir" ]]; then
    if ! /bin/mkdir -p "$dir"; then
      print -u2 "ERROR: Failed to create output directory: $dir"
      exit 3
    fi
  fi
  if [[ ! -w "$dir" ]]; then
    print -u2 "ERROR: Output directory is not writable: $dir"
    exit 3
  fi
}

validate_input_dir "$INDIR"

FFMPEG_BIN="${FFMPEG:-ffmpeg}"
FFPROBE_BIN="${FFPROBE:-ffprobe}"

req_bin() {
  local name="$1" bin="$2"
  if [[ -n "$bin" && "$bin" != "$name" ]]; then
    [[ -x "$bin" ]] || { print -u2 "$name not executable: $bin"; exit 1; }
  else
    command -v "$name" >/dev/null || { print -u2 "$name required"; exit 1; }
  fi
}

req() { command -v "$1" >/dev/null || { print -u2 "$1 required"; exit 1; }; }
req_bin ffmpeg "$FFMPEG_BIN"
req_bin ffprobe "$FFPROBE_BIN"
req awk; req sed; req sort

ffmpeg() { "$FFMPEG_BIN" "$@"; }
ffprobe() { "$FFPROBE_BIN" "$@"; }

print -u2 "Scanning: $INDIR"
IDX="$(mktemp -t tesla_idx)"
JOBS="$(mktemp -t tesla_jobs)"
cleanup_tmp(){ rm -f "$IDX" "$JOBS"; }
trap cleanup_tmp EXIT

: > "$IDX"
LC_ALL=C find "$INDIR" -type f \( -iname '*.mp4' -o -iname '*.mov' \) -print \
| LC_ALL=C sort \
| while IFS= read -r f; do
  bn="${f##*/}"; core="${bn%.*}"; cam="${core##*-}"; ts="${core%-*}"
  [[ "$cam" == "rear" ]] && cam="back"
  case "$cam" in
    front|back|left_repeater|right_repeater|left_pillar|right_pillar) printf '%s|%s|%s\n' "$ts" "$cam" "$f" >> "$IDX" ;;
  esac
done

awk -F'|' '{M[$1]=1; P[$1 "," $2]=$3}
  END{for(ts in M) print ts "|" P[ts ",front"] "|" P[ts ",back"] "|" P[ts ",left_repeater"] "|" P[ts ",right_repeater"] "|" P[ts ",left_pillar"] "|" P[ts ",right_pillar"]}' \
  "$IDX" | LC_ALL=C sort > "$JOBS"

TOTAL=$(wc -l < "$JOBS" | tr -d ' ')
(( TOTAL > 0 )) || { print -u2 "No timestamps."; exit 2; }
(( LIMIT_SETS > 0 )) && { head -n "$LIMIT_SETS" "$JOBS" > "$JOBS.tmp" && mv "$JOBS.tmp" "$JOBS"; TOTAL=$(wc -l < "$JOBS" | tr -d ' '); }
print -u2 "6-cam sets: $TOTAL"

first_real="$(awk -F'|' '{for(i=2;i<=7;i++) if($i!=""){print $i; exit}}' "$JOBS")"

typeset -a CAM_ORDER
typeset -A CAM_LABEL CAM_FILTER CAM_COLOR
CAM_ORDER=(front back left_repeater right_repeater left_pillar right_pillar)
CAM_LABEL=([front]=v1 [back]=v2 [left_repeater]=v3 [right_repeater]=v4 [left_pillar]=v5 [right_pillar]=v6)

get_dims(){
  local clip="$1" dims w h
  [[ -z "$clip" || ! -f "$clip" ]] && return
  dims="$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=p=0 "$clip" 2>/dev/null || true)"
  [[ "$dims" == *,* ]] || return
  w="${dims%%,*}"; h="${dims#*,}"
  printf '%s %s' "$w" "$h"
}

detect_tile(){
  local line ts f b l r lp rp w h maxw=0 maxh=0
  line="$(head -n 1 "$JOBS")"
  IFS='|' read -r ts f b l r lp rp <<< "$line"
  for c in "$f" "$b" "$l" "$r" "$lp" "$rp"; do
    read -r w h <<<"$(get_dims "$c")"
    [[ -n "${w:-}" && -n "${h:-}" ]] || continue
    (( w > maxw )) && maxw="$w"
    (( h > maxh )) && maxh="$h"
  done
  if (( maxw == 0 || maxh == 0 )); then
    read -r w h <<<"$(get_dims "$first_real")"
    maxw="${w:-1280}"
    maxh="${h:-960}"
  fi
  TILE_W="$maxw"
  TILE_H="$maxh"
}

typeset TILE_W TILE_H FILTER_COMPLEX
detect_tile
for C in "${CAM_ORDER[@]}"; do
  CAM_FILTER[$C]="setsar=1,scale=${TILE_W}:${TILE_H}:flags=lanczos"
  CAM_COLOR[$C]="${TILE_W}x${TILE_H}"
done
print -u2 "Tile size: ${TILE_W}x${TILE_H}"

typeset -a FILTER_STEPS
integer idx in_idx
for idx in {1..6}; do
  CAM="${CAM_ORDER[idx]}"
  LABEL="${CAM_LABEL[$CAM]}"
  FILTER="${CAM_FILTER[$CAM]}"
  (( in_idx = idx - 1 ))
  FILTER_STEPS+=("[${in_idx}:v]${FILTER}[${LABEL}]")
done
FILTER_COMPLEX="${(j:;:)FILTER_STEPS};[${CAM_LABEL[front]}][${CAM_LABEL[back]}][${CAM_LABEL[left_repeater]}][${CAM_LABEL[right_repeater]}][${CAM_LABEL[left_pillar]}][${CAM_LABEL[right_pillar]}]xstack=inputs=6:layout=0_0|w0_0|2*w0_0|0_h0|w0_h0|2*w0_h0,setsar=1[v]"

FPS_R="$(ffprobe -v error -select_streams v:0 -show_entries stream=avg_frame_rate -of csv=p=0 "$first_real" || true)"
FPS="$(awk -v r="$FPS_R" 'BEGIN{n=split(r,a,"/"); if(n==2&&a[2]>0){printf("%.3f",a[1]/a[2]);} else if(r+0>0){printf("%.3f",r);} else{printf("36.027");}}')"
print -u2 "Using FPS=$FPS"

typeset -a VENC MOV
typeset EXT
case "$PRESET" in
  HEVC_MAX)
    VT_Q="${VT_Q:-16}"; GOP="${GOP:-36}"
    VENC=(-c:v hevc_videotoolbox -tag:v hvc1 -pix_fmt yuv420p -q:v "$VT_Q" -allow_sw 1 -g "$GOP" -bf 0)
    MOV=(-movflags +faststart); EXT="mp4" ;;
  X265_LOSSLESS)
    VENC=(-c:v libx265 -x265-params lossless=1:profile=main -pix_fmt yuv420p)
    MOV=(-movflags +faststart); EXT="mp4" ;;
  DNXHR_HQ)
    VENC=(-c:v dnxhd -profile:v dnxhr_hq -pix_fmt yuv422p)
    MOV=(-movflags +faststart); EXT="mov" ;;
  PRORES_HQ)
    VENC=(-c:v prores_ks -profile:v 3 -pix_fmt yuv422p10le)
    MOV=(-movflags +faststart); EXT="mov" ;;
  *)
    print -u2 "Unknown PRESET: $PRESET"; exit 3 ;;
esac
OUTDIR="$(dirname "$OUT")"; OUTBASE="$(basename "$OUT")"; OUT="${OUTDIR%/}/${OUTBASE%.*}.${EXT}"
validate_output_path "$OUT"

if [[ -z "$WORKDIR" ]]; then
  WORKDIR="$(mktemp -d -t teslacam_6up)"
  WORKDIR_EPHEMERAL=1
else
  /bin/mkdir -p "$WORKDIR"
  WORKDIR_EPHEMERAL=0
fi
PARTS="$WORKDIR/parts"
INPUT="$WORKDIR/input"
FINAL="$WORKDIR/final"
/bin/mkdir -p "$PARTS" "$INPUT" "$FINAL"
print -u2 "WORKDIR: $WORKDIR"

append_concat="$WORKDIR/concat.txt"
: > "$append_concat"

build_one(){
  local ts="$1" front="$2" back="$3" left="$4" right="$5" lp="$6" rp="$7"
  local i=0 inputs=()
  if [[ -n "$front" ]]; then ln -f "$front" "$INPUT/${ts}-front.${front##*.}" 2>/dev/null || cp "$front" "$INPUT/${ts}-front.${front##*.}"; inputs+=("-i" "$INPUT/${ts}-front.${front##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[front]}:r=$FPS"); fi
  if [[ -n "$back" ]]; then ln -f "$back" "$INPUT/${ts}-back.${back##*.}" 2>/dev/null || cp "$back" "$INPUT/${ts}-back.${back##*.}"; inputs+=("-i" "$INPUT/${ts}-back.${back##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[back]}:r=$FPS"); fi
  if [[ -n "$left" ]]; then ln -f "$left" "$INPUT/${ts}-left.${left##*.}" 2>/dev/null || cp "$left" "$INPUT/${ts}-left.${left##*.}"; inputs+=("-i" "$INPUT/${ts}-left.${left##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[left_repeater]}:r=$FPS"); fi
  if [[ -n "$right" ]]; then ln -f "$right" "$INPUT/${ts}-right.${right##*.}" 2>/dev/null || cp "$right" "$INPUT/${ts}-right.${right##*.}"; inputs+=("-i" "$INPUT/${ts}-right.${right##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[right_repeater]}:r=$FPS"); fi
  if [[ -n "$lp" ]]; then ln -f "$lp" "$INPUT/${ts}-lp.${lp##*.}" 2>/dev/null || cp "$lp" "$INPUT/${ts}-lp.${lp##*.}"; inputs+=("-i" "$INPUT/${ts}-lp.${lp##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[left_pillar]}:r=$FPS"); fi
  if [[ -n "$rp" ]]; then ln -f "$rp" "$INPUT/${ts}-rp.${rp##*.}" 2>/dev/null || cp "$rp" "$INPUT/${ts}-rp.${rp##*.}"; inputs+=("-i" "$INPUT/${ts}-rp.${rp##*.}"); ((i++)); else inputs+=("-f" "lavfi" "-i" "color=c=black:s=${CAM_COLOR[right_pillar]}:r=$FPS"); fi

  local out="$PARTS/${ts}.mp4"
  ffmpeg -y -loglevel "$FFLOGLEVEL" "${inputs[@]}" \
    -filter_complex "$FILTER_COMPLEX" -map "[v]" "${VENC[@]}" "${MOV[@]}" "$out" \
    || { print -u2 "Failed part: $ts"; return 1; }
  printf "file '%s'\n" "$out" >> "$append_concat"
}

print -u2 "Processing parts..."
integer idx=0
while IFS='|' read -r ts f b l r lp rp; do
  (( idx++ ))
  print -u2 "[$idx/$TOTAL] $ts"
  build_one "$ts" "$f" "$b" "$l" "$r" "$lp" "$rp" || exit 4
done < "$JOBS"

print -u2 "Concatenating..."
ffmpeg -y -loglevel "$FFLOGLEVEL" -f concat -safe 0 -i "$append_concat" -c copy "$FINAL/out.${EXT}" \
  || { print -u2 "Concat failed"; exit 5; }

/bin/mv -f "$FINAL/out.${EXT}" "$OUT"
print -u2 "Done: $OUT"

if (( WORKDIR_EPHEMERAL == 1 )); then
  /bin/rm -rf "$WORKDIR"
fi
