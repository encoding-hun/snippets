# snippetek frissítése
update_snippets() { curl -fsSL https://gist.githubusercontent.com/nyuszika7h/26759fadd3505138d6eb5926394ebd02/raw/update_snippets.sh | bash -; }

# mkv fájlok címét a fájlnévre írja át
mkvtitles() { for i in "$@"; do mkvpropedit "$i" -e info -s "title=${i%.mkv}"; done; }

# iso fájl kibontása
isoextract() { for i in "$@"; do 7z x "$i" -o"${i%.iso}"; done; }

# eac3to-val demuxolt wavok átnevezése úgy, hogy dolby media procuder kezelje
renamewav() { for i in "$@"; do rename 's/SL/Ls/; s/SR/Rs/; s/BL/Lrs/; s/BR/Rrs/' "$i"; done; }

# sxcu-ra képfeltöltés
sxcu() {
  site=${SXCU_SITE:-sxcu.net}
  token=$SXCU_TOKEN

  while getopts 's:t:' OPTION; do
    case $OPTION in
      s) site=$OPTARG;;
      t) token=$OPTARG;;
      *) exit 1;;
    esac
  done

  for i in "$@"; do
    curl -s -F "image=@$i" -F "token=$token" -F "noembed=1" "https://$site/upload" | jq -r .url
  done
}

# aac kódolás wavból
# aacenc [input]
aacenc() { for i in "$@"; do qaac64.exe -V 100 --no-delay --ignorelength -o "${i%.*}.m4a" "$i"; done; }

# ffmpeg frissítés
update_ffmpeg() { curl -s 'https://johnvansickle.com/ffmpeg/builds/ffmpeg-git-amd64-static.tar.xz' | tar -xJf - && sudo cp ffmpeg-git-*-amd64-static/{ffmpeg,ffprobe} /usr/local/bin && rm -rf ffmpeg-git-*-amd64-static; }

# spektrogram készítés
spec() { for i in "$@"; do sox "$i" -n spectrogram -o "${i%.*}.png"; done; }

# AviSynthes 2pass encode, az avs script magába a
# parancsba írható. A snippetben benne vannak a
# beállítások, csak azokat az opciókat kell megadni,
# amiket szeretnénk felülírni, példa:
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

# 7.1 hang szétbontása wav fájlokra
extract7.1() {
    (
    command -v emulate >/dev/null && emulate bash
    channels=(FL FR FC LFE BL BR SL SR)
    params=(-filter_complex "channelsplit=channel_layout=7.1")

    for c in "${channels[@]}"; do
        params[1]+="[$c]"
    done

    for c in "${channels[@]}"; do
        params+=(-c:a pcm_s24le -map "[$c]" "$c.wav")
    done

    ffmpeg "${params[@]}"
    )
}

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

# több szálas letöltés aria2c-vel
fastgrab() {
    if [[ $1 == *cadoth.net* ]]; then
        auth=("--http-user=encoding" "--http-passwd=REDACTED")
    fi
    aria2c -j 16 -x 16 -s 16 -Z "$@"
}

# több szálas letöltés aria2c-vel
fastgrabdir() {
    fastgrab "$(getlinks "$1")"
}
