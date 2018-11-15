#!/bin/sh

PATH="$PATH:$HOME/zepto8"
PATH="$PATH:$HOME/pico-8"

TMPFILE=.p8z-temp.p8
EXTRA=2048

TOOL="z8tool --headless"
while [ -n "$1" ]; do
  case "$1" in
    --pico8)
      export DISPLAY=:0
      TMPFILE=.p8z-pico8.p8
      TOOL="pico8 -x"
      ;;
    --no-minify)
      NO_MINIFY=1
      ;;
  esac
  shift
done

minify() {
  head -n 3 "$1"
  if [ -n "$NO_MINIFY" ]; then cat "$1" | tail -n +4; return; fi
  ./minify < "$1"
}

# Inspect p8z.p8 for stats
echo "# Inspecting: p8z.p8"
minify p8z.p8 > "$TMPFILE"
z8tool --inspect "$TMPFILE"
echo "printh('Cart code: valid')" >> "$TMPFILE"
$TOOL "$TMPFILE"
echo ""

# Check that the code works
test_common() {
  minify p8z.p8 > "$TMPFILE.tmp"
  echo 'c=' >> "$TMPFILE.tmp"
  cat $* | ./p8z --count $EXTRA > "$TMPFILE.data"
  cat $* | ./p8z --skip $EXTRA >> "$TMPFILE.tmp"
  echo "t=p8u(c,0,$EXTRA) x=0 for i=1,#t do x+=t[i] end printh('Uncompressed '..(4*#t)..' Checksum '..tostr(x, true)) if puts and #t < 128 then puts(t) end" >> "$TMPFILE.tmp"
  z8tool --data "$TMPFILE.data" "$TMPFILE.tmp" --top8 > "$TMPFILE"
  rm -f "$TMPFILE.tmp" "$TMPFILE.data"
  out="$($TOOL "$TMPFILE")"
  case "$out" in Uncompressed*) echo "$out" ;; *) echo "ERROR! $out" ;; esac
}

test_string() {
  STR="$1"
  echo "# Compressing string: '$STR'"
  printf '%s' "$STR" >| "$TMPFILE"
  test_common "$TMPFILE"
}

test_file() {
  echo "# Compressing file: $1"
  test_common "$@"
}

test_string ""
test_string "ABCD"
test_string "11112222333344445555"
test_string "21112222333344445555211122223333444455552111222233334444555511112222333344445555"
test_string "to be or not to be or to be or maybe not to be or maybe finally to be..."
test_string "98398743287509834098332165732043059430973981643159327439827439217594327643982715432543"

find ../payloads -type f | tail -n +1 | while read i; do test_file $i; done

#printf %s $STR | od -v -An -t x1 -w1000

#        (cat $(TMPDATA) | dd bs=1 skip=17152; echo '') | od -v -An -x --endian=little \
#          | xargs -n2 | awk '{ print "0x"$$2"."$$1"," }' | sed 's/0*,/,/ ; s/0x00*/0x/g' \
#          | xargs -n 6 | tr -d ' ' >> $(TMPCART2)

rm -f "$TMPFILE"

