#!/usr/bin/env zsh
emulate -L zsh
set -u
setopt PIPE_FAIL NONOMATCH

# Usage: PRESET={HEVC_MAX|X265_LOSSLESS|DNXHR_HQ|PRORES_HQ} WORKDIR=<dir> ./teslacam_4up_all_max.sh <INPUT_DIR> [OUTPUT_FILE]
INDIR="${1:-.}"
OUT="${2:-cctv_4up_all.mp4}"
PRESET="${PRESET:-HEVC_MAX}"
WORKDIR="${WORKDIR:-}"
FFLOGLEVEL="${FFLOGLEVEL:-info}"
LIMIT_SETS="${LIMIT_SETS:-0}"

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
  add_in(){ local p="$1"; if [[ -n "$p" && -f "$p" ]]; then INARGS+=(-r "$FPS" -i "$p"); else INARGS+=(-f lavfi -t "$DUR" -r "$FPS" -i "color=size=1280x960:rate=${FPS}:color=black"); fi; }
  add_in "$FP"; add_in "$BP"; add_in "$LP"; add_in "$RP"

  if ffmpeg -hide_banner -loglevel "$FFLOGLEVEL" -stats -y \
      "${INARGS[@]}" \
      -filter_complex "\
        [0:v]setsar=1[vf];[1:v]setsar=1[vb];[2:v]setsar=1[vl];[3:v]setsar=1[vr];\
        [vf][vb][vl][vr]xstack=inputs=4:layout=0_0|w0_0|0_h0|w0_h0,setsar=1[v]" \
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
