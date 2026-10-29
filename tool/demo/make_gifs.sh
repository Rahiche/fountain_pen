#!/bin/sh
# Renders the README's demos and turns them into doc/*.gif (ffmpeg, a palette
# made for each). Run from the package's root:
#   sh tool/demo/make_gifs.sh            # all of them
#   sh tool/demo/make_gifs.sh paper inks # just these
# RENDER=0 makes the GIFs again from frames already rendered.
set -e
FRAMES=${FRAMES_DIR:-build/demo}
ONLY=$(echo "$@" | tr ' ' ',')
if [ "${RENDER:-1}" != 0 ]; then
  FRAMES_DIR=$FRAMES ONLY=$ONLY flutter test tool/demo/render_test.dart
fi
for dir in "$FRAMES"/*/; do
  name=$(basename "$dir")
  [ -n "$ONLY" ] && case ",$ONLY," in *",$name,"*) ;; *) continue ;; esac
  # (Filmed shots move every pixel, the paper's grain too: fewer frames and
  # colours keep them under 2 MB. White ink on black needs few.)
  case $name in
    film*) fps=12; width=560; palette="max_colors=32"; dither="dither=none" ;;
    closeup) fps=15; width=640; palette="max_colors=96"; dither="dither=bayer:bayer_scale=4" ;;
    *) fps=15; width=720; palette="max_colors=128"; dither="dither=bayer:bayer_scale=4" ;;
  esac
  ffmpeg -loglevel error -y -framerate 30 -i "$dir/f%05d.png" -vf \
    "fps=$fps,scale=$width:-1:flags=lanczos,split[a][b];[a]palettegen=$palette:stats_mode=diff[p];[b][p]paletteuse=$dither:diff_mode=rectangle" \
    "doc/$name.gif"
  echo "doc/$name.gif $(du -k "doc/$name.gif" | cut -f1) KB"
done
