#!/bin/bash

# updating snippets
# snippetek frissítése
update_snippets() {
  local file
  file=$(curl -fsSL https://raw.githubusercontent.com/nyuszika7h/snippets/master/update_snippets.sh | bash -s - --selfupdate)
  if [[ -n "$file" ]]; then
    printf 'Sourcing %s\n' "$file"
    # shellcheck disable=SC1090
    source "$file"
  fi
}

# renames mkv title to the filename
# mkv fájlok címét a fájlnévre írja át
mkvtitles() {
  local i b
  for i in "$@"; do
    b=$(basename "$i")
    mkvpropedit "$i" -e info -s "title=${b%.mkv}"
  done
}

# extracting iso file
# iso fájl kibontása
isoextract() { local i; for i in "$@"; do 7z x "$i" -o"${i%.iso}"; done; }

# renames audio files that were demuxed with eac3to to a format that Dolby Media Producer understands
# eac3to-val demuxolt wavok átnevezése úgy, hogy Dolby Media Producer kezelje
renamewav() { local i; for i in "$@"; do rename 's/SL/Ls/; s/SR/Rs/; s/BL/Lrs/; s/BR/Rrs/' "$i"; done; }

# uploading to sxcu
# sxcu-ra képfeltöltés
sxcu() {
  local help site token f

  help="Usage: sxcu [-s SITE] [-t TOKEN] URL [URL..]"

  site=${SXCU_SITE:-sxcu.net}
  token=$SXCU_TOKEN

  while getopts ':hs:t:' OPTION; do
    case "$OPTION" in
      h) echo "$help"; return 0;;
      s) site=$OPTARG;;
      t) token=$OPTARG;;
      *) echo "ERROR: Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done

  shift "$((OPTIND - 1))"

  if [[ $# -eq 0 ]]; then
    echo "$help"
    return 1
  fi

  for f in "$@"; do
    curl -fsS -F "image=@$f" -F "token=$token" -F "noembed=1" "https://$site/upload" | jq -r .url
  done
}

# encoding aac from wav files
# aac kódolás wavból
# aacenc [input]
# aacenc xy.wav / aacenc *wav
aacenc() {
  local args i b

  args=(--no-notice -j 4)
  if (( $# == 1 )); then
    args+=(-u)
  fi

  for i in "$@"; do
    b=$(basename "$i")
    if [[ $i == *.wav ]]; then
      echo qaac64.exe -V 110 --no-delay --ignorelength -o "${b%.*}.m4a" "$i" >&2 | tee
    else
      echo "ffmpeg -i '$i' -v quiet -f wav - | qaac64.exe -V 110 --no-delay --ignorelength -o '${b%.*}.m4a' -" >&2 | tee
    fi
  done | parallel "${args[@]}"
}

# ffmpeg frissítés
# updating ffmpeg
update_ffmpeg() {
  type=${1:-release} # release, git
  if [[ $type == 'release' ]]; then
    dir='releases'
  else
    dir='builds'
  fi
  sudo sh -c "curl -# 'https://johnvansickle.com/ffmpeg/${dir}/ffmpeg-${type}-amd64-static.tar.xz' | tar -C /usr/local/bin -xvJf - --strip 1 --wildcards '*/ffmpeg' '*/ffprobe'"
}

# creates spectrograms and uploads them to kek.sh
# spectrogramok létrehozása és feltöltése kek.sh-ra
spec() {
  local help channel x b

  help=$(cat <<'EOF'
Usage: spec -c [channel] [input(s)]
  inputs can be any audio file
  (they will be decoded with ffmpeg)

Options:
  -c [channel]   Sets number of channels. [2/6]

Examples:
  spec *wav
  spec -c 6 input.ac3
EOF
  )
  channel=2
  while getopts ':hc:' OPTION; do
    case "$OPTION" in
      h) echo "$help"; return 0;;
      c) channel=$OPTARG;;
      *) echo "ERROR: Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done

  shift "$((OPTIND - 1))"

  if [[ $channel != 6 && $channel != 2 ]]; then
    echo "ERROR: Unsupported channel number." >&2; return 1
  fi

  for x in "$@"; do
    b=$(basename "$x")
    printf '%s: ' "$b"
    if [[ "$x" == *.wav ]] || [[ "$x" == *.w64 ]]; then
      sox "$x" -n spectrogram -x 1776 -Y 1080 -o "${b%.*}.png"
    else
      ffmpeg -y -v quiet -i "$x" -ac "$channel" spec_temp.w64
      sox spec_temp.w64 -n spectrogram -x 1776 -Y 1080 -o "${b%.*}.png"
    fi
    curl -fsSL https://kek.sh/api/v1/posts -F file="@${b%.*}.png" | jq -r '"https://i.kek.sh/\(.filename)"'
  done
  rm -f spec_temp.w64
}

# AviSynth 2pass encode, the avs script can be written right in the command. The snippet contains settings, you only have to specify settings that you want to overwrite
# AviSynthes 2pass encode, az avs script magába a parancsba írható. A snippetben benne vannak a beállítások, csak azokat az opciókat kell megadni, amiket szeretnénk felülírni
# avsenc 'FFMS2("[source]").AutoResize("480")' --bitrate 1800 -- *mkv
avsenc() {
  local avs_script x264_opts arg f

  avs_script=$1
  shift
  # shellcheck disable=SC2054
  x264_opts=(--level 4.1 --preset veryslow --no-fast-pskip --keyint 240
             --colormatrix bt709  --vbv-maxrate 62500 --vbv-bufsize 78125 --merange 32
             --bframes 10 --deblock -3,-3 --qcomp 0.65 --aq-mode 3 --aq-strength 0.8 --psy-rd 1.2 --ipratio 1.3)

  for arg in "$@"; do
    if [[ $arg == '--' ]]; then
      shift
      break
    fi

    x264_opts+=("$arg")
    shift
  done

  for f in "$@"; do
    printf '%s\n' "${avs_script/'[source]'/"$f"}" > temp.avs
    x264.exe "${x264_opts[@]}" --pass 1 --output NUL temp.avs
    x264.exe "${x264_opts[@]}" --pass 2 --log-file "${f%.*}_log.txt" --output "${f%.*}_e.mkv" temp.avs
  done

  rm -f temp.avs
  rm -f x264*log
  rm -r x264*mbtree
}

extract2.0() {
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -i "$i" \
    -filter_complex "channelsplit=channel_layout=5.1[FL][FR]" \
    -c:a pcm_s24le -map "[FL]" "${b%.*}"_L.wav \
    -c:a pcm_s24le -map "[FR]" "${b%.*}"_R.wav
  done
}

extract5.1() {
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -i "$i" \
    -filter_complex "channelsplit=channel_layout=5.1[FL][FR][FC][LFE][BL][BR]" \
    -c:a pcm_s24le -map "[FL]" "${b%.*}"_L.wav \
    -c:a pcm_s24le -map "[FR]" "${b%.*}"_R.wav \
    -c:a pcm_s24le -map "[FC]" "${b%.*}"_C.wav \
    -c:a pcm_s24le -map "[LFE]" "${b%.*}"_LFE.wav \
    -c:a pcm_s24le -map "[BL]" "${b%.*}"_Ls.wav \
    -c:a pcm_s24le -map "[BR]" "${b%.*}"_Rs.wav
  done
}

extract7.1() {
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -i "$i" \
    -filter_complex "channelsplit=channel_layout=7.1[FL][FR][FC][LFE][BL][BR][SL][SR]" \
    -c:a pcm_s24le -map "[FL]" "${b%.*}"_L.wav \
    -c:a pcm_s24le -map "[FR]" "${b%.*}"_R.wav \
    -c:a pcm_s24le -map "[FC]" "${b%.*}"_C.wav \
    -c:a pcm_s24le -map "[LFE]" "${b%.*}"_LFE.wav \
    -c:a pcm_s24le -map "[SL]" "${b%.*}"_Ls.wav \
    -c:a pcm_s24le -map "[SR]" "${b%.*}"_Rs.wav \
    -c:a pcm_s24le -map "[BL]" "${b%.*}"_Lrs.wav \
    -c:a pcm_s24le -map "[BR]" "${b%.*}"_Rrs.wav
  done
}

# extracting links from a link pointing to a directory
# mappára mutató linkből visszadja a fájlok linkjeit
getlinks() {
  local link auth proto auth_param

  link=$1

  if [[ $link == *://*:*@* ]]; then
    auth=${link%%@*}
    auth=${auth#*://}
    proto=${link%%://*}
    link=${link##*@}
    link=$proto://$link
  fi

  if [[ -n "$auth" ]]; then
    auth_param=("-auth=$auth")
  fi

  lynx "${auth_param[@]}" -hiddenlinks=ignore -listonly -nonumbers -dump "$link" | grep -Ev '\?|/$' | sed -r 's/ /%20/g'
}

# downloading with aria2c
# több szálas letöltés aria2c-vel
fastgrab() {
  local url host http_code http_user http_passwd auth

  url="$1"

  host=${url#*//}
  host=${host%%/*}

  if [[ $host != *:*@* ]]; then
    http_code=$(curl -s -I -o/dev/null -w '%{http_code}' "$url")

    if [[ $http_code == 401 ]]; then
      printf 'Username for %s: ' "$host"
      read -r http_user
      printf 'Password for %s: ' "$host"
      read -rs http_passwd
    fi
  fi

  auth=("--http-user=${http_user}" "--http-passwd=${http_passwd}")

  aria2c --auto-file-renaming=false --allow-overwrite=true -j 16 -x 16 -s 16 -Z "${auth[@]}" "$@"
}
fastgrabdir() {
  # shellcheck disable=SC2046
  fastgrab $(getlinks "$1")
}

# ISO-8859-2 (Latin-2) to UTF-8 subtitle conversion, converted files will be in the "utf8" folder.
# ISO-8859-2 (Latin-2) feliratok UTF-8-ra konvertálása, a konvertált fájlok az "utf8" mappában lesznek.
# latin2toutf8 [input]
# latin2toutf8 xy.srt / latin2toutf8 *.srt
latin2toutf8() {
  local i
  mkdir -p utf8
  for i in "$@"; do
    iconv -f iso-8859-2 -t utf-8 "$i" -o utf8/"$i"
  done
}

# UTF-8 to ISO-8859-2 (Latin-2) subtitle conversion, converted files will be in the "latin2" folder.
# UTF-8 feliratok ISO-8859-2-re (Latin-2) konvertálása, a konvertált fájlok az "latin2" mappában lesznek.
# utf8tolatin2 [input]
# utf8tolatin2 xy.srt / latin2toutf8 *.srt
utf8tolatin2() {
  local i
  mkdir -p latin2
  for i in "$@"; do
    iconv -f utf-8 -t iso-8859-2 "$i" -o latin2/"$i"
  done
}

# extracts chapters from input mpls files
# kibontja a chaptereket a megadott input mpls fájlokból
chapterextract() {
  local i
  for i in "$@"; do
    mkvmerge -o chapter.mks -A -D -S -B -T -M --no-global-tags "$i"
    mkvextract chapters chapter.mks -s > "${i%.*}.txt"
  done
  rm chapter.mks
}

# generates a 4x15 thumbnail image
# egy 4x15-ös thumbnailt generál
thumbnailgen() {
  local tilex tiley width border images x b i c seconds interval framepos timestamp

  tilex=4
  tiley=15
  width=1600
  border=0
  images=$(( tilex * tiley ))

  mkdir -p thumb_temp

  for x in "$@"; do
    b=$(basename "$x")
    printf '\r%s\n' "$b"
    seconds=$(ffprobe "$x" -v quiet -print_format json -show_format | jq -r '.format.duration')
    interval=$(bc <<< "scale=4; $seconds/($images+1)")
    for i in $(seq -f '%03.0f' 1 "$images"); do
      framepos=$(bc <<< "scale=4; $interval*$i")
      timestamp=$(date -d"@$framepos" -u +%H\\:%M\\:%S)
      ffmpeg -y -v quiet -ss "$framepos" -i "$x" -frames:v 1 -vf "scale=$(( width / tilex )):-1, drawtext=fontsize=14:box=1:boxcolor=black:boxborderw=3:fontcolor=white:x=8:y=H-th-8:text='${timestamp}'" "thumb_temp/$i.bmp"
	  (( c++ ))
      printf '\rImages: %02d%% [%d/%d]' "$(bc <<< "$i*100/$images")" "$c" "$images"
    done
    montage thumb_temp/*bmp -tile "$tilex"x"$tiley" -geometry +"$border"+"$border" "${b%.*}_thumbnail.png"
  done
  printf '\n'
  rm -rf thumb_temp
}

# generates 12 images for each source
# 12 képet generál minden megadott forráshoz
imagegen() {
  local images x b i c seconds interval framepos

  images=12

  for x in "$@"; do
    b=$(basename "$x")
    printf '\r%s\n' "$b"
    seconds=$(ffprobe "$x" -v quiet -print_format json -show_format | jq -r '.format.duration')
    interval=$(bc <<< "scale=4; $seconds/($images+1)")
    for i in $(seq -f '%03.0f' 1 "$images"); do
      framepos=$(bc <<< "scale=4; $interval*$i")
      ffmpeg -y -v quiet -ss "$framepos" -i "$x" -frames:v 1 -q:v 100 -compression_level 6 "${b%.*}_$i.webp"
      (( c++ ))
	    printf '\rSaving images: %02d%% [%d/%d]' "$(bc <<< "$i*100/$images")" "$c" "$images"
    done
  done
  printf '\n'
}

dvdtomkv() {
  local help mode x i

  help=$(cat <<'EOF'
Usage: dvdtomkv -m [mode] [input(s)]
  inputs can be both folders or ISO files.

Options:

  -m [mode]      Sets mode. [series/movie]
                 In series mode the first title of each source (which is all the episodes in one)
                 will be skipped. In movie mode all titles of all sources will be remuxed.
                 (default: series)

Examples:

  dvdtomkv DVD1 DVD2
  dvdtomkv *.iso
EOF
  )

  while getopts ':hm:' OPTION; do
    case "$OPTION" in
      h) echo "$help"; return 0;;
      m) mode=$OPTARG;;
      *) echo "ERROR: Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done

  shift "$((OPTIND - 1))"

  if [[ $mode == series ]]; then dvdmode='1'
  elif [[ $mode == movie ]]; then dvdmode='0'
  else echo "ERROR: Unsupported DVD mode." >&2; return 1
  fi

  for x in "$@"; do
    mkdir -p out/"$x"
    if [[ $x == *.iso ]]; then
      title_number=$(makemkvcon info iso:"$x" | grep -c -E 'Title #.*was added')
      for i in $(seq "$dvdmode" "$(( title_number - 1 ))"); do
        makemkvcon mkv iso:"$x" "$i" out/"$x"
      done
    else
      title_number=$(makemkvcon info iso:"$x" | grep -c -E 'Title #.*was added')
      for i in $(seq "$dvdmode" "$(( title_number - 1 ))"); do
        makemkvcon mkv file:"$x" "$i" out/"$x"
      done
    fi
  done
}

audiostretch() {
  local args help from to mode channel threads factor i b samplerate soxsample logo starttime bitdepth

  help=$(cat <<'EOF'
Usage:
audiostretch [options] [input(s)]

Examples:
audiostretch input.mp2
audiostretch -c 6 input.ac3
audiostretch -m resample -f 24000/1001 -t 24 s01e*
audiostretch -l nf.wav input.mp2

Options:
-f [from fps]       Sets FPS of the input.
(default: 25)

-t [to fps]         Sets FPS of the output.
(default: 24000/1001)
Speed/tempo value will be calculated from "-f" and "-t".

-m [mode]           Sets mode. [tstretch/resample]
(default: tstretch) tstretch (also called as timestretch, or tempo in sox) stretches
                    the audio and applies pitch correction so the pitch stays the same.
                    resample (called as speed in sox) only stretches the audio
                    without applying pitch correction so the pitch will change.

-c [channel]        Sets number of channels for output. [2/6/8]
(default: 2)        2=2.0, 6=5.1, 8=7.1

-s [sample rate]    Sets same rate for output.
                    If you omit this the output's sample rate won't be changed.

-b [bit depth]      Sets bit depth for output.
(default: 24)

-j [threads]        Sets number of threads that will be used in order
(default: 4)        to parallelize the commands.

-l [logo]           Requires getlogotime: https://github.com/pcroland/getlogotime
                    Searches for logo/intro sound(s) and only stretches from there.
                    It can be a file or a folder containing the sounds.
EOF
  )

  from=25; to=24000/1001; mode=tstretch; channel=2; threads=4; bitdepth=24

  while getopts ':hf:t:m:c:j:s:b:l:' OPTION; do
    case "$OPTION" in
      h) echo "$help"; return 0;;
      f) from=$OPTARG;;
      t) to=$OPTARG;;
      m) mode=$OPTARG;;
      c) channel=$OPTARG;;
      j) threads=$OPTARG;;
      s) samplerate=$OPTARG;;
      b) bitdepth=$OPTARG;;
      l) logo=$OPTARG;;
      *) echo "ERROR: Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done

  shift "$((OPTIND - 1))"

  factor=$(bc <<< "scale=20; ($to)/($from)")

  if [[ "$channel" == 2 ]]; then outformat='wav'
  elif [[ "$channel" == 6 ]] || [[ "$channel" = 8 ]]; then outformat='w64'
  else echo "ERROR: Unsupported channel number." >&2; return 1
  fi

  if [[ $mode == tstretch ]]; then soxmode='tempo'
  elif [[ $mode == resample ]]; then soxmode='speed'
  else echo "ERROR: Unsupported mode." >&2; return 1
  fi

  if [[ -n "$samplerate" ]]; then
    soxsample="rate ${samplerate}"
  fi

  args=(--no-notice -j "$threads")
  if (( threads == 1 || $# == 1 )); then
    args+=(-u)
  fi

  for i in "$@"; do
    if [[ -n "$logo" ]]; then
      # shellcheck disable=SC2016
      # shellcheck disable=SC1003
      starttime=(' -ss $(getlogotime '"${i}" "${logo}"' | tr '\''\'\\r\' \''\'\\n\'' | tail -1)')
    else
      starttime=()
    fi
    b=$(basename "$i")
    # shellcheck disable=SC2128
    echo "ffmpeg${starttime} -i '$i' -v quiet -ac ${channel} -f sox - | sox -p -S -b $bitdepth '${b%.*}_as.${outformat}' ${soxmode} $factor $soxsample" >&2 | tee
  done | parallel "${args[@]}"
}

update_p10k() {
  # shellcheck disable=SC2154
  if [[ -n "$__p9k_root_dir" ]]; then
    git -C "$__p9k_root_dir" pull && exec zsh
  else
    echo "ERROR: powerlevel10k not found" >&2
    return 1
  fi
}

# downmixes inputs to stereo audios
# inputok stereora downmixelése
downmix() {
  local i
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -i "$i" -ac 2 -f sox - | sox -p -S -b 24 --norm=-0.1 "${b%.*}_dm.wav"
  done
}

# find forced tables
# forced táblák keresése
findforced() { grep -P -C2 '\b[A-Z]{2,}\b|♪' "$1"; }

# downloads dub links from list.txt
# szinkronok letöltése list.txt-ből
grabdub() { wget -i list.txt -P out -q --show-progress --trust-server-names --content-disposition --load-cookies cookies.txt; }

# uploads images to kek.sh
# képek feltöltése kek.sh-ra
keksh() {
  local i b
  for i in "$@"; do
    b=$(basename "$i")
    printf '%s: ' "$b"
    curl -fsSL https://kek.sh/api/v1/posts -F file="@$i" | jq -r '"https://i.kek.sh/\(.filename)"'
  done
}

# uploads files to x0.at
# fájlok feltöltése x0.at-re
x0() {
  local i b
  if (( $# == 0 )); then
    echo "$(curl -s -F "file=@-" "https://x0.at")"
  else
    for i in "$@"; do
      b=$(basename "$i")
      printf '%s: ' "$b"
      echo "$(curl -s -F "file=@${i}" "https://x0.at")"
    done
  fi
}

# uploads files to femto.pw
# fájlok feltöltése femto.pw-re
femto() {
  local i b
  if (( $# == 0 )); then
    echo "$(curl -s -F "upload=@-" https://v2.femto.pw/upload | jq -r '"https://femto.pw/\(.data.short)"')"
  else
    for i in "$@"; do
      b=$(basename "$i")
      printf '%s: ' "$b"
      echo "$(curl -s -F "upload=@$i" https://v2.femto.pw/upload | jq -r '"https://femto.pw/\(.data.short)"')"
    done
  fi
}

# creates a 90 seconds sample from input
# 90mp-es sample készítése input fájlból
createsample() { mkvmerge -o sample/sample.mkv --title sample --split parts:00:05:00-00:06:30 "$1"; }

# creates two files that compare2.exe can open and opens them
# you can set a start time for the second source with the third argument
# létrehoz két fájlt, amit compare2.exe kezelni tud, majd megnyitja őket
# harmadik opcióval megadható egy kezdési idő a második forrásnak
# examples:
# audiocomp eng.eac3 szinkron.mka
# audiocomp eng.eac3 szinkron.mka 10:15
audiocomp() {
  local starttime
  if [[ -n "$3" ]]; then
    starttime=(-ss "$3")
  else
    starttime=(-ss 0)
  fi
  ffmpeg -y -v quiet -i "$1" -ac 1 -c:a pcm_s16le -ar 48000 -t 10:00 audiocomp_orig.wav
  ffmpeg -y -v quiet "${starttime[@]}" -i "$2" -ac 1 -c:a pcm_s16le -ar 48000 -t 10:00 audiocomp_other.wav
  compare2.exe audiocomp_orig.wav audiocomp_other.wav
  rm audiocomp_*wav
}

# prints out dialnorm value for each minute in each input file
# kiírja a dialnorm értékeket minden perchez minden input fájlban
# examples:
# getdialnorm input.ac3
# getdialnorm *ac3
getdialnorm() {
  local i x b ss dialnorm newdialnorm
  for i in "$@"; do
    b=$(basename "$i")
    printf '%s:\n' "$b"
    seconds=$(ffprobe "$i" -v quiet -print_format json -show_format | jq -r '.format.duration')
    minutes=$(bc <<< "scale=0; $seconds/60")
    dialnorm=$(mediainfo "$i" --full | grep 'Dialog Normalization' | tail -1 | cut -c44-49)
    printf '  0 min: %s\n' "$dialnorm"
    [[ "$minutes" == 0 ]] && return 1
    for x in $(seq 1 "$minutes"); do
      ss="$x:00"
      ffmpeg -y -v quiet -ss "$ss" -i "$i" -t 0.1 -c copy getdialnorm.ac3
      newdialnorm=$(mediainfo getdialnorm.ac3 --full | grep 'Dialog Normalization' | tail -1 | cut -c44-49)
      if [[ "$newdialnorm" == "$dialnorm" ]]; then
        printf '\r%3s min: %s' "$x" "$newdialnorm"
      else
        dialnorm="$newdialnorm"
        printf '\r%3s min: %s\n' "$x" "$dialnorm"
      fi
    done
    printf '\33[2K\n'
  done
  rm getdialnorm.ac3
}

# prints out channel numbers for each minute in each input file
# kiírja a csatornák számát minden perchez minden input fájlban
# examples:
# getchannels input.ac3
# getchannels *ac3
getchannels() {
  local i x b ss channels newchannels
  for i in "$@"; do
    b=$(basename "$i")
    printf '%s:\n' "$b"
    seconds=$(ffprobe "$i" -v quiet -print_format json -show_format | jq -r '.format.duration')
    minutes=$(bc <<< "scale=0; $seconds/60")
    channels=$(mediainfo "$i" | grep 'Channel(s)' | cut -c 44-60)
    printf '  0 min: %s\n' "$channels"
    [[ "$minutes" == 0 ]] && return 1
    for x in $(seq 1 "$minutes"); do
      ss="$x:00"
      ffmpeg -y -v quiet -ss "$ss" -i "$i" -t 0.1 -c copy getchannels.ac3
      newchannels=$(mediainfo getchannels.ac3 | grep 'Channel(s)' | cut -c 44-60)
      if [[ "$newchannels" == "$channels" ]]; then
        printf '\r%3s min: %s' "$x" "$newchannels"
      else
        channels="$newchannels"
        printf '\r%3s min: %s\n' "$x" "$channels"
      fi
    done
    printf '\33[2K\n'
  done
  rm getchannels.ac3
}

# install / update pip, setuptools and wheel to the latest version
# pip, setuptools és wheel telepítése / frissítése a legújabb verzióra
update_pip() {
  pip install --upgrade pip setuptools wheel
}

# create pyenv virtualenv using global version or specified one
# pyenv virtualenv létrehozása globális vagy adott verzióval
# examples:
# pvenv
# pvenv 3.9.0
# pvenv 3.9.0 name
pvenv() (
  set -e

  version=${1:-$(pyenv global)}
  version=${version%% *}
  name=${2:-${PWD##*/}}

  echo "[+] Creating virtualenv $version/$name"
  pyenv virtualenv "$version" "$name"
  pyenv local "$name"

  echo '[+] Updating base packages'
  update_pip
)

# update pyenv virtualenv to global or specified version, keeping installed packages
# pyenv virtualenv frissítése globális vagy adott verzióra, telepített csomagok megtartásával
# examples:
# migrateenv
# migrateenv 3.9.0
migrateenv() (
  set -e

  tmpfile=$(mktemp /tmp/requirements.XXXXXXXXXX)

  echo "[+] Saving installed packages to $tmpfile"
  pip freeze >> "$tmpfile"

  echo '[+] Removing old virtualenv'
  pyenv uninstall -f "${PYENV_VIRTUAL_ENV##*/}"

  pvenv "$1"

  echo '[+] Reinstalling packages'
  pip install -r "$tmpfile"
  rm -f "$tmpfile"
)

winuptime() { uptime.exe | cut -c22-; }

decode_challenge() {
  curl -s 'https://integration.widevine.com/_/license_request' -H 'content-type: text/plain' --data-binary "${1:-$(cat)}" | tail +2 | jq
}

decode_license() {
  curl -s 'https://integration.widevine.com/_/license_response' -H 'content-type: text/plain' --data-binary "${1:-$(cat)}" | tail +2 | jq
}

decode_pssh() {
  curl -s 'https://integration.widevine.com/_/pssh_decode' -H 'content-type: text/plain' --data-binary "${1:-$(cat)}" | tail +2 | jq
}

cheatsh() {
  curl cheat.sh/"$1"
}

scat() {
  pygmentize -O style=native "$@"
}

showfunc() {
  declare -f "$1" | sed -r 's/\t/    /g; s/    /  /g' | scat -l sh
}

sleepuntilmidnight() {
  local seconds
  seconds=$(($(date -d "tomorrow 0:00" +%s) - $(date +%s)))
  echo "sleeping $seconds seconds"
  sleep "$seconds"
}

getranges() {
  local start
  local end

  while read -r num; do
    if [[ -z "$start" ]]; then
      start="$num"
    elif [[ -z "$end" ]] || (( num == end + 1 )); then
      end="$num"
    else
      printf '%d %d\n' "$start" "$end"
      start="$num"
      end=""
    fi
  done

  if [[ -n "$start" ]] && [[ -n "$end" ]]; then
    printf '%d %d\n' "$start" "$end"
  fi
}

crushpng() { oxipng --strip safe -i 0 "$@"; }
