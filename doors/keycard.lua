-- KEYCARD READER / WRITER (floppy disks are keycards, levels 1-5)
--
-- SETUP PER DOOR:
--   1. Attach a disk drive to this computer (wired modem or directly adjacent).
--   2. Run: keycard.lua
--   3. Set C.REQUIRED_LEVEL below: card level >= requirement opens the door.
--      L5 opens everything, L1 only opens L1 doors.
-- WRITE A CARD:
--   Insert a floppy disk, click a level 1-5 (or keys 1-5), click WRITE CARD.
--   The level is stored in ".keycard" on the floppy + disk label "KEYCARD Lx".
--   ERASE wipes the file and relabels the disk BLANK.
-- DOOR WIRING:
--   Redstone output on C.DOOR_SIDE pulses for C.OPEN_TIME seconds.
--   Point it at the door / use a wired modem + redstone integrator as needed.
-- LOG:
--   Every write / erase / open / denied event appends to keycard.log.

local C = {
  REQUIRED_LEVEL = 3,
  DOOR_SIDE = "bottom",
  OPEN_TIME = 5,
  AUTO_OPEN = true,
  CARD_FILE = ".keycard",
  AUDIT = "keycard.log",
  LOG_LINES = 4,
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
local LROW, WROW, EROW = 4, 6, 7

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
  text(2, 1, "KEYCARD L" .. C.REQUIRED_LEVEL, colors.white, colors.gray)
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

local function writeCard(level, card)
  if not drv or not card or not card.present then return false, "NO DISK" end
  level = clamp(math.floor(tonumber(level) or 0), 1, 5)
  local wroteFile = false
  local mount = card.mount
  if not mount then
    local ok, m = pcall(drv.getMountPath)
    if ok and m then mount = m end
  end
  if mount then
    local f = fs.open(fs.combine(mount, C.CARD_FILE), "w")
    if f then
      f.write("level=" .. level)
      f.close()
      wroteFile = true
    end
  end
  if not pcall(drv.setDiskLabel, "KEYCARD L" .. level) then
    pcall(drv.setLabel, "KEYCARD L" .. level)
  end
  audit("WRITE L" .. level .. " id " .. tostring(card.id) .. (wroteFile and "" or " LABEL-ONLY"))
  return true, wroteFile and ("WROTE L" .. level) or ("LABEL L" .. level)
end

local function eraseCard(card)
  if not drv or not card or not card.present then return false, "NO DISK" end
  if card.mount and fs.exists(fs.combine(card.mount, C.CARD_FILE)) then
    pcall(fs.delete, fs.combine(card.mount, C.CARD_FILE))
  else
    local ok, m = pcall(drv.getMountPath)
    if ok and m then pcall(fs.delete, fs.combine(m, C.CARD_FILE)) end
  end
  if not pcall(drv.setDiskLabel, "BLANK") then
    pcall(drv.setLabel, "BLANK")
  end
  audit("ERASE id " .. tostring(card.id))
  return true, "ERASED"
end

local openUntil = nil

local function closeDoor(silent)
  pcall(redstone.setOutput, C.DOOR_SIDE, false)
  if openUntil and not silent then audit("DOOR CLOSE") end
  openUntil = nil
end

local function pulseDoor(card)
  pcall(redstone.setOutput, C.DOOR_SIDE, true)
  openUntil = os.clock() + C.OPEN_TIME
  audit("DOOR OPEN L" .. tostring(card and card.level) .. " id " .. tostring(card and card.id))
end

local function lvlBtnW()
  return math.max(3, math.floor(RW / 5))
end

local function lvlBtnX(i)
  local bw = lvlBtnW()
  if i >= 5 then return RX + RW - bw end
  return RX + (i - 1) * bw
end

local function drawMain(card, granted, selLevel, msg)
  clear()
  local status, color = "READY ", colors.lime
  if not drv then
    status, color = "NO DRIVE ", colors.red
  elseif openUntil then
    status, color = "OPEN " .. math.ceil(openUntil - os.clock()) .. "s ", colors.orange
  elseif card.present and granted then
    status, color = "GRANTED ", colors.lime
  elseif card.present then
    status, color = "DENIED ", colors.red
  end
  header(status, color)
  text(2, 3, "KEYCARD", colors.yellow)
  text(RX, 3, "SET LEVEL", colors.yellow)
  local bw = lvlBtnW()
  for i = 1, 5 do
    local x = lvlBtnX(i)
    local w = (i == 5) and (RX + RW - x) or bw
    local on = (i == selLevel)
    fill(x, LROW, w, on and colors.green or colors.gray)
    local label = tostring(i)
    text(x + math.floor((w - #label) / 2), LROW, label, colors.white, on and colors.green or colors.gray)
  end
  local wl = "WRITE L" .. selLevel
  fill(RX, WROW, RW, colors.green)
  text(RX + math.floor((RW - #wl - 2) / 2), WROW, "[ " .. wl .. " ]", colors.white, colors.green)
  fill(RX, EROW, RW, colors.gray)
  text(RX + math.floor((RW - 9) / 2), EROW, "[ ERASE ]", colors.white, colors.gray)
  text(2, 4, "DISK  " .. (drv and (card.present and "PRESENT" or "EMPTY") or "NO DRIVE"), colors.white)
  text(2, 5, "LABEL " .. trunc(card.label or "--", 18), colors.white)
  text(2, 6, "ID    " .. trunc(card.id or "--", 18), colors.white)
  if card.present and card.level then
    local c = LEVEL_COLORS[card.level] or colors.white
    text(2, 7, "CARD  LEVEL " .. card.level .. " " .. (C.LEVEL_NAMES[card.level] or ""), c)
    fill(2, 8, 22, c)
    text(4, 8, "LEVEL " .. card.level .. (card.fromLabel and "*" or ""), colors.black, c)
  elseif card.present then
    text(2, 7, "CARD  BLANK", colors.gray)
    fill(2, 8, 22, colors.gray)
    text(4, 8, "NO LEVEL", colors.white, colors.gray)
  else
    text(2, 7, "CARD  --", colors.gray)
    fill(2, 8, 22, colors.black)
    text(4, 8, "INSERT DISK", colors.gray, colors.black)
  end
  text(2, 10, "DOOR", colors.yellow)
  text(2, 11, "NEED  LEVEL " .. C.REQUIRED_LEVEL .. "+ (" .. (C.LEVEL_NAMES[C.REQUIRED_LEVEL] or "") .. ")", colors.white)
  if not card.present then
    text(2, 12, "ACCESS WAITING", colors.gray)
  elseif granted then
    text(2, 12, "ACCESS GRANTED", colors.lime)
  else
    text(2, 12, "ACCESS DENIED", colors.red)
  end
  if openUntil then
    text(2, 13, "OPEN " .. math.ceil(openUntil - os.clock()) .. "s", colors.orange)
  elseif C.AUTO_OPEN then
    text(2, 13, "AUTO-OPEN ON", colors.gray)
  else
    text(2, 13, "PRESS OPEN", colors.gray)
  end
  text(RX, 9, "DOORS", colors.yellow)
  for i = 1, 5 do
    local c = LEVEL_COLORS[i] or colors.white
    text(RX, 9 + i, "L" .. i .. " " .. (C.LEVEL_NAMES[i] or ""), c)
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
  if granted and card.present then
    fill(2, 18, 12, colors.red)
    text(5, 18, "OPEN", colors.white, colors.red)
  else
    fill(2, 18, 12, colors.gray)
    text(5, 18, "OPEN", colors.lightGray, colors.gray)
  end
  fill(15, 18, 9, colors.gray)
  text(17, 18, "EJECT", colors.white, colors.gray)
  text(2, 19, "1-5 lvl W write X erase", colors.gray)
end

local function main()
  pcall(redstone.setOutput, C.DOOR_SIDE, false)
  findDrive()
  local selLevel = C.REQUIRED_LEVEL
  local msg = ""
  local prevPresent = false
  local timer = os.startTimer(0.5)
  while true do
    findDrive()
    local card = readCard()
    local granted = card.present and card.level and card.level >= C.REQUIRED_LEVEL
    if openUntil and os.clock() >= openUntil then closeDoor() end
    if card.present ~= prevPresent then msg = "" end
    if C.AUTO_OPEN and granted and card.present and not prevPresent and not openUntil then
      pulseDoor(card)
      msg = "OPEN L" .. card.level
    end
    prevPresent = card.present
    drawMain(card, granted, selLevel, msg)
    local e, a, b, c = os.pullEvent()
    if e == "timer" and a == timer then
      timer = os.startTimer(0.5)
    elseif e == "terminate" then
      closeDoor(true)
      return
    elseif e == "key" then
      if a == keys.one then selLevel = 1
      elseif a == keys.two then selLevel = 2
      elseif a == keys.three then selLevel = 3
      elseif a == keys.four then selLevel = 4
      elseif a == keys.five then selLevel = 5
      elseif a == keys.e then
        if drv then pcall(drv.ejectDisk) end
      elseif a == keys.enter or a == keys.space then
        if granted and card.present then
          pulseDoor(card)
          msg = "OPEN L" .. card.level
        else
          msg = "DENIED"
          audit("DENIED tap")
        end
      end
    elseif e == "char" then
      local ch = string.lower(a)
      if ch >= "1" and ch <= "5" then
        selLevel = tonumber(ch)
      elseif ch == "w" then
        local ok, m = writeCard(selLevel, card)
        msg = m
      elseif ch == "x" then
        local ok, m = eraseCard(card)
        msg = m
      elseif ch == "e" then
        if drv then pcall(drv.ejectDisk) end
      elseif ch == "o" then
        if granted and card.present then
          pulseDoor(card)
          msg = "OPEN L" .. card.level
        else
          msg = "DENIED"
        end
      end
    elseif e == "mouse_click" then
      local x, y = b, c
      if y == LROW and x >= RX and x < RX + RW then
        local bw = lvlBtnW()
        selLevel = clamp(math.floor((x - RX) / bw) + 1, 1, 5)
      elseif y == WROW and x >= RX and x < RX + RW then
        local ok, m = writeCard(selLevel, card)
        msg = m
      elseif y == EROW and x >= RX and x < RX + RW then
        local ok, m = eraseCard(card)
        msg = m
      elseif y == 18 and x >= 2 and x <= 13 then
        if granted and card.present then
          pulseDoor(card)
          msg = "OPEN L" .. card.level
        else
          msg = "DENIED"
          audit("DENIED click")
        end
      elseif y == 18 and x >= 15 and x <= 23 then
        if drv then pcall(drv.ejectDisk) end
      end
    end
  end
end

local ok, err = pcall(main)
closeDoor(true)
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
