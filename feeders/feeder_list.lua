--[[
  FEEDER LIST - see every farm feeder on the network
  ---------------------------------------------------------------
  Run on any computer with a modem (the main computer works too,
  in a second tab: "bg feeder_list" on an advanced computer).
  Uses a monitor if one is attached, otherwise the terminal.

  Keys: P pause all   R resume all   Q quit
]]

local PROTOCOL = "vault_feeders"
local STALE = 15   -- seconds without a report = OFFLINE

local out = peripheral.find("monitor") or term
if out ~= term then out.setTextScale(0.5) end
local feeders, order = {}, {}

for _, n in ipairs(peripheral.getNames()) do
  if peripheral.getType(n) == "modem" then pcall(rednet.open, n) end
end
if not rednet.isOpen() then error("Put a modem on this computer.", 0) end
rednet.broadcast({cmd = "ping"}, PROTOCOL)

local COL = {MOVING = colours.lime, IDLE = colours.lightGrey, PAUSED = colours.yellow, OFFLINE = colours.grey}
local function short(id) return (tostring(id or "-"):gsub("^[%w_]+:", ""):gsub("_", " ")) end

local function draw()
  local w, h = out.getSize()
  out.setBackgroundColour(colours.black); out.clear()
  out.setCursorPos(1, 1); out.setBackgroundColour(colours.grey); out.clearLine()
  out.setTextColour(colours.yellow); out.write(" FEEDERS ")
  out.setTextColour(colours.white); out.write(#order .. " on the network")
  out.setBackgroundColour(colours.black)
  out.setCursorPos(2, 3); out.setTextColour(colours.lightGrey)
  out.write(("%-18s %-12s %9s %6s  %s"):format("FARM", "STATE", "MOVED", "/MIN", "LAST ITEM"))
  for i, key in ipairs(order) do
    local f = feeders[key]
    local y = 3 + i
    if y > h then break end
    local state = (os.clock() - f.seen > STALE) and "OFFLINE" or f.state
    out.setCursorPos(2, y)
    out.setTextColour(colours.white); out.write(("%-18s "):format(f.name:sub(1, 18)))
    out.setTextColour(COL[state] or colours.red); out.write(("%-12s "):format(state))
    out.setTextColour(colours.white); out.write(("%9d %6d  "):format(f.moved or 0, f.perMin or 0))
    out.setTextColour(colours.lightGrey); out.write(short(f.last):sub(1, math.max(0, w - 53)))
  end
  if #order == 0 then
    out.setCursorPos(2, 4); out.setTextColour(colours.lightGrey); out.write("Waiting for feeders...")
  end
  if out == term then
    out.setCursorPos(2, h); out.setTextColour(colours.grey); out.write("P pause all   R resume all   Q quit")
  end
end

local tick = os.startTimer(1)
draw()
while true do
  local e, a, b, c = os.pullEvent()
  if e == "rednet_message" and c == PROTOCOL and type(b) == "table" and b.kind == "feeder" then
    local key = b.name .. "#" .. tostring(a)
    if not feeders[key] then order[#order + 1] = key; table.sort(order) end
    b.seen = os.clock()
    feeders[key] = b
    draw()
  elseif e == "timer" and a == tick then
    draw(); tick = os.startTimer(1)
  elseif e == "key" then
    if a == keys.q then break
    elseif a == keys.p then rednet.broadcast({cmd = "pause"}, PROTOCOL)
    elseif a == keys.r then rednet.broadcast({cmd = "resume"}, PROTOCOL) end
  end
end
out.setBackgroundColour(colours.black); out.clear(); out.setCursorPos(1, 1)
