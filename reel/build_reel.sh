#!/bin/bash
set -e
cd /tmp/work
FONT_MAIN=/tmp/work/fonts/NotoSerifCJKjp-Bold.otf
FONT_SUB=/tmp/work/fonts/NotoSerifCJKjp-Regular.otf
QR=/tmp/work/qr.png
CW=2160; CH=3840          # 2x canvas for crisp Ken Burns
OUT_W=1080; OUT_H=1920
FPS=30
mkdir -p seg txt still

# ---- text files (avoid escaping issues) ----
w(){ printf '%s' "$2" > "txt/$1"; }
w t1m  "初夏を味わう"
w t1s  "ー 今だけの旬を愉しむ ー"
w t2m  "一本の包丁が、料理を変える"
w t3m  "飾り包丁"
w t3s  "イカに、繊細な切り込みを"
w t4s  "くるりと巻く、職人の手"
w t5m  "切　る"
w t6s  "ミリ単位の手仕事"
w t7m  "揚げる"
w t9m  "焼　く"
w t9s  "炭火の生命線"
w t10m "旨味を、閉じ込める"
w t11m "ご予約はお早めに"
w tqr  "ご予約はこちらから▼"

# segment table: idx|image|dur|mode(in/out)|mainfile|subfile
SEGS=(
"01|ashirai/ashirai0006.jpg|3.0|in|t1m|t1s"
"02|cook/cook0030.jpg|3.6|in|t2m|"
"03|cook/cook0028.jpg|3.2|out|t3m|t3s"
"04|cook/cook0033.jpg|3.0|in||t4s"
"05|cook/cook0034.jpg|2.6|in|t5m|"
"06|cook/cook0041.jpg|2.6|out||t6s"
"07|cook/cook0058.jpg|2.8|in|t7m|"
"08|cook/cook0064.jpg|2.4|out||"
"09|cook/cook0094.jpg|3.0|in|t9m|t9s"
"10|cook/cook0103.jpg|2.8|out|t10m|"
"11|ashirai/ashirai0012.jpg|3.6|in|t11m|"
)

for row in "${SEGS[@]}"; do
  IFS='|' read -r idx img dur mode mf sf <<< "$row"
  N=$(python3 -c "print(int($dur*$FPS))")

  # ---- text drawfilters (no scrim; outline + shadow for legibility) ----
  DT=""
  if [ -n "$mf" ]; then
    DT+="drawtext=fontfile=${FONT_MAIN}:textfile=txt/${mf}:fontcolor=white:fontsize=128:"
    DT+="borderw=4:bordercolor=black@0.55:x=(w-text_w)/2:y=h-560:shadowcolor=black@0.7:shadowx=4:shadowy=4,"
  fi
  if [ -n "$sf" ]; then
    DT+="drawtext=fontfile=${FONT_SUB}:textfile=txt/${sf}:fontcolor=white@0.95:fontsize=64:"
    DT+="borderw=3:bordercolor=black@0.5:x=(w-text_w)/2:y=h-355:shadowcolor=black@0.7:shadowx=3:shadowy=3,"
  fi
  DT="${DT%,}"
  [ -n "$DT" ] && DT=",${DT}"

  # ---- still: full-bleed 9:16 cover crop + grade + text (2x canvas) ----
  ffmpeg -y -loglevel error -i "$img" -filter_complex \
"[0:v]scale=${CW}:${CH}:force_original_aspect_ratio=increase,crop=${CW}:${CH},\
eq=contrast=1.06:saturation=1.07:brightness=-0.02${DT},format=rgb24" \
    -frames:v 1 "still/${idx}.png"

  # ---- Ken Burns motion ----
  if [ "$mode" = "in" ]; then
    Z="z='min(1.0+0.0010*on,1.14)'"
  else
    Z="z='if(eq(on,0),1.14,max(1.14-0.0010*on,1.0))'"
  fi
  ffmpeg -y -loglevel error -loop 1 -i "still/${idx}.png" -t "$dur" -filter_complex \
"zoompan=${Z}:d=${N}:x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s=${OUT_W}x${OUT_H}:fps=${FPS},format=yuv420p" \
    -c:v libx264 -preset medium -crf 18 -r ${FPS} "seg/${idx}.mp4"
  echo "built seg ${idx} (${dur}s, ${mode})"
done

# ---- final QR reservation card page (static, full card kept scannable) ----
QDUR=4.6
CARDW=1820
CARDH=$(python3 -c "print(round($CARDW*1350/1080))")          # QR png is 1080x1350
TOPBAND=$(python3 -c "print(($CH-$CARDH)//2)")                 # blurred margin above card
ffmpeg -y -loglevel error -i "$QR" -filter_complex \
"[0:v]scale=${CW}:${CH}:force_original_aspect_ratio=increase,crop=${CW}:${CH},boxblur=55:2,eq=brightness=-0.22:saturation=1.0[bg];\
[0:v]scale=${CARDW}:-1[card];\
[bg][card]overlay=(W-w)/2:(H-h)/2,\
drawtext=fontfile=${FONT_MAIN}:textfile=txt/tqr:fontcolor=white:fontsize=82:borderw=4:bordercolor=black@0.55:\
x=(w-text_w)/2:y=(${TOPBAND}-text_h)/2:shadowcolor=black@0.7:shadowx=4:shadowy=4,\
format=rgb24" \
  -frames:v 1 "still/12.png"
ffmpeg -y -loglevel error -loop 1 -i "still/12.png" -t "$QDUR" -filter_complex \
"scale=${OUT_W}:${OUT_H},format=yuv420p" \
  -c:v libx264 -preset medium -crf 18 -r ${FPS} "seg/12.mp4"
echo "built seg 12 (QR card, ${QDUR}s, static)"
echo "ALL SEGMENTS DONE"
