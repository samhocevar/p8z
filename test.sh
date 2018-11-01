#!/bin/sh

PATH="$PATH:$HOME/zepto8"
PATH="$PATH:$HOME/pico-8"

export DISPLAY=:0
TMPFILE=.p8z-temp.p8
TOOL="z8tool --headless"
if [ "x$1" = "x--pico8" ]; then
  TMPFILE=.p8z-temp2.p8
  TOOL="pico8 -x"
fi

minify() {
  head -n 3 "$1"
#  cat "$1" | tail -n +4; return
  cat "$1" | tail -n +4 \
    | sed 's/_ ",i,/PROTECTME/' \
    | grep -v -- "-- *debug" | sed 's/^  *//' | sed 's/ *--.*//' | grep . \
    | tr '\n' ' ' | sed 's/ *$//' | awk '{ print $0 }' \
    | sed 's/ *\([][<>(){}-+*\/=:!~-]\) */\1/g' \
    | sed 's/\(0\) \([g-wyz]\)/\1\2/g' \
    | sed 's/\([1-9]\) \([g-z]\)/\1\2/g' \
    | tr ' ' '\n' \
    | sed 's/PROTECTME/_ ",i,/'
}

# Inspect p8z.p8 for stats
echo "# Inspecting: p8z.p8"
minify p8z.p8 > "$TMPFILE"
z8tool --inspect "$TMPFILE"
echo "printh('Cart code: valid')" >> "$TMPFILE"
$TOOL "$TMPFILE"
echo ""

# Check that the code works
test_string() {
  STR="$1"
  echo "# Compressing string: '$STR'"

  echo "### hexdump"
  printf %s "$STR" | od -v -An -x --endian=little | xargs -n2 | awk '{ print "0x"$2"."$1 }'

  echo "### PICO-8"
  minify p8z.p8 > "$TMPFILE"
  echo 'function error(m) printh("Error: "..tostr(m)) end c=' >> "$TMPFILE"
  printf %s "$STR" | ./p8z >> "$TMPFILE"
  echo 't=inflate(c) x=0 for i=0,#t do x+=t[i] end printh("Compressed "..#c.." Uncompressed "..(4*(#t+1)).." Checksum "..tostr(x, true))' >> "$TMPFILE"
  out="$($TOOL "$TMPFILE")"
  case "$out" in Compressed*) echo "$out" ;; *) echo "ERROR! $out" ;; esac
}

test_file() {
  echo "# Compressing files: $*"
  minify p8z.p8 > "$TMPFILE"
  echo 'function error(m) printh("Error: "..tostr(m)) end c=' >> "$TMPFILE"
  cat $* | ./p8z >> "$TMPFILE"
  echo 't=inflate(c) x=0 for i=0,#t do x+=t[i] end printh("Compressed "..#c.." Uncompressed "..(4*(#t+1)).." Checksum "..tostr(x, true))' >> "$TMPFILE"
  out="$($TOOL "$TMPFILE")"
  case "$out" in Compressed*) echo "$out" ;; *) echo "ERROR! $out" ;; esac
}

test_string "to be or not to be"
test_string "to be or not to be or to be or maybe not to be or maybe finally to be..."
test_string "98398743287509834098332165732043059430973981643159327439827439217594327643982715432543"

find ../payloads -type f | tail -n +1 | while read i; do test_file $i; done

#printf %s $STR | od -v -An -t x1 -w1000

#        (cat $(TMPDATA) | dd bs=1 skip=17152; echo '') | od -v -An -x --endian=little \
#          | xargs -n2 | awk '{ print "0x"$$2"."$$1"," }' | sed 's/0*,/,/ ; s/0x00*/0x/g' \
#          | xargs -n 6 | tr -d ' ' >> $(TMPCART2)

rm -f "$TMPFILE"

