#!/bin/sh

PATH="$PATH:$HOME/zepto8"

# Inspect p8z.p8 for stats
echo "# Inspecting: p8z.p8"
z8tool --inspect p8z.p8
echo ""

# Check that the code works
test_string() {
  TMPFILE=.p8z-temp.p8
  STR="$1"
  echo "# Compressing string: '$STR'"

  echo "### hexdump"
  printf %s "$STR" | od -v -An -x --endian=little | xargs -n2 | awk '{ print "0x"$2"."$1 }'

  echo "### PICO-8"
  cat p8z.p8 > "$TMPFILE"
  echo 'c={' >> "$TMPFILE"
  # Compress and skip first two bytes (zlib header)
  printf %s "$STR" | zlib-flate -compress | od -v -An -t x1 -w1 \
      | tail -n +3 | while read i; do echo "0x$i,"; done | tr -d '\n' >> "$TMPFILE"
  echo '} t=inflate(c) printh("Compressed bytes "..#c) printh("Uncompressed "..(4*(#t+1))) for i=0,#t do printh(tostr(t[i], true)) end' >> "$TMPFILE"
  z8tool --headless "$TMPFILE"
}

test_string "to be or not to be or to be or maybe not to be or maybe finally to be..."
#test_string "to be or not to be"

#printf %s $STR | od -v -An -t x1 -w1000

#        (cat $(TMPDATA) | dd bs=1 skip=17152; echo '') | od -v -An -x --endian=little \
#          | xargs -n2 | awk '{ print "0x"$$2"."$$1"," }' | sed 's/0*,/,/ ; s/0x00*/0x/g' \
#          | xargs -n 6 | tr -d ' ' >> $(TMPCART2)

