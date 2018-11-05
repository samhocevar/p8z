pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

function inflate(s,p,l)
  -- free: m
  -- replaces: reverse z char_lut y
  -- replaces: state x bit_buffer w temp_buffer v sn u
  -- replaces: outpos g max_bits i
  -- replaces: build_huff_tree h

  -- this is valid because write() is called after all uses of bit_buffer,
  -- same for getb()/state, getv()/sn:
  -- replaces: getv u write w getb x

  -- init reverse array
  local reverse = {}
  for i=0,255 do
    reverse[i] = 0
    for j=0,7 do reverse[i]+=band(i,2^j)*128/4^j end
  end

  -- init char lookup method
  local char_lut = {}
  for i=1,58 do char_lut[sub("0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_ ",i,i)]=i end

  -- init stream reader
  local state = 0       -- 0: nothing in accumulator, 1: 2 chunks remaining, 2: 1 chunk remaining
  local bit_buffer = 0  -- bit buffer, starting from bit 0 (= 0x.0001)
  local temp_buffer = 0 -- temp chunk buffer
  local sn = 0          -- number of bits in buffer

  -- init stream writer
  local out = {}    -- output array
  local outpos = 1  -- output position, only used in write() and readback()

  -- get rid of n first bits
  local function flb(nbits)
    -- replaces: nbits i
    sn -= nbits
    bit_buffer = lshr(bit_buffer,nbits)
  end

  -- debug function to display hex numbers with minimal chars
  local function strx(nbits)                               -- debug
    local s = sub(tostr(nbits,1),3,6)                      -- debug
    while #s > 1 and sub(s,1,1) == "0" do s = sub(s,2) end -- debug
    return "0x"..s                                         -- debug
  end                                                      -- debug

  -- handle error reporting
  local function error(s) -- debug
    printh(s)             -- debug
    abort()               -- debug
  end                     -- debug

  -- peek n bits from the stream
  local function pkb(nbits)
    -- replaces: nbits i highbits j
    -- we need "while" instead of "do" because when reading
    -- from memory we may need more than one 8-bit run.
    while sn < nbits do
      -- not enough data in the stream:
      -- if there is still data in memory, read the next byte; otherwise
      -- unpack the next 8 characters of base59 data into 47 bits of
      -- information that we insert into bit_buffer in chunks of 16 or
      -- 15 bits.
      if l and l > 0 then
        bit_buffer += shr(peek(p),16-sn)
        sn += 8
        p += 1
        l -= 1
      elseif state == 0 then
        local e = 2^-16
        local highbits = {9,579} -- these are the higher bits (>=32) of 59^7 and 59^8
        local p = 0 temp_buffer = 0
        for i=1,8 do
          local c = char_lut[sub(s,i,i)] or 0
          temp_buffer += e%1*c
          p += (lshr(e,16) + (highbits[i-6] or 0))*c
          e *= 59
        end
        s = sub(s,9)
        bit_buffer += temp_buffer%1*2^sn
        sn += 16
        state += 1
        temp_buffer = p + shr(temp_buffer,16)
      elseif state == 1 then
        bit_buffer += temp_buffer%1*2^sn
        sn += 16
        state += 1
      else
        bit_buffer += lshr(temp_buffer,16)*2^sn
        sn += 15
        state = 0
      end
    end
    --printh("pkb("..nbits..") = "..strx(lshr(shl(bit_buffer,32-nbits),16-nbits)).." [bit_buffer = "..strx(shl(bit_buffer,16)).."]")
    return lshr(shl(bit_buffer,32-nbits),16-nbits)
    -- this cannot work because of getb(16)
    -- maybe bring this back if we disable uncompressed blocks
    --return band(shl(bit_buffer,16),2^nbits-1)
  end

  -- get a number of n bits from stream and flush them
  local function getb(nbits)
    -- replaces: nbits i
    return pkb(nbits),flb(nbits)
  end

  -- get next variable value from stream, according to huffman table
  local function getv(huff_tree)
    -- replaces: huff_tree i
    -- require at least n bits, even if only p<n bytes may be actually consumed
    pkb(huff_tree.max_bits)
    -- reverse using a 16-bit word
    -- fixme: maybe we could get rid of reversing in the encoder?
    local h = reverse[band(shl(bit_buffer,16),255)]
    local l = reverse[band(shl(bit_buffer,8),255)]
    local v = band(shr(256*h+l,16-huff_tree.max_bits),2^huff_tree.max_bits-1)
    flb(huff_tree[v]%1*16)
    return flr(huff_tree[v])
  end

  -- write 8 bits to the output, packed into a 32-bit number
  local function write(nbits)
    -- replaces: nbits i
    local d = (outpos)%1  -- the parentheses here help compressing the code!
    local p = flr(outpos)
    out[p]=nbits*256^(4*d-2)+(out[p]or 0)
    outpos+=1/4
  end

  -- read back 8 bits from the output, at offset -p
  local function readback(distance)
    -- replaces: distance i
    local d = (outpos-distance/4)%1
    local distance = flr(outpos-distance/4)
    return band(out[distance]/256^(4*d-2),255)
  end

  -- build a huffman table
  local function build_huff_tree(tree_desc)
    -- replaces: tree_desc i tree h
    local tree = {max_bits=1}
    -- fill c with the bit length counts
    local c = {}
    for i=1,17 do
      c[i] = 0
    end
    for j=1,#tree_desc do
      -- fixme: get rid of the local?
      local n = tree_desc[j]
      tree.max_bits = max(tree.max_bits,n)
      c[n+1] += 2 -- premultiply by 2
    end
    -- replace the contents of c with the next code lengths
    c[1]=0
    for i=2,tree.max_bits do
      c[i] += c[i-1]
      c[i] += c[i-1]
    end
    -- fill tree with the proper codes
    for j=1,#tree_desc do
      local l = tree_desc[j]
      if l > 0 then
        local c0 = shl(c[l],tree.max_bits-l)
        c[l] += 1
        local c1 = shl(c[l],tree.max_bits-l)
        if c1 > shl(1,tree.max_bits) then -- debug
          error("code error")             -- debug
        end                               -- debug
        for i=c0,c1-1 do
          tree[i] = j-1+l/16
        end
      end
    end
    return tree
  end

  -- decompress a block using the two huffman tables
  local function do_block(lit_tree, len_tree)
    -- replaces: lit_tree g len_tree i
    local lit
    repeat
      lit = getv(lit_tree)
      if lit < 256 then
        write(lit)
      elseif lit > 256 then
        lit -= 257
        local n = 0
        local size = 3
        local dist = 1
        if lit < 8 then
          size += lit
        elseif lit < 28 then
          n = flr(lit/4-1)
          size += shl(lit%4+4,n)
          size += getb(n)
        else
          size = 258
        end
        local v = getv(len_tree)
        if v < 4 then
          dist += v
        else
          n = flr(v/2-1)
          dist += shl(v%2+2,n)
          dist += getb(n)
        end
        for i = 1,size do
          write(readback(dist))
        end
      end
    until lit == 256
  end

  local methods = {}

  -- inflate dynamic block
  methods[2] = function()
    local tree_desc = {}
    local hlit = 257 + getb(5)
    local hdist = 1 + getb(5)
    local hclen = 4 + getb(4)
    for j=1,19 do
      -- the formula below differs from the original deflate
      tree_desc[(j+15)%19+1] = j>hclen and 0 or getb(3)
    end
    local z = build_huff_tree(tree_desc)
    tree_desc = {}
    local d2 = {}
    local c = 0
    while #tree_desc+#d2<hlit+hdist do
      local v = getv(z)
      if v >= 19 then                                                        -- debug
        error("wrong entry in depth table for literal/length alphabet: "..v) -- debug
      end                                                                    -- debug
      if v < 16 then c=v add(#tree_desc<hlit and tree_desc or d2,c) end
      if v == 16 then for j=-2,getb(2) do add(#tree_desc<hlit and tree_desc or d2,c) end end
      if v == 17 then c=0 for j=-2,getb(3) do add(#tree_desc<hlit and tree_desc or d2,c) end end
      if v == 18 then c=0 for j=-2,getb(7)+8 do add(#tree_desc<hlit and tree_desc or d2,c) end end
    end
    do_block(build_huff_tree(tree_desc),build_huff_tree(d2))
  end

  -- inflate static block
  methods[1] = function()
    local tree_desc = {}
    for j=1,288 do tree_desc[j]=8 end
    for j=145,280 do tree_desc[j]+=sgn(256-j) end
    local d2 = {}
    for j=1,32 do d2[j]=5 end
    do_block(build_huff_tree(tree_desc),build_huff_tree(d2))
  end

  -- inflate uncompressed byte array
  methods[0] = function()
    -- we do not align the input buffer to a byte boundary, because there
    -- is no concept of byte boundary in a stream we read in 47-bit chunks.
    -- also, we do not store the bit complement of the length value, it is
    -- not really important with such small data.
    for i=1,getb(16) do
      write(getb(8))
    end
  end

  -- block type 3 does not exist
  methods[3] = function()           -- debug
    error("unsupported block type") -- debug
  end                               -- debug

  while getb(1)>0 do
    methods[getb(2)]()
  end
  flb(sn%8)  -- debug (no need to flush!)

  return out
end

