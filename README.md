# p8z

A compression program targeting PICO-8, based on [deflate](https://en.wikipedia.org/wiki/DEFLATE),
with the following characteristics:

  * can decompress data from **cart RAM**, in **cart code**, or **both**.
  * data is decompressed in Lua memory, allowing for up to 2 MiB of data to exist.
  * the `p8u` decompressor code is optimised for **storage size**¹.

¹: this is slightly different from optimising for symbol count; `p8u` could use fewer
symbols but at the cost of larger stored size, which is actually less desirable.

### Technical details

The p8z algorithm differs from zlib’s original deflate in the following **incompatible** ways:

 * there is no zlib header or checksum (makes compressed data smaller)
 * block headers are smaller (helps reduce decoder code size)
 * the algorithm’s bit length code table was simplified (helps reduce decoder code size)
 * stored (uncompressed) blocks have no length checksum and are not byte-aligned (makes compressed data smaller)

### History

p8z uses code from [zlib](https://zlib.net/) and [zzlib](https://github.com/zerkman/zzlib).

