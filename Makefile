

CPPFLAGS = -I./zlib -DP8Z -DZ_SOLO -DNO_GZIP -DHAVE_MEMCPY -Dlocal= -Os -g -ggdb -Wall -Wextra

all: p8z minify

clean:
	rm -f *.o .*.p8 p8z zlib/.zlib.*

p8z: p8z.o zlib/.zlib.o
	$(CXX) $(CPPFLAGS) $^ -o $@

minify: minify.cpp
	$(CXX) $(CPPFLAGS) $^ -o $@

p8z.o: p8z.cpp
	$(CXX) $(CPPFLAGS) -c $^ -o $@

zlib/.zlib.o: zlib/.zlib.c
	$(CC) $(CPPFLAGS) -c $^ -o $@

zlib/.zlib.c: zlib/deflate.c zlib/trees.c
	echo '#include <string.h>' > $@
	echo '#include <stdio.h>' >> $@
	#echo '#include "zlib.h"' >> $@
	echo '#include "zutil.h"' >> $@
	echo '#define adler32(...) 0' >> $@
	cat $^ >> $@

