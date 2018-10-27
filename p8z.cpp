
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
    std::vector<uint8_t> data;
    for (uint8_t ch : std::vector<char>{ std::istreambuf_iterator<char>(std::cin),
                                         std::istreambuf_iterator<char>() } )
        data.push_back(ch);

    std::vector<uint8_t> dest(data.size() * 2);

    z_stream zs = {};
    zs.zalloc = [](void *, unsigned int n, unsigned int m) -> void * { return new char[n * m]; };
    zs.zfree = [](void *, void *p) -> void { delete[] (char *)p; };
    zs.next_in = (Bytef *)data.data();
    zs.next_out = (Bytef *)dest.data();
    zs.avail_in = (uInt)data.size();
    zs.avail_out = (uInt)dest.size();
    
    deflateInit(&zs, Z_BEST_COMPRESSION);
    deflate(&zs, Z_FINISH);
    deflateEnd(&zs);

    fwrite(dest.data(), 1, zs.total_out, stdout);
}

