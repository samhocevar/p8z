pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

function inflate(data)
  local reverse = {}

  -- init reverse array
  for i=0,255 do
    local k=0
    for j=0,7 do k+=band(i,2^j)*128/4^j end
    reverse[i] = k
  end

  local pos = 1     -- input char buffer index
  local sb = 0      -- bit buffer, starting from bit 0 (= 0x.0001)
  local sn = 0      -- number of bits in buffer
  local out = {}    -- output array
  local outpos = 0  -- output position

  -- get rid of n first bits
  local function flb(n)
    sn -= n
    sb = shr(sb,n)
  end

  local function pkb(n)
    while sn < n do
      sb += shr(data[pos],16-sn)
      pos += 1
      sn += 8
    end
    return band(shl(sb,16),2^n-1)
  end

  -- get a number of n bits from stream
  local function getb(n)
    return pkb(n),flb(n)
  end

  -- get next variable-size of maximum size=n element from stream, according to huffman table
  local function getv(t,n)
    -- require at least n bits, even if p<n bytes may be actually consumed
    pkb(n)
    -- reverse using a 16-bit word
    -- fixme: maybe we could get rid of reversing in the encoder?
    local h = reverse[band(shl(sb,16),255)]
    local l = reverse[band(shl(sb,8),255)]
    local v = band(shr(256*h+l,16-n),2^n-1)
    flb(t[v]%16)
    return flr(t[v]/16)
  end

  local function write(n)
    local d = (outpos)%1  -- the parentheses here help compressing the code!
    local p = flr(outpos)
    out[p]=n*256^(4*d-2)+(out[p]or 0)
    outpos+=1/4
  end

  local function readback(p)
    local d = (outpos+p/4)%1
    local p = flr(outpos+p/4)
    return band(out[p]/256^(4*d-2),255)
  end

  -- build a huffman table
  local function construct(table,depths)
    local bl_count = {}
    local nbits = 1
    for i=1,17 do
      bl_count[i] = 0
    end
    for i=1,#depths do
      local d = depths[i]
      nbits = max(nbits,d)
      bl_count[d+1] += 1
    end
    local code = 0
    local next_code = {}
    bl_count[1] = 0
    for i=1,nbits do
      code = (code + bl_count[i]) * 2
      next_code[i] = code
    end
    for i=1,#depths do
      local len = depths[i] or 0
      if len > 0 then
        local code0 = shl(next_code[len],nbits-len)
        next_code[len] += 1
        local code1 = shl(next_code[len],nbits-len)
        if code1 > shl(1,nbits) then -- debug
          error("code error")        -- debug
        end                          -- debug
        for j=code0,code1-1 do
          table[j] = (i-1)*16 + len
        end
      end
    end
    return nbits
  end

  local methods = {}
  local littable = {}
  local disttable = {}

  local function inflate_block_loop(nlit,ndist)
    local lit
    repeat
      lit = getv(littable,nlit)
      if lit < 256 then
        write(lit)
      elseif lit > 256 then
        lit -= 257
        local nbits = 0
        local size = 3
        local dist = 1
        if lit < 8 then
          size += lit
        elseif lit < 28 then
          nbits = flr(lit/4)-1
          size += shl(lit%4+4,nbits)
          size += getb(nbits)
        else
          size = 258
        end
        local v = getv(disttable,ndist)
        if v < 4 then
          dist += v
        else
          nbits = flr(v/2-1)
          dist += shl(v%2+2,nbits)
          dist += getb(nbits)
        end
        for n = 1,size do
          write(readback(-dist))
        end
      end
    until lit == 256
  end

  -- inflate dynamic block
  methods[2] = function()
    local litdepths = {}
    local distdepths = {}
    local depths = {}
    local lengthtable = {}
    local hlit = 257 + getb(5)
    local hdist = 1 + getb(5)
    local hclen = 4 + getb(4)
    for i=1,19 do
      -- the formula below differs from the original deflate
      depths[(i+15)%19+1] = i>hclen and 0 or getb(3)
    end
    local nlen = construct(lengthtable,depths)
    local i=1
    while i<=hlit+hdist do
      local v = getv(lengthtable,nlen)
      if v < 16 then
        depths[i] = v
        i += 1
      elseif v < 19 then
        local nbt = {2,3,7}
        local nb = nbt[v-15]
        local c = 0
        local n = 3 + getb(nb)
        if v == 16 then
          c = depths[i-1]
        elseif v == 18 then
          n += 8
        end
        for j=1,n do
          depths[i] = c
          i += 1
        end
      else                                                                   -- debug
        error("wrong entry in depth table for literal/length alphabet: "..v) -- debug
      end
    end
    for i=1,hlit do litdepths[i] = depths[i] end
    local nlit = construct(littable,litdepths)
    for i=1,hdist do distdepths[i] = depths[i+hlit] end
    local ndist = construct(disttable,distdepths)
    inflate_block_loop(nlit,ndist,littable,disttable)
  end

  -- inflate static block
  methods[1] = function()
    local depths = {}
    for i=1,32 do depths[i]=5 end
    local ndist = construct(disttable,depths)
    for i=1,288 do depths[i]=8 end
    for i=145,280 do depths[i]+=sgn(256-i) end
    local nlit = construct(littable,depths)
    inflate_block_loop(nlit,ndist,littable,disttable)
  end

  -- inflate uncompressed byte array
  methods[0] = function()
    -- align input buffer to byte (as per spec)
    -- fixme: we could omit this!
    flb(sn%8)
    local len = getb(16)
    if sn > 0 then                                                   -- debug
      error("unexpected.. should be zero remaining bits in buffer.") -- debug
    end                                                              -- debug
    local nlen = getb(16)
    if bxor(len,nlen) != 0xffff then    -- debug
      error("len and nlen don't match") -- debug
    end                                 -- debug
    for i=0,len-1 do
      write(data[pos+i])
    end
    pos += len
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

