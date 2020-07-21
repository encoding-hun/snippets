#!/bin/bash

# updating snippets
# snippetek frissítése
update_snippets() {
  local file
  file=$(curl -fsSL https://raw.githubusercontent.com/nyuszika7h/snippets/master/update_snippets.sh | bash -s - --selfupdate | tee >&2 | tail -1 | cut -d' ' -f2)
  # shellcheck disable=SC1090
  source "$file"
}

# run exe files from WSL without .exe suffix
# exe fájlok futtatása WSL-ből .exe végződés nélkül
command_not_found_handle() {
  local PATHEXT readopt pathext ext command shell
  if [[ $1 != *.* && -x "$(command -v cmd.exe)" ]]; then
    PATHEXT=$(cmd.exe /c 'echo %PATHEXT%' 2>/dev/null)

    [[ -n "$BASH_VERSION" ]] && readopt='-a'
    [[ -n "$ZSH_VERSION" ]] && readopt='-A'

    while IFS=';' read -r "${readopt?}" pathext; do
      for ext in "${pathext[@]}"; do
        if [[ -x "$(command -v "$1$ext")" ]]; then
          command=$1$ext
          break
        fi
      done
    done <<< "$PATHEXT"
  fi

  if [[ -n "$command" ]]; then
    shift
    "$command" "$@"
  elif [[ -x /usr/share/command-not-found/command-not-found ]]; then
    /usr/share/command-not-found/command-not-found -- "$1"
  elif [[ -x /usr/lib/command-not-found ]]; then
    /usr/lib/command-not-found -- "$1"
  else
    [[ -n "$BASH_ARGV0" ]] && shell=${BASH_ARGV0#-}
    [[ -n "$ZSH_ARGZERO" ]] && shell=${ZSH_ARGZERO#-}
    printf '%s: command not found: %s\n' "$shell" "$1"
    return 127
  fi
}

command_not_found_handler() { command_not_found_handle "$@"; }

# renames mkv title to the filename
# mkv fájlok címét a fájlnévre írja át
mkvtitles() { local i; for i in "$@"; do mkvpropedit "$i" -e info -s "title=${i%.mkv}"; done; }

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
  local i b 
  for i in "$@"; do
    b=$(basename "$i")
    if [[ $i == *.wav ]]; then
      echo qaac64.exe -V 110 --no-delay --ignorelength -o "${b%.*}.m4a" "$i"
    else
      echo "ffmpeg -i '$i' -f wav - | qaac64.exe -V 110 --no-delay --ignorelength -o '${b%.*}.m4a' -"
    fi
  done | parallel --no-notice -j4
}

# ffmpeg frissítés
# updating ffmpeg
update_ffmpeg() {
  sudo sh -c "curl -# 'https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz' | tar -C /usr/local/bin -xvJf - --wildcards '*/ffmpeg' '*/ffprobe'"
}

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
    echo -n "$b: "
    ffmpeg -y -loglevel panic -i "$x" -ac "$channel" spec_temp.w64
    sox spec_temp.w64 -n spectrogram -x 1776 -Y 1080 -o "${b%.*}.png"
    keksh "${b%.*}.png"
  done
  rm spec_temp.w64
}

# AviSynth 2pass encode, the avs script can be written right in the command. The snippet contains settings, you only have to specify settings that you want to overwrite
# AviSynthes 2pass encode, az avs script magába a parancsba írható. A snippetben benne vannak a beállítások, csak azokat az opciókat kell megadni, amiket szeretnénk felülírni
# avsenc 'FFMS2("[source]").AutoResize("480")' --bitrate 1800 -- *mkv
avsenc() {
  local avs_script x264_opts arg f

  avs_script=$1
  shift

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

# extracting sounds to mono wav files
# hang szétbontása wav fájlokra
extractmono() {
  (
    command -v emulate >/dev/null && emulate bash

    for f in "$@"; do
      channel_layout=$(ffprobe -v error -show_entries stream=channel_layout -of csv=p=0 "$1" | sed '/^$/d')

      if [[ $channel_layout == 'unknown' && $f != *.wav ]]; then
        wav=${f%.*}.wav
        ffmpeg -hide_banner -i "$f" -map 0:a:0 "$wav" -y && echo && extractmono "$wav" && rm -f "$wav"
        continue
      fi

      [[ -n "$BASH_VERSION" ]] && readopt='-a'
      [[ -n "$ZSH_VERSION" ]] && readopt='-A'

      while read -r "${readopt?}" channel; do
        channels_ffmpeg+=("$channel")
        channels_dmp+=("$(sed -r 's/^F//g; s/^S([LR])$/\1s/g; s/^B([LR])$/\1rs/g' <<< "$channel")")
      done < <(ffmpeg -hide_banner -layouts | awk "\$1 == \"${channel_layout}\" { print \$2 }" | tr '+' ' ')

      num_channels=${#channels_ffmpeg[@]}

      params=(-filter_complex "channelsplit=channel_layout=${channel_layout}")
      for c in "${channels_ffmpeg[@]}"; do
        params[1]+="[$c]"
      done

      for i in $(seq 0 "$(( num_channels - 1 ))"); do
        params+=(-c:a pcm_s24le -map "[${channels_ffmpeg[i]}]" "${f%.*}_${channels_dmp[i]}.wav")
      done

      ffmpeg -hide_banner -i "$f" "${params[@]}" -y
    done
  )
}

# extracting links from a link pointing to a directory
# mappára mutató linkből visszadja a fájlok linkjeit
getlinks () {
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

# ISO-8859-2 (Latin-2) to UTF-8 subtitle conversion, original files will be in the "latin2" folder.
# ISO-8859-2 (Latin-2) feliratok UTF-8-ra konvertálása, az eredeti fájlok a "latin2" nevű mappában lesznek.
# latin2toutf8 [input]
# latin2toutf8 xy.srt / latin2toutf8 *.srt
latin2toutf8() {
  mkdir -p latin2
  local i
  for i in "$@"; do
    mv "$i" latin2/
    iconv -f iso-8859-2 -t utf-8 latin2/"$i" -o "$i"
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
  local tilex tiley width border images x b i seconds interval framepos timestamp

  tilex=4
  tiley=15
  width=1600
  border=0
  images=$(( tilex * tiley ))

  mkdir -p thumb_temp

  for x in "$@"; do
    b=$(basename "$x")
    for i in $(seq -f '%03.0f' 1 "$images"); do
      seconds=$(ffprobe -i "$x" -show_format -v quiet | sed -n 's/duration=//p')
      interval=$(bc <<< "scale=4; $seconds/($images+1)")
      framepos=$(bc <<< "scale=4; $interval*$i")
      timestamp=$(date -d"@$framepos" -u +%H\\:%M\\:%S)
      ffmpeg -y -loglevel panic -ss "$framepos" -i "$x" -vframes 1 -vf "scale=$(( width / tilex )):-1, drawtext=fontsize=14:box=1:boxcolor=black:boxborderw=3:fontcolor=white:x=8:y=H-th-8:text='${timestamp}'" "thumb_temp/$i.bmp"
      echo -ne "Thumbnails: $(bc <<< "$i*100/$images")%\\r"
    done
    echo -ne 'Merging images...\r'
    montage thumb_temp/*bmp -tile "$tilex"x"$tiley" -geometry +"$border"+"$border" "${b%.*}_thumbnail.png"
  done

  rm -rf thumb_temp
}

# generates 12 images for each source
# 12 képet generál minden megadott forráshoz
imagegen() {
  local images x b i seconds interval framepos

  images=12

  for x in "$@"; do
    b=$(basename "$x")
    for i in $(seq -f '%03.0f' 1 "$images"); do
      seconds=$(ffprobe -i "$x" -show_format -v quiet | sed -n 's/duration=//p')
      interval=$(bc <<< "scale=4; $seconds/($images+1)")
      framepos=$(bc <<< "scale=4; $interval*$i")
      ffmpeg -y -loglevel panic -ss "$framepos" -i "$x" -vframes 1 "${b%.*}_$i.png"
      echo -ne "Images: $(bc <<< "$i*100/$images")%\\r"
    done
  done
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
  local help from to mode channel threads factor i b

  help=$(cat <<'EOF'
Usage: audiostretch [options] [input(s)]

Options:

  -f [from fps]  Sets input file(s)' FPS.
                 (default: 25)

  -t [to fps]    Sets output file(s)' FPS.
                 (default: 24000/1001)

  -m [mode]      Sets mode. [tstretch/resample]
                 tstretch (also called as timestretch, or tempo in sox) stretches
                 the audio and applies pitch correction so the pitch stays the same.
                 resample (called as speed in sox) only stretches the audio
                 without applying pitch correction so the pitch will change.
                 (default: tstretch)

  -c [channel]   Sets number of channels. [2/6]
                 2=2.0
                 6=5.1
                 (default: 2)

  -j [threads]   Sets number of threads that will be used in order
                 to parallelize the commands.
                 (default: 4)

Examples:

  audiostretch input.mp2
  audiostretch -c 6 input.ac3
  audiostretch -m resample -f 25 -t 24 *.aac
EOF
  )

  from=25; to=24000/1001; mode=tstretch; channel=2; threads=4

  while getopts ':hf:t:m:c:j:' OPTION; do
    case "$OPTION" in
      h) echo "$help"; return 0;;
      f) from=$OPTARG;;
      t) to=$OPTARG;;
      m) mode=$OPTARG;;
      c) channel=$OPTARG;;
      j) threads=$OPTARG;;
      *) echo "ERROR: Invalid option: -$OPTARG" >&2; return 1;;
    esac
  done

  shift "$((OPTIND - 1))"

  factor=$(bc <<< "scale=20; ($to)/($from)")

  if [[ $channel == 2 ]]; then outformat='wav'
  elif [[ $channel == 6 ]]; then outformat='w64'
  else echo "ERROR: Unsupported channel number." >&2; return 1
  fi

  if [[ $mode == tstretch ]]; then soxmode='tempo'
  elif [[ $mode == resample ]]; then soxmode='speed'
  else echo "ERROR: Unsupported mode." >&2; return 1
  fi

  for i in "$@"; do
    b=$(basename "$i")
    echo "ffmpeg -i '$i' -loglevel warning -ac ${channel} -f sox - | sox -p -S -b 24 '${b%.*}.${outformat}' ${soxmode} $factor"
  done

  for i in "$@"; do
    b=$(basename "$i")
    echo "ffmpeg -i '$i' -loglevel warning -ac ${channel} -f sox - | sox -p -S -b 24 '${b%.*}.${outformat}' ${soxmode} $factor"
  done | parallel --no-notice -j "$threads"
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

downmix() {
  local i
  for i in "$@"; do
    b=$(basename "$i")
    ffmpeg -i "$i" -ac 2 -f sox - | sox -p -S -b 24 --norm=-0.1 "${b%.*}.wav"
  done
}

findforced() { grep -P -C2 '\b[A-Z]{2,}\b|♪' "$1"; }

grabdub() { wget -i list.txt -P out -q --show-progress --trust-server-names --content-disposition --load-cookies cookies.txt; }

keksh() {
  for f in "$@"; do
    curl -fsSL https://kek.sh/api/v1/posts -F file="@$f" | jq -r '"https://i.kek.sh/\(.filename)"'
  done
}
