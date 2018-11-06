pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

-- strategy for minifying (renaming variables):
--
-- rename functions, in order of appearance:
--   replaces: flush_bits f
--   replaces: peek_bits h
--   replaces: get_bits x
--   replaces: getv u
--   replaces: write_byte w
--   replaces: readback_byte a    (todo)
--   replaces: build_huff_tree h  (no conflict with peek_bits)
--   replaces: do_block b         (todo)
--
-- rename local variables in functions to the same name
-- as their containing functions:
--   replaces: tree h (in build_huff_tree)
-- or not:
--   replaces: symbol l     (local variable in do_block)
--
-- first, we rename some internal variables:
--   replaces: char_lut y methods y  (no conflict)
--   replaces: state x               (valid because always used before get_bits)
--   replaces: bit_buffer w          (valid because always used before write_byte)
--   replaces: temp_buffer v
--   replaces: available_bits u      (valid because always used before getv)
--   replaces: output_pos g
--
-- "i" is typically used for function arguments, sometimes "g":
--   replaces: nbits i          (first argument of get_bits/peek_bits/flush_bits)
--   replaces: byte i           (first argument of write_byte)
--   replaces: distance i       (first arg of readback_byte)
--   replaces: huff_tree i      (first arg of getv)
--   replaces: tree_desc i      (first arg of build_huff_tree)
--   replaces: lit_tree_desc i  (only appears after tree_desc is no longer used)
--   replaces: len_tree_desc q
--   replaces: lit_tree g       (first arg of do_block, no conflict with output_pos)
--   replaces: len_tree i       (second arg of do_block)
--
-- this is not a local variable but a table member, however
-- the string "i=1" appears just after it is initialised, so
-- we can save one byte by calling it "i" too:
--   replaces: max_bits i
--
-- we can also rename this because "j" is only used as
-- a local variable in functions that do not use output_buffer:
--   replaces: output_buffer j
--
-- not cleaned yet:
--   replaces: dist d size r
--   replaces: code o c1 m
--
-- free: l z

function inflate(s, p, l)
  -- init stream reader
  local state = 0           -- 0: nothing in accumulator, 1: 2 chunks remaining, 2: 1 chunk remaining
  local bit_buffer = 0      -- bit buffer, starting from bit 0 (= 0x.0001)
  local available_bits = 0  -- number of bits in buffer
  local temp_buffer = 0     -- temp chunk buffer

  -- init stream writer
  local output_buffer = {} -- output array (32-bit numbers)
  local output_pos = 1     -- output position, only used in write_byte() and readback_byte()

  -- get rid of n first bits
  local function flush_bits(nbits)
    available_bits -= nbits
    bit_buffer = lshr(bit_buffer, nbits)
  end

  -- debug function to display hex numbers with minimal chars
  local function strx(nbits)                                  -- debug
    local s = sub(tostr(nbits, 1), 3, 6)                      -- debug
    while #s > 1 and sub(s, 1, 1) == "0" do s = sub(s, 2) end -- debug
    return "0x"..s                                            -- debug
  end                                                         -- debug

  -- handle error reporting
  local function error(s) -- debug
    printh(s)             -- debug
    abort()               -- debug
  end                     -- debug

  -- init lookup table for peek_bits()
  --  - indices 1 and 2 are the higher bits (>=32) of 59^7 and 59^8
  --    used to compute these powers
  --  - string indices are for char -> byte lookups; the order in the
  --    base string is not important but we exploit it to make our
  --    compressed code shorter
  local char_lut = { 9, 579 }
  for i = 1, 58 do char_lut[sub("y={9,570123468functio[lshrabdegjkmpqvwxz!#%()]}<>+/*:;.~_ ", i, i)] = i end

  -- peek n bits from the stream
  local function peek_bits(nbits)
    -- we need "while" instead of "do" because when reading
    -- from memory we may need more than one 8-bit run.
    while available_bits < nbits do
      -- not enough data in the stream:
      -- if there is still data in memory, read the next byte; otherwise
      -- unpack the next 8 characters of base59 data into 47 bits of
      -- information that we insert into bit_buffer in chunks of 16 or
      -- 15 bits.
      if l and l > 0 then
        bit_buffer += shr(peek(p), 16 - available_bits)
        available_bits += 8
        p += 1
        l -= 1
      elseif state == 0 then
        local e = 2^-16
        local p = 0 temp_buffer = 0
        for i = 1, 8 do
          local c = char_lut[sub(s, i, i)] or 0
          temp_buffer += e % 1 * c
          p += (lshr(e, 16) + (char_lut[i - 6] or 0)) * c
          e *= 59
        end
        s = sub(s, 9)
        bit_buffer += temp_buffer % 1 * 2 ^ available_bits
        available_bits += 16
        state += 1
        temp_buffer = p + shr(temp_buffer, 16)
      elseif state == 1 then
        bit_buffer += temp_buffer % 1 * 2 ^ available_bits
        available_bits += 16
        state += 1
      else
        bit_buffer += lshr(temp_buffer, 16) * 2 ^ available_bits
        available_bits += 15
        state = 0
      end
    end
    --printh("peek_bits("..nbits..") = "..strx(lshr(shl(bit_buffer, 32-nbits), 16-nbits))
    --       .." [bit_buffer = "..strx(shl(bit_buffer, 16)).."]")
    return lshr(shl(bit_buffer, 32 - nbits), 16 - nbits)
    -- this cannot work because of get_bits(16)
    -- maybe bring this back if we disable uncompressed blocks?
    --return band(shl(bit_buffer, 16), 2 ^ nbits - 1)
  end

  -- get a number of n bits from stream and flush them
  local function get_bits(nbits)
    return peek_bits(nbits), flush_bits(nbits)
  end

  -- get next variable value from stream, according to huffman table
  local function getv(huff_tree)
    -- require at least n bits, even if only p<n bytes may be actually consumed
    local j = peek_bits(huff_tree.max_bits)
    flush_bits(huff_tree[j] % 1 * 16)
    return flr(huff_tree[j])
  end

  -- write_byte 8 bits to the output, packed into a 32-bit number
  local function write_byte(byte)
    local d = (output_pos) % 1  -- the parentheses here help compressing the code!
    local p = flr(output_pos)
    output_buffer[p] = byte * 256 ^ (4 * d - 2) + (output_buffer[p] or 0)
    output_pos += 1 / 4
  end

  -- read back 8 bits from the output, at offset -p
  local function readback_byte(distance)
    local d = (output_pos - distance / 4) % 1
    local distance = flr(output_pos - distance / 4)
    return band(output_buffer[distance] / 256 ^ (4 * d - 2), 255)
  end

  -- build a huffman table
  local function build_huff_tree(tree_desc)
    local tree = { max_bits = 1 }
    -- fill c with the bit length counts
    local c = {}
    for j = 1, 17 do
      c[j] = 0
    end
    for j = 1, #tree_desc do
      -- fixme: get rid of the local?
      local n = tree_desc[j]
      tree.max_bits = max(tree.max_bits, n)
      c[n+1] += 2 -- premultiply by 2
    end
    -- replace the contents of c with the next code lengths
    c[1] = 0
    for j = 2, tree.max_bits do
      c[j] += c[j-1]
      c[j] += c[j-1]
    end
    -- fill tree with the possible codes, pre-flipped so that we do not
    -- have to reverse every chunk we read.
    for j = 1, #tree_desc do
      local l = tree_desc[j]
      if l > 0 then
        -- flip the first l bits of c[l]
        local code = 0
        for j = 1, l do code += shl(band(shr(c[l], j - 1), 1), l - j) end
        -- store all possible n-bit values that end with flip(c[l])
        while code < 2 ^ tree.max_bits do
          tree[code] = j - 1 + l / 16
          code += 2 ^ l
        end
        -- point to next code of length l
        c[l] += 1
      end
    end
    return tree
  end

  -- decompress a block using the two huffman tables
  local function do_block(lit_tree, len_tree)
    local symbol
    repeat
      symbol = getv(lit_tree)
      if symbol < 256 then
        write_byte(symbol)
      elseif symbol > 256 then
        symbol -= 257
        local n = 0
        local size = 3
        local dist = 1
        if symbol < 8 then
          size += symbol
        elseif symbol < 28 then
          n = flr(symbol / 4 - 1)
          size += shl(symbol % 4 + 4, n)
          size += get_bits(n)
        else
          size += 255
        end
        local v = getv(len_tree)
        if v < 4 then
          dist += v
        else
          n = flr(v / 2 - 1)
          dist += shl(v % 2 + 2, n)
          dist += get_bits(n)
        end
        for i = 1, size do
          write_byte(readback_byte(dist))
        end
      end
    until symbol == 256
  end

  local methods = {}

  -- inflate dynamic block
  methods[2] = function()
    -- replaces: lit_count l len_count y desc_len k
    local tree_desc = {}
    local lit_count = 257 + get_bits(5)
    local len_count = 1 + get_bits(5)
    local desc_len = 4 + get_bits(4)
    for j = 1, 19 do
      -- the formula below differs from the original deflate
      tree_desc[(j + 15) % 19 + 1] = j > desc_len and 0 or get_bits(3)
    end
    local z = build_huff_tree(tree_desc)
    local lit_tree_desc = {}
    local len_tree_desc = {}
    local c = 0
    while #lit_tree_desc + #len_tree_desc < lit_count + len_count do
      local v = getv(z)
      if v >= 19 then                                                        -- debug
        error("wrong entry in depth table for literal/length alphabet: "..v) -- debug
      end                                                                    -- debug
      -- it is legal to precompute z here because the trees are read separately
      -- (see send_all_trees() in zlib/trees.c)
      local z = #lit_tree_desc < lit_count and lit_tree_desc or len_tree_desc
      if v < 16  then c = v add(z, c) end
      if v == 16 then       for j = -2, get_bits(2)     do add(z, c) end end
      if v == 17 then c = 0 for j = -2, get_bits(3)     do add(z, c) end end
      if v == 18 then c = 0 for j = -2, get_bits(7) + 8 do add(z, c) end end
    end
    do_block(build_huff_tree(lit_tree_desc),
             build_huff_tree(len_tree_desc))
  end

  -- inflate static block
  methods[1] = function()
    local lit_tree_desc = {}
    local len_tree_desc = {}
    for j = 1, 288 do lit_tree_desc[j] = 8 end
    for j = 145, 280 do lit_tree_desc[j] += sgn(256 - j) end
    for j = 1, 32 do len_tree_desc[j] = 5 end
    do_block(build_huff_tree(lit_tree_desc),
             build_huff_tree(len_tree_desc))
  end

  -- inflate uncompressed byte array
  methods[0] = function()
    -- we do not align the input buffer to a byte boundary, because there
    -- is no concept of byte boundary in a stream we read in 47-bit chunks.
    -- also, we do not store the bit complement of the length value, it is
    -- not really important with such small data.
    for i = 1, get_bits(16) do
      write_byte(get_bits(8))
    end
  end

  -- block type 3 does not exist
  methods[3] = function()           -- debug
    error("unsupported block type") -- debug
  end                               -- debug

  while get_bits(1) > 0 do
    methods[get_bits(2)]()
  end
  flush_bits(available_bits % 8)  -- debug (no need to flush!)

  return output_buffer
end

