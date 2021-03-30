#!/bin/bash

shell=$(cat "/proc/$PPID/comm" 2>/dev/null)
detect_shell() {
  if [[ $shell == *bash* ]]; then
    shell='bash'
  elif [[ $shell == *zsh* ]]; then
    shell='zsh'
  else
    if [[ "$shell" == "$SHELL" ]]; then
      printf 'ERROR: Unsupported shell: %s\n' "$shell" >&2
      exit 1
    else
      shell=$SHELL
      detect_shell
    fi
  fi
}
detect_shell
printf 'Detected shell as %s\n\n' "$shell" >&2

printf 'Updating snippets...\n' >&2
tmpfile=$(mktemp "${TMPDIR:-/tmp}/snippets.XXXXXXXXXX")
curl -fsSL https://raw.githubusercontent.com/nyuszika7h/snippets/main/snippets.sh -o "$tmpfile"

rcfile="$HOME/.${shell}rc"
snippets_file="$HOME/.${shell}_snippets"

needs_source=1

printf '\n' >&2
if [[ -f "$snippets_file" ]]; then
  if diff -q "$snippets_file" "$tmpfile" >/dev/null; then
    printf '\e[32mAlready up to date\e[0m\n' >&2
    needs_source=0
  else
    diff --color=always -u "$snippets_file" "$tmpfile" >&2
  fi
else
  diff --color=always -u "/dev/null" "$tmpfile" >&2
fi
printf '\n' >&2

if (( needs_source )); then
  printf 'Saving snippets to %s\n' "$snippets_file" >&2
  mv "$tmpfile" "$snippets_file"
else
  rm -f "$tmpfile"
fi

if grep -q -F "$(basename "$snippets_file")" "$rcfile"; then
  printf 'Found existing source line in %s\n' "$rcfile" >&2
else
  printf 'Adding source line to %s\n' "$rcfile" >&2
  printf 'source %s\n' "$snippets_file" >> "$rcfile"
fi

printf '\nDone!' >&2

if (( needs_source )); then
  if [[ $1 == '--selfupdate' ]]; then
    printf '%s' "$rcfile"
    printf '\n' >&2
  else
    printf ' Restart your shell or run:\n' >&2
    printf '$ \e[1msource %s\e[0m\n' "$rcfile" >&2
  fi
else
  printf '\n' >&2
fi
