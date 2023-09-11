#!/bin/bash

# updating snippets
# snippetek frissítése
update_snippets() {
  local file
  file=$(curl -fsSL https://raw.githubusercontent.com/encoding-hun/snippets/main/update_snippets.sh | bash -s - --selfupdate)
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
    echo "ffmpeg -i '$i' -v quiet -f wav - | qaac64.exe -V 110 --no-delay --ignorelength -o '${b%.*}.m4a' -" >&2 | tee
  done | parallel "${args[@]}"
}

# ffmpeg frissítés
# updating ffmpeg
update_ffmpeg() {
  if [[ $1 == -* ]]; then
    opt=$1
    shift
  fi

  type=${1:-release} # release, git
  if [[ $type == 'release' ]]; then
    dir='releases'
  else
    dir='builds'
  fi

  if [[ $opt != -l && $opt != --local && $(sudo -n -l sh) ]]; then
    sudo sh -c "curl -# 'https://johnvansickle.com/ffmpeg/${dir}/ffmpeg-${type}-amd64-static.tar.xz' | tar -C /usr/local/bin -xvJf - --strip 1 --wildcards '*/ffmpeg' '*/ffprobe'"
  else
    sh -c "curl -# 'https://johnvansickle.com/ffmpeg/${dir}/ffmpeg-${type}-amd64-static.tar.xz' | tar -C ~/.local/bin -xvJf - --strip 1 --wildcards '*/ffmpeg' '*/ffprobe'"
  fi
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
  -c [channel]   Sets number of channels. [1/2/6/8]

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

  if [[ $channel != 1 && $channel != 2 && $channel != 6 && $channel != 8 ]]; then
    echo "ERROR: Unsupported channel number." >&2; return 1
  fi

  for x in "$@"; do
    b=$(basename "$x")
    printf '%s: ' "$b"
    if [[ "$x" == *.wav ]] || [[ "$x" == *.w64 ]]; then
      sox "$x" -n spectrogram -x 1776 -Y 1080 -o "${b%.*}.png"
    else
      ffmpeg -y -v quiet -drc_scale 0 -i "$x" -ac "$channel" spec_temp.w64
      sox spec_temp.w64 -n spectrogram -x 1776 -Y 1080 -o "${b%.*}.png"
    fi
    curl -fsSL https://kek.sh/api/v1/posts -F file="@${b%.*}.png" | jq -r '"https://i.kek.sh/\(.filename)"'
    rm -f "${b%.*}.png"
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
    ffmpeg -drc_scale 0 -i "$i" \
    -filter_complex "channelsplit=channel_layout=5.1[FL][FR]" \
    -c:a pcm_s24le -map "[FL]" "${b%.*}"_L.wav \
    -c:a pcm_s24le -map "[FR]" "${b%.*}"_R.wav
  done
}

extract5.1() {
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -drc_scale 0 -i "$i" \
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
    ffmpeg -drc_scale 0 -i "$i" \
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

  local connections=128
  aria2c -x "$connections" &>/dev/null
  if [[ $? == 28 ]]; then
    # Unmodified aria2c build, can't handle more than 16 connections
    connections=16
  fi

  aria2c --auto-file-renaming=false --allow-overwrite=true --file-allocation=none -j "$connections" -x "$connections" -s "$connections" -Z "${auth[@]}" "$@"
}
fastgrabdir() {
  # shellcheck disable=SC2046
  fastgrab $(getlinks "$1")
}

# ANSI to UTF-8 subtitle conversion, converted files will be in the "utf8" folder.
# ANSI feliratok UTF-8-ra konvertálása, a konvertált fájlok az "utf8" mappában lesznek.
# ansitoutf8 [input]
# ansitoutf8 xy.srt / latin2toutf8 *.srt
ansitoutf8() {
  local i
  mkdir -p utf8
  for i in "$@"; do
    iconv -f windows-1250 -t utf-8 "$i" -o utf8/"$i"
  done
}

# UTF-8 to ANSI subtitle conversion, converted files will be in the "ansi" folder.
# UTF-8 feliratok ANSI-ra konvertálása, a konvertált fájlok az "ansi" mappában lesznek.
# utf8toansi [input]
# utf8toansi xy.srt / latin2toutf8 *.srt
utf8toansi() {
  local i
  mkdir -p ansi
  for i in "$@"; do
    iconv -f utf-8 -t windows-1250 "$i" -o ansi/"$i"
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

# generates 6 images for each source
# 6 képet generál minden megadott forráshoz
imagegen() {
  local images x b i c seconds interval framepos

  images=6

  for x in "$@"; do
    b=$(basename "$x")
    printf '\r%s\n' "$b"
    seconds=$(ffprobe "$x" -v quiet -print_format json -show_format | jq -r '.format.duration')
    interval=$(bc <<< "scale=4; $seconds/($images+1)")
    for i in $(seq -f '%03.0f' 1 "$images"); do
      framepos=$(bc <<< "scale=4; $interval*$i")
      ffmpeg -y -v quiet -ss "$framepos" -i "$x" -frames:v 1 "${b%.*}_$i.png"
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
    echo "ffmpeg${starttime} -drc_scale 0 -i '$i' -v quiet -ac ${channel} -f sox - | sox -p -S -b $bitdepth '${b%.*}_as.${outformat}' ${soxmode} $factor $soxsample" >&2 | tee
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
    ffmpeg -drc_scale 0 -i "$i" -ac 2 -f sox - | sox -p -S -b 24 --norm=-1 "${b%.*}_dm.wav"
  done
}

# find forced tables
# forced táblák keresése
findforced() { grep -P -C2 '\b[A-Z]{2,}\b|♪' "$1"; }

# downloads dub links from list.txt
# szinkronok letöltése list.txt-ből
grabdub() { wget -i "$1" -P out -q --show-progress --trust-server-names --content-disposition --load-cookies "$2"; }

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
    curl -s -F "file=@-" "https://x0.at"
  else
    for i in "$@"; do
      b=$(basename "$i")
      printf '%s: ' "$b"
      curl -s -F "file=@${i}" "https://x0.at"
    done
  fi
}

# uploads files to envs.sh
# fájlok feltöltése envs.sh-re
envs() {
  local i b
  if (( $# == 0 )); then
    curl -s -F "file=@-" "https://envs.sh"
  else
    for i in "$@"; do
      b=$(basename "$i")
      printf '%s: ' "$b"
      curl -s -F "file=@${i}" "https://envs.sh"
    done
  fi
}

ovpnto() {
  local i b
  if (( $# == 0 )); then
    curl -s -4 -F "fileToUpload=@-" -F "output=plain" -F "expire=1209600" -F "maxhits=0" https://up.ovpn.to/upload | sed -n '5,5p' | awk -v N=3 '{print $N}'
  else
    for i in "$@"; do
      b=$(basename "$i")
      printf '%s: ' "$b"
      curl -s -4 -F "fileToUpload=@$i" -F "output=plain" -F "expire=1209600" -F "maxhits=0" https://up.ovpn.to/upload | sed -n '5,5p' | awk -v N=3 '{print $N}'
    done
  fi
}

# creates a 90 seconds sample from input and saves it in a sample folder next to the input
# 90mp-es sample készítése input fájlból. az input mellé menti a fájlt egy sample mappába
createsample() {
  local i
  for i in "$@"; do
    mkvmerge -o "$(dirname "$i")"/sample/sample.mkv --title sample --split parts:00:05:00-00:06:30 "$i"
  done
}

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
  ffmpeg -y -v quiet -drc_scale 0 -i "$1" -ac 1 -c:a pcm_s16le -ar 48000 -t 10:00 audiocomp_orig.wav
  ffmpeg -y -v quiet -drc_scale 0 "${starttime[@]}" -i "$2" -ac 1 -c:a pcm_s16le -ar 48000 -t 10:00 audiocomp_other.wav
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

# install / update poetry to the latest version
# poetry telepítése / frissítése a legújabb verzióra
update_poetry() {
  pip uninstall -qq -y poetry  # remove other versions of poetry
  curl -fsSL https://install.python-poetry.org | python3 - "$@"
}

# update poetry virtualenv to a specific version from pyenv
# poetry virtualenv frissítése megadott verzióra pyenv-ből
poetry_use() {
  poetry env use ~/.pyenv/versions/"$1"/bin/python
  poetry install "${@:2}"
}

# install / update deew to the latest version
# deew telepítése / frissítése a legújabb verzióra
update_deew() {
  pip install deew --upgrade
}

# install / update to the latest version
# telepítés / frissítés a legújabb verzióra
update_vt() {
  git pull
  git submodule update --init
  poetry install
}

# update outdated Python libraries
# Python library-k frissítése
update_libs() {
  local up
  up=$(pip list --outdated)
  if [[ -z "$up" ]]; then
    echo "Nothing to update!"
  else
    echo "$up" | grep -v '^\-e' | cut -d = -f 1  | xargs -n1 pip install --upgrade
  fi
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

  if ! [[ -f poetry.lock || -f requirements.txt ]]; then
    tmpfile=$(mktemp /tmp/requirements.XXXXXXXXXX)

    echo "[+] Saving installed packages to $tmpfile"
    pip freeze >> "$tmpfile"
  fi

  echo '[+] Removing old virtualenv'
  pyenv uninstall -f "${PYENV_VIRTUAL_ENV##*/}"

  pvenv "$1"

  echo '[+] Reinstalling packages'

  if [[ -f poetry.lock ]]; then
    pyenv exec poetry install
  elif [[ -f requirements.txt ]]; then
    pip install -r requirements.txt
  else
    pip install -r "$tmpfile"
    rm -f "$tmpfile"
  fi
)

piprmall() {
  pip freeze | sed -r 's/\s*@.*//g' | xargs pip uninstall -y
}

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
  local body

  if [[ $0 == *bash* ]]; then
    body=${BASH_ALIASES[$1]}
    if [[ -z "$body" ]]; then
      body=$(declare -f "$1")
    fi
  else  # zsh
    body=$(whence -f "$1")
  fi

  printf '%s\n' "$body" | sed -r 's/\t/    /g; s/    /  /g' | scat -l sh
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

fixbranch() {
  git branch -m master main
  git fetch origin
  git branch -u origin/main main
  git remote set-head origin -a
}

nfocat() {
  local i
  for i in "$@"; do
    iconv -f CP437 -t UTF-8 "$i" -o nfo_temp.txt
    cat nfo_temp.txt
    rm nfo_temp.txt
  done
}

createtorrent() {
  local i
  for i in "$@"; do
    mktorrent -l 24 "$i"
  done
}

rclonesrv() {
  while true; do
    for f in ~/.config/rclone/srv*.json; do
      rclone --drive-service-account-file "$f" --drive-stop-on-upload-limit "$@" && break 2
    done
  done
}

# run a command at a specified time
# parancs futtatása egy megadott időben
# example:
# at 12:00 echo hello
at() {
  now=$(date +%s)
  d=$(date +%s --date="$1")

  if (( now > d )); then
    d=$(date +%s --date="tomorrow $1")
  fi

  seconds=$(( d - now ))

  echo "Running in ${seconds}s: ${*:2}"
  sleep "$seconds"
  "${@:2}"
}

# crop RPU on an existing DV or DV.HDR file
# RPU cropolása meglévő DV vagy DV.HDR fájlon
# example: dvcrop dvhdr.mkv
dvcrop() {
  if [[ $# -lt 1 ]]; then
    echo "ERROR: Not enough arguments" >&2
    echo "Usage: dvcrop input.mkv [output.mkv]" >&2
    return 1
  fi

  if [[ $# -gt 2 ]]; then
    echo "ERROR: Too many arguments" >&2
    echo "Usage: dvcrop input.mkv [output.mkv]" >&2
    return 1
  fi

  ffmpeg -i "$1" -map 0:v:0 -c:v copy -vbsf hevc_mp4toannexb -f hevc - | "$dovi_tool" "${args[@]}" -m 0 extract-rpu - -o temp_dv_cropped.bin
  mkvextract tracks "$1" 0:temp_dv.hevc
  dovi_tool demux temp_dv.hevc -b temp_hdr.hevc
  "$dovi_tool" inject-rpu -i temp_hdr.hevc --rpu-in temp_dv.bin -o temp_dv_cropped.hevc
  output=${2:-${1%.mkv}.cropped}
  output=${output%.mkv}
  language=$(mkvmerge -F json --identify "$1" | jq -r '.tracks[0].properties.language')
  mkvmerge -o "$output".mkv --title "$output" --language 0:"$language" temp_dv_cropped.hevc -D "$1"
  rm temp_dv* temp_hdr*
}

# merging DV and HDR into a single stream
# DV és HDR merge-dzselése egy streambe
# example: dvmerge dv.mkv hdr.mkv
dvmerge() {
  local args=()
  local crop=0

  if [[ $1 == -c || $1 == --crop ]]; then
    args+=(--crop)
    crop=1
    shift
  fi

  dovi_tool=$(command -v dovi_tool.exe || command -v dovi_tool)
  if [[ -z "$dovi_tool" ]]; then
    echo "ERROR: dovi_tool not found" >&2
    return 1
  fi

  if [[ $# -lt 2 ]]; then
    echo "ERROR: Not enough arguments" >&2
    echo "Usage: dvmerge dv.mkv hdr.mkv [dv.hdr.mkv]" >&2
    return 1
  fi

  if [[ $# -gt 3 ]]; then
    echo "ERROR: Too many arguments" >&2
    echo "Usage: dvmerge dv.mkv hdr.mkv [dv.hdr.mkv]" >&2
    return 1
  fi

  dv_res=$(mediainfo --Output=JSON "$1" | jq  -r '[.media.track[] | select(.["@type"] == "Video")][0] | "\(.Width)x\(.Height)"')
  hdr_res=$(mediainfo --Output=JSON "$2" | jq  -r '[.media.track[] | select(.["@type"] == "Video")][0] | "\(.Width)x\(.Height)"')

  if [[ "$dv_res" != "$hdr_res" ]] && ! (( crop )); then
    echo "ERROR: Resolutions are different (DV: $dv_res, HDR: $hdr_res), cannot merge." >&2
    return 1
  fi

  ffmpeg -i "$1" -map 0:v:0 -c:v copy -vbsf hevc_mp4toannexb -f hevc - | "$dovi_tool" "${args[@]}" -m 3 extract-rpu - -o temp_dv.bin
  mkvextract tracks "$2" 0:temp_hdr.hevc
  "$dovi_tool" inject-rpu -i temp_hdr.hevc --rpu-in temp_dv.bin -o temp_dv.hevc
  output=${3:-$(basename "${1%.*}" | sed 's/DV/DV.HDR/; s/DoVi/DoVi.HDR/')}
  output=${output%.mkv}
  language=$(mkvmerge -F json --identify "$1" | jq -r '.tracks[0].properties.language')
  mkvmerge -o "$output".mkv --title "$output" --language 0:"$language" temp_dv.hevc -D "$1"
  rm temp_dv* temp_hdr*
}

# remount Windows drive letters to /mnt/...
# Windows betűjelek újramountolása /mnt/... alá
remount() {
  lower=$(echo "$1" | tr '[:upper:]' '[:lower:]')
  upper=$(echo "$1" | tr '[:lower:]' '[:upper:]')
  sudo umount "/mnt/$lower"
  sudo mkdir -p "/mnt/$lower"
  sudo mount -t drvfs "$upper:" "/mnt/$lower"
}

createicon() {
  mkdir icon_temp
  for i in "$@"; do
    for r in 16 20 24 32 40 48 64 72 96 128 256; do
      convert "$i" -resize "$r"x"$r" icon_temp/"$r".png
    done
    convert icon_temp/16.png icon_temp/20.png icon_temp/24.png icon_temp/32.png icon_temp/40.png icon_temp/48.png icon_temp/64.png icon_temp/72.png icon_temp/96.png icon_temp/128.png icon_temp/256.png "${i%.*}.ico"
  done
  rm -rf icon_temp
}

# hdr10plus_tool frissítés
# updating hdr10plus_tool
update_hdr10plus_tool() {
  url=$(curl -s https://api.github.com/repos/quietvoid/hdr10plus_tool/releases/latest | jq -r '.assets[] | .browser_download_url | select(endswith("linux-musl.tar.gz"))') &&
  curl -sL "$url" | gzip -d | sudo tar --no-same-owner -C /usr/local/bin -xf - &&
  echo Update successful
  hdr10plus_tool --version
}

# dovi_tool frissítés
# updating dovi_tool
update_dovi_tool() {
  url=$(curl -s https://api.github.com/repos/quietvoid/dovi_tool/releases/latest | jq -r '.assets[] | .browser_download_url | select(endswith("linux-musl.tar.gz"))') &&
  curl -sL "$url" | gzip -d | sudo tar --no-same-owner -C /usr/local/bin -xf - &&
  echo Update successful
  dovi_tool --version
}

# edit a YAML file
# YAML fájl szerkesztése
yamledit() {
  yq -iyY --yml-out-ver=1.2 "$@"
}

# send notification to Telegram
# értesítés küldése Telegramra
tgnotify() (
  # shellcheck disable=SC1090
  source ~/.config/tgnotify/config || return

  if [[ -z "$TG_BOT_TOKEN" ]]; then
    echo "ERROR: Missing TG_BOT_TOKEN" >&2
    return 1
  fi

  if [[ -z "$TG_CHAT_ID" ]]; then
    echo "ERROR: Missing TG_CHAT_ID" >&2
    return 1
  fi

  curl -fsSL -o /dev/null "https://api.telegram.org/bot${TG_BOT_TOKEN}/sendMessage" -d "chat_id=${TG_CHAT_ID}" -d text="$*" -d "parse_mode=markdown"
)

scu() {
  systemctl --user "$@"
}

sc() {
  systemctl "$@"
}

rn() {
  if [ "$#" -lt 2 ]; then
    echo "Usage: \033[0;36mrn 's/from/to/' file(s)"; return 1
  fi

  search="$1"
  replace="$2"
  from=$(echo "$search" | sed 's#s/\([^/]*\)/.*#\1#')
  shift 1

  for file in "$@"; do
    newname=$(echo "$file" | sed "$search")
    if [ "$newname" != "$file" ]; then
      mv "$file" "$newname"
      printf "renaming \033[0;36m%s\033[0m -> \033[0;35m%s\033[0m...\n" "$(echo "$file" | sed "s/$from/$(printf '\033[0;35m')&$(printf '\033[0;36m')/g")" "$newname"
    fi
  done
}

# hola-proxy telepítése vagy frissítés
# installing or updating hola-proxy
update_hola_proxy() {
  if [[ $1 == -* ]]; then
    opt=$1
    shift
  fi

  url="https://github.com/Snawoot/hola-proxy/releases/latest/download/hola-proxy.linux-amd64"

  if [[ $opt != -l && $opt != --local && $(sudo -n -l sh) ]]; then
    if [ -f "/usr/local/bin/hola-proxy" ]; then
      sudo rm /usr/local/bin/hola-proxy
    fi
    sudo sh -c "curl -sL "$url" >> /usr/local/bin/hola-proxy"
    sudo chmod +x /usr/local/bin/hola-proxy
  else
    if [ -f "~/.local/bin/hola-proxy" ]; then
      rm ~/.local/bin/hola-proxy
    fi
    curl -sL "$url" >> ~/.local/bin/hola-proxy
    chmod +x ~/.local/bin/hola-proxy
  fi

  echo Successfully updated to $(hola-proxy -version)
}

# show ip address
# ip cím kiírása
myip() {
  curl -s ipinfo.io/json | jq
}

# fix env variable after sudo su login
# env variable javítása sudo su login után
fixlogin() {
  export XDG_RUNTIME_DIR=/run/user/$(id -u)
}
