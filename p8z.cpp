
#include <vector>
#include <iostream>
#include <streambuf>
#include <cstdint>
#include <cstdlib>
#include <regex>

extern "C" {
#include "zlib.h"
extern z_const char * const z_errmsg[] = {};
}

std::string encode59(std::vector<uint8_t> const &v)
{
    char chr = '#';
    int const n = 28; // bits in a chunk
    int const p = 49; // alphabet size

    std::string ret;

    // Read all the data
    for (size_t pos = 0; pos < v.size() * 8; pos += n)
    {
        // Read a group of n bits
        uint64_t val = 0;
        for (size_t i = pos / 8; i <= (pos + n - 1) / 8 && i < v.size(); ++i)
            val |= (uint64_t)v[i] << ((i - pos / 8) * 8);
        val = (val >> (pos % 8)) & (((uint64_t)1 << n) - 1);

        // Convert those n bits to a string
        for (uint64_t k = p; k < 2 << n; k *= p)
        {
            ret += char(chr + val % p);
            val /= p;
        }
    }

    // Remove trailing zeroes
    while (ret.size() && ret.back() == chr)
        ret.erase(ret.end() - 1);

    return '"' + ret + '"';
}

int main(int argc, char *argv[])
{
    std::vector<uint8_t> input;
    for (uint8_t ch : std::vector<char>{ std::istreambuf_iterator<char>(std::cin),
                                         std::istreambuf_iterator<char>() })
        input.push_back(ch);

    // Prepare a vector twice as big... we don't really care.
    std::vector<uint8_t> output(input.size() * 2 + 10);

    z_stream zs = {};
    zs.zalloc = [](void *, unsigned int n, unsigned int m) -> void * { return new char[n * m]; };
    zs.zfree = [](void *, void *p) -> void { delete[] (char *)p; };
    zs.next_in = input.data();
    zs.next_out = output.data();
    zs.avail_in = (uInt)input.size();
    zs.avail_out = (uInt)output.size();
    
    deflateInit(&zs, Z_BEST_COMPRESSION);
    deflate(&zs, Z_FINISH);
    // Strip first 2 bytes (deflate header) and last 4 bytes (checksum)
    output = std::vector<uint8_t>(output.begin() + 2, output.begin() + zs.total_out - 4);
    deflateEnd(&zs);

    if (argc == 3 && argv[1] == std::string("--count"))
    {
        size_t count = atoi(argv[2]);
        fwrite(output.data(), 1, std::min(count, output.size()), stdout);
        return EXIT_SUCCESS;
    }

    if (argc == 3 && argv[1] == std::string("--skip"))
    {
        size_t skip = atoi(argv[2]);
        output.erase(output.begin(), output.begin() + std::min(skip, output.size()));
    }
    else if (argc != 1)
    {
        std::cerr << "Invalid arguments\n";
        return EXIT_FAILURE;
    }

    std::cout << encode59(output) << '\n';
    return EXIT_SUCCESS;
}

