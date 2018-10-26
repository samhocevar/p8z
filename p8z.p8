pico-8 cartridge // http://www.pico-8.com
version 16
__lua__

local reverse = {}
local methods = {}

local function bs_init(data)
  local bs = {
    data = data, -- char buffer
    pos = 1,     -- char buffer index
    b = 0,       -- bit buffer
    n = 0,       -- number of bits in buffer
    out = {},    -- output array
    outpos = 0,  -- output position
  }
  -- get rid of n first bits
  function bs:flushb(n)
    self.n -= n
    self.b = shr(self.b,n)
  end
  -- get a number of n bits from stream
  function bs:getb(n)
    while self.n < n do
      self.b += shr(self.data[self.pos],16-self.n)
      self.pos += 1
      self.n += 8
    end
    local ret = shl(band(self.b,shl(0x.0001,n)-0x.0001),16)
    bs:flushb(n)
    return ret
  end
  -- get next variable-size of maximum size=n element from stream, according to huffman table
  function bs:getv(t,n)
    while self.n < n do
      self.b += shr(self.data[self.pos],16-self.n)
      self.pos += 1
      self.n += 8
    end
    local h = reverse[band(shl(self.b,16),0xff)]
    local l = reverse[band(shl(self.b,8),0xff)]
    local v = band(shr(shl(h,8)+l,16-n),shl(1,n)-1)
    local e = t[v]
    bs:flushb(e%16)
    return flr(e/16)
  end
  function bs:write(n)
    local d = band(self.outpos, 0.75)
    local off = flr(self.outpos)
    if d==0 then
      n=shr(n,16)
    else
      if d==0.25 then
        n=shr(n,8)
      elseif d==0.75 then
        n=shl(n,8)
      end
      n+=self.out[off]
    end
    self.out[off] = n
    self.outpos += 0.25
  end
  function bs:readback(off)
    local d = band(self.outpos + off * 0.25, 0.75)
    local n = self.out[flr(self.outpos + off * 0.25)]
    if d==0 then
      n=shl(n,16)
    elseif d==0.25 then
      n=shl(n,8)
    elseif d==0.75 then
      n=shr(n,8)
    end
    return band(n,0xff)
  end
  return bs
end

local function construct(table,depths,nvalues)
  local bl_count = {}
  local nbits = 1
  for i=1,17 do
    bl_count[i] = 0
  end
  for i=1,nvalues do
    local d = depths[i]
    nbits = max(nbits, d)
    bl_count[d+1] += 1
  end
  local code = 0
  local next_code = {}
  bl_count[1] = 0
  for i=1,nbits do
    code = (code + bl_count[i]) * 2
    next_code[i] = code
  end
  for i=1,nvalues do
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

local littable = {}
local disttable = {}

local function inflate_block_loop(bs,nlit,ndist)
  local lit
  repeat
    lit = bs:getv(littable,nlit)
    if lit < 256 then
      bs:write(lit)
    elseif lit > 256 then
      local nbits = 0
      local size = 3
      local dist = 1
      if lit < 265 then
        size += lit - 257
      elseif lit < 285 then
        nbits = flr(shr(lit-261,2))
        size += shl(band(lit-261,3)+4,nbits)
      else
        size = 258
      end
      if nbits > 0 then
        size += bs:getb(nbits)
      end
      local v = bs:getv(disttable,ndist)
      if v < 4 then
        dist += v
      else
        nbits = flr(v/2-1)
        dist += shl(band(v,1)+2,nbits)
        dist += bs:getb(nbits)
      end
      for n = 1,size do
        bs:write(bs:readback(-dist))
      end
    end
  until lit == 256
end

-- inflate dynamic block
methods[2] = function(bs)
  local litdepths = {}
  local distdepths = {}
  local depths = {}
  local lengthtable = {}
  local order = { 17, 18, 19, 1, 9, 8, 10, 7, 11, 6, 12, 5, 13, 4, 14, 3, 15, 2, 16 }
  local hlit = 257 + bs:getb(5)
  local hdist = 1 + bs:getb(5)
  local hclen = 4 + bs:getb(4)
  for i=1,19 do
    depths[order[i]] = i>hclen and 0 or bs:getb(3)
  end
  local nlen = construct(lengthtable,depths,19)
  local i=1
  while i<=hlit+hdist do
    local v = bs:getv(lengthtable,nlen)
    if v < 16 then
      depths[i] = v
      i += 1
    elseif v < 19 then
      local nbt = {2,3,7}
      local nb = nbt[v-15]
      local c = 0
      local n = 3 + bs:getb(nb)
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
  local nlit = construct(littable,litdepths,hlit)
  for i=1,hdist do distdepths[i] = depths[i+hlit] end
  local ndist = construct(disttable,distdepths,hdist)
  inflate_block_loop(bs,nlit,ndist,littable,disttable)
end

-- inflate static block
methods[1] = function(bs)
  local depths = {}
  for i=1,288 do depths[i]=8 end
  for i=145,280 do depths[i]+=sgn(256-i) end
  local nlit = construct(littable,depths,288)
  for i=1,32 do depths[i]=5 end
  local ndist = construct(disttable,depths,32)
  inflate_block_loop(bs,nlit,ndist,littable,disttable)
end

-- inflate uncompressed byte array
methods[0] = function(bs)
  -- align input buffer to byte (as per spec)
  -- fixme: we could omit this!
  bs:flushb(band(bs.n,7))
  local len = bs:getb(16)
  if bs.n > 0 then                                                 -- debug
    error("unexpected.. should be zero remaining bits in buffer.") -- debug
  end                                                              -- debug
  local nlen = bs:getb(16)
  if bxor(len,nlen) != 0xffff then    -- debug
    error("len and nlen don't match") -- debug
  end                                 -- debug
  for i=0,len-1 do
    bs:write(bs.data[bs.pos+i])
  end
  bs.pos += len
end

-- block type 3 does not exist
methods[3] = function()           -- debug
  error("unsupported block type") -- debug
end                               -- debug

function inflate(data)
  local bs = bs_init(data)
  repeat
    last = bs:getb(1)
    methods[bs:getb(2)](bs)
  until last == 1
  bs:flushb(band(bs.n,7))  -- debug (no need to flush!)
  return bs.out
end

-- init reverse array
for i=0,255 do
  local k=0
  for j=0,7 do
    if band(i,shl(1,j)) != 0 then
      k += shl(1,7-j)
    end
  end
  reverse[i] = k
end

