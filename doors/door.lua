-- DOOR SELECT (linked to keycard.lua)
--
-- Run this on a door controller with a disk drive attached.
-- Insert a floppy keycard (written by keycard.lua, level 1-5).
-- Doors 1-5 unlock based on the card level: door N needs level >= N.
--   L1 card -> door 1 only.  L3 card -> doors 1, 2, 3.  L5 card -> all doors.
--
-- WIRING (pick one):
--   A) Bundled cable (default): one cable into C.BUNDLED_SIDE.
--      Door 1 = white, 2 = orange, 3 = magenta, 4 = lightBlue, 5 = yellow.
--      Change C.DOOR_COLORS to rewire without moving cables.
--   B) Separate sides: set C.DOOR_SIDES, e.g. { [1] = "left", [2] = "right" }.
--      Any door listed there uses plain redstone on that side instead.
--      Set C.BUNDLED_SIDE = nil to use sides only.
-- CARD FORMAT (must match keycard.lua):
--   File ".keycard" on the floppy containing "level=N", label "KEYCARD LN" fallback.

local C = {
  OPEN_TIME = 5,
  CARD_FILE = ".keycard",
  AUDIT = "door.log",
  LOG_LINES = 4,
  BUNDLED_SIDE = "back",
  DOOR_COLORS = { colors.white, colors.orange, colors.magenta, colors.lightBlue, colors.yellow },
  DOOR_SIDES = nil,
  LEVEL_NAMES = { "VISITOR", "STAFF", "SECURITY", "ENGINEER", "ADMIN" },
}

local LEVEL_COLORS = {
  [1] = colors.lightBlue,
  [2] = colors.lime,
  [3] = colors.yellow,
  [4] = colors.orange,
  [5] = colors.red,
}

local PULL0 = os.pullEvent
os.pullEvent = os.pullEventRaw or os.pullEvent

local W, H = term.getSize()
local PX = 28
local RX = PX - 1
local RW = W - PX + 1

local function clamp(x, lo, hi) return math.max(lo, math.min(hi, x)) end

local function trunc(s, n)
  s = tostring(s or "")
  if #s > n then return s:sub(1, n) end
  return s
end

local function fill(x, y, w, bg)
  term.setBackgroundColor(bg)
  term.setCursorPos(x, y)
  term.write(string.rep(" ", w))
end

local function text(x, y, s, fg, bg)
  term.setCursorPos(x, y)
  term.setTextColor(fg)
  term.setBackgroundColor(bg or colors.black)
  term.write(s)
end

local function clear()
  term.setCursorBlink(false)
  term.setBackgroundColor(colors.black)
  term.clear()
end

local function header(status, color)
  fill(1, 1, W, colors.gray)
  text(2, 1, "DOORS 1-5", colors.white, colors.gray)
  text(W - #status, 1, status, color, colors.gray)
end

local function audit(s)
  local f = fs.open(C.AUDIT, "a")
  if f then
    f.writeLine(os.date("%Y-%m-%d %H:%M") .. " " .. s)
    f.close()
  end
  -- FACTORY DOORS board: tell the door diagram what just happened (needs a modem)
  if rednet then
    pcall(peripheral.find, "modem", function(name) if not rednet.isOpen(name) then rednet.open(name) end end)
    pcall(rednet.broadcast, {log = s, need = C.REQUIRED_LEVEL, openTime = C.OPEN_TIME, label = os.getComputerLabel()}, "factory_doors")
  end
end

local function logTail(n)
  local out = {}
  if not fs.exists(C.AUDIT) then return out end
  local f = fs.open(C.AUDIT, "r")
  if not f then return out end
  local raw = f.readAll() or ""
  f.close()
  local lines = {}
  for line in (raw .. "\n"):gmatch("([^\n]*)\n") do
    lines[#lines + 1] = line
  end
  for i = math.max(1, #lines - n + 1), #lines do
    out[#out + 1] = lines[i]
  end
  return out
end

local drvName, drv = nil, nil

local function findDrive()
  if drvName then
    if peripheral.isPresent(drvName) then
      local ok, t = pcall(peripheral.getType, drvName)
      if ok and t == "drive" then
        if not drv then drv = peripheral.wrap(drvName) end
        return true
      end
    end
    drvName, drv = nil, nil
  end
  for _, n in ipairs(peripheral.getNames()) do
    if peripheral.hasType(n, "drive") then
      drvName, drv = n, peripheral.wrap(n)
      return true
    end
  end
  return false
end

local function readCard()
  local card = { present = false }
  if not drv then return card end
  local ok, present = pcall(drv.isDiskPresent)
  if not ok or not present then return card end
  card.present = true
  local okId, id = pcall(drv.getDiskID)
  if okId then card.id = id end
  local okL, vL = pcall(drv.getDiskLabel)
  if not okL then okL, vL = pcall(drv.getLabel) end
  if okL then card.label = vL end
  local okM, m = pcall(drv.getMountPath)
  if okM then card.mount = m end
  card.level = nil
  if card.mount then
    local p = fs.combine(card.mount, C.CARD_FILE)
    if fs.exists(p) then
      local f = fs.open(p, "r")
      if f then
        local raw = f.readAll() or ""
        f.close()
        local lv = tonumber(raw:match("level%s*=%s*(%d)")) or tonumber(raw:match("(%d)"))
        if lv and lv >= 1 and lv <= 5 then card.level = lv end
      end
    end
  end
  if not card.level and card.label then
    local lv = tonumber(card.label:match("[Ll]%s*(%d)"))
    if lv and lv >= 1 and lv <= 5 then
      card.level = lv
      card.fromLabel = true
    end
  end
  return card
end

local function unlocked(n, card)
  return card.present and card.level and card.level >= n
end

local openDoors = {}

local function applyOutputs()
  if C.BUNDLED_SIDE then
    local mask = 0
    for n in pairs(openDoors) do
      local col = C.DOOR_COLORS and C.DOOR_COLORS[n]
      if col then mask = mask + col end
    end
    pcall(redstone.setBundledOutput, C.BUNDLED_SIDE, mask)
  end
  if C.DOOR_SIDES then
    for n = 1, 5 do
      local s = C.DOOR_SIDES[n]
      if s then pcall(redstone.setOutput, s, openDoors[n] ~= nil) end
    end
  end
end

local function clearOutputs()
  if C.BUNDLED_SIDE then pcall(redstone.setBundledOutput, C.BUNDLED_SIDE, 0) end
  if C.DOOR_SIDES then
    for n = 1, 5 do
      local s = C.DOOR_SIDES[n]
      if s then pcall(redstone.setOutput, s, false) end
    end
  end
  openDoors = {}
end

local function openDoor(n, card)
  n = clamp(math.floor(tonumber(n) or 0), 1, 5)
  openDoors[n] = os.clock() + C.OPEN_TIME
  applyOutputs()
  audit("DOOR " .. n .. " OPEN L" .. tostring(card and card.level) .. " id " .. tostring(card and card.id))
end

local function doorRow(i) return 4 + (i - 1) * 2 end

local function openCount()
  local n = 0
  for _ in pairs(openDoors) do n = n + 1 end
  return n
end

local function drawDoors(card, msg)
  clear()
  local status, color = "READY ", colors.lime
  if not drv then
    status, color = "NO DRIVE ", colors.red
  elseif openCount() > 0 then
    local first, left = nil, 0
    for n, untilT in pairs(openDoors) do
      if not first or n < first then first = n end
      left = math.max(left, math.ceil(untilT - os.clock()))
    end
    status, color = "OPEN " .. tostring(first) .. " " .. left .. "s ", colors.orange
  elseif card.present and card.level then
    status, color = "L" .. card.level .. " 1-" .. card.level .. " ", colors.lime
  elseif card.present then
    status, color = "BLANK CARD ", colors.red
  else
    status, color = "INSERT CARD ", colors.gray
  end
  header(status, color)
  text(2, 3, "KEYCARD", colors.yellow)
  text(RX, 3, "SELECT DOOR", colors.yellow)
  text(2, 4, "DISK  " .. (drv and (card.present and "PRESENT" or "EMPTY") or "NO DRIVE"), colors.white)
  text(2, 5, "LABEL " .. trunc(card.label or "--", 18), colors.white)
  text(2, 6, "ID    " .. trunc(card.id or "--", 18), colors.white)
  if card.present and card.level then
    local c = LEVEL_COLORS[card.level] or colors.white
    text(2, 7, "CARD  LEVEL " .. card.level .. " " .. (C.LEVEL_NAMES[card.level] or ""), c)
    fill(2, 8, 22, c)
    text(4, 8, "OPENS 1-" .. card.level, colors.black, c)
  elseif card.present then
    text(2, 7, "CARD  BLANK", colors.gray)
    fill(2, 8, 22, colors.gray)
    text(4, 8, "NO LEVEL", colors.white, colors.gray)
  else
    text(2, 7, "CARD  --", colors.gray)
    fill(2, 8, 22, colors.black)
    text(4, 8, "INSERT DISK", colors.gray, colors.black)
  end
  text(2, 10, "ACCESS", colors.yellow)
  if card.present and card.level then
    text(2, 11, "DOORS 1-" .. card.level .. " OPEN", colors.lime)
  elseif card.present then
    text(2, 11, "NO DOORS", colors.red)
  else
    text(2, 11, "WAITING", colors.gray)
  end
  if openCount() > 0 then
    text(2, 12, "OPEN NOW", colors.orange)
  elseif C.BUNDLED_SIDE then
    text(2, 12, "OUT " .. C.BUNDLED_SIDE, colors.gray)
  else
    text(2, 12, "SIDES MODE", colors.gray)
  end
  for i = 1, 5 do
    local r = doorRow(i)
    if unlocked(i, card) then
      fill(RX, r, RW, colors.green)
      fill(RX, r + 1, RW, colors.green)
      local t = i .. " " .. (C.LEVEL_NAMES[i] or "")
      text(RX + math.floor((RW - #t) / 2), r, t, colors.white, colors.green)
      text(RX + math.floor((RW - 12) / 2), r + 1, "TAP TO OPEN", colors.white, colors.green)
    else
      fill(RX, r, RW, colors.gray)
      fill(RX, r + 1, RW, colors.black)
      local t = i .. " " .. (C.LEVEL_NAMES[i] or "")
      text(RX + math.floor((RW - #t) / 2), r, t, colors.lightGray, colors.gray)
      local u = card.present and "NEEDS L" .. i or "NEEDS CARD"
      text(RX + math.floor((RW - #u) / 2), r + 1, u, colors.gray, colors.black)
    end
  end
  text(RX, 15, "ACCESS LOG", colors.yellow)
  local lines = logTail(C.LOG_LINES)
  local start = C.LOG_LINES - #lines
  for i = 1, C.LOG_LINES do
    local row = 15 + i
    if row <= H then
      fill(RX, row, RW, colors.black)
      local li = i - start
      if li >= 1 and lines[li] then
        text(RX, row, trunc(lines[li], RW), colors.lightGray)
      end
    end
  end
  if msg and msg ~= "" then text(2, 17, trunc(msg, 24), colors.red) end
  fill(2, 18, 12, colors.gray)
  text(5, 18, "EJECT", colors.white, colors.gray)
  text(2, 19, "insert card, click door", colors.gray)
end

local function tryOpen(n, card)
  n = clamp(math.floor(tonumber(n) or 0), 1, 5)
  if unlocked(n, card) then
    openDoor(n, card)
    return "OPEN " .. n
  end
  audit("DENIED door " .. n .. " id " .. tostring(card and card.id))
  if not card.present then return "INSERT CARD" end
  if not card.level then return "BLANK CARD" end
  return "DENIED NEED L" .. n
end

local function main()
  clearOutputs()
  findDrive()
  local msg = ""
  local prevPresent = false
  local timer = os.startTimer(0.5)
  while true do
    findDrive()
    local card = readCard()
    local now = os.clock()
    local done = {}
    for n, untilT in pairs(openDoors) do
      if now >= untilT then done[#done + 1] = n end
    end
    for _, n in ipairs(done) do
      openDoors[n] = nil
      audit("DOOR " .. n .. " CLOSE")
    end
    if #done > 0 then applyOutputs() end
    if card.present ~= prevPresent then msg = "" end
    prevPresent = card.present
    drawDoors(card, msg)
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == timer then
      timer = os.startTimer(0.5)
    elseif e == "terminate" then
      clearOutputs()
      return
    elseif e == "key" then
      if a == keys.one then msg = tryOpen(1, card)
      elseif a == keys.two then msg = tryOpen(2, card)
      elseif a == keys.three then msg = tryOpen(3, card)
      elseif a == keys.four then msg = tryOpen(4, card)
      elseif a == keys.five then msg = tryOpen(5, card)
      elseif a == keys.e then
        if drv then pcall(drv.ejectDisk) end
      end
    elseif e == "char" then
      if a >= "1" and a <= "5" then
        msg = tryOpen(tonumber(a), card)
      elseif string.lower(a) == "e" then
        if drv then pcall(drv.ejectDisk) end
      end
    elseif e == "mouse_click" then
      local x, y = b, c
      if x >= RX and x < RX + RW and y >= 4 and y <= 13 then
        msg = tryOpen(math.floor((y - 4) / 2) + 1, card)
      elseif y == 18 and x >= 2 and x <= 13 then
        if drv then pcall(drv.ejectDisk) end
      end
    end
  end
end

local ok, err = pcall(main)
clearOutputs()
os.pullEvent = PULL0
term.setCursorBlink(false)
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
if not ok then
  term.setCursorPos(1, H - 1)
  term.setTextColor(colors.red)
  term.write(tostring(err))
end
term.setCursorPos(1, H)
