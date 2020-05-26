# updating snippets
# snippetek frissítése
update_snippets() {
  file=$(curl -fsSL https://gist.githubusercontent.com/nyuszika7h/26759fadd3505138d6eb5926394ebd02/raw/update_snippets.sh | bash -s - --selfupdate | tee >&2 | tail -1 | cut -d' ' -f2)
  source "$file"
}

# renames mkv title to the filename
# mkv fájlok címét a fájlnévre írja át
mkvtitles() { for i in "$@"; do mkvpropedit "$i" -e info -s "title=${i%.mkv}"; done; }

# extracting iso file
# iso fájl kibontása
isoextract() { for i in "$@"; do 7z x "$i" -o"${i%.iso}"; done; }

# renames audio files that were demuxed with eac3to to a format that Dolby Media Producer understands
# eac3to-val demuxolt wavok átnevezése úgy, hogy Dolby Media Producer kezelje
renamewav() { for i in "$@"; do rename 's/SL/Ls/; s/SR/Rs/; s/BL/Lrs/; s/BR/Rrs/' "$i"; done; }

# uploading to sxcu
# sxcu-ra képfeltöltés
sxcu() {
  site=${SXCU_SITE:-sxcu.net}
  token=$SXCU_TOKEN

  while getopts 's:t:' OPTION; do
    case "$OPTION" in
      s) site=$OPTARG;;
      t) token=$OPTARG;;
      *) return 1;;
    esac
  done

  for i in "$@"; do
    curl -s -F "image=@$i" -F "token=$token" -F "noembed=1" "https://$site/upload" | jq -r .url
  done
}

# encoding aac from wav files
# aac kódolás wavból
# aacenc [input]
# aacenc xy.wav / aacenc *wav
aacenc() {
  for i in "$@"; do
    if [[ $i == *.wav ]]; then
      echo qaac64.exe -V 110 --no-delay --ignorelength -o "${i%.*}.m4a" "$i"
    else
      echo "ffmpeg -i '$i' -f wav - | qaac64.exe -V 100 --no-delay --ignorelength -o '${i%.*}.m4a' -"
    fi
  done | parallel --no-notice -j4
}

# ffmpeg frissítés
# updating ffmpeg
update_ffmpeg() { curl -s 'https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz' | tar -xJf - && sudo cp ffmpeg-git-*-amd64-static/{ffmpeg,ffprobe} /usr/local/bin && rm -rf ffmpeg-git-*-amd64-static; }

# spectrogram generation
# spektrogram készítés
spec() { for i in "$@"; do sox "$i" -n spectrogram -o "${i%.*}.png"; done; }

# AviSynth 2pass encode, the avs script can be written right in the command. The snippet contains settings, you only have to specify settings that you want to overwrite
# AviSynthes 2pass encode, az avs script magába a parancsba írható. A snippetben benne vannak a beállítások, csak azokat az opciókat kell megadni, amiket szeretnénk felülírni
# avsenc 'FFMS2("[source]").AutoResize("480")' --bitrate 1800 -- *mkv
avsenc() {
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

      channels_ffmpeg=($(ffmpeg -hide_banner -layouts | awk "\$1 == \"${channel_layout}\" { print \$2 }" | tr '+' ' '))
      channels_dmp=($(sed -r 's/\bF//g; s/\bS([LR])\b/\1s/g; s/\bB([LR])\b/\1rs/g' <<< "${channels_ffmpeg[*]}"))

      echo ${channels_ffmpeg[@]}
      echo ${channels_dmp[@]}

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
  local link
  local auth
  local auth_param
  local proto

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

  lynx "${auth_param[@]}" -hiddenlinks=ignore -listonly -nonumbers -dump "$link" | grep -Ev '\?|/$'
}

# downloading with aria2c
# több szálas letöltés aria2c-vel
fastgrab() {
  for url in "$@"; do
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

    aria2c -j 16 -x 16 -s 16 -Z "${auth[@]}" "$url"
  done
}
fastgrabdir() {
  fastgrab "$(getlinks "$1")"
}

# ISO-8859-2 (Latin-2) to UTF-8 subtitle conversion, original files will be in the "latin2" folder.
# ISO-8859-2 (Latin-2) feliratok UTF-8-ra konvertálása, az eredeti fájlok a "latin2" nevű mappában lesznek.
# latin2toutf8 [input]
# latin2toutf8 xy.srt / latin2toutf8 *.srt
latin2toutf8() {
  mkdir latin2
  for i in "$@"; do
    mv "$i" latin2/
    iconv -f iso-8859-2 -t utf-8 latin2/"$i" -o "$i"
  done
}

# generates a 4x15 thumbnail image
# egy 4x15-ös thumbnailt generál
thumbnailgen() {
  tilex=4
  tiley=15
  width=1600
  border=0
  images=$(( tilex * tiley ))
  [ -d thumb_temp ] || mkdir thumb_temp
  for x in "$@"; do
    for i in $(seq -f '%03.0f' 1 "$images"); do
      seconds=$(ffprobe -i $x -show_format -v quiet | sed -n 's/duration=//p')
      interval=$(bc <<< 'scale=4; '$seconds'/('$images'+1)')
      framepos=$(bc <<< 'scale=4; '$interval'*'$i'')
      ffmpeg -y -loglevel panic -ss "$framepos" -i "$x" -vframes 1 -vf scale=$(( width / tilex )):-1 "thumb_temp/$i.bmp"
    done
    montage thumb_temp/*bmp -tile "$tilex"x"$tiley" -geometry +"$border"+"$border" ${x%.*}_thumbnail.png
  done
  rm -rf thumb_temp
}

# extracts chapters from input mpls files
# kibontja a chaptereket a megadott input mpls fájlokból
chapterextract() {
  for i in "$@"; do
    mkvmerge -o chapter.mks -A -D -S -B -T -M --no-global-tags "$i"
    mkvextract chapters chapter.mks -s > ${i%.*}.txt
  done
  rm chapter.mks
}

# generates 10 images for each source
# 10 képet generál minden megadott forráshoz
imagegen() {
  images=5
  for x in "$@"; do
    for i in $(seq -f '%03.0f' 1 "$images"); do
      seconds=$(ffprobe -i $x -show_format -v quiet | sed -n 's/duration=//p')
      interval=$(bc <<< 'scale=4; '$seconds'/('$images'+1)')
      framepos=$(bc <<< 'scale=4; '$interval'*'$i'')
      ffmpeg -y -loglevel panic -ss "$framepos" -i "$x" -vframes 1 ${x%.*}_"$i".png
    done
  done
}
