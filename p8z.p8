pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

function inflate(s,p,l)
  -- init reverse array
  local reverse = {}
  for i=0,255 do
    reverse[i] = 0
    for j=0,7 do reverse[i]+=band(i,2^j)*128/4^j end
  end

  -- init char lookup method
  local lut = {}
  for i=1,58 do lut[sub("0123456789abcdefghijklmnopqrstuvwxyz!#%(){}[]<>+=/*:;.,~_ ",i,i)]=i end

  -- init stream reader
  local state = 0   -- 0: nothing in accumulator, 1: 2 chunks remaining, 2: 1 chunk remaining
  local sb = 0      -- bit buffer, starting from bit 0 (= 0x.0001)
  local sb2 = 0     -- temp chunk buffer
  local sn = 0      -- number of bits in buffer

  -- init stream writer
  local out = {}    -- output array
  local outpos = 1  -- output position

  -- get rid of n first bits
  local function flb(n)
    sn -= n
    sb = lshr(sb,n)
  end

  -- debug function to display hex numbers with minimal chars
  local function strx(n)                                   -- debug
    n = sub(tostr(n,1),3,6)                                -- debug
    while #n > 1 and sub(n,1,1) == "0" do n = sub(n,2) end -- debug
    return "0x"..n                                         -- debug
  end                                                      -- debug

  -- handle error reporting
  local function error(s) -- debug
    printh(s)             -- debug
    abort()               -- debug
  end                     -- debug

  -- peek n bits from the stream
  local function pkb(n)
    -- we need "while" instead of "do" because when reading
    -- from memory we may need more than one 8-bit run.
    while sn < n do
      -- not enough data in the stream:
      -- unpack the next 8 characters of base59 data into
      -- 47 bits of information that we insert into sb in
      -- chunks of 16 or 15 bits.
      if l and l > 0 then
        sb += shr(peek(p),16-sn)
        sn += 8
        p += 1
        l -= 1
      elseif state == 0 then
        local x = 2^-16
        local t = {9,579} -- these are the higher bits (>=32) of 59^7 and 59^8
        local p = 0 sb2 = 0
        for i=1,8 do
          local c = lut[sub(s,i,i)] or 0
          sb2 += x%1*c
          p += (lshr(x,16) + (t[i-6] or 0))*c
          x *= 59
        end
        s = sub(s,9)
        sb += sb2%1*2^sn
        sn += 16
        state += 1
        sb2 = p + shr(sb2,16)
      elseif state == 1 then
        sb += sb2%1*2^sn
        sn += 16
        state += 1
      else
        sb += lshr(sb2,16)*2^sn
        sn += 15
        state = 0
      end
    end
    --printh("pkb("..n..") = "..strx(lshr(shl(sb,32-n),16-n)).." [sb = "..strx(shl(sb,16)).."]")
    return lshr(shl(sb,32-n),16-n)
    -- this cannot work because of getb(16)
    -- maybe bring this back if we disable uncompressed blocks
    --return band(shl(sb,16),2^n-1)
  end

  -- get a number of n bits from stream and flush them
  local function getb(n)
    return pkb(n),flb(n)
  end

  -- get next variable value from stream, according to huffman table
  local function getv(t)
    -- require at least n bits, even if only p<n bytes may be actually consumed
    pkb(t.n)
    -- reverse using a 16-bit word
    -- fixme: maybe we could get rid of reversing in the encoder?
    local h = reverse[band(shl(sb,16),255)]
    local l = reverse[band(shl(sb,8),255)]
    local v = band(shr(256*h+l,16-t.n),2^t.n-1)
    flb(t[v]%1*16)
    return flr(t[v])
  end

  -- write 8 bits to the output, packed into a 32-bit number
  local function write(n)
    local d = (outpos)%1  -- the parentheses here help compressing the code!
    local p = flr(outpos)
    out[p]=n*256^(4*d-2)+(out[p]or 0)
    outpos+=1/4
  end

  -- read back 8 bits from the output, at offset -p
  local function readback(p)
    local d = (outpos-p/4)%1
    local p = flr(outpos-p/4)
    return band(out[p]/256^(4*d-2),255)
  end

  -- build a huffman table
  local function mkhuf(d)
    local t = {n=1}
    -- fill c with the bit length counts
    local c = {}
    for i=1,17 do
      c[i] = 0
    end
    for i=1,#d do
      local n = d[i]
      t.n = max(t.n,n)
      c[n+1] += 2 -- premultiply by 2
    end
    -- replace the contents of c with the next code lengths
    c[1]=0
    for i=2,t.n do
      c[i] += c[i-1]
      c[i] += c[i-1]
    end
    -- fill tree with the proper codes
    for i=1,#d do
      local l = d[i]
      if l > 0 then
        local c0 = shl(c[l],t.n-l)
        c[l] += 1
        local c1 = shl(c[l],t.n-l)
        if c1 > shl(1,t.n) then -- debug
          error("code error")   -- debug
        end                     -- debug
        for j=c0,c1-1 do
          t[j] = i-1+l/16
        end
      end
    end
    return t
  end

  -- decompress a block using the two huffman tables
  local function do_block(t1,t2)
    local lit
    repeat
      lit = getv(t1)
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
        local v = getv(t2)
        if v < 4 then
          dist += v
        else
          n = flr(v/2-1)
          dist += shl(v%2+2,n)
          dist += getb(n)
        end
        for n = 1,size do
          write(readback(dist))
        end
      end
    until lit == 256
  end

  local methods = {}

  -- inflate dynamic block
  methods[2] = function()
    local d = {}
    local hlit = 257 + getb(5)
    local hdist = 1 + getb(5)
    local hclen = 4 + getb(4)
    for i=1,19 do
      -- the formula below differs from the original deflate
      d[(i+15)%19+1] = i>hclen and 0 or getb(3)
    end
    local t = mkhuf(d)
    d = {}
    local d2 = {}
    local c = 0
    while #d+#d2<hlit+hdist do
      local v = getv(t)
      if v >= 19 then                                                        -- debug
        error("wrong entry in depth table for literal/length alphabet: "..v) -- debug
      end                                                                    -- debug
      if v < 16 then c=v add(#d<hlit and d or d2,c) end
      if v == 16 then for j=-2,getb(2) do add(#d<hlit and d or d2,c) end end
      if v == 17 then c=0 for j=-2,getb(3) do add(#d<hlit and d or d2,c) end end
      if v == 18 then c=0 for j=-2,getb(7)+8 do add(#d<hlit and d or d2,c) end end
    end
    do_block(mkhuf(d),mkhuf(d2))
  end

  -- inflate static block
  methods[1] = function()
    local d = {}
    for i=1,288 do d[i]=8 end
    for i=145,280 do d[i]+=sgn(256-i) end
    local d2 = {}
    for i=1,32 do d2[i]=5 end
    do_block(mkhuf(d),mkhuf(d2))
  end

  -- inflate uncompressed byte array
  methods[0] = function()
    -- align input buffer to byte (as per spec)
    -- fixme: we could omit this!
    flb(sn%8)
    if sn%8 != 0 then                                                -- debug
      error("unexpected.. should be zero remaining bits in buffer.") -- debug
    end                                                              -- debug
    local len = getb(16)
    local nlen = getb(16)
    if bxor(len,nlen) != -1 then        -- debug
      error("len and nlen don't match") -- debug
    end                                 -- debug
    for i=1,len do
      write(getb(8))
    end
  end

  -- block type 3 does not exist
  methods[3] = function()           -- debug
    error("unsupported block type") -- debug
  end                               -- debug

  repeat
    local last = getb(1)
    methods[getb(2)]()
  until last == 1
  flb(sn%8)  -- debug (no need to flush!)

  return out
end

