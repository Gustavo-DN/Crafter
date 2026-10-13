--[[
  FACTORY DOORS - live door diagram (6 wide x 2 tall monitor)
  ---------------------------------------------------------------
  A floor plan of the factory. Every door slides open / closed on
  the monitor when the real door does, little people (in their card
  colour) walk through, denied cards bounce off the door.

  HOW IT HEARS THE DOORS
    door.lua and keycard.lua (the patched copies next to this file)
    broadcast every log line on rednet, protocol "factory_doors".
    So: put a modem (wireless or wired) on every door computer AND
    on this computer. That is all.

    Optional: run the door bundled cable into this computer too and
    set CONFIG.senseSide. Then the board also reads the real
    redstone state of every door.

  SCREEN
    6 wide x 2 tall monitor at text scale 0.5 = 121 x 24 characters.
    Tap a door (or a room) to see its details. Tap the LIVE/DEMO chip
    to switch the demo on/off. Keys: D demo, arrows select, Q quit.

  With no modem (or nothing heard for a while) it plays a DEMO so you
  can see it working. The first real message switches it to LIVE.
]]

local CONFIG = {
  monitor   = nil,              -- monitor name, nil = first one found
  textScale = 0.5,
  protocol  = "factory_doors",  -- must match door.lua / keycard.lua
  outside   = "LOBBY",          -- the room before door 1
  -- door N = door N of door.lua. need = card level it needs.
  -- sense = bundled colour of the door (only used if senseSide is set),
  --         or a side name ("left") for a plain redstone door.
  doors = {
    {name = "MAIN GATE",   room = "WORKSHOP",      need = 1, sense = colors.white},
    {name = "STAFF DOOR",  room = "STORAGE VAULT", need = 2, sense = colors.orange},
    {name = "SECURITY",    room = "FACTORY FLOOR", need = 3, sense = colors.magenta},
    {name = "ENGINEERING", room = "BRAIN ROOM",    need = 4, sense = colors.lightBlue},
    {name = "ADMIN",       room = "CORE VAULT",    need = 5, sense = colors.yellow},
  },
  -- keycard.lua readers: [computer id] = door number on this board.
  -- A reader not listed here is shown on the door matching its REQUIRED_LEVEL.
  keycardDoors = {},
  senseSide = nil,              -- e.g. "back": side where the door bundled cable comes in
  openTime  = 5,                -- seconds a door stays open (door.lua OPEN_TIME)
  demo      = true,             -- play a demo while nothing real is heard
  demoAfter = 20,               -- seconds of silence (with a modem) before the demo starts
  frame     = 0.1,              -- seconds between redraws
}

---------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------
local floor, max, min = math.floor, math.max, math.min
local C = {white=0,orange=1,magenta=2,lightBlue=3,yellow=4,lime=5,pink=6,gray=7,
           lightGray=8,cyan=9,purple=10,blue=11,brown=12,green=13,red=14,black=15}
local HEXC = {}
for i = 0, 15 do HEXC[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
-- same dark palette as the vault screens
local PALETTE = {0xE6EBF0,0xE38B3B,0xC878D2,0x72B4E6,0xE9C34B,0x88CE5E,0xE99CB2,0x2B3542,
                 0x7E8B9C,0x4FB2AB,0x9B7DE1,0x1A212B,0x8E6B46,0x3F9157,0xE2574F,0x0D1117}
local LEVEL_NAMES = {"VISITOR", "STAFF", "SECURITY", "ENGINEER", "ADMIN"}
local LEVEL_COL = {C.lightBlue, C.lime, C.yellow, C.orange, C.red}
local CH_R, CH_L, CH_DOT, CH_DIA, CH_MAN = "\16", "\17", "\7", "\4", "\2"

local function now() return os.clock() end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function trunc(s, n) s = tostring(s) if #s > n then return s:sub(1, max(0, n)) end return s end
local function padR(s, n) s = trunc(s, n) return s .. (" "):rep(n - #s) end
local function lvlCol(l) return LEVEL_COL[l or 0] or C.lightGray end
local function clockStr()
  local ok, s = pcall(os.date, "%H:%M")
  if ok and type(s) == "string" then return s end
  return textutils.formatTime(os.time(), true)
end
local function blink(rate) return floor(now() * (rate or 2)) % 2 == 0 end

---------------------------------------------------------------------
-- Screen buffer (0-based), flushed with blit()
---------------------------------------------------------------------
local mon, monName
local W, H = 121, 24
local Bc, Bf, Bb, prevRows = {}, {}, {}, {}
local B = {}
function B.resize(w, h)
  W, H = w, h
  Bc, Bf, Bb, prevRows = {}, {}, {}, {}
  for i = 1, w * h do Bc[i] = " "; Bf[i] = C.white; Bb[i] = C.black end
end
function B.put(x, y, ch, fg, bg)
  if x < 0 or y < 0 or x >= W or y >= H then return end
  local i = y * W + x + 1
  Bc[i] = ch
  if fg then Bf[i] = fg end
  if bg then Bb[i] = bg end
end
function B.text(x, y, s, fg, bg)
  s = tostring(s)
  for k = 1, #s do B.put(x + k - 1, y, s:sub(k, k), fg, bg) end
end
function B.fill(x, y, w, h, bg)
  for j = 0, h - 1 do for i = 0, w - 1 do B.put(x + i, y + j, " ", C.white, bg) end end
end
function B.flush()
  local t, f, b = {}, {}, {}
  for y = 0, H - 1 do
    local base = y * W
    for x = 1, W do local i = base + x; t[x] = Bc[i]; f[x] = HEXC[Bf[i]]; b[x] = HEXC[Bb[i]] end
    local ts, fs, bs = table.concat(t, "", 1, W), table.concat(f, "", 1, W), table.concat(b, "", 1, W)
    local p = prevRows[y]
    if not p or p[1] ~= ts or p[2] ~= fs or p[3] ~= bs then
      mon.setCursorPos(1, y + 1); mon.blit(ts, fs, bs); prevRows[y] = {ts, fs, bs}
    end
  end
end

local function tele(tl, tr, ml, mr, bl, br)
  local inv = false
  if br then inv = true; tl, tr, ml, mr, bl = not tl, not tr, not ml, not mr, not bl end
  local code = 128 + (tl and 1 or 0) + (tr and 2 or 0) + (ml and 4 or 0) + (mr and 8 or 0) + (bl and 16 or 0)
  return string.char(code), inv
end
local THIN = tele(true, true, true, true, false, false)

---------------------------------------------------------------------
-- Pixel canvas for the floor plan: 2x3 pixels per character
---------------------------------------------------------------------
local PL = {top = 2, rows = 12}           -- plan occupies screen rows 2..13
local P, PW, PH = {}, 0, 0
local function pset(x, y, c)
  if x < 0 or y < 0 or x >= PW or y >= PH then return end
  P[y * PW + x + 1] = c
end
local function prect(x, y, w, h, c)
  for j = y, y + h - 1 do for i = x, x + w - 1 do pset(i, j, c) end end
end
local function picon(x, y, rows, c)
  for j, r in ipairs(rows) do
    for i = 1, #r do if r:sub(i, i) == "#" then pset(x + i - 1, y + j - 1, c) end end
  end
end
-- turn the pixels into teletext characters (2 colours per character)
local function pflush()
  local cnt = {}
  for cy = 0, PH / 3 - 1 do
    for cx = 0, W - 1 do
      local px = {}
      for k = 0, 5 do
        px[k + 1] = P[(cy * 3 + floor(k / 2)) * PW + cx * 2 + (k % 2) + 1]
      end
      for k = 1, 6 do cnt[px[k]] = 0 end
      local bg, bn = px[1], 0
      for k = 1, 6 do local c = px[k]; cnt[c] = cnt[c] + 1; if cnt[c] > bn then bg, bn = c, cnt[c] end end
      local fg, fn = nil, 0
      for k = 1, 6 do local c = px[k]; if c ~= bg and cnt[c] > fn then fg, fn = c, cnt[c] end end
      local y = PL.top + cy
      if not fg then
        B.put(cx, y, " ", C.white, bg)
      else
        local ch, inv = tele(px[1] == fg, px[2] == fg, px[3] == fg, px[4] == fg, px[5] == fg, px[6] == fg)
        if inv then B.put(cx, y, ch, bg, fg) else B.put(cx, y, ch, fg, bg) end
      end
    end
  end
end

---------------------------------------------------------------------
-- State
---------------------------------------------------------------------
local ICONS = {
  {"..##..", ".####.", "..##..", "..##..", ".####.", ".####."},  -- lobby: plant
  {"######", "######", ".####.", "..##..", ".####.", "######"},  -- workshop: anvil
  {"##.##.", "##.##.", "......", "##.##.", "##.##.", "......"},  -- storage: crates
  {".#..#.", "######", "##..##", "##..##", "######", ".#..#."},  -- factory: cog
  {"######", "#....#", "#....#", "######", "..##..", ".####."},  -- brain: computer
  {"######", "#.##.#", "##..##", "##..##", "#.##.#", "######"},  -- core: vault
}
local OPEN_SECS, CLOSE_SECS = 0.5, 0.8
local S
local function fresh(keep)
  local s = {
    doors = {}, feed = {}, walkers = {}, pending = {}, regions = {},
    used = {0, 0, 0, 0, 0}, denied = 0, issued = 0, events = 0,
    sel = keep and keep.sel or 1, start = now(), live = keep and keep.live or false,
    demoManual = keep and keep.demoManual, modem = keep and keep.modem, lastReal = now(),
    demoNext = now() + 1, roomLast = {},
  }
  for i, d in ipairs(CONFIG.doors) do
    s.doors[i] = {cfg = d, state = "locked", f = 0, openUntil = 0, deniedUntil = 0,
                  opens = 0, denies = 0, last = nil, from = nil, tl = {}, lastOpenAt = -9}
  end
  return s
end

local function feed(kind, door, text, col, lvl)
  S.events = S.events + 1
  table.insert(S.feed, 1, {t = clockStr(), kind = kind, door = door, text = text, col = col, lvl = lvl})
  if #S.feed > 60 then table.remove(S.feed) end
end
local function mark(d, v)
  local b = floor(now() / 10)
  if (d.tl[b] or 0) < v then d.tl[b] = v end
end

local function walker(i, lvl, deny)
  if #S.walkers > 24 then table.remove(S.walkers, 1) end
  local lanes = {13, 16, 19}
  S.walkers[#S.walkers + 1] = {door = i, x = -22, y = lanes[math.random(1, 3)], col = deny and C.red or lvlCol(lvl),
                               deny = deny, wait = 0, dir = 1}
end

local function openDoor(i, lvl, id, from, secs)
  local d = S.doors[i]
  if not d then return end
  local merge = now() - d.lastOpenAt < 1
  d.state = "open"
  d.openUntil = now() + (secs or CONFIG.openTime)
  if lvl or id then d.last = {lvl = lvl, id = id, t = clockStr()} end
  if from then d.from = from end
  if merge then return end
  d.lastOpenAt = now()
  d.opens = d.opens + 1
  mark(d, 1)
  if lvl and S.used[lvl] then S.used[lvl] = S.used[lvl] + 1 end
  S.roomLast[i + 1] = {lvl = lvl, t = clockStr()}
  walker(i, lvl, false)
  local who = lvl and ("L" .. lvl .. " " .. (LEVEL_NAMES[lvl] or "")) or "redstone"
  feed("OPEN", i, who .. (id and (" #" .. id) or ""), C.lime, lvl)
end
local function closeDoor(i)
  local d = S.doors[i]
  if not d or d.state ~= "open" then return end
  d.state = "closing"
  feed("CLOSE", i, "closed", C.lightGray)
end
local function denyDoor(i, lvl, id, from)
  local d = S.doors[i]
  if not d then return end
  d.deniedUntil = now() + 2
  d.denies = d.denies + 1
  if from then d.from = from end
  S.denied = S.denied + 1
  mark(d, 2)
  walker(i, lvl, true)
  feed("DENIED", i, (lvl and ("L" .. lvl .. " card") or "no access") .. (id and (" #" .. id) or ""), C.red, lvl)
end

---------------------------------------------------------------------
-- Messages from door.lua / keycard.lua
---------------------------------------------------------------------
local function num(v) return tonumber(v) end
local function keycardDoor(sender, need)
  return CONFIG.keycardDoors[sender] or clamp(num(need) or 1, 1, #CONFIG.doors)
end
local function goLive(sender)
  if S.live then return end
  local wasDemo = S.demoManual ~= true
  local keep = S
  if wasDemo then S = fresh(keep) end
  S.live = true
  S.demoManual = nil
  feed("LIVE", nil, "first message from computer #" .. tostring(sender), C.lime)
end
local function handle(sender, msg)
  local info = type(msg) == "table" and msg or {}
  local s = type(msg) == "string" and msg or info.log
  goLive(sender)
  S.lastReal = now()
  local from
  if info.need then from = "keycard #" .. tostring(sender) else from = "door ctrl #" .. tostring(sender) end
  if info.label then from = from .. " " .. info.label end
  local secs = num(info.openTime)
  -- generic form other programs can send: {door=3, state="open"|"close"|"denied", level=4}
  if info.door and info.state then
    local i = num(info.door)
    if info.state == "open" then openDoor(i, num(info.level), info.id, from, secs)
    elseif info.state == "close" then closeDoor(i)
    elseif info.state == "denied" then denyDoor(i, num(info.level), info.id, from) end
    return
  end
  if type(s) ~= "string" then return end
  local n, lv, id = s:match("^DOOR (%d+) OPEN L(%S+) id (%S+)")
  if n then return openDoor(num(n), num(lv), id ~= "nil" and id or nil, from, secs) end
  n = s:match("^DOOR (%d+) CLOSE")
  if n then return closeDoor(num(n)) end
  n, id = s:match("^DENIED door (%d+) id (%S+)")
  if n then return denyDoor(num(n), nil, id ~= "nil" and id or nil, from) end
  lv, id = s:match("^DOOR OPEN L(%S+) id (%S+)")
  if lv then return openDoor(keycardDoor(sender, info.need), num(lv), id ~= "nil" and id or nil, from, secs) end
  if s:match("^DOOR CLOSE") then return closeDoor(keycardDoor(sender, info.need)) end
  if s:match("^DENIED") then return denyDoor(keycardDoor(sender, info.need), nil, nil, from) end
  lv, id = s:match("^WRITE L(%d) id (%S+)")
  if lv then
    S.issued = S.issued + 1
    return feed("CARD", nil, "card #" .. id .. " written L" .. lv .. " " .. (LEVEL_NAMES[num(lv)] or ""), C.cyan, num(lv))
  end
  id = s:match("^ERASE id (%S+)")
  if id then return feed("ERASE", nil, "card #" .. id .. " wiped", C.magenta) end
  feed("MSG", nil, trunc(s, 40), C.lightBlue)
end

-- optional: read the real door redstone
local function sense()
  for i, d in ipairs(S.doors) do
    local on
    local sn = d.cfg.sense
    if type(sn) == "string" then
      on = redstone.getInput(sn)
    elseif sn and CONFIG.senseSide then
      on = colors.test(redstone.getBundledInput(CONFIG.senseSide), sn)
    end
    if on == true and d.state ~= "open" then openDoor(i, nil, nil, "redstone")
    elseif on == false and d.state == "open" then closeDoor(i) end
  end
end

---------------------------------------------------------------------
-- Demo traffic
---------------------------------------------------------------------
local function demoOn()
  if S.demoManual ~= nil then return S.demoManual end
  if not CONFIG.demo or S.live then return false end
  return not S.modem or now() - S.start > CONFIG.demoAfter
end
local function demoStep()
  local t = now()
  for k = #S.pending, 1, -1 do
    local p = S.pending[k]
    if t >= p.at then table.remove(S.pending, k); p.fn() end
  end
  if not demoOn() or t < S.demoNext then return end
  S.demoNext = t + 1 + math.random() * 2.5
  local r = math.random()
  if r < 0.08 then
    S.issued = S.issued + 1
    local l = math.random(1, 5)
    return feed("CARD", nil, "card #" .. math.random(0, 40) .. " written L" .. l .. " " .. LEVEL_NAMES[l], C.cyan, l)
  end
  local i = math.random(1, #S.doors)
  local lvlW = {1, 1, 1, 2, 2, 3, 3, 4, 5}
  local l = lvlW[math.random(1, #lvlW)]
  local d = S.doors[i]
  if l >= (d.cfg.need or i) then
    if d.state == "open" then return end
    openDoor(i, l, tostring(math.random(0, 40)), "demo", CONFIG.openTime)
    S.pending[#S.pending + 1] = {at = t + CONFIG.openTime, fn = function() closeDoor(i) end}
  else
    denyDoor(i, l, tostring(math.random(0, 40)), "demo")
  end
end

---------------------------------------------------------------------
-- Update
---------------------------------------------------------------------
local G = {}   -- geometry: rooms and doors in characters
local function layout()
  local n = #CONFIG.doors
  local free = W - 2 - n * 3
  local rw = floor(free / (n + 1))
  local extra = free - rw * (n + 1)
  G.rooms, G.doors = {}, {}
  local x = 1
  for i = 1, n + 1 do
    local w = rw + ((i > n + 1 - extra) and 1 or 0)
    G.rooms[i] = {x = x, w = w}
    x = x + w
    if i <= n then G.doors[i] = {x = x}; x = x + 3 end
  end
  PW, PH = W * 2, PL.rows * 3
  G.planCache = nil
  G.panelY = PL.top + PL.rows + 1
end
local function update(dt)
  local t = now()
  for i, d in ipairs(S.doors) do
    if d.state == "open" then
      d.f = min(1, d.f + dt / OPEN_SECS)
      if t > d.openUntil + 3 then closeDoor(i) end           -- lost CLOSE message
    else
      d.f = max(0, d.f - dt / CLOSE_SECS)
      if d.state == "closing" and d.f <= 0 then d.state = "locked" end
    end
  end
  for k = #S.walkers, 1, -1 do
    local w = S.walkers[k]
    local d = S.doors[w.door]
    local speed = 20 * dt
    if w.wait > 0 then
      w.wait = w.wait - dt
      if w.wait <= 0 then w.dir = -1 end
    else
      local nx = w.x + speed * w.dir
      if w.dir > 0 and w.deny and nx >= -4 then nx = -4; w.wait = 0.9
      elseif w.dir > 0 and not w.deny and nx > -4 and w.x <= -4 and d.f < 0.7 then nx = w.x end
      w.x = nx
    end
    if w.x > 22 or w.x < -26 then table.remove(S.walkers, k) end
  end
end

---------------------------------------------------------------------
-- Drawing
---------------------------------------------------------------------
local function region(fn, x, y, w, h) S.regions[#S.regions + 1] = {x = x, y = y, w = w, h = h, fn = fn} end

local function stateOf(d)
  local t = now()
  if t < d.deniedUntil then return "DENIED", C.red end
  if d.state == "open" then
    if d.f < 1 then return "OPENING", C.lime end
    return "OPEN " .. max(0, math.ceil(d.openUntil - t)) .. "s", C.lime
  elseif d.state == "closing" then return "CLOSING", C.yellow end
  return "LOCKED", C.lightGray
end

local function drawPlan()
  local WALL, FLOOR = C.lightGray, C.blue
  local t = now()
  -- what the moving parts look like this frame; redraw pixels only if it changed
  local look, key = {}, {}
  for i, d in ipairs(S.doors) do
    local pc, lc = C.white, C.red
    if t < d.deniedUntil then pc = blink(6) and C.red or C.white; lc = blink(6) and C.red or C.gray
    elseif d.state == "open" then pc, lc = C.lime, C.lime
    elseif d.state == "closing" then pc = C.yellow; lc = blink(4) and C.yellow or C.gray end
    look[i] = {pc = pc, lc = lc, half = floor(7 * (1 - d.f) + 0.5)}
    key[#key + 1] = pc .. "," .. lc .. "," .. look[i].half
  end
  for _, w in ipairs(S.walkers) do
    w.px = floor(G.doors[w.door].x * 2 + 3 + w.x)
    w.pc = w.deny and (blink(6) and C.red or C.white) or w.col
    key[#key + 1] = w.px .. "," .. w.y .. "," .. w.pc
  end
  key = table.concat(key, ";")
  local cache = G.planCache
  if cache and cache.key == key then
    for k, v in pairs(cache.c) do Bc[k] = v; Bf[k] = cache.f[k]; Bb[k] = cache.b[k] end
  else
    for k = 1, PW * PH do P[k] = FLOOR end
    prect(0, 0, PW, 3, WALL)
    prect(0, PH - 2, PW, 2, WALL)
    prect(0, 0, 2, PH, WALL)
    prect(PW - 2, 0, 2, PH, WALL)
    prect(0, 13, 2, 10, FLOOR)                              -- entrance gap
    for x = 0, PW - 1, 4 do pset(x, 17, C.gray) end         -- walkway
    for i, r in ipairs(G.rooms) do
      local col = i == 1 and C.gray or lvlCol(CONFIG.doors[i - 1].need)
      prect(r.x * 2, 2, r.w * 2, 1, col)                    -- clearance stripe
      picon((r.x + r.w - 4) * 2, 27, ICONS[(i - 1) % #ICONS + 1], i == 1 and C.gray or col)
    end
    for i, g in ipairs(G.doors) do
      local l = look[i]
      local wx = g.x * 2 + 2
      prect(wx, 0, 2, PH, WALL)
      prect(wx, 11, 2, 14, FLOOR)                           -- door gap
      pset(wx - 1, 10, WALL); pset(wx + 2, 10, WALL); pset(wx - 1, 25, WALL); pset(wx + 2, 25, WALL)
      prect(wx, 11, 2, l.half, l.pc)                        -- top panel slides up
      prect(wx, 25 - l.half, 2, l.half, l.pc)               -- bottom panel slides down
      prect(wx, 6, 2, 2, l.lc)                              -- status light
    end
    for _, w in ipairs(S.walkers) do prect(w.px, w.y, 2, 2, w.pc) end
    pflush()
    cache = {key = key, c = {}, f = {}, b = {}}
    for k = PL.top * W + 1, (PL.top + PL.rows) * W do cache.c[k] = Bc[k]; cache.f[k] = Bf[k]; cache.b[k] = Bb[k] end
    G.planCache = cache
  end
  -- text on top of the plan
  B.put(0, 7, CH_R, C.white, nil)
  for i, r in ipairs(G.rooms) do
    local name = i == 1 and CONFIG.outside or CONFIG.doors[i - 1].room
    name = trunc(name, r.w - 1)
    B.text(r.x + floor((r.w - #name) / 2), PL.top + 1, name, C.white, nil)
    local need = i > 1 and CONFIG.doors[i - 1].need
    local sub = need and ("L" .. need .. "+ " .. (LEVEL_NAMES[need] or "")) or "PUBLIC"
    sub = trunc(sub, r.w - 1)
    B.text(r.x + floor((r.w - #sub) / 2), PL.top + 2, sub, need and lvlCol(need) or C.lightGray, nil)
    local last = S.roomLast[i]
    if last then
      B.text(r.x + 1, PL.top + 10, CH_MAN, lvlCol(last.lvl), nil)
      B.text(r.x + 3, PL.top + 10, trunc((last.lvl and ("L" .. last.lvl .. " ") or "") .. last.t, r.w - 8), C.lightGray, nil)
    end
    region(function() S.sel = max(1, i - 1) end, r.x, PL.top, r.w, PL.rows)
  end
  for _, w in ipairs(S.walkers) do
    if w.deny and w.wait > 0 then
      local cx = G.doors[w.door].x * 2 + 3
      B.text(floor((cx + w.x) / 2), PL.top + floor(w.y / 3) - 1, "!", C.red, nil)
    end
  end
end

local function drawDoorsRows()
  B.fill(0, 1, W, 1, C.black)
  B.fill(0, PL.top + PL.rows, W, 1, C.black)
  B.text(1, 1, "ENTRANCE", C.lightGray, C.black)
  for i, g in ipairs(G.doors) do
    local d = S.doors[i]
    local need = d.cfg.need or i
    B.text(g.x, 1, " " .. i .. " ", C.black, lvlCol(need))
    if S.sel == i then
      B.text(g.x - 1, 1, CH_R, C.white, C.black); B.text(g.x + 3, 1, CH_L, C.white, C.black)
    end
    local s, col = stateOf(d)
    local y = PL.top + PL.rows
    local x = g.x + 1 - floor(#s / 2)
    if s == "DENIED" then B.text(x - 1, y, " " .. s .. " ", C.white, blink(4) and C.red or C.black)
    else B.text(x, y, s, col, C.black) end
    if S.sel == i then B.text(x - 2, y, CH_R, C.white, C.black) end
    region(function() S.sel = i end, g.x - 2, 1, 7, PL.rows + 2)
  end
end

local function drawHeader()
  B.fill(0, 0, W, 1, C.gray)
  B.text(0, 0, " FACTORY DOORS ", C.black, C.yellow)
  local o, c, l = 0, 0, 0
  for _, d in ipairs(S.doors) do
    if d.state == "open" then o = o + 1 elseif d.state == "closing" then c = c + 1 else l = l + 1 end
  end
  local x = 17
  local function chip(label, n, col)
    B.text(x, 0, CH_DIA, n > 0 and col or C.lightGray, C.gray)
    local s = " " .. n .. " " .. label
    B.text(x + 1, 0, s, n > 0 and C.white or C.lightGray, C.gray)
    x = x + #s + 3
  end
  chip("OPEN", o, C.lime); chip("CLOSING", c, C.yellow); chip("LOCKED", l, C.lightGray)
  chip("DENIED", S.denied, C.red); chip("CARDS USED", S.used[1] + S.used[2] + S.used[3] + S.used[4] + S.used[5], C.lightBlue)
  local r = W
  local tm = " " .. clockStr() .. " "
  r = r - #tm; B.text(r, 0, tm, C.lightGray, C.gray)
  local mode, mfg, mbg
  if demoOn() then mode, mfg, mbg = " DEMO ", C.black, C.magenta
  elseif S.live then mode, mfg, mbg = (blink(1) and " " .. CH_DOT .. " LIVE " or "   LIVE "), C.black, C.lime
  else mode, mfg, mbg = " WAITING " .. max(0, math.ceil(CONFIG.demoAfter - (now() - S.start))) .. "s ", C.black, C.lightGray end
  r = r - #mode - 1
  B.text(r, 0, mode, mfg, mbg)
  region(function() S.demoManual = not demoOn() end, r, 0, #mode, 1)
end

local function panel(x, y, w, h, title, meta, metaCol)
  B.fill(x, y, w, h, C.blue)
  B.fill(x, y, w, 1, C.gray)
  B.text(x + 1, y, trunc(title, w - 2), C.yellow, C.gray)
  if meta then B.text(x + w - 1 - #meta, y, meta, metaCol or C.lightGray, C.gray) end
end

local function drawFeed(x, y, w, h)
  panel(x, y, w, h, "ACCESS FEED", S.events .. (S.events == 1 and " event" or " events"))
  for k = 1, h - 1 do
    local e = S.feed[k]
    local ry = y + k
    if e then
      B.text(x + 1, ry, e.t, C.lightGray, nil)
      B.text(x + 7, ry, padR(e.kind, 6), e.col, nil)
      local cx = x + 14
      if e.door then
        local d = S.doors[e.door]
        B.text(cx, ry, "D" .. e.door, lvlCol(d and d.cfg.need), nil)
        B.text(cx + 3, ry, padR(d and d.cfg.room or "?", 13), C.white, nil)
        cx = cx + 17
        region(function() S.sel = e.door end, x, ry, w, 1)
      end
      B.text(cx, ry, trunc(e.text, x + w - 1 - cx), e.lvl and lvlCol(e.lvl) or C.lightGray, nil)
    elseif k == 1 then
      B.text(x + 1, ry, "nothing yet - waiting for a door", C.lightGray, nil)
    end
  end
end

local function drawDetail(x, y, w, h)
  local i = S.sel
  local d = S.doors[i]
  local s, col = stateOf(d)
  local need = d.cfg.need or i
  panel(x, y, w, h, "DOOR " .. i .. "  " .. d.cfg.name, s, col)
  local function row(k, label, text, c)
    if k >= h then return end
    B.text(x + 1, y + k, label, C.lightGray, nil)
    B.text(x + 8, y + k, trunc(text, w - 9), c or C.white, nil)
  end
  row(1, "ROOM", d.cfg.room)
  row(2, "NEEDS", "L" .. need .. "+ " .. (LEVEL_NAMES[need] or ""), lvlCol(need))
  if d.state == "open" and now() < d.openUntil then
    row(3, "STATE", s, col)
    local frac = clamp((d.openUntil - now()) / CONFIG.openTime, 0, 1)
    local bw = w - 20
    for k = 0, bw - 1 do B.put(x + 18 + k, y + 3, THIN, k < frac * bw and C.lime or C.gray, nil) end
  else
    row(3, "STATE", s, col)
  end
  row(4, "COUNT", "")
  B.text(x + 8, y + 4, d.opens .. " opened", C.lime, nil)
  B.text(x + 9 + #(d.opens .. " opened"), y + 4, " " .. d.denies .. " denied", d.denies > 0 and C.red or C.lightGray, nil)
  if d.last then
    row(5, "LAST", (d.last.lvl and ("L" .. d.last.lvl .. " " .. (LEVEL_NAMES[d.last.lvl] or "") .. " ") or "")
      .. (d.last.id and ("card #" .. d.last.id .. " ") or "") .. "at " .. d.last.t, lvlCol(d.last.lvl))
  else
    row(5, "LAST", "nobody yet", C.lightGray)
  end
  row(6, "FROM", d.from or "-", C.lightGray)
  if h > 7 then
    local ry = y + 7
    B.text(x + 1, ry, "5 MIN", C.lightGray, nil)
    local b0 = floor(now() / 10)
    local n = w - 13
    for k = 0, n - 1 do
      local v = d.tl[b0 - (n - 1 - k)]
      B.put(x + 8 + k, ry, THIN, v == 2 and C.red or v == 1 and C.lime or C.gray, nil)
    end
    B.text(x + 9 + n, ry, "now", C.lightGray, nil)
  end
end

local function drawStats(x, y, w, h)
  panel(x, y, w, h, "CARDS USED", nil)
  local top = 1
  for l = 1, 5 do top = max(top, S.used[l]) end
  for l = 1, 5 do
    if l < h then
      local ry = y + l
      B.text(x + 1, ry, "L" .. l, lvlCol(l), nil)
      local n = tostring(S.used[l])
      local bw = w - 6 - #n
      local fill = floor(S.used[l] / top * bw + 0.5)
      for k = 0, bw - 1 do B.put(x + 4 + k, ry, THIN, k < fill and lvlCol(l) or C.gray, nil) end
      B.text(x + w - 1 - #n, ry, n, C.white, nil)
    end
  end
  if h > 6 then
    B.text(x + 1, y + 6, "DENIED", C.red, nil)
    B.text(x + w - 1 - #tostring(S.denied), y + 6, tostring(S.denied), C.white, nil)
  end
  if h > 7 then
    B.text(x + 1, y + 7, "CARDS WRITTEN", C.cyan, nil)
    B.text(x + w - 1 - #tostring(S.issued), y + 7, tostring(S.issued), C.white, nil)
  end
end

local function drawStatus()
  local y = H - 1
  B.fill(0, y, W, 1, C.gray)
  local x = 1
  local function part(s, c)
    B.text(x, y, CH_DOT, c, C.gray); B.text(x + 2, y, s, C.white, C.gray); x = x + #s + 4
  end
  if S.modem then part("rednet " .. S.modem .. " : " .. CONFIG.protocol, C.lime)
  else part("NO MODEM - put a modem on this computer", C.red) end
  part(CONFIG.senseSide and ("sensing " .. CONFIG.senseSide) or "sensing off", CONFIG.senseSide and C.lime or C.lightGray)
  local hint = "tap a door   D demo   Q quit "
  B.text(W - #hint - 1, y, hint, C.lightGray, C.gray)
end

local function render()
  S.regions = {}
  B.fill(0, 0, W, H, C.black)
  drawHeader()
  drawPlan()
  drawDoorsRows()
  local py = G.panelY
  local ph = H - 1 - py
  if ph >= 3 then
    local fw = floor(W * 0.43)
    local sw = 24
    local dw = W - fw - sw - 2
    drawFeed(0, py, fw, ph)
    drawDetail(fw + 1, py, dw, ph)
    drawStats(fw + dw + 2, py, sw, ph)
  end
  drawStatus()
  B.flush()
end

---------------------------------------------------------------------
-- Setup and main loop
---------------------------------------------------------------------
local function openModems()
  S.modem = nil
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "modem" then
      pcall(rednet.open, n)
      S.modem = S.modem or n
    end
  end
end
local function setupMonitor()
  if CONFIG.monitor then mon = peripheral.wrap(CONFIG.monitor); monName = CONFIG.monitor
  else mon = peripheral.find("monitor"); monName = mon and peripheral.getName(mon) end
  if not mon then error("No monitor found. Attach the 6x2 advanced monitor.", 0) end
  if not mon.isColour() then error("This needs an ADVANCED (gold) monitor.", 0) end
  mon.setTextScale(CONFIG.textScale)
  for i = 0, 15 do mon.setPaletteColour(2 ^ i, PALETTE[i + 1]) end
  B.resize(mon.getSize())
  layout()
end
local function restore()
  if not mon then return end
  for i = 0, 15 do local c = 2 ^ i; mon.setPaletteColour(c, term.nativePaletteColour(c)) end
  mon.setBackgroundColour(colours.black); mon.clear(); mon.setCursorPos(1, 1)
end
local function drawTerminal()
  term.setBackgroundColour(colours.black); term.clear(); term.setCursorPos(1, 1)
  term.setTextColour(colours.yellow); print("FACTORY DOORS board")
  term.setTextColour(colours.lightGrey)
  print(("Monitor %s  %dx%d"):format(monName or "?", W, H))
  print("Modem: " .. (S.modem or "NONE (demo only)"))
  print("Protocol: " .. CONFIG.protocol)
  print("")
  term.setTextColour(colours.white)
  print("D  demo on/off")
  print("<- ->  select door")
  print("Q  quit")
end

local function main()
  S = fresh()
  setupMonitor()
  openModems()
  feed("BOARD", nil, S.modem and ("online, listening on " .. S.modem) or "online - NO MODEM, showing demo", S.modem and C.lightBlue or C.red)
  drawTerminal()
  sense()
  local last = now()
  local timer = os.startTimer(CONFIG.frame)
  while true do
    local e, a, b, c = os.pullEventRaw()
    if e == "terminate" then return
    elseif e == "timer" and a == timer then
      local t = now()
      update(t - last); last = t
      demoStep()
      render()
      timer = os.startTimer(CONFIG.frame)
    elseif e == "rednet_message" and c == CONFIG.protocol then
      handle(a, b)
    elseif e == "redstone" then
      sense()
    elseif e == "monitor_touch" and (a == monName or not monName) then
      for k = #S.regions, 1, -1 do
        local g = S.regions[k]
        if b >= g.x + 1 and c >= g.y + 1 and b < g.x + 1 + g.w and c < g.y + 1 + g.h then g.fn(); break end
      end
    elseif e == "monitor_resize" then
      B.resize(mon.getSize()); layout()
    elseif e == "peripheral" or e == "peripheral_detach" then
      openModems(); drawTerminal()
    elseif e == "key" then
      if a == keys.q then return
      elseif a == keys.d then S.demoManual = not demoOn()
      elseif a == keys.left then S.sel = max(1, S.sel - 1)
      elseif a == keys.right then S.sel = min(#S.doors, S.sel + 1) end
    end
  end
end

local ok, err = pcall(main)
restore()
term.setBackgroundColour(colours.black); term.setTextColour(colours.white)
if not ok then printError(err) end
