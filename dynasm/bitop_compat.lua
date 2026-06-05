------------------------------------------------------------------------------
-- DynASM BitOp compatibility module.
--
-- Provides a wrapper emulating Lua BitOp, using either Lua 5.2's bit32 module,
-- or Lua 5.3's bitwise operators.
--
-- Copyright (C) 2005-2026 Mike Pall. All rights reserved.
-- See dynasm.lua for full copyright notice.
------------------------------------------------------------------------------

local function bitop_test(bit)
  -- Test cases for bit operations library.
  local vb = {
    0, 1, -1, 2, -2, 0x12345678, 0x87654321,
    0x33333333, 0x77777777, 0x55aa55aa, 0xaa55aa55,
    0x7fffffff, 0x80000000, 0xffffffff
  }

  local function cksum(name, s, r)
    local z = 0
    for i=1,#s do z = (z + string.byte(s, i)*i) % 2147483629 end
    if z ~= r then
      error("bit."..name.." test failed (got "..z..", expected "..r..")", 0)
    end
  end

  local function check_unop(name, r)
    local f = bit[name]
    local s = ""
    if pcall(f) or pcall(f, "z") or pcall(f, true) then
      error("bit."..name.." fails to detect argument errors", 0)
    end
    for _,x in ipairs(vb) do s = s..","..tostring(f(x)) end
    cksum(name, s, r)
  end

  local function check_binop(name, r)
    local f = bit[name]
    local s = ""
    if pcall(f) or pcall(f, "z") or pcall(f, true) then
      error("bit."..name.." fails to detect argument errors", 0)
    end
    for _,x in ipairs(vb) do
      for _,y in ipairs(vb) do s = s..","..tostring(f(x, y)) end
    end
    cksum(name, s, r)
  end

  local function check_binop_range(name, r, yb, ye)
    local f = bit[name]
    local s = ""
    if pcall(f) or pcall(f, "z") or pcall(f, true) or pcall(f, 1, true) then
      error("bit."..name.." fails to detect argument errors", 0)
    end
    for _,x in ipairs(vb) do
      for y=yb,ye do s = s..","..tostring(f(x, y)) end
    end
    cksum(name, s, r)
  end

  local function check_shift(name, r)
    check_binop_range(name, r, 0, 31)
  end

  -- Minimal sanity checks.
  assert(0x7fffffff == 2147483647, "broken hex literals")
  assert(0xffffffff == -1 or 0xffffffff == 2^32-1, "broken hex literals")
  assert(tostring(-1) == "-1", "broken tostring()")
  assert(tostring(0xffffffff) == "-1" or tostring(0xffffffff) == "4294967295", "broken tostring()")

  -- Basic argument processing.
  assert(bit.tobit(1) == 1)
  assert(bit.band(1) == 1)
  assert(bit.bxor(1,2) == 3)
  assert(bit.bor(1,2,4,8,16,32,64,128) == 255)

  -- Apply operations to test vectors and compare checksums.
  check_unop("tobit", 277312)
  check_unop("bnot", 287870)
  check_unop("bswap", 307611)

  check_binop("band", 41206764)
  check_binop("bor", 51253663)
  check_binop("bxor", 79322427)

  check_shift("lshift", 325260344)
  check_shift("rshift", 139061800)
  check_shift("arshift", 111364720)
  check_shift("rol", 302401155)
  check_shift("ror", 302316761)

  check_binop_range("tohex", 47880306, -8, 8)

  return bit
end

if bit then return bitop_test(bit) end

if require then
  local s, v
  s, v = pcall(require, "bit")
  if s then return bitop_test(v) end

  local b32
  s, b32 = pcall(require, "bit32")
  if s then
    local band = b32.band
    local bor = b32.bor
    local bnot = b32.bnot
    local bxor = b32.bxor
    local lshift = b32.lshift
    local rshift = b32.rshift
    local arshift = b32.arshift
    local lrotate = b32.lrotate
    local rrotate = b32.rrotate
    
    local function asi32(x)
      return band(x, 0xffffffff)
    end

    -- sign-extend integer
    local function tobit(x)
      local m = 0x80000000
      return bxor(band(x, 0xffffffff), m) - m
    end

    local function intcheck(x, fname, arg)
      if type(x) ~= "number" then
        error(("bad argument #%s to '%s' (number expected, got %s)"):format(arg, fname, type(x)), 2)
      end
      return math.ceil(x - 0.5)
    end

    return bitop_test({
      tobit = function(x)
        return tobit(intcheck(x, "tobit", 1))
      end,
      tohex = function(x, n)
        if n == nil then n = 8 end
        x = intcheck(x, "tohex", 1)
        n = intcheck(n, "tohex", 2)
        if n == 0 then return "" end

        local t
        if n > 0 then
          t = "x"
        else
          t = "X"
          n = -n
        end

        return string.sub(string.format("%."..n..t, asi32(x)), -n)
      end,
      bnot = function(n)
        n = intcheck(n, "bnot", 1)
        return tobit(bnot(n))
      end,
      band = function(...)
        local argc = select("#", ...)
        if argc == 0 then
          error("bad argument #1 to 'band' (number expected, got no value)")
        end
        local res = intcheck((...), "band", 1)
        for i=2, argc do
          local n = intcheck(select(i, ...), "band", i)
          res = band(res, n)
        end
        return tobit(res)
      end,
      bor = function(...)
        local argc = select("#", ...)
        if argc == 0 then
          error("bad argument #1 to 'bor' (number expected, got no value)")
        end
        local res = intcheck((...), "bor", 1)
        for i=2, argc do
          local n = intcheck(select(i, ...), "bor", i)
          res = bor(res, n)
        end
        return tobit(res)
      end,
      bxor = function(...)
        local argc = select("#", ...)
        if argc == 0 then
          error("bad argument #1 to 'bxor' (number expected, got no value)")
        end
        local res = intcheck((...), "bxor", 1)
        for i=2, argc do
          local n = intcheck(select(i, ...), "bxor", i)
          res = bxor(res, n)
        end
        return tobit(res)
      end,
      lshift = function(x, n)
        x = intcheck(x, "lshift", 1)
        n = intcheck(n, "lshift", 2)
        return tobit(lshift(x, band(n, 31)))
      end,
      rshift = function(x, n)
        x = intcheck(x, "rshift", 1)
        n = intcheck(n, "rshift", 2)
        return tobit(rshift(asi32(x), band(n, 31)))
      end,
      arshift = function(x, n)
        x = intcheck(x, "arshift", 1)
        n = intcheck(n, "arshift", 2)
        return tobit(arshift(asi32(x), band(n, 31)))
      end,
      rol = function(x, n)
        x = intcheck(x, "rol", 1)
        n = intcheck(n, "rol", 2)
        return tobit(lrotate(asi32(x), band(n, 31)))
      end,
      ror = function(x, n)
        x = intcheck(x, "ror", 1)
        n = intcheck(n, "ror", 2)
        return tobit(rrotate(asi32(x), band(n, 31)))
      end,
      bswap = function(x)
        x = asi32( intcheck(x, "bswap", 1) )
        local res = x
        res = bor(
          lshift(band(res, 0x0000FFFF), 16),
          rshift(band(res, 0xFFFF0000), 16))
        res = bor(
          lshift(band(res, 0x00FF00FF), 8),
          rshift(band(res, 0xFF00FF00), 8))
        return tobit(res)
      end
    })
  end
end

-- Neither BitOp or bit32 exist. Could either be Lua 5.1 or older, or 5.4+,
-- which removes the bit32 module in favor of its built-in bitwise operators.
-- Assume the latter. Also, load and run it as a dynamically loaded string
-- so that Lua versions older than 5.3 don't raise a syntax error when
-- loading this file.
local f = (loadstring or load)([[
local U32_MAX = 0xffffffff

local function intcheck(x, fname, arg)
  if type(x) ~= "number" then
    error(("bad argument #%s to '%s' (number expected, got %s)"):format(arg, fname, type(x)), 2)
  end
  return math.tointeger(math.ceil(x - 0.5))
end

local function asi32(x)
  return x & U32_MAX
end

local function tobit(x)
  -- sign-extend integer
  local m = 0x80000000
  return ((x & U32_MAX) ~ m) - m
end

return {
    tobit = function(x)
      return tobit( intcheck(x, "tobit", 1) )
    end,
    tohex = function(x, n)
      if n == nil then n = 8 end  
      x = intcheck(x, "tohex", 1)
      n = intcheck(n, "tohex", 2)
      if n == 0 then return "" end
      local t
      if n > 0 then
        t = "x"
      else
        t = "X"
        n = -n
      end
      return string.sub(string.format("%."..n..t, asi32(x)), -n)
    end,
    bnot = function(n) return ~tobit( intcheck(n, 1, "bnot") ) end,
    band = function(...)
      local argc = select("#", ...)
      if argc == 0 then
        error("bad argument #1 to 'band' (number expected, got no value)")
      end
      local res = intcheck((...), "band", 1)
      for i=2, argc do
        local n = intcheck(select(i, ...), "band", i)
        res = res & n
      end
      return tobit(res)
    end,
    bor = function(...)
      local argc = select("#", ...)
      if argc == 0 then
        error("bad argument #1 to 'bor' (number expected, got no value)")
      end
      local res = intcheck((...), "bor", 1)
      for i=2, argc do
        local n = intcheck(select(i, ...), "bor", i)
        res = res | n
      end
      return tobit(res)
    end,
    bxor = function(...)
      local argc = select("#", ...)
      if argc == 0 then
        error("bad argument #1 to 'bxor' (number expected, got no value)")
      end
      local res = intcheck((...), "bxor", 1)
      for i=2, argc do
        local n = intcheck(select(i, ...), "bxor", i)
        res = res ~ n
      end
      return tobit(res)
    end,
    lshift = function(x, n)
      x = intcheck(x, "lshift", 1)
      n = intcheck(n, "lshift", 2)
      return tobit(x << (n & 31))
    end,
    rshift = function(x, n)
      x = intcheck(x, "rshift", 1)
      n = intcheck(n, "rshift", 2)
      return tobit(asi32(x) >> (n & 31))
    end,
    arshift = function(x, n)
      x = asi32( intcheck(x, "arshift", 1) )
      n = intcheck(n, "arshift", 2) & 31
      local m = (x & 0x80000000) >> n
      return tobit( ((x >> n) ~ m) - m )
    end,
    rol = function(x, n)
      x = asi32( intcheck(x, "rol", 1) )
      n = intcheck(n, "rol", 2) & 31
      return tobit((x << n) | (x >> (32 - n)))
    end,
    ror = function(x, n)
      x = asi32( intcheck(x, "ror", 1) )
      n = intcheck(n, "ror", 2) & 31
      return tobit((x << (32 - n)) | (x >> n))
    end,
    bswap = function(x)
    x = asi32(x)
      x = asi32( intcheck(x, "bswap", 1) )
      local res = x
      res = ((res & 0x0000FFFF) << 16) | ((res & 0xFFFF0000) >> 16)
      res = ((res & 0x00FF00FF) << 8 ) | ((res & 0xFF00FF00) >> 8 )
      return tobit(res)
    end
}
]])

if f then
  return bitop_test(f())
end

io.stderr:write("ERROR: unsupported lua version: must either include Lua BitOp, or be version 5.2 or higher.\n")
os.exit(1)