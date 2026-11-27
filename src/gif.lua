-- Animated GIF encoder for dev recordings (README clips). Pure Lua (no love.*).
--
-- Gif.encode(frames, o) -> string (the .gif file)
--   frames  list of RGBA pixel buffers, each indexable from 0: p[(y * w + x) * 4 + c]
--           (a Lua table or an FFI uint8_t pointer)
--   o       { w, h, scale = 1, delay = 5 (centiseconds per frame) }
-- Up to 255 colours (most used first; the rest snap to the nearest). Index 0 is transparent:
-- pixels that did not change since the previous frame are left transparent, so a mostly
-- still scene compresses to almost nothing.
local Gif = {}

local floor = math.floor
local char = string.char

local function key(p, i) return p[i] * 65536 + p[i + 1] * 256 + p[i + 2] end

-- Palette: count colours over all frames, keep the 255 most used.
local function buildPalette(frames, n)
  local count, keys = {}, {}
  for _, p in ipairs(frames) do
    for i = 0, n - 1 do
      local k = key(p, i * 4)
      local c = count[k]
      if c then count[k] = c + 1 else count[k] = 1; keys[#keys + 1] = k end
    end
  end
  table.sort(keys, function(a, b) return count[a] > count[b] end)
  local pal, index = {}, {}
  for i = 1, math.min(255, #keys) do pal[i] = keys[i]; index[keys[i]] = i end
  -- everything else: nearest palette colour (cached in index)
  for i = 256, #keys do
    local k = keys[i]
    local r, g, b = floor(k / 65536), floor(k / 256) % 256, k % 256
    local best, bd = 1, math.huge
    for j = 1, #pal do
      local q = pal[j]
      local dr, dg, db = r - floor(q / 65536), g - floor(q / 256) % 256, b - q % 256
      local d = 2 * dr * dr + 4 * dg * dg + 3 * db * db
      if d < bd then best, bd = j, d end
    end
    index[k] = best
  end
  return pal, index
end

-- Byte writer: collects numbers, flushes to strings in chunks.
local function writer()
  local w = { parts = {}, buf = {}, n = 0 }
  function w.byte(b)
    w.n = w.n + 1; w.buf[w.n] = b
    if w.n == 4096 then w.flush() end
  end
  function w.flush()
    if w.n > 0 then
      local s = {}
      for i = 1, w.n, 256 do s[#s + 1] = char(unpack(w.buf, i, math.min(i + 255, w.n))) end
      w.parts[#w.parts + 1] = table.concat(s)
      w.buf, w.n = {}, 0
    end
  end
  function w.u16(v) w.byte(v % 256); w.byte(floor(v / 256)) end
  function w.str(s) for i = 1, #s do w.byte(s:byte(i)) end end
  function w.result() w.flush(); return table.concat(w.parts) end
  return w
end

-- LZW-compress `count` indices from nextIndex() into GIF data sub-blocks (8-bit codes).
local function lzw(w, count, nextIndex)
  local clear, eoi = 256, 257
  local dict, nextCode, size = {}, 258, 9
  local block, bn = {}, 0
  local acc, bits = 0, 0
  local function emit(code)
    acc = acc + code * 2 ^ bits
    bits = bits + size
    while bits >= 8 do
      bn = bn + 1; block[bn] = acc % 256
      acc = floor(acc / 256); bits = bits - 8
      if bn == 255 then w.byte(255); for i = 1, 255 do w.byte(block[i]) end; bn = 0 end
    end
    -- code size grows once the next code no longer fits (decoder does the same, one step behind)
    if code == clear then size = 9
    elseif nextCode > 2 ^ size - 1 and size < 12 then size = size + 1 end
  end
  w.byte(8)                                   -- minimum code size
  emit(clear)
  local prefix = nextIndex()
  for _ = 2, count do
    local k = nextIndex()
    local id = prefix * 256 + k
    local code = dict[id]
    if code then
      prefix = code
    else
      emit(prefix)
      if nextCode < 4096 then
        dict[id] = nextCode
        nextCode = nextCode + 1
      else
        emit(clear)
        dict, nextCode = {}, 258
      end
      prefix = k
    end
  end
  emit(prefix)
  emit(eoi)
  if bits > 0 then bn = bn + 1; block[bn] = acc % 256 end
  if bn > 0 then w.byte(bn); for i = 1, bn do w.byte(block[i]) end end
  w.byte(0)                                   -- block terminator
end

function Gif.encode(frames, o)
  local W, H, S = o.w, o.h, o.scale or 1
  local n = W * H
  local pal, index = buildPalette(frames, n)
  local w = writer()
  w.str("GIF89a"); w.u16(W * S); w.u16(H * S)
  w.byte(0xF7); w.byte(0); w.byte(0)          -- global colour table, 256 entries
  w.byte(0); w.byte(0); w.byte(0)             -- index 0: transparent
  for i = 1, 255 do
    local k = pal[i] or 0
    w.byte(floor(k / 65536)); w.byte(floor(k / 256) % 256); w.byte(k % 256)
  end
  w.str("\33\255\11NETSCAPE2.0\3\1"); w.u16(0); w.byte(0)   -- loop forever

  local row = {}
  for f, p in ipairs(frames) do
    local prev = frames[f - 1]
    for i = 0, n - 1 do
      local k = key(p, i * 4)
      row[i] = (prev and key(prev, i * 4) == k) and 0 or index[k]
    end
    w.byte(0x21); w.byte(0xF9); w.byte(4)     -- graphic control: keep previous, index 0 transparent
    w.byte(prev and 0x05 or 0x04); w.u16(o.delay or 5); w.byte(0); w.byte(0)
    w.byte(0x2C); w.u16(0); w.u16(0); w.u16(W * S); w.u16(H * S); w.byte(0)
    local x, y, sx, sy = 0, 0, 0, 0
    lzw(w, n * S * S, function()
      local v = row[y * W + x]
      sx = sx + 1
      if sx == S then
        sx = 0; x = x + 1
        if x == W then
          x = 0; sy = sy + 1
          if sy == S then sy = 0; y = y + 1 end
        end
      end
      return v
    end)
  end
  w.byte(0x3B)
  return w.result()
end

return Gif
