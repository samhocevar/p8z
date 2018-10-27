
#include <vector>
#include <iostream>
#include <streambuf>
#include <cstdint>

extern "C" {
#include "zlib.h"
extern z_const char * const z_errmsg[] = {};
}

int main()
{
    std::vector<uint8_t> input;
    for (uint8_t ch : std::vector<char>{ std::istreambuf_iterator<char>(std::cin),
                                         std::istreambuf_iterator<char>() } )
        input.push_back(ch);

    // Prepare a vector twice as big... we don't really care.
    std::vector<uint8_t> output(input.size() * 2);

    z_stream zs = {};
    zs.zalloc = [](void *, unsigned int n, unsigned int m) -> void * { return new char[n * m]; };
    zs.zfree = [](void *, void *p) -> void { delete[] (char *)p; };
    zs.next_in = input.data();
    zs.next_out = output.data();
    zs.avail_in = (uInt)input.size();
    zs.avail_out = (uInt)output.size();
    
    deflateInit(&zs, Z_BEST_COMPRESSION);
    deflate(&zs, Z_FINISH);
    deflateEnd(&zs);

    fwrite(output.data() + 2, 1, zs.total_out - 6, stdout);
}

