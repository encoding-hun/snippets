#!/bin/bash

if [[ $SHELL == *bash* ]]; then
  shell='bash'
elif [[ $SHELL == *zsh* ]]; then
  shell='zsh'
else
  printf 'ERROR: Unsupported shell: %s\n' "$shell" >&2
  exit 1
fi

printf 'Updating snippets...\n'
tmpfile=$(mktemp snippets.XXXXXXXXXX)
curl -fsSL https://gist.githubusercontent.com/nyuszika7h/26759fadd3505138d6eb5926394ebd02/raw/snippets.sh -o "$tmpfile"

rcfile="$HOME/.${shell}rc"
snippets_file="$HOME/.${shell}_snippets"

printf '\n'
if [[ -f "$snippets_file" ]]; then
  if diff -q "$snippets_file" "$tmpfile" >/dev/null; then
    printf '\e[32mAlready up to date\e[0m\n'
  else
    diff --color=always -u "$snippets_file" "$tmpfile"
  fi
else
  diff --color=always -u "/dev/null" "$tmpfile"
fi
printf '\n'

printf 'Saving snippets to %s\n' "$snippets_file"
mv "$tmpfile" "$snippets_file"

if grep -q -F "$(basename "$snippets_file")" "$rcfile"; then
  printf 'Found existing source line in %s\n' "$rcfile"
else
  printf 'Adding source line to %s\n' "$rcfile"
  printf 'source %s\n' "$snippets_file" >> "$rcfile"
fi

printf '\nDone! Restart your shell or run:\n'
printf '$ \e[1msource %s\e[0m\n' "$rcfile"
