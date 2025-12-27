#!/usr/bin/env zsh
emulate -L zsh
set -u
setopt PIPE_FAIL NONOMATCH

usage(){
  cat <<'USAGE' >&2
Usage:
  PRESET={HEVC_MAX|X265_LOSSLESS|DNXHR_HQ|PRORES_HQ} WORKDIR=<dir> \
    ./teslacam_4up_all_max.sh INPUT_DIR [OUTPUT_FILE]

Arguments:
  INPUT_DIR     Directory containing TeslaCam minute files (.mp4/.mov).
  OUTPUT_FILE   Optional output name (default: cctv_4up_all.mp4). The final
                extension is chosen by PRESET.

Options:
  -h, --help    Show this help and exit.

Environment:
  PRESET        Output codec preset (default: HEVC_MAX)
  HARDWARE      HW3 or HW4; if unset the script prompts (defaults to HW3 when
                no TTY is available)
  VT_Q          HEVC_MAX quality (lower is higher quality, default: 16)
  GOP           HEVC_MAX GOP length (default: 36)
  FFLOGLEVEL    ffmpeg log level (default: info)
  LIMIT_SETS    Process only the first N 4-cam sets (default: 0 = all)
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
    -*)
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
OUT="${2:-cctv_4up_all.mp4}"
PRESET="${PRESET:-HEVC_MAX}"
WORKDIR="${WORKDIR:-}"
FFLOGLEVEL="${FFLOGLEVEL:-info}"
LIMIT_SETS="${LIMIT_SETS:-0}"
HARDWARE="${HARDWARE:-}"

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
  dir="$(dirname "$path")"
  if [[ ! -d "$dir" ]]; then
    if ! mkdir -p "$dir"; then
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

normalize_hw(){
  local v="${1:-}"
  [[ -z "$v" ]] && return
  v="${v:l}"
  case "$v" in
    3|hw3) printf '3' ;;
    4|hw4) printf '4' ;;
  esac
}

select_hw(){
  local ans norm
  norm="$(normalize_hw "$HARDWARE")"
  if [[ -n "$norm" ]]; then
    HW_GEN="$norm"
    HARDWARE="HW$norm"
    return
  fi
  if [[ -t 0 && -t 2 ]]; then
    while :; do
      read -r "?Tesla hardware generation (3=HW3, 4=HW4) [3]: " ans || ans=""
      ans="${ans:-3}"
      norm="$(normalize_hw "$ans")"
      if [[ -n "$norm" ]]; then
        HW_GEN="$norm"
        HARDWARE="HW$norm"
        return
      fi
      print -u2 "Please enter 3 or 4."
    done
  else
    HW_GEN=3
    HARDWARE="HW3"
    print -u2 "WARN: HARDWARE not set and no TTY detected; defaulting to HW3."
  fi
}

typeset HW_GEN
select_hw
print -u2 "Hardware generation: $HARDWARE"

typeset -a CAM_ORDER
typeset -A CAM_LABEL CAM_FILTER CAM_COLOR
CAM_ORDER=(front back left_repeater right_repeater)
CAM_LABEL=([front]=vf [back]=vb [left_repeater]=vl [right_repeater]=vr)
for C in "${CAM_ORDER[@]}"; do
  CAM_FILTER[$C]="setsar=1"
done

typeset TILE_W TILE_H FILTER_COMPLEX
case "$HW_GEN" in
  3)
    TILE_W=1280
    TILE_H=960
    ;;
  4)
    TILE_W=2896
    TILE_H=1876
    CAM_FILTER[left_repeater]="setsar=1,scale=${TILE_W}:${TILE_H}:flags=lanczos"
    CAM_FILTER[right_repeater]="setsar=1,scale=${TILE_W}:${TILE_H}:flags=lanczos"
    ;;
  *)
    print -u2 "Unsupported hardware generation: $HW_GEN"
    exit 5
    ;;
esac
for C in "${CAM_ORDER[@]}"; do
  CAM_COLOR[$C]="${TILE_W}x${TILE_H}"
done
print -u2 "Tile size: ${TILE_W}x${TILE_H}"

typeset -a FILTER_STEPS
integer idx in_idx
for idx in {1..4}; do
  CAM="${CAM_ORDER[idx]}"
  LABEL="${CAM_LABEL[$CAM]}"
  FILTER="${CAM_FILTER[$CAM]}"
  (( in_idx = idx - 1 ))
  FILTER_STEPS+=("[${in_idx}:v]${FILTER}[${LABEL}]")
done
FILTER_COMPLEX="${(j:;:)FILTER_STEPS};[${CAM_LABEL[front]}][${CAM_LABEL[back]}][${CAM_LABEL[left_repeater]}][${CAM_LABEL[right_repeater]}]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,setsar=1[v]"

req() { command -v "$1" >/dev/null || { print -u2 "$1 required"; exit 1; }; }
req ffmpeg; req ffprobe; req awk; req sed; req sort

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
    front|back|left_repeater|right_repeater) printf '%s|%s|%s\n' "$ts" "$cam" "$f" >> "$IDX" ;;
  esac
done

awk -F'|' '{M[$1]=1; P[$1 "," $2]=$3}
  END{for(ts in M) print ts "|" P[ts ",front"] "|" P[ts ",back"] "|" P[ts ",left_repeater"] "|" P[ts ",right_repeater"]}' \
  "$IDX" | LC_ALL=C sort > "$JOBS"

TOTAL=$(wc -l < "$JOBS" | tr -d ' ')
(( TOTAL > 0 )) || { print -u2 "No timestamps."; exit 2; }
(( LIMIT_SETS > 0 )) && { head -n "$LIMIT_SETS" "$JOBS" > "$JOBS.tmp" && mv "$JOBS.tmp" "$JOBS"; TOTAL=$(wc -l < "$JOBS" | tr -d ' '); }
print -u2 "4-cam sets: $TOTAL"

first_real="$(awk -F'|' '{for(i=2;i<=5;i++) if($i!=""){print $i; exit}}' "$JOBS")"
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
  PARTDIR="$(mktemp -d -t tesla_parts)"
else
  mkdir -p "$WORKDIR"
  PARTDIR="$WORKDIR"
fi
PLIST="$PARTDIR/parts.txt"
: > "$PLIST"
print -u2 "PARTDIR=$PARTDIR"

dur_of(){ ffprobe -v error -show_entries format=duration -of default=nk=1:nw=1 "$1" 2>/dev/null | awk '{if($0+0<=0){print 60}else{printf("%.3f",$0)}}'; }

i=0
while IFS='|' read -r TS FP BP LP RP; do
  ((++i))
  PART="$PARTDIR/$(printf '%06d' "$i").${EXT}"
  print -u2 "Render $i/$TOTAL: $TS → ${PART##*/}"

  if [[ -s "$PART" ]]; then
    print -u2 "Skip existing $PART"
    printf "file '%s'\n" "$PART" >> "$PLIST"
    continue
  fi

  ANY=""; for C in "$FP" "$BP" "$LP" "$RP"; do [[ -n "$C" && -f "$C" ]] && { ANY="$C"; break; }; done
  DUR="$(dur_of "${ANY:-$first_real}")"

  INARGS=()
  add_in(){
    local p="$1" cam="$2" size
    size="${CAM_COLOR[$cam]:-${TILE_W}x${TILE_H}}"
    if [[ -n "$p" && -f "$p" ]]; then
      INARGS+=(-r "$FPS" -i "$p")
    else
      INARGS+=(-f lavfi -t "$DUR" -r "$FPS" -i "color=size=${size}:rate=${FPS}:color=black")
    fi
  }
  add_in "$FP" front; add_in "$BP" back; add_in "$LP" left_repeater; add_in "$RP" right_repeater

  if ffmpeg -hide_banner -loglevel "$FFLOGLEVEL" -stats -y \
      "${INARGS[@]}" \
      -filter_complex "$FILTER_COMPLEX" \
      -map "[v]" -an \
      -r "$FPS" "${VENC[@]}" "${MOV[@]}" "$PART"; then
    printf "file '%s'\n" "$PART" >> "$PLIST"
  else
    print -u2 "WARN: failed $TS → continuing"
    rm -f "$PART"
  fi
done < "$JOBS"

print -u2 "Concatenating -> $OUT"
ffmpeg -hide_banner -loglevel "$FFLOGLEVEL" -y -f concat -safe 0 -i "$PLIST" -c copy "${MOV[@]}" "$OUT" \
  && print -u2 "Done: $OUT" \
  || { print -u2 "Concat failed. Parts kept in $PARTDIR"; exit 4; }
