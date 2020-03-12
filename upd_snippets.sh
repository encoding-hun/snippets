#!/bin/bash

if [[ $SHELL == *bash* ]]; then
  shell='bash'
elif [[ $SHELL == *zsh* ]]; then
  shell='zsh'
else
  echo "ERROR: Unsupported shell: $shell" >&2
  exit 1
fi

echo "Updating snippets..."
tmpfile=$(mktemp snippets.XXXXXXXXXX)
curl -s https://cadoth.net/shell_snippets.txt -O "$tmpfile"

rcfile="$HOME/.${shell}rc"
snippets_file="$HOME/.${shell}_snippets"

if [[ -f "$snippets_file" ]]; then
  diff --color=always -u "$snippets_file" "$tmpfile"
fi

mv "$tmpfile" "$snippets_file"

if grep -q -F "$(basename "$snippets_file")" "$rcfile"; then
  echo "Found existing source line in $rcfile"
else
  echo "Adding source line to $rcfile"
  echo "source $snippets_file" >> "$rcfile"
fi

echo
echo "Done! Restart your shell or run:"
echo "\$ source $shellrc"