#!/usr/bin/env bash
# Mechanical atlas extraction only. Original character art is generated, not drawn here.
set -euo pipefail
cd "$(dirname "$0")/../.."
mkdir -p assets/art/characters/garrison_v2_frames
work=$(mktemp -d /tmp/garrison-pack.XXXXXX)
export XDG_CACHE_HOME="$work/cache"; mkdir -p "$XDG_CACHE_HOME"
palette=(20252c 30343b 463d39 624a3a 896345 b18b60 d7c7a4 efe2bd c58c67 e2b58b f3d6a7 733d3a a65143 dc7552 606d70 879c9a b8cbc4 37463d 526044 778258 ed9b49 f5cb76 4d626a 729ba0)
args=()
for c in "${palette[@]}"; do args+=( -size 1x1 "xc:#$c" ); done
magick "${args[@]}" +append assets/art/palette.png
crops=('216x278+60+45' '231x280+347+45' '306x260+615+65' '333x260+917+65' '320x280+20+350' '290x280+340+350' '281x280+623+350' '340x282+913+348' '311x246+20+681' '266x302+329+625' '387x247+620+679' '300x275+944+652' '319x280+18+946' '235x279+353+949' '284x221+623+1009' '340x150+911+1080')
for i in {0..15}; do
  printf -v n '%02d' "$i"
  magick assets/art/source/garrison_01-generation-v2.png -crop "${crops[$i]}" +repage -channel A -threshold 55% +channel -trim +repage -filter point -resize 18% -resize '60x60>' -background none -gravity south -extent 64x64 -define png:color-type=6 "$work/$n.png"
  magick "$work/$n.png" -alpha extract "$work/$n-alpha.png"
  component=$(magick "$work/$n-alpha.png" -define connected-components:verbose=true -connected-components 8 null: | awk '/gray\(255\)|srgb\(255,255,255\)/ {gsub(":","",$1); print $1; exit}')
  magick "$work/$n-alpha.png" -define connected-components:mean-color=true -define connected-components:keep="$component" -connected-components 8 "$work/$n-clean.png"
  magick "$work/$n.png" -alpha off -dither None -remap assets/art/palette.png "$work/$n-clean.png" -alpha off -compose CopyOpacity -composite -define png:color-type=6 "assets/art/characters/garrison_v2_frames/$n.png"
done
magick montage assets/art/characters/garrison_v2_frames/*.png -tile 4x4 -geometry 64x64+0+0 -background none -define png:color-type=6 assets/art/characters/garrison_01_v2.png
cp assets/art/characters/garrison_v2_frames/00.png assets/art/characters/garrison_01_v2-idle.png
magick assets/art/characters/garrison_01_v2.png -filter point -resize 300% -background '#59645d' -alpha remove assets/art/previews/Shiganshina-garrison-sheet-canon-v2.png
magick -size 576x320 xc:'#293136' \( assets/art/characters/garrison_v2_frames/00.png \) -geometry +64+144 -composite \( assets/art/characters/garrison_v2_frames/00.png -filter point -resize 200% \) -geometry +192+112 -composite \( assets/art/characters/garrison_v2_frames/00.png -filter point -resize 300% \) -geometry +352+80 -composite -fill '#d7c7a4' -font DejaVu-Sans -pointsize 16 -annotate +30+38 'GARRISON / 845' -pointsize 12 -annotate +64+238 '1x / 64 px' -annotate +208+270 '2x / 128 px' -annotate +385+302 '3x / 192 px' assets/art/previews/Shiganshina-garrison-scale-canon-v2.png
for pair in 'move 02 03 04 05 06 07' 'attack 08 09 10 11 12 00'; do
 read -ra seq <<< "$pair"; name=${seq[0]}; frames=(); for n in "${seq[@]:1}"; do frames+=( "assets/art/characters/garrison_v2_frames/$n.png" ); done
 magick -delay 12 "${frames[@]}" -background '#59645d' -alpha remove -filter point -resize 400% -loop 0 "assets/art/previews/Shiganshina-garrison-${name}-canon-v2.gif"
done
