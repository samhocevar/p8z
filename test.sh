#!/bin/sh

PATH="$PATH:$HOME/zepto8"
TMPFILE=.p8z-temp.p8

# Inspect p8z.p8 for stats
echo "# Inspecting: p8z.p8"
cat p8z.p8 | grep -v -- "-- *debug" | sed 's/^  *//' | sed 's/ *--.*//' | grep . > "$TMPFILE"
z8tool --inspect "$TMPFILE"
echo ""

# Check that the code works
test_string() {
  STR="$1"
  echo "# Compressing string: '$STR'"

  echo "### hexdump"
  printf %s "$STR" | od -v -An -x --endian=little | xargs -n2 | awk '{ print "0x"$2"."$1 }'

  echo "### PICO-8"
  cat p8z.p8 > "$TMPFILE"
  echo 'function error(m) printh("Error: "..tostr(m)) end c={' >> "$TMPFILE"
  # Compress and skip first two bytes (zlib header)
  printf %s "$STR" | zlib-flate -compress | od -v -An -t x1 -w1 \
      | tail -n +3 | while read i; do echo "0x$i,"; done | tr -d '\n' >> "$TMPFILE"
  echo '} t=inflate(c) printh("Compressed bytes "..#c) printh("Uncompressed "..(4*(#t+1))) for i=0,#t do printh(tostr(t[i], true)) end' >> "$TMPFILE"
  z8tool --headless "$TMPFILE"
}

test_file() {
  echo "# Compressing files: $*"
  cat p8z.p8 > "$TMPFILE"
  echo 'function error(m) printh("Error: "..tostr(m)) end c={' >> "$TMPFILE"
  # Compress and skip first two bytes (zlib header)
  cat $* | zlib-flate -compress | od -v -An -t x1 -w1 \
      | tail -n +3 | while read i; do echo "0x$i,"; done | tr -d '\n' >> "$TMPFILE"
  echo '} t=inflate(c) printh("Compressed bytes "..#c) printh("Uncompressed "..(4*(#t+1)))' >> "$TMPFILE"
  z8tool --headless "$TMPFILE"
}

test_string "to be or not to be"
test_string "to be or not to be or to be or maybe not to be or maybe finally to be..."
test_string "98398743287509834098332165732043059430973981643159327439827439217594327643982715432543"

find .. -name '*.p8' -o -name '*.p8.png' | head -n 1000 | while read i; do echo; echo "-- $i --"; ../z8tool --todata $i >| .tmp.p8; test_file .tmp.p8; done
test_file p8z.p8
test_file /etc/motd
#test_file data2 data2

#printf %s $STR | od -v -An -t x1 -w1000

#        (cat $(TMPDATA) | dd bs=1 skip=17152; echo '') | od -v -An -x --endian=little \
#          | xargs -n2 | awk '{ print "0x"$$2"."$$1"," }' | sed 's/0*,/,/ ; s/0x00*/0x/g' \
#          | xargs -n 6 | tr -d ' ' >> $(TMPCART2)

rm -f "$TMPFILE"

