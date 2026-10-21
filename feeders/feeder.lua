--[[
  FEEDER - move everything from a farm barrel into the vault
  ---------------------------------------------------------------
  One small computer per farm. It empties the farm's barrel/chest into
  the vault's INPUT barrel (minecraft:barrel_73), and the vault program
  stores it like anything you drop in by hand. It also tells the
  network who it is ("Andesite Farm"), what it moved and if it is stuck.

  SETUP
    1. Put the computer next to the farm barrel (touching it).
    2. Put a wired modem on the computer and connect it with networking
       cable to the vault network (the same cable as the vault's
       input barrel). Right-click the modems so they turn red.
    3. Run it. The first run asks for the farm name and the target,
       then saves it in feeder.cfg. Run "feeder setup" to change it.
    4. To start it by itself after a server restart, save it as startup:
       wget <url> startup.lua

  Items can only move through cable (or a barrel touching the computer).
  A wireless/ender modem only carries the status messages.

  Keys: P pause/resume   S setup   Q quit
]]

local ARGS = {...}
local PROTOCOL = "vault_feeders"
local CFG_FILE = "feeder.cfg"
local DEFAULT_TARGET = "minecraft:barrel_73"   -- vault INPUT_CHEST in vaultMain.lua
local INTERVAL = 1                             -- seconds between barrel checks
local REPORT_EVERY = 5                         -- seconds between status broadcasts
local SIDES = {"top", "bottom", "left", "right", "front", "back"}

local cfg
local st = {state = "STARTING", total = 0, items = {}, recent = {}, paused = false,
            last = nil, lastAt = nil, modem = nil, sourceUsed = 0, sourceSize = 0}

---------------------------------------------------------------------
-- Config
---------------------------------------------------------------------
local function isInventory(name)
  if peripheral.hasType then return peripheral.hasType(name, "inventory") end
  local m = peripheral.wrap(name)
  return m ~= nil and m.pushItems ~= nil and m.list ~= nil
end
local function sideInventories()
  local out = {}
  for _, s in ipairs(SIDES) do if peripheral.isPresent(s) and isInventory(s) then out[#out + 1] = s end end
  return out
end
local function networkInventories(skip)
  local out = {}
  for _, n in ipairs(peripheral.getNames()) do
    local isSide = false
    for _, s in ipairs(SIDES) do if s == n then isSide = true end end
    if not isSide and n ~= skip and isInventory(n) then out[#out + 1] = n end
  end
  table.sort(out, function(a, b)
    local ab, bb = a:find("barrel", 1, true) ~= nil, b:find("barrel", 1, true) ~= nil
    if ab ~= bb then return ab end
    return a < b
  end)
  return out
end
local function loadCfg()
  if not fs.exists(CFG_FILE) then return nil end
  local f = fs.open(CFG_FILE, "r")
  local t = textutils.unserialize(f.readAll() or "")
  f.close()
  if type(t) == "table" and t.name and t.from and t.to then return t end
  return nil
end
local function saveCfg(t)
  local f = fs.open(CFG_FILE, "w")
  f.write(textutils.serialize(t))
  f.close()
end
local function ask(prompt, default)
  term.setTextColour(colours.white)
  write(prompt .. (default and (" [" .. default .. "]") or "") .. ": ")
  term.setTextColour(colours.yellow)
  local s = read()
  term.setTextColour(colours.white)
  if s == "" then return default end
  return s
end
local function setup(old)
  term.setBackgroundColour(colours.black); term.clear(); term.setCursorPos(1, 1)
  term.setTextColour(colours.yellow); print("FEEDER SETUP"); print("")
  local t = {}
  t.name = ask("Farm name (e.g. Andesite Farm)", old and old.name or "Andesite Farm")

  -- source: a barrel/chest touching the computer
  local sides = sideInventories()
  term.setTextColour(colours.lightGrey)
  print("")
  print("Inventories touching this computer: " .. (#sides > 0 and table.concat(sides, ", ") or "none"))
  local defFrom = (old and old.from) or sides[1]
  t.from = ask("Take items FROM", defFrom)
  while not t.from or not peripheral.isPresent(t.from) do
    printError("No inventory '" .. tostring(t.from) .. "'. Put the barrel next to the computer.")
    t.from = ask("Take items FROM", defFrom)
  end

  -- target: something on the cable network
  local nets = networkInventories(t.from)
  term.setTextColour(colours.lightGrey)
  print("")
  print("On the cable network (" .. #nets .. "):")
  for i = 1, math.min(6, #nets) do print("  " .. nets[i]) end
  if #nets > 6 then print("  ... type part of a name to search") end
  local defTo = (old and old.to) or (peripheral.isPresent(DEFAULT_TARGET) and DEFAULT_TARGET) or nets[1]
  while true do
    local want = ask("Push items TO", defTo)
    if want and peripheral.isPresent(want) and want ~= t.from then t.to = want; break end
    local hit
    for _, n in ipairs(nets) do if want and n:find(want, 1, true) then hit = n; break end end
    if hit and ask("Use " .. hit .. "? (y/n)", "y"):lower() == "y" then t.to = hit; break end
    printError("Not found on the network. Check the modem is red and the cable is connected.")
  end
  saveCfg(t)
  term.setTextColour(colours.lime); print(""); print("Saved to " .. CFG_FILE); sleep(1)
  return t
end

---------------------------------------------------------------------
-- Network
---------------------------------------------------------------------
local function openModem()
  st.modem = nil
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.getType(n) == "modem" then
      pcall(rednet.open, n)
      st.modem = st.modem or n
    end
  end
  -- register the name once so other computers can rednet.lookup("vault_feeders")
  if st.modem and st.hosted ~= cfg.name then
    if st.hosted then pcall(rednet.unhost, PROTOCOL) end
    if pcall(rednet.host, PROTOCOL, cfg.name) then st.hosted = cfg.name end
  end
end
local function ratePerMin()
  local cut, n = os.clock() - 60, 0
  for i = #st.recent, 1, -1 do
    local r = st.recent[i]
    if r.t < cut then table.remove(st.recent, i) else n = n + r.n end
  end
  return n
end
local function status()
  local top = {}
  for name, n in pairs(st.items) do top[#top + 1] = {name = name, count = n} end
  table.sort(top, function(a, b) return a.count > b.count end)
  while #top > 5 do table.remove(top) end
  return {kind = "feeder", name = cfg.name, id = os.getComputerID(), state = st.state,
          from = cfg.from, to = cfg.to, moved = st.total, perMin = ratePerMin(), top = top,
          last = st.last, sourceUsed = st.sourceUsed, sourceSize = st.sourceSize}
end
local function report(to)
  if not st.modem then return end
  if to then rednet.send(to, status(), PROTOCOL) else rednet.broadcast(status(), PROTOCOL) end
end

---------------------------------------------------------------------
-- Work
---------------------------------------------------------------------
local function setState(s)
  if s ~= st.state then st.state = s; report() end
end
local function pass()
  if st.paused then return setState("PAUSED") end
  local src = peripheral.wrap(cfg.from)
  if not src then return setState("NO SOURCE") end
  if not peripheral.isPresent(cfg.to) then return setState("NO TARGET") end
  local ok, list = pcall(src.list)
  if not ok or type(list) ~= "table" then return setState("NO SOURCE") end
  local okS, size = pcall(src.size)
  st.sourceSize = okS and size or 0
  local used, moved, stuck = 0, 0, false
  for slot, item in pairs(list) do
    used = used + 1
    local okP, n = pcall(src.pushItems, cfg.to, slot)
    n = okP and n or 0
    if n > 0 then
      moved = moved + n
      st.items[item.name] = (st.items[item.name] or 0) + n
      st.last = item.name
      st.lastAt = os.clock()
    end
    if n < item.count then stuck = true end
  end
  st.sourceUsed = used
  if moved > 0 then
    st.total = st.total + moved
    st.recent[#st.recent + 1] = {t = os.clock(), n = moved}
  end
  if stuck then setState("TARGET FULL")
  elseif moved > 0 then setState("MOVING")
  else setState("IDLE") end
end

---------------------------------------------------------------------
-- Screen
---------------------------------------------------------------------
local STATE_COL = {MOVING = colours.lime, IDLE = colours.lightGrey, PAUSED = colours.yellow,
                   ["TARGET FULL"] = colours.red, ["NO SOURCE"] = colours.red, ["NO TARGET"] = colours.red}
local function short(id)
  return (tostring(id):gsub("^[%w_]+:", ""):gsub("_", " "))
end
local function draw()
  local w, h = term.getSize()
  term.setBackgroundColour(colours.black); term.clear()
  term.setCursorPos(1, 1); term.setBackgroundColour(colours.grey); term.clearLine()
  term.setTextColour(colours.yellow); write(" FEEDER  "); term.setTextColour(colours.white); write(cfg.name)
  local s = " " .. st.state .. " "
  term.setCursorPos(w - #s + 1, 1); term.setBackgroundColour(STATE_COL[st.state] or colours.grey)
  term.setTextColour(colours.black); write(s)
  term.setBackgroundColour(colours.black)
  local function line(y, label, value, col)
    term.setCursorPos(2, y); term.setTextColour(colours.lightGrey); write(label)
    term.setCursorPos(12, y); term.setTextColour(col or colours.white); write(value)
  end
  line(3, "From", cfg.from .. "  (" .. st.sourceUsed .. "/" .. st.sourceSize .. " slots)")
  line(4, "To", cfg.to)
  line(5, "Moved", st.total .. " items   " .. ratePerMin() .. "/min", colours.lime)
  line(6, "Last", st.last and short(st.last) or "-")
  line(7, "Network", st.modem and ("reporting on " .. st.modem) or "no modem - not reporting",
       st.modem and colours.white or colours.orange)
  term.setCursorPos(2, 9); term.setTextColour(colours.yellow); write("Moved per item")
  local top = status().top
  for i, t in ipairs(top) do
    if 9 + i < h - 1 then line(9 + i, tostring(t.count), short(t.name)) end
  end
  if st.state == "TARGET FULL" then
    term.setCursorPos(2, h - 1); term.setTextColour(colours.red); write("Target full - vault program off or crafting?")
  end
  term.setCursorPos(2, h); term.setTextColour(colours.grey); write("P pause   S setup   Q quit")
end

---------------------------------------------------------------------
-- Main
---------------------------------------------------------------------
cfg = loadCfg()
if not cfg or ARGS[1] == "setup" then cfg = setup(cfg) end
openModem()

local function worker()
  while true do pass(); sleep(INTERVAL) end
end
local function listener()
  while true do
    local from, msg = rednet.receive(PROTOCOL)
    if type(msg) == "table" and (msg.to == nil or msg.to == cfg.name or msg.to == os.getComputerID()) then
      if msg.cmd == "ping" then report(from)
      elseif msg.cmd == "pause" then st.paused = true; report(from)
      elseif msg.cmd == "resume" then st.paused = false; report(from) end
    end
  end
end
local function ui()
  local tick = os.startTimer(1)
  local sinceReport = 0
  draw()
  while true do
    local e, a = os.pullEvent()
    if e == "timer" and a == tick then
      sinceReport = sinceReport + 1
      if sinceReport >= REPORT_EVERY then sinceReport = 0; report() end
      draw(); tick = os.startTimer(1)
    elseif e == "key" then
      if a == keys.q then return
      elseif a == keys.p then st.paused = not st.paused; if not st.paused then st.state = "IDLE" end; draw()
      elseif a == keys.s then cfg = setup(cfg); openModem(); draw() end
    elseif e == "peripheral" or e == "peripheral_detach" then
      openModem()
    end
  end
end

parallel.waitForAny(worker, listener, ui)
if st.modem then pcall(rednet.unhost, PROTOCOL) end
term.setBackgroundColour(colours.black); term.setTextColour(colours.white); term.clear(); term.setCursorPos(1, 1)
