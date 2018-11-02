#!/bin/sh

PATH="$PATH:$HOME/zepto8"
PATH="$PATH:$HOME/pico-8"

TMPFILE=.p8z-temp.p8
EXTRA=2048

TOOL="z8tool --headless"
if [ "x$1" = "x--pico8" ]; then
  export DISPLAY=:0
  TMPFILE=.p8z-pico8.p8
  TOOL="pico8 -x"
fi

minify() {
  head -n 3 "$1"

#  cat "$1" | tail -n +4; return
  cat "$1" | tail -n +4 \
    | tr A-Z a-z \
    | sed 's/_ ",i,/Z/' \
    | grep -v -- "-- *debug" | sed 's/^  *//' | sed 's/ *--.*//' | grep . \
    | sed "$(echo mkhuf h do_block b methods f write w \
                  reverse r out o outpos op state e \
                  hlit hl hdist hd lit l dist d last l \
                  readback rb getb gb getv gv \
              | xargs -n 2 printf 's/\<%s\>/%s/g;')" \
    | sed 's/.*[-+*/%]=.*/X&X/' \
    | tr '\n' ' ' | sed 's/ *$//' | awk '{ print $0 }' \
    | sed 's/\(0\) \([g-wyz]\)/\1\2/g' \
    | sed 's/\([1-9]\) \([g-z]\)/\1\2/g' \
    | sed 's/ *X[ X]*/ /g' \
    | sed 's/ *\([][<>(){}-+*\/=:!~-]\) */\1/g' \
    | sed 's/Z/_ ",i,/'
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
  echo 'c=' >> "$TMPFILE"
  printf %s "$STR" | ./p8z >> "$TMPFILE"
  echo 't=inflate(c) x=0 for i=0,#t do x+=t[i] end printh("Uncompressed "..(4*(#t+1)).." Checksum "..tostr(x, true))' >> "$TMPFILE"
  out="$($TOOL "$TMPFILE")"
  case "$out" in Uncompressed*) echo "$out" ;; *) echo "ERROR! $out" ;; esac
}

test_file() {
  echo "# Compressing files: $*"
  minify p8z.p8 > "$TMPFILE.tmp"
  echo 'c=' >> "$TMPFILE.tmp"
  cat $* | ./p8z --count $EXTRA > "$TMPFILE.data"
  cat $* | ./p8z --skip $EXTRA >> "$TMPFILE.tmp"
  echo "t=inflate(c,0,$EXTRA) x=0 for i=0,#t do x+=t[i] end printh('Uncompressed '..(4*(#t+1))..' Checksum '..tostr(x, true))" >> "$TMPFILE.tmp"
  z8tool --data "$TMPFILE.data" "$TMPFILE.tmp" --top8 > "$TMPFILE"
  rm -f "$TMPFILE.tmp" "$TMPFILE.data"
  out="$($TOOL "$TMPFILE")"
  case "$out" in Uncompressed*) echo "$out" ;; *) echo "ERROR! $out" ;; esac
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

