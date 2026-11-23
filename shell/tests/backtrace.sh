#!/bin/sh
# Turn crash backtraces in gosaab-wm logs into function names and file:line.
bin=$1; shift
cat "$@" 2>/dev/null | grep -oE 'gosaab-wm\((\+0x[0-9a-f]+)?\) \[0x[0-9a-f]+\]' | while read -r frame; do
  case "$frame" in
    *"(+"*) addr=$(echo "$frame" | sed -E 's/.*\(\+(0x[0-9a-f]+)\).*/\1/') ;;
    *) addr=$(echo "$frame" | sed -E 's/.*\[(0x[0-9a-f]+)\]/\1/') ;;
  esac
  addr2line -f -C -i -p -e "$bin" "$addr"
done | head -40
