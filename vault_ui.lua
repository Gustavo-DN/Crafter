--[[
  VAULT UI - monitor interfaces (DEMO MODE)
  ---------------------------------------------------------------
  One program for three computers. It looks at the size of the
  attached monitor and shows the matching screen:

    7 wide x 5 tall  (143x67)  BRAIN    control: craft, jobs, machines
    7 wide x 3 tall  (143x38)  STORAGE  items, search, withdraw
    7 wide x 6 tall  (143x81)  FACTORY  gauge board of every production line

  You can also force a screen:  vault_ui brain | storage | factory

  Everything shown is SIMULATED, so you can see and use the screens
  before they are wired into the real vault engine.

  Keys on the computer:
    D drop items into input   F fail next turtle batch
    U unplug/replug silo_46   P palette   S speed
    R reset demo              Q quit
]]

local ARGS = {...}
local CONFIG = {
  role      = nil,     -- "brain", "storage" or "factory"; nil = pick by monitor size
  monitor   = nil,     -- monitor peripheral name, nil = first one found
  textScale = 0.5,     -- 0.5 = 143x67 on a 7x5 monitor
  palette   = "brain", -- "brain" (custom colours) or "cc" (default colours)
  frame     = 0.15,    -- seconds between redraws
}
local ROLE = "brain"

---------------------------------------------------------------------
-- Basics
---------------------------------------------------------------------
local floor, max, min, abs = math.floor, math.max, math.min, math.abs
local unpack = table.unpack or unpack
local C = {white=0,orange=1,magenta=2,lightBlue=3,yellow=4,lime=5,pink=6,gray=7,
           lightGray=8,cyan=9,purple=10,blue=11,brown=12,green=13,red=14,black=15}
local HEXC = {}
for i = 0, 15 do HEXC[i] = ("0123456789abcdef"):sub(i + 1, i + 1) end
local PALETTES = {
  brain = {0xE6EBF0,0xE38B3B,0xC878D2,0x72B4E6,0xE9C34B,0x88CE5E,0xE99CB2,0x2B3542,
           0x7E8B9C,0x4FB2AB,0x9B7DE1,0x1A212B,0x8E6B46,0x3F9157,0xE2574F,0x0D1117},
  -- factory board: wood planks, gold frames, grey pipes (like Create factory gauges)
  factory = {0xF3EBDA,0xE0873A,0xC772C9,0x7FB1E3,0xE2B44A,0x7CC659,0xE7A0B4,0x595D63,
             0xA3A7AC,0x4BA8A3,0x2E1F13,0xC9A06A,0xB28854,0x3F8F4F,0xD9534A,0x3A2818},
}
local CH_R, CH_L, CH_U, CH_D, CH_DOT, CH_DIA, CH_CHK = "\16", "\17", "\30", "\31", "\7", "\4", "\127"

local function rt() return os.clock() end
local function clamp(v, a, b) if v < a then return a elseif v > b then return b end return v end
local function round(v) return floor(v + 0.5) end
local function fmt(n)
  n = round(n)
  local s = ("%d"):format(abs(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  if n < 0 then out = "-" .. out end
  return out
end
local function kfmt(n)
  if n >= 1e6 then return ("%.1fM"):format(n / 1e6) end
  if n >= 1e5 then return ("%dk"):format(floor(n / 1e3)) end
  if n >= 1e4 then return ("%.1fk"):format(n / 1e3) end
  return fmt(n)
end
local function trunc(s, n)
  s = tostring(s)
  if n <= 0 then return "" end
  if #s <= n then return s end
  if n <= 2 then return s:sub(1, n) end
  return s:sub(1, n - 1) .. "."
end
local function padR(s, n) s = trunc(s, n) return s .. (" "):rep(max(0, n - #s)) end
local function padL(s, n) s = trunc(s, n) return (" "):rep(max(0, n - #s)) .. s end
local function wrapWords(t, w)
  local out, line = {}, ""
  for word in tostring(t):gmatch("%S+") do
    if line ~= "" and #line + 1 + #word > w then out[#out + 1] = line; line = word
    else line = (line == "" and word) or (line .. " " .. word) end
    while #line > w do out[#out + 1] = line:sub(1, w); line = line:sub(w + 1) end
  end
  if line ~= "" then out[#out + 1] = line end
  return out
end
local function rng(seed)
  local s = seed
  return function() s = (s * 1103515245 + 12345) % 2147483648; return s / 2147483648 end
end
local function contains(t, v) for _, x in ipairs(t) do if x == v then return true end end return false end

---------------------------------------------------------------------
-- Data: items (real ids from the modpack recipe export)
-- id, name, category, colour, start count, short label, stack, farm target, recipes using it
---------------------------------------------------------------------
local IT_RAW = {
{"minecraft:oak_log","Oak Log","Nature","brown",2840,"LOG",64,2000,704},
{"minecraft:spruce_log","Spruce Log","Nature","brown",912,"SLOG"},
{"minecraft:birch_log","Birch Log","Nature","white",404,"BLOG"},
{"minecraft:oak_planks","Oak Planks","Blocks","brown",1236,"PLNK"},
{"minecraft:spruce_planks","Spruce Planks","Blocks","brown",380,"SPLK"},
{"minecraft:birch_planks","Birch Planks","Blocks","yellow",96,"BPLK"},
{"minecraft:oak_slab","Oak Slab","Blocks","brown",214,"SLAB"},
{"minecraft:stick","Stick","Other","brown",512,"STCK"},
{"minecraft:cobblestone","Cobblestone","Blocks","lightGray",48210,"COBL",64,10000,86},
{"minecraft:stone","Stone","Blocks","lightGray",3201,"STON"},
{"minecraft:smooth_stone","Smooth Stone","Blocks","lightGray",640,"SMST"},
{"minecraft:andesite","Andesite","Blocks","lightGray",12145,"ANDS",64,4000,338},
{"minecraft:granite","Granite","Blocks","pink",1920,"GRAN"},
{"minecraft:diorite","Diorite","Blocks","white",2005,"DIOR"},
{"minecraft:sand","Sand","Blocks","yellow",2770,"SAND",64,2000,52},
{"minecraft:gravel","Gravel","Blocks","lightGray",1152,"GRVL"},
{"minecraft:glass","Glass","Blocks","lightBlue",1408,"GLAS"},
{"minecraft:glass_pane","Glass Pane","Blocks","lightBlue",96,"PANE"},
{"minecraft:clay_ball","Clay Ball","Nature","lightBlue",704,"CLAY",64,500,130},
{"minecraft:brick","Brick","Other","red",256,"BRIK"},
{"minecraft:iron_ingot","Iron Ingot","Valuables","white",3912,"IRON",64,3000,660},
{"minecraft:iron_nugget","Iron Nugget","Valuables","white",1377,"NUGT"},
{"minecraft:iron_block","Block of Iron","Valuables","white",48,"IBLK"},
{"minecraft:gold_ingot","Gold Ingot","Valuables","yellow",611,"GOLD",64,500,79},
{"minecraft:copper_ingot","Copper Ingot","Valuables","orange",1844,"COPR",64,1500,196},
{"create:zinc_ingot","Zinc Ingot","Valuables","lightGray",214,"ZINC",64,500,67},
{"create:brass_ingot","Brass Ingot","Valuables","yellow",180,"BRAS",64,300,80},
{"minecraft:redstone","Redstone Dust","Valuables","red",2433,"RDST",64,1500,278},
{"minecraft:lapis_lazuli","Lapis Lazuli","Valuables","blue",388,"LAPS",64,300,461},
{"minecraft:diamond","Diamond","Valuables","cyan",37,"DIAM"},
{"minecraft:quartz","Nether Quartz","Valuables","white",512,"QRTZ",64,300,80},
{"minecraft:coal","Coal","Valuables","gray",940,"COAL"},
{"minecraft:charcoal","Charcoal","Valuables","gray",1250,"CHAR",64,1000,80},
{"create:iron_sheet","Iron Sheet","Tech","lightGray",96,"ISHT",64,512,243},
{"create:copper_sheet","Copper Sheet","Tech","orange",210,"CSHT",64,256,134},
{"create:golden_sheet","Golden Sheet","Tech","yellow",22,"GSHT"},
{"create:andesite_alloy","Andesite Alloy","Tech","lightGray",340,"ALOY",64,512,18},
{"create:andesite_casing","Andesite Casing","Tech","lightGray",58,"CASE",64,128,110},
{"create:brass_casing","Brass Casing","Tech","yellow",12,"BCAS"},
{"create:shaft","Shaft","Tech","lightGray",128,"SHFT"},
{"create:cogwheel","Cogwheel","Tech","brown",64,"COG"},
{"create:large_cogwheel","Large Cogwheel","Tech","brown",20,"LCOG"},
{"create:electron_tube","Electron Tube","Tech","pink",18,"TUBE"},
{"create:precision_mechanism","Precision Mechanism","Tech","yellow",6,"PREC"},
{"create:propeller","Propeller","Tech","lightGray",4,"PROP"},
{"create:basin","Basin","Tech","lightGray",9,"BASN"},
{"create:depot","Depot","Tech","lightGray",14,"DEPO"},
{"create:mechanical_press","Mechanical Press","Tech","lightGray",3,"PRES"},
{"create:encased_fan","Encased Fan","Tech","lightGray",22,"FAN"},
{"create:whisk","Whisk","Tech","lightGray",2,"WHSK"},
{"create:item_vault","Item Vault","Tech","lightGray",31,"VALT"},
{"create:belt_connector","Mechanical Belt","Tech","gray",48,"BELT"},
{"create:crushing_wheel","Crushing Wheel","Tech","lightGray",2,"CRSH"},
{"create:hand_crank","Hand Crank","Tech","brown",3,"CRNK"},
{"create:gearbox","Gearbox","Tech","lightGray",6,"GBOX"},
{"create:mechanical_drill","Mechanical Drill","Tech","lightGray",4,"DRIL"},
{"computercraft:computer_normal","Computer","Tech","lightGray",4,"CPU"},
{"computercraft:turtle_normal","Turtle","Tech","lightGray",1,"TRTL"},
{"minecraft:dried_kelp","Dried Kelp","Food","green",2560,"KELP",64,1500,40},
{"minecraft:wheat","Wheat","Food","yellow",1024,"WHET",64,512,28},
{"minecraft:bread","Bread","Food","brown",64,"BRED"},
{"minecraft:beetroot","Beetroot","Food","red",230,"BEET",64,256,432},
{"farmersdelight:rice","Rice","Food","white",320,"RICE"},
{"minecraft:white_wool","White Wool","Mob","white",640,"WOOL",64,500,359},
{"minecraft:gray_wool","Gray Wool","Mob","gray",128,"GWOL"},
{"minecraft:bone","Bone","Mob","white",812,"BONE",64,500,517},
{"minecraft:leather","Leather","Mob","brown",140,"LETH",64,128,75},
{"minecraft:string","String","Mob","white",300,"STRG"},
{"minecraft:honeycomb","Honeycomb","Nature","yellow",96,"COMB",64,300,209},
{"minecraft:blaze_rod","Blaze Rod","Mob","orange",44,"BLZE",64,64,85},
{"minecraft:ender_pearl","Ender Pearl","Mob","cyan",15,"PERL"},
{"minecraft:chest","Chest","Other","brown",41,"CHST"},
{"minecraft:barrel","Barrel","Other","brown",18,"BARL"},
{"minecraft:crafting_table","Crafting Table","Other","brown",6,"TABL"},
{"minecraft:hopper","Hopper","Other","gray",9,"HOPR"},
{"minecraft:torch","Torch","Other","yellow",222,"TRCH"},
{"minecraft:redstone_torch","Redstone Torch","Other","red",30,"RTRC"},
{"minecraft:piston","Piston","Other","brown",12,"PIST"},
{"minecraft:iron_bars","Iron Bars","Other","lightGray",64,"BARS"},
{"minecraft:diamond_pickaxe","Diamond Pickaxe","Equipment","cyan",2,"DPIK",1},
{"minecraft:iron_sword","Iron Sword","Equipment","white",3,"ISWD",1},
{"minecraft:shield","Shield","Equipment","brown",1,"SHLD",1},
}
local ITEMS, ITEM_ORDER = {}, {}
for _, r in ipairs(IT_RAW) do
  local id, name, cat, col, count, sh, stack, target, usedBy = unpack(r)
  ITEMS[id] = {id=id, name=name, cat=cat, col=C[col], count=count, sh=sh or name:sub(1,4):upper(),
               stack=stack or 64, target=target or 0, usedBy=usedBy or 0}
  ITEM_ORDER[#ITEM_ORDER + 1] = id
end
local TAGS = {
  ["#planks"] = {name="Any Planks", sh="PLK*", col=C.brown,
                 members={"minecraft:oak_planks","minecraft:spruce_planks","minecraft:birch_planks"}},
  ["#slabs"]  = {name="Any Wooden Slab", sh="SLB*", col=C.brown, members={"minecraft:oak_slab"}},
}
local function iName(id)
  if ITEMS[id] then return ITEMS[id].name end
  if TAGS[id] then return TAGS[id].name end
  return (tostring(id):gsub("^.*:", ""):gsub("_", " "))
end
local function iCol(id) return (ITEMS[id] and ITEMS[id].col) or (TAGS[id] and TAGS[id].col) or C.lightGray end
local function iSh(id) return (ITEMS[id] and ITEMS[id].sh) or (TAGS[id] and TAGS[id].sh) or "?" end
local CATS = {"All","Blocks","Valuables","Food","Nature","Equipment","Mob","Tech","Other"}

-- Recipes: real patterns from the export. m: T = Crafty Turtles, C = Crafter 21 A, B = Blasters A
local P, N = "#planks", false
local AL, IR, CB = "create:andesite_alloy", "minecraft:iron_ingot", "minecraft:cobblestone"
local RECIPES = {
 ["minecraft:oak_planks"]={out=4,m="T",g={{"minecraft:oak_log"}}},
 ["minecraft:spruce_planks"]={out=4,m="T",g={{"minecraft:spruce_log"}}},
 ["minecraft:birch_planks"]={out=4,m="T",g={{"minecraft:birch_log"}}},
 ["minecraft:oak_slab"]={out=6,m="T",g={{"minecraft:oak_planks","minecraft:oak_planks","minecraft:oak_planks"}}},
 ["minecraft:stick"]={out=4,m="T",g={{P},{P}}},
 ["minecraft:crafting_table"]={out=1,m="T",g={{P,P},{P,P}}},
 ["minecraft:chest"]={out=1,m="T",g={{P,P,P},{P,N,P},{P,P,P}}},
 ["minecraft:barrel"]={out=1,m="T",g={{P,"#slabs",P},{P,N,P},{P,"#slabs",P}}},
 ["minecraft:torch"]={out=4,m="T",g={{"minecraft:charcoal"},{"minecraft:stick"}}},
 ["minecraft:redstone_torch"]={out=1,m="T",g={{"minecraft:redstone"},{"minecraft:stick"}}},
 ["minecraft:piston"]={out=1,m="T",g={{P,P,P},{CB,IR,CB},{CB,"minecraft:redstone",CB}}},
 ["minecraft:hopper"]={out=1,m="T",g={{IR,N,IR},{IR,"minecraft:chest",IR},{N,IR,N}}},
 ["minecraft:iron_bars"]={out=16,m="T",g={{IR,IR,IR},{IR,IR,IR}}},
 ["minecraft:iron_block"]={out=1,m="T",g={{IR,IR,IR},{IR,IR,IR},{IR,IR,IR}}},
 ["minecraft:iron_nugget"]={out=9,m="T",g={{IR}}},
 ["minecraft:glass_pane"]={out=16,m="T",g={{"minecraft:glass","minecraft:glass","minecraft:glass"},{"minecraft:glass","minecraft:glass","minecraft:glass"}}},
 ["create:andesite_alloy"]={out=1,m="T",g={{"minecraft:iron_nugget","minecraft:andesite"},{"minecraft:andesite","minecraft:iron_nugget"}}},
 ["create:shaft"]={out=8,m="T",g={{AL},{AL}}},
 ["create:cogwheel"]={out=1,m="T",g={{"create:shaft",P}}},
 ["create:large_cogwheel"]={out=1,m="T",g={{"create:shaft",P,P}}},
 ["create:hand_crank"]={out=1,m="T",g={{P,P,P},{N,N,AL}}},
 ["create:basin"]={out=1,m="T",g={{AL,N,AL},{AL,AL,AL}}},
 ["create:depot"]={out=1,m="T",g={{AL,"create:andesite_casing"}}},
 ["create:propeller"]={out=1,m="T",g={{N,"create:iron_sheet",N},{"create:iron_sheet",AL,"create:iron_sheet"},{N,"create:iron_sheet",N}}},
 ["create:encased_fan"]={out=1,m="T",g={{"create:shaft"},{"create:andesite_casing"},{"create:propeller"}}},
 ["create:mechanical_press"]={out=1,m="T",g={{"create:shaft"},{"create:andesite_casing"},{"minecraft:iron_block"}}},
 ["create:item_vault"]={out=1,m="T",g={{"create:iron_sheet"},{"minecraft:barrel"},{"create:iron_sheet"}}},
 ["create:whisk"]={out=1,m="T",g={{N,AL,N},{"create:iron_sheet",AL,"create:iron_sheet"},{"create:iron_sheet","create:iron_sheet","create:iron_sheet"}}},
 ["create:belt_connector"]={out=1,m="T",g={{"minecraft:dried_kelp","minecraft:dried_kelp","minecraft:dried_kelp"},{"minecraft:dried_kelp","minecraft:dried_kelp","minecraft:dried_kelp"}}},
 ["create:gearbox"]={out=1,m="T",g={{N,"create:cogwheel",N},{"create:cogwheel","create:andesite_casing","create:cogwheel"},{N,"create:cogwheel",N}}},
 ["create:mechanical_drill"]={out=1,m="T",g={{N,AL,N},{AL,IR,AL},{N,"create:andesite_casing",N}}},
 ["computercraft:turtle_normal"]={out=1,m="T",g={{IR,IR,IR},{IR,"computercraft:computer_normal",IR},{IR,"minecraft:chest",IR}}},
 ["create:crushing_wheel"]={out=2,m="C",g={
   {N,AL,AL,AL,N},{AL,AL,P,AL,AL},{AL,P,"minecraft:granite",P,AL},{AL,AL,P,AL,AL},{N,AL,AL,AL,N}}},
 ["minecraft:stone"]={out=1,m="B",input="minecraft:cobblestone"},
 ["minecraft:smooth_stone"]={out=1,m="B",input="minecraft:stone"},
 ["minecraft:glass"]={out=1,m="B",input="minecraft:sand"},
 ["minecraft:brick"]={out=1,m="B",input="minecraft:clay_ball"},
}
local RECIPE_IDS = {}
for id, r in pairs(RECIPES) do
  if r.input then r.g = {{r.input}} end
  RECIPE_IDS[#RECIPE_IDS + 1] = id
end
table.sort(RECIPE_IDS, function(a, b) return iName(a) < iName(b) end)
local EXTERNAL = {
 ["create:iron_sheet"]="Mechanical Press - not connected",
 ["create:copper_sheet"]="Mechanical Press - not connected",
 ["create:golden_sheet"]="Mechanical Press - not connected",
 ["create:andesite_casing"]="Deployer - not connected",
 ["create:brass_casing"]="Deployer - not connected",
 ["create:brass_ingot"]="Mixer + Blaze Burner - not connected",
 ["create:electron_tube"]="Polishing + press - not connected",
 ["create:precision_mechanism"]="Sequenced assembly - not connected",
}
local MACH = {
  T={name="Crafty Turtles", tag="TURTLE", col=C.cyan},
  C={name="Crafter 21 A", tag="CRAFTER 21", col=C.purple},
  B={name="Blasters A", tag="BLASTING", col=C.orange},
}
local CHAINS = {
 {"Iron Sheet","Iron Ingot","Mechanical Press",false,243},
 {"Copper Sheet","Copper Ingot","Mechanical Press",false,134},
 {"Glass","Sand","Blasters A",true,130},
 {"Andesite Casing","Alloy + Stripped Log","Deployer + Saw",false,110},
 {"Brass Casing","Brass + Stripped Log","Deployer + Saw",false,104},
 {"Clay Ball","Gravel","Washing fan",false,97},
 {"Brass Ingot","Copper + Zinc","Mixer + Blaze Burner",false,80},
 {"Stone","Cobblestone","Blasters A",true,64},
 {"Precision Mech.","Golden Sheet + cogs","Sequenced assembly",false,63},
 {"Blackstone","Cobblestone","Haunting fan",false,47},
}
local function ingredients(r)
  if r._ing then return r._ing end
  local m, order = {}, {}
  for _, row in ipairs(r.g) do for _, c in ipairs(row) do
    if c then if not m[c] then m[c] = 0; order[#order + 1] = c end; m[c] = m[c] + 1 end
  end end
  local out = {}
  for _, id in ipairs(order) do out[#out + 1] = {id, m[id]} end
  r._ing = out
  return out
end

---------------------------------------------------------------------
-- Simulated world state
---------------------------------------------------------------------
local STORAGE_DEFS = {
 {id="create_connected:item_silo_43",name="silo_43",role="MAIN",slots=864,mult=1},
 {id="create_connected:item_silo_44",name="silo_44",role="MAIN",slots=864,mult=1},
 {id="create_connected:item_silo_45",name="silo_45",role="MAIN",slots=864,mult=1},
 {id="create_connected:item_silo_46",name="silo_46",role="MAIN",slots=864,mult=1},
 {id="create:item_vault_51",name="item_vault_51",role="REST",slots=405,mult=1},
 {id="sophisticatedbackpacks:backpack_3",name="backpack_3",role="REST",slots=81,mult=16},
 {id="create:item_vault_148",name="item_vault_148",role="REST",slots=162,mult=1,note="crafter out"},
 {id="minecraft:chest_12",name="chest_12",role="REST",slots=27,mult=1},
}
local S
local AUTOSTOCK = nil  -- set by the factory board

local function freshState()
  local r = rng(1337)
  local storages = {}
  for i, d in ipairs(STORAGE_DEFS) do
    storages[i] = {id=d.id, name=d.name, role=d.role, slots=d.slots, mult=d.mult, note=d.note,
                   online=true, inv={}, cap=d.slots * 64 * d.mult}
  end
  local w = {0.36, 0.29, 0.21}
  for _, id in ipairs(ITEM_ORDER) do
    local it = ITEMS[id]
    local n = it.count
    local function put(i, k)
      k = max(0, round(k)); if k <= 0 then return end
      storages[i].inv[id] = (storages[i].inv[id] or 0) + k; n = n - k
    end
    if n >= 1500 then put(6, n * 0.08) end
    if r() < 0.35 then put(5, n * (0.05 + r() * 0.12)) end
    if r() < 0.12 then put(8, min(n, 64 * (1 + floor(r() * 3)))) end
    local base, acc = n, 0
    for i = 1, 3 do
      local k = round(base * w[i] * (0.8 + r() * 0.4)); acc = acc + k
      storages[i].inv[id] = (storages[i].inv[id] or 0) + k
    end
    local rest = max(0, base - acc)
    if rest > 0 then storages[4].inv[id] = (storages[4].inv[id] or 0) + rest end
  end
  storages[7].inv["minecraft:cobblestone"] = 320
  local hist = {}
  for i = 1, 72 do hist[i] = max(0, round(40 + 30 * math.sin(i / 6) + r() * 40)) end
  local turtles = {}
  for i = 0, 5 do turtles[#turtles + 1] = {name="turtle_" .. i, id=12 + i, state="IDLE", task=nil, inv={}, made=0, err=nil} end
  local basins = {}
  for i = 1, 11 do basins[i] = {name="basin_" .. i, item=nil, count=0, heat=0} end
  return {
    tab="home", t=0, tod=8 * 60 + 40, day=214, speed=1, palette=CONFIG.palette,
    storages=storages, input={}, output={}, outputAt=0, log={}, toasts={},
    jobs={}, history={
      {item="create:shaft", qty=64, ok=true, secs=11.2, msg="Delivered"},
      {item="minecraft:chest", qty=16, ok=true, secs=6.8, msg="Delivered"},
      {item="create:propeller", qty=8, ok=false, secs=0.4, msg="Missing Iron Sheet x28"},
    },
    nextJobId=1, craftedToday=1184,
    turtles=turtles, c21={state="IDLE", cells={}, relay=false, task=nil, flash=0},
    basins=basins, blast={task=nil}, failNext=false,
    lastTouch=-999, touchInfo=nil, auto={on=true, acc=0}, depAcc=0, farmAcc=0, sec=0,
    hist=hist, histAcc=0, defrag={active=false, t=0, log={}, moved=0, freed=0, acc=0},
    iv={cat=1, page=0, sel=nil, search="", catOff=1},
    cv={sel="create:shaft", qty=64, page=0, filter="ALL", search="", planPage=0, detail=false},
    mv={sub="t"}, fv={page=0}, kb={open=false, target=nil}, confirm={key=nil, until_=0},
    ready={}, readyAt=-9, tot={}, totN=0,
    ftarget={}, keep={}, autoStock=true, autoStockAcc=0, fsel="create:andesite_alloy",
  }
end

local function recount()
  local m, n = {}, 0
  for _, s in ipairs(S.storages) do
    if s.online then for k, v in pairs(s.inv) do if v > 0 then
      if not m[k] then n = n + 1 end
      m[k] = (m[k] or 0) + v
    end end end
  end
  S.tot, S.totN = m, n
end
local function have(id) return S.tot[id] or 0 end
local function used(s) local u = 0 for _, v in pairs(s.inv) do u = u + v end return u end
local function slotsUsed(s)
  local u = 0
  for k, v in pairs(s.inv) do if v > 0 then u = u + math.ceil(v / (((ITEMS[k] and ITEMS[k].stack) or 64) * s.mult)) end end
  return u
end
local function mainStorages()
  local out = {}
  for _, s in ipairs(S.storages) do if s.role == "MAIN" and s.online then out[#out + 1] = s end end
  return out
end
local function addStock(id, n)
  if n <= 0 then return nil end
  local mains = mainStorages(); if #mains == 0 then return nil end
  local best, bestF = nil, math.huge
  for _, s in ipairs(mains) do local f = used(s) / s.cap; if f < bestF then best, bestF = s, f end end
  best.inv[id] = (best.inv[id] or 0) + n
  recount()
  return best
end
local function removeStock(id, n)
  local left = n
  local src = {}
  for _, s in ipairs(S.storages) do if s.online and (s.inv[id] or 0) > 0 then src[#src + 1] = s end end
  table.sort(src, function(a, b) return a.inv[id] > b.inv[id] end)
  for _, s in ipairs(src) do
    if left <= 0 then break end
    local k = min(left, s.inv[id]); s.inv[id] = s.inv[id] - k
    if s.inv[id] <= 0 then s.inv[id] = nil end
    left = left - k
  end
  recount()
  return n - left
end
local function resolveTag(sel, n)
  local tg = TAGS[sel]; if not tg then return sel end
  local best, bestN = tg.members[1], -1
  for _, m in ipairs(tg.members) do if have(m) >= n then return m end; if have(m) > bestN then best, bestN = m, have(m) end end
  return best
end

---------------------------------------------------------------------
-- Log, toasts, throughput
---------------------------------------------------------------------
local LOGCOL = {INPUT=C.lightBlue, AUTO=C.lime, PLAN=C.yellow, CRAFT=C.yellow, TURTLE=C.cyan, C21=C.purple,
                BLAST=C.orange, OUTPUT=C.white, ERROR=C.red, DEFRAG=C.magenta, SYSTEM=C.lightGray}
local function log(kind, text)
  S.log[#S.log + 1] = {kind=kind, text=text, tod=S.tod}
  if #S.log > 200 then table.remove(S.log, 1) end
end
local function toast(text, col)
  S.toasts[#S.toasts + 1] = {text=text, col=col or C.lime, until_=rt() + 3.6}
  if #S.toasts > 3 then table.remove(S.toasts, 1) end
end
local function moved(n) S.histAcc = S.histAcc + n end
local function clockStr(tod)
  local m = floor(tod or S.tod) % 1440
  return ("%02d:%02d"):format(floor(m / 60), m % 60)
end

---------------------------------------------------------------------
-- Planner: one craft tree for READY checks, MAX and the job runner
---------------------------------------------------------------------
local function stepSecs(s)
  local nT = 0
  for _, t in ipairs(S.turtles) do if t.state ~= "ERROR" then nT = nT + 1 end end
  nT = max(1, nT)
  if s.m == "T" then return math.ceil(s.crafts / (64 * nT)) * 2.3 + 0.4 end
  if s.m == "C" then return s.crafts * 4.2 end
  return math.ceil(s.crafts / (11 * 64)) * 3.4 + 0.5
end

local function plan(item, qty)
  local avail = {}
  for k, v in pairs(S.tot) do avail[k] = v end
  avail[item] = 0
  local steps, order, missing, missOrder = {}, {}, {}, {}
  local function need(sel, q, visit, depth)
    local node = {sel=sel, q=q, use=0, craft=nil, kids={}, miss=0, reason=nil, depth=depth, picks=nil}
    local tg = TAGS[sel]
    if tg then
      local left = q; node.picks = {}
      local ms = {unpack(tg.members)}
      table.sort(ms, function(a, b) return (avail[a] or 0) > (avail[b] or 0) end)
      for _, m in ipairs(ms) do
        local k = min(avail[m] or 0, left)
        if k > 0 then avail[m] = (avail[m] or 0) - k; left = left - k; node.picks[#node.picks + 1] = {m, k} end
      end
      node.use = q - left
      if left > 0 then
        local m
        for _, x in ipairs(tg.members) do if RECIPES[x] then m = x break end end
        node.kids[#node.kids + 1] = need(m, left, visit, depth + 1)
      end
      return node
    end
    local h = avail[sel] or 0
    local use = min(h, q); avail[sel] = h - use; node.use = use
    local short = q - use
    if short <= 0 then return node end
    local r = RECIPES[sel]
    if not r or visit[sel] then
      node.miss = short; node.reason = EXTERNAL[sel] or "Raw resource - needs a farm"
      if not missing[sel] then missing[sel] = 0; missOrder[#missOrder + 1] = sel end
      missing[sel] = missing[sel] + short
      return node
    end
    local crafts = math.ceil(short / r.out)
    node.craft = {crafts=crafts, made=crafts * r.out, m=r.m}
    local v2 = {}
    for k in pairs(visit) do v2[k] = true end
    v2[sel] = true
    for _, ing in ipairs(ingredients(r)) do
      node.kids[#node.kids + 1] = need(ing[1], ing[2] * crafts, v2, depth + 1)
    end
    avail[sel] = (avail[sel] or 0) + crafts * r.out - short
    if not steps[sel] then steps[sel] = {item=sel, crafts=0, m=r.m}; order[#order + 1] = sel end
    steps[sel].crafts = steps[sel].crafts + crafts
    return node
  end
  local root = need(item, qty, {}, 0)
  local st, eta = {}, 0
  for _, k in ipairs(order) do st[#st + 1] = steps[k]; eta = eta + stepSecs(steps[k]) end
  local miss = {}
  for _, id in ipairs(missOrder) do miss[#miss + 1] = {id=id, n=missing[id]} end
  return {root=root, steps=st, missing=miss, ok=(#miss == 0), eta=eta}
end
local function maxCraft(item)
  local lo, hi = 0, 4096
  while lo < hi do
    local mid = floor((lo + hi + 1) / 2)
    if plan(item, mid).ok then lo = mid else hi = mid - 1 end
  end
  return lo
end
local function flattenPlan(node, out)
  out = out or {}
  out[#out + 1] = node
  for _, k in ipairs(node.kids) do flattenPlan(k, out) end
  return out
end
local function missingText(p)
  local parts = {}
  for _, m in ipairs(p.missing) do parts[#parts + 1] = iName(m.id) .. " x" .. m.n end
  return table.concat(parts, ", ")
end

---------------------------------------------------------------------
-- Simulation
---------------------------------------------------------------------
local function queueCraft(item, qty, stock)
  local r = RECIPES[item]
  local p = plan(item, qty)
  if not p.ok then toast("Missing " .. missingText(p), C.red) return false end
  S.jobs[#S.jobs + 1] = {id=S.nextJobId, item=item, qty=qty, state="QUEUED", steps={}, started=0, err=nil, out=r.out, stock=stock}
  S.nextJobId = S.nextJobId + 1
  log("PLAN", "Queued " .. iName(item) .. " x" .. qty .. (#S.jobs > 1 and (" (position " .. #S.jobs .. ")") or ""))
  toast(((#S.jobs > 1) and "Queued " or "Crafting ") .. iName(item) .. " x" .. qty, C.yellow)
  return true
end
local function failJob(job, msg)
  job.state = "FAILED"; job.err = msg; job.ended = S.t
  log("ERROR", msg); toast("Craft failed - open JOBS", C.red)
end
local function pushHistory(rec)
  table.insert(S.history, 1, rec)
  while #S.history > 12 do table.remove(S.history) end
end
local function finishJob(job)
  if job.stock then
    job.state = "DONE"; S.craftedToday = S.craftedToday + job.qty
    log("CRAFT", "Stocked " .. iName(job.item) .. " x" .. job.qty .. " (kept in storage)")
    toast("Stocked: " .. iName(job.item) .. " x" .. job.qty, C.lime)
    pushHistory({item=job.item, qty=job.qty, ok=true, secs=S.t - job.started, msg="Stocked"})
    table.remove(S.jobs, 1)
    return
  end
  local got = removeStock(job.item, job.qty)
  S.output[job.item] = (S.output[job.item] or 0) + got; S.outputAt = S.t
  job.state = "DONE"; S.craftedToday = S.craftedToday + job.qty; moved(got)
  log("OUTPUT", iName(job.item) .. " x" .. got .. " > barrel_74")
  toast("Done: " .. iName(job.item) .. " x" .. got .. " in output barrel", C.lime)
  pushHistory({item=job.item, qty=job.qty, ok=true, secs=S.t - job.started, msg="Delivered"})
  table.remove(S.jobs, 1)
end
local function machinesBusy()
  for _, t in ipairs(S.turtles) do if t.task then return true end end
  return S.c21.task ~= nil or S.blast.task ~= nil
end
local function consumeFor(job, r, crafts)
  for _, ing in ipairs(ingredients(r)) do
    local id, c = ing[1], ing[2]
    local want, got = c * crafts, 0
    if TAGS[id] then
      local ms = {unpack(TAGS[id].members)}
      table.sort(ms, function(a, b) return have(a) > have(b) end)
      for _, m in ipairs(ms) do if got >= want then break end; got = got + removeStock(m, want - got) end
    else
      got = removeStock(id, want)
    end
    if got < want then failJob(job, "Ingredient no longer available: " .. iName(id)) return false end
  end
  return true
end
local TSLOT = {{1,2,3},{5,6,7},{9,10,11}}
local GRID_SLOTS = {[1]=true,[2]=true,[3]=true,[5]=true,[6]=true,[7]=true,[9]=true,[10]=true,[11]=true}
local function dispatch(job, step)
  local r = RECIPES[step.item]
  if step.m == "T" then
    local free = {}
    for _, t in ipairs(S.turtles) do if t.state == "IDLE" and not t.task then free[#free + 1] = t end end
    while #free > 0 and step.assigned < step.crafts do
      local remaining = step.crafts - step.assigned
      local b = min(64, math.ceil(remaining / #free))
      local t = table.remove(free, 1)
      if not consumeFor(job, r, b) then return end
      step.assigned = step.assigned + b
      t.inv = {}
      for y, row in ipairs(r.g) do for x, c in ipairs(row) do
        if c then t.inv[TSLOT[y][x]] = {id=resolveTag(c, 1), n=b} end
      end end
      t.task = {job=job, step=step, b=b, phase="LOADING", pt=0}; t.state = "LOADING"
    end
  elseif step.m == "C" then
    local c = S.c21
    if not c.task and step.assigned < step.crafts then
      if not consumeFor(job, r, 1) then return end
      step.assigned = step.assigned + 1
      local cells = {}
      for y = 1, 5 do for x = 1, 5 do
        if not ((y == 1 or y == 5) and (x == 1 or x == 5)) then
          local v = r.g[y][x]; cells[#cells + 1] = v and resolveTag(v, 1) or false
        end
      end end
      c.task = {job=job, step=step, phase="LOADING", pt=0, idx=0, cells=cells}; c.state = "LOADING"; c.cells = {}
    end
  elseif step.m == "B" then
    local b = S.blast
    if not b.task and step.assigned < step.crafts then
      local n = min(step.crafts - step.assigned, 11 * 64)
      if not consumeFor(job, r, n) then return end
      step.assigned = step.assigned + n
      local left = n
      for i, bs in ipairs(S.basins) do
        local k = math.ceil(left / (12 - i)); bs.item = r.input; bs.count = k; left = left - k
      end
      b.task = {job=job, step=step, n=n, phase="LOADING", pt=0}
      log("BLAST", "Loaded " .. n .. " " .. iName(r.input) .. " into 11 basins")
    end
  end
end
local function advanceTurtles(dt)
  for _, t in ipairs(S.turtles) do
    local k = t.task
    if k then
      k.pt = k.pt + dt
      local r = RECIPES[k.step.item]
      if k.phase == "LOADING" and k.pt >= 0.9 then
        k.phase = "CRAFTING"; k.pt = 0; t.state = "CRAFTING"
      elseif k.phase == "CRAFTING" and k.pt >= 0.6 then
        if S.failNext then
          S.failNext = false; t.state = "ERROR"; t.err = "Timed out after craft"; t.task = nil
          failJob(k.job, "Timed out waiting for Turtle " .. t.name .. " (craft " .. iName(k.step.item) .. " x" .. k.b ..
            "). Its slots still hold the ingredients - CLEAR CRAFTERS returns them to MAIN.")
        else
          k.phase = "STORING"; k.pt = 0; t.state = "STORING"
          for s in pairs(GRID_SLOTS) do t.inv[s] = nil end
          t.inv[16] = {id=k.step.item, n=k.b * r.out}
        end
      elseif k.phase == "STORING" and k.pt >= 0.7 then
        local made = k.b * r.out
        local dst = addStock(k.step.item, made)
        k.step.done = k.step.done + k.b; t.made = t.made + made; moved(made)
        log("TURTLE", t.name .. ": " .. iName(k.step.item) .. " x" .. made .. " > " .. (dst and dst.name or "MAIN"))
        t.inv[16] = nil; t.task = nil; t.state = "IDLE"
      end
    end
  end
end
local function advanceC21(dt)
  local c = S.c21; local k = c.task
  if not k then return end
  k.pt = k.pt + dt
  local r = RECIPES[k.step.item]
  local vault = S.storages[7]
  if k.phase == "LOADING" then
    while k.pt >= 0.07 and k.idx < 21 do k.pt = k.pt - 0.07; k.idx = k.idx + 1; c.cells[k.idx] = k.cells[k.idx] end
    if k.idx >= 21 then k.phase = "PULSE"; k.pt = 0; c.state = "PULSE"; c.relay = true; log("C21", "redstone_relay_503 pulse") end
  elseif k.phase == "PULSE" and k.pt >= 0.5 then
    k.phase = "CRAFTING"; k.pt = 0; c.relay = false; c.state = "CRAFTING"
  elseif k.phase == "CRAFTING" then
    c.flash = k.pt
    if k.pt >= 1.6 then
      k.phase = "OUTPUT"; k.pt = 0; c.state = "OUTPUT"; c.cells = {}
      vault.inv[k.step.item] = (vault.inv[k.step.item] or 0) + r.out; recount()
    end
  elseif k.phase == "OUTPUT" and k.pt >= 0.6 then
    vault.inv[k.step.item] = (vault.inv[k.step.item] or 0) - r.out
    if vault.inv[k.step.item] <= 0 then vault.inv[k.step.item] = nil end
    addStock(k.step.item, r.out); k.step.done = k.step.done + 1; moved(r.out)
    log("C21", iName(k.step.item) .. " x" .. r.out .. " item_vault_148 > MAIN")
    c.task = nil; c.state = "IDLE"
  end
end
local function advanceBlast(dt)
  local b = S.blast; local k = b.task
  if not k then return end
  k.pt = k.pt + dt
  if k.phase == "LOADING" and k.pt >= 0.6 then k.phase = "HEATING"; k.pt = 0
  elseif k.phase == "HEATING" then
    for _, bs in ipairs(S.basins) do bs.heat = clamp(k.pt / 2.8, 0, 1) end
    if k.pt >= 2.8 then
      addStock(k.step.item, k.n); k.step.done = k.step.done + k.n; moved(k.n)
      log("BLAST", iName(k.step.item) .. " x" .. k.n .. " > MAIN")
      for _, bs in ipairs(S.basins) do bs.item = nil; bs.count = 0; bs.heat = 0 end
      b.task = nil
    end
  end
end
local function clearCrafters()
  local n = 0
  for _, t in ipairs(S.turtles) do
    for i = 1, 16 do local s = t.inv[i]; if s then addStock(s.id, s.n); n = n + s.n; t.inv[i] = nil end end
    if not t.task then t.state = "IDLE"; t.err = nil end
  end
  if not S.c21.task then
    for i = 1, 21 do local v = S.c21.cells[i]; if v then addStock(v, 1); n = n + 1; S.c21.cells[i] = nil end end
  end
  log("SYSTEM", "Clear crafters: " .. n .. " items returned to MAIN")
  toast("Crafters cleared: " .. n .. " items back in MAIN", C.orange)
end
local function simJobs(dt)
  local job = S.jobs[1]
  if job and job.state == "QUEUED" then
    local p = plan(job.item, job.qty)
    if not p.ok then failJob(job, "Missing " .. missingText(p))
    else
      job.steps = {}
      for _, s in ipairs(p.steps) do job.steps[#job.steps + 1] = {item=s.item, crafts=s.crafts, m=s.m, done=0, assigned=0, state="WAIT"} end
      job.state = "RUNNING"; if job.started == 0 then job.started = S.t end
      log("PLAN", "Plan ready: " .. #job.steps .. " step(s) for " .. iName(job.item) .. " x" .. job.qty)
    end
  end
  if job and job.state == "RUNNING" then
    local step, idx
    for i, s in ipairs(job.steps) do if s.done < s.crafts then step, idx = s, i break end end
    if not step then
      if not machinesBusy() then finishJob(job) end
    else
      if step.state == "WAIT" then
        step.state = "RUN"
        log("CRAFT", "Step " .. idx .. "/" .. #job.steps .. ": " .. iName(step.item) .. " x" ..
          step.crafts * RECIPES[step.item].out .. " on " .. MACH[step.m].name)
      end
      dispatch(job, step)
    end
  end
  if job and job.state == "STOPPING" and not machinesBusy() then
    job.state = "STOPPED"; job.ended = S.t
    log("SYSTEM", "Craft stopped: " .. iName(job.item))
    pushHistory({item=job.item, qty=job.qty, ok=false, secs=S.t - job.started, msg="Stopped by user"})
    table.remove(S.jobs, 1)
  end
  advanceTurtles(dt); advanceC21(dt); advanceBlast(dt)
end
local function simWorld(dt)
  S.tod = S.tod + dt * 1.2
  if S.tod >= 1440 then S.tod = S.tod - 1440; S.day = S.day + 1 end
  -- farms push into the input barrel
  S.farmAcc = S.farmAcc + dt
  if S.farmAcc >= 5 then
    S.farmAcc = 0
    local r = math.random()
    local f
    if r < 0.3 then f = {"minecraft:oak_log", 32 + math.random(0, 31)}
    elseif r < 0.55 then f = {"minecraft:cobblestone", 64}
    elseif r < 0.7 then f = {"minecraft:dried_kelp", 32}
    elseif r < 0.85 then f = {"minecraft:wheat", 16}
    else f = {"minecraft:bone", 8} end
    S.input[#S.input + 1] = {id=f[1], n=f[2]}
  end
  -- deposit loop: barrel_73 -> least-filled MAIN
  S.depAcc = S.depAcc + dt
  if S.depAcc >= 0.35 and #S.input > 0 then
    S.depAcc = 0
    local s = table.remove(S.input, 1)
    local dst = addStock(s.id, s.n); moved(s.n)
    log("INPUT", iName(s.id) .. " x" .. s.n .. " > " .. (dst and dst.name or "?"))
  end
  -- player picks up the output barrel after a while
  if next(S.output) and S.t - S.outputAt > 14 then S.output = {}; log("SYSTEM", "Output barrel emptied by player") end
  -- AUTO: REST -> MAIN when idle; never changes the screen
  local idle = (S.t - S.lastTouch > 20) and #S.jobs == 0 and not S.defrag.active
  if S.auto.on and idle then
    S.auto.acc = S.auto.acc + dt
    if S.auto.acc >= 1.3 then
      S.auto.acc = 0
      local cap = 0
      for _, s in ipairs(mainStorages()) do cap = cap + s.cap end
      local target = floor(cap * 0.95 / max(1, S.totN))
      local function mainHave(id) local n = 0 for _, s in ipairs(mainStorages()) do n = n + (s.inv[id] or 0) end return n end
      local done = false
      for _, s in ipairs(S.storages) do
        if done then break end
        if s.role == "REST" and s.online then
          for id, n in pairs(s.inv) do
            if n > 0 and mainHave(id) < target then
              local k = min(64, n, target - mainHave(id))
              s.inv[id] = n - k; if s.inv[id] <= 0 then s.inv[id] = nil end
              local dst = addStock(id, k); moved(k)
              log("AUTO", iName(id) .. " x" .. k .. " " .. s.name .. " > " .. (dst and dst.name or "MAIN"))
              done = true
              break
            end
          end
        end
      end
    end
  end
  -- defrag
  local d = S.defrag
  if d.active then
    d.t = d.t + dt; d.acc = d.acc + dt
    if d.acc >= 0.25 then
      d.acc = 0
      local ids = {}
      for id in pairs(S.tot) do ids[#ids + 1] = id end
      local id = ids[math.random(1, max(1, #ids))]
      local a = math.random(0, 3); local b = (a + math.random(1, 3)) % 4
      local n = math.random(1, 63); d.moved = d.moved + n
      if math.random() < 0.45 then d.freed = d.freed + 1 end
      d.log[#d.log + 1] = ("PACK %s silo_4%d:%d > silo_4%d:%d x%d"):format(iName(id or "?"), 3 + a, math.random(1, 864), 3 + b, math.random(1, 864), n)
      if #d.log > 60 then table.remove(d.log, 1) end
    end
    if d.t >= 7 then
      d.active = false
      d.log[#d.log + 1] = "DONE moved " .. d.moved .. " items, freed " .. d.freed .. " slots"
      log("DEFRAG", "Defrag done: freed " .. d.freed .. " slots"); toast("Defrag freed " .. d.freed .. " slots", C.magenta)
    end
  end
  -- factory auto-stock (only on the factory screen)
  if ROLE == "factory" and AUTOSTOCK then AUTOSTOCK(dt) end
  -- throughput history (one bucket per sim second)
  S.sec = S.sec + dt
  if S.sec >= 1 then
    S.sec = S.sec - 1
    S.hist[#S.hist + 1] = S.histAcc; S.histAcc = 0
    if #S.hist > 72 then table.remove(S.hist, 1) end
  end
end

---------------------------------------------------------------------
-- Screen buffer: 0-based x,y; flushed to the monitor with blit()
---------------------------------------------------------------------
local mon, monName
local W, H = 143, 67
local Bc, Bf, Bb = {}, {}, {}
local clipR = nil
local prevRows = {}
local B = {}
function B.resize(w, h)
  W, H = w, h
  Bc, Bf, Bb, prevRows = {}, {}, {}, {}
  for i = 1, w * h do Bc[i] = " "; Bf[i] = C.white; Bb[i] = C.black end
end
function B.clear(bg)
  for i = 1, W * H do Bc[i] = " "; Bf[i] = C.white; Bb[i] = bg end
end
function B.put(x, y, ch, fg, bg)
  if x < 0 or y < 0 or x >= W or y >= H then return end
  local r = clipR
  if r and (x < r.x or y < r.y or x >= r.x + r.w or y >= r.y + r.h) then return end
  local i = y * W + x + 1
  Bc[i] = ch
  if fg then Bf[i] = fg end
  if bg then Bb[i] = bg end
end
function B.text(x, y, s, fg, bg)
  s = tostring(s)
  for k = 1, #s do B.put(x + k - 1, y, s:sub(k, k), fg, bg) end
end
function B.fill(x, y, w, h, bg, ch, fg)
  ch = ch or " "
  for j = 0, h - 1 do for i = 0, w - 1 do B.put(x + i, y + j, ch, fg, bg) end end
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

---------------------------------------------------------------------
-- Drawing helpers
---------------------------------------------------------------------
local UI = {regions={}, pressed=nil, pressedAt=-9}
local function region(key, x, y, w, h, fn) UI.regions[#UI.regions + 1] = {key=key, x=x, y=y, w=w, h=h, fn=fn} end
local function isPressed(k) return UI.pressed == k and rt() - UI.pressedAt < 0.25 end
local function button(key, x, y, w, h, label, o)
  if w <= 0 or h <= 0 then return end
  o = o or {}
  local bg, fg = o.bg or C.gray, o.fg or C.white
  if o.disabled then bg = o.dbg or C.blue; fg = C.lightGray end
  if isPressed(key) then bg, fg = fg, bg end
  B.fill(x, y, w, h, bg)
  local lines = type(label) == "table" and label or {label}
  local y0 = y + floor((h - #lines) / 2)
  for i, l in ipairs(lines) do
    l = trunc(l, max(1, w - 2))
    local tx = (o.align == "left") and (x + 1) or (x + floor((w - #l) / 2))
    B.text(tx, y0 + i - 1, l, i == 1 and fg or (o.fg2 or fg), nil)
  end
  if not o.disabled and o.on then region(key, x, y, w, h, o.on) end
end
local function confirmButton(key, x, y, w, h, label, confirmLabel, on, o)
  o = o or {}
  local armed = S.confirm.key == key and rt() < S.confirm.until_
  local oo = {}
  for k, v in pairs(o) do oo[k] = v end
  oo.bg = armed and C.red or (o.bg or C.gray)
  oo.fg = (armed or not o.fg) and C.white or o.fg
  oo.on = function()
    if armed then S.confirm.key = nil; on() else S.confirm = {key=key, until_=rt() + 3} end
  end
  button(key, x, y, w, h, armed and confirmLabel or label, oo)
end
local function panel(x, y, w, h, title, meta, metaCol)
  B.fill(x, y, w, h, C.blue)
  if title then
    B.fill(x, y, w, 1, C.gray)
    B.text(x + 1, y, trunc(title:upper(), w - 2), C.yellow, C.gray)
    if meta then
      local m = trunc(meta, max(0, w - #title - 4))
      B.text(x + w - 1 - #m, y, m, metaCol or C.lightGray, C.gray)
    end
  end
end
local function tele(tl, tr, ml, mr, bl, br)
  local inv = false
  if br then inv = true; tl, tr, ml, mr, bl = not tl, not tr, not ml, not mr, not bl end
  local code = 128 + (tl and 1 or 0) + (tr and 2 or 0) + (ml and 4 or 0) + (mr and 8 or 0) + (bl and 16 or 0)
  return string.char(code), inv
end
local EMPTY_TELE = string.char(128)
local function bitmap(x, y, rows, fg, bg)
  local maxw = 0
  for _, r in ipairs(rows) do if #r > maxw then maxw = #r end end
  local hs, ws = math.ceil(#rows / 3) * 3, math.ceil(maxw / 2) * 2
  local function px(cx, cy) local r = rows[cy + 1]; return r ~= nil and r:sub(cx + 1, cx + 1) == "#" end
  for cy = 0, hs / 3 - 1 do for cx = 0, ws / 2 - 1 do
    local sx, sy = cx * 2, cy * 3
    local ch, inv = tele(px(sx, sy), px(sx + 1, sy), px(sx, sy + 1), px(sx + 1, sy + 1), px(sx, sy + 2), px(sx + 1, sy + 2))
    if ch == EMPTY_TELE then B.put(x + cx, y + cy, " ", fg, inv and fg or bg)
    else B.put(x + cx, y + cy, ch, inv and bg or fg, inv and fg or bg) end
  end end
end
local FONT = {
 ["0"]={"###","#.#","#.#","#.#","###"}, ["1"]={".#.","##.",".#.",".#.","###"}, ["2"]={"###","..#","###","#..","###"},
 ["3"]={"###","..#",".##","..#","###"}, ["4"]={"#.#","#.#","###","..#","..#"}, ["5"]={"###","#..","###","..#","###"},
 ["6"]={"###","#..","###","#.#","###"}, ["7"]={"###","..#",".#.",".#.",".#."}, ["8"]={"###","#.#","###","#.#","###"},
 ["9"]={"###","#.#","###","..#","###"}, [","]={".",".",".","#","#"}, ["."]={".",".",".",".","#"},
 ["%"]={"#.#","..#",".#.","#..","#.#"}, ["k"]={"#..","#.#","##.","#.#","#.#"}, ["M"]={"#.#","###","###","#.#","#.#"},
 [" "]={".",".",".",".","."}, ["x"]={"...","#.#",".#.","#.#","..."}, ["/"]={"..#","..#",".#.","#..","#.."},
}
local function bigText(x, y, s, fg, bg)
  local rows = {"", "", "", "", "", ""}
  s = tostring(s)
  for k = 1, #s do
    local g = FONT[s:sub(k, k)] or FONT[" "]
    for r = 1, 5 do rows[r] = rows[r] .. g[r] .. "." end
    rows[6] = rows[6] .. ("."):rep(#g[1] + 1)
  end
  bitmap(x, y, rows, fg, bg)
  return math.ceil(#rows[1] / 2)
end
local TELE_FULL_THIN = tele(true, true, true, true, false, false)
local TELE_HALF_THIN = tele(true, false, true, false, false, false)
local TELE_HALF = tele(true, false, true, false, true, false)
local function bar(x, y, w, frac, fg, track, thin)
  if w <= 0 then return end
  track = track or C.gray
  local halves = round(clamp(frac, 0, 1) * w * 2)
  for i = 0, w - 1 do
    local h = halves - i * 2
    if thin then
      if h >= 2 then B.put(x + i, y, TELE_FULL_THIN, fg, nil)
      elseif h == 1 then B.put(x + i, y, TELE_HALF_THIN, fg, nil)
      else B.put(x + i, y, TELE_FULL_THIN, track, nil) end
    else
      if h >= 2 then B.put(x + i, y, " ", fg, fg)
      elseif h == 1 then B.put(x + i, y, TELE_HALF, fg, track)
      else B.put(x + i, y, " ", fg, track) end
    end
  end
end
local function spark(x, y, w, h, data, fg, bg)
  local ws, hs = w * 2, h * 3
  local d = {}
  for i = max(1, #data - ws + 1), #data do d[#d + 1] = data[i] end
  local mx = 1
  for _, v in ipairs(d) do if v > mx then mx = v end end
  local rows = {}
  local offset = ws - #d
  for r = 0, hs - 1 do
    local s = {}
    for c = 0, ws - 1 do
      local v = d[c - offset + 1]
      local hgt = 0
      if v then hgt = round(v / mx * (hs - 1)) + (v > 0 and 1 or 0) end
      s[#s + 1] = (hs - r <= hgt) and "#" or "."
    end
    rows[#rows + 1] = table.concat(s)
  end
  bitmap(x, y, rows, fg, bg)
  return mx
end
local ICONS = {
 home={"..##..",".####.","######",".#..#.",".#..#.",".####."},
 items={"##.##.","##.##.","......","##.##.","##.##.","......"},
 craft={"#.#.#.","......","#.#.#.","......","#.#.#.","......"},
 jobs={"######","......","####..","......","##....","......"},
 mach={"######","#.##.#","######","#....#","######","......"},
 store={".####.","#....#",".####.","#....#",".####.","......"},
 farms={"#...#.",".#.#..","..#...","..#...","######","......"},
}
local TABS = {{"home","HOME"},{"items","ITEMS"},{"craft","CRAFT"},{"jobs","JOBS"},{"mach","MACHINES"},{"store","STORAGE"},{"farms","FARMS"}}
local TABS_SHORT = {home="HOME",items="ITEMS",craft="CRAFT",jobs="JOBS",mach="MACH",store="STORE",farms="FARMS"}
local function go(tab) S.tab = tab; S.kb.open = false end
local function tabLabel(key) for _, t in ipairs(TABS) do if t[1] == key then return t[2] end end return "" end

---------------------------------------------------------------------
-- Shell: header, nav, status bar, toasts, keyboard
---------------------------------------------------------------------
local function alerts()
  local a = {}
  for _, s in ipairs(S.storages) do if not s.online then a[#a + 1] = {sev="crit", text=s.name .. " is offline", sub="Reconnect the modem", tab="store"} end end
  local j = S.jobs[1]
  if j and j.state == "FAILED" then a[#a + 1] = {sev="crit", text="Craft failed: " .. iName(j.item), sub="Open JOBS to retry", tab="jobs"} end
  for _, id in ipairs(ITEM_ORDER) do
    local it = ITEMS[id]
    if it.target > 0 and have(id) < it.target * 0.5 then
      a[#a + 1] = {sev=(have(id) < it.target * 0.2) and "crit" or "warn",
                   text="Low " .. it.name .. " " .. fmt(have(id)) .. "/" .. fmt(it.target),
                   sub=EXTERNAL[id] or "Check the farm", tab="farms"}
    end
  end
  return a
end
local function drawHeader(wide)
  B.fill(0, 0, W, 1, C.gray)
  B.text(0, 0, " VAULT BRAIN ", C.black, C.yellow)
  if wide then B.text(14, 0, " " .. tabLabel(S.tab) .. " ", C.white, C.gray) end
  local r = W
  local t = "Day " .. S.day .. " " .. clockStr() .. " "
  r = r - #t; B.text(r, 0, t, C.lightGray, C.gray)
  local al = alerts()
  local crit = 0
  for _, a in ipairs(al) do if a.sev == "crit" then crit = crit + 1 end end
  if #al > 0 then
    local s = " " .. #al .. " ALERT" .. (#al > 1 and "S" or "") .. " "
    r = r - #s - 1
    B.text(r, 0, s, crit > 0 and C.white or C.black, crit > 0 and C.red or C.orange)
    region("hdr:alerts", r, 0, #s, 1, function() go("home") end)
  end
  local j = S.jobs[1]
  if j then
    local s = (j.state == "FAILED") and " JOB FAILED " or (" CRAFTING " .. ((#S.jobs > 1) and ("+" .. (#S.jobs - 1) .. " ") or ""))
    r = r - #s - 1
    B.text(r, 0, s, j.state == "FAILED" and C.white or C.black, j.state == "FAILED" and C.red or C.yellow)
    region("hdr:job", r, 0, #s, 1, function() go("jobs") end)
  end
  local autoActive = S.auto.on and S.t - S.lastTouch > 20 and #S.jobs == 0
  if wide or not j then
    local spin = ("-\\|/"):sub(floor(rt() * 6) % 4 + 1, floor(rt() * 6) % 4 + 1)
    local s = autoActive and (" AUTO " .. spin .. " ") or " AUTO idle "
    r = r - #s - 1
    B.text(r, 0, s, autoActive and C.black or C.lightGray, autoActive and C.lime or C.blue)
  end
end
local function drawSidebar(x, y, w, h)
  B.fill(x, y, w, h, C.blue)
  local yy = y + 1
  for _, tab in ipairs(TABS) do
    local key, label = tab[1], tab[2]
    local sel, k = S.tab == key, "nav:" .. key
    local pr = isPressed(k)
    local bg = pr and C.yellow or (sel and C.gray or C.blue)
    B.fill(x, yy, w, 3, bg)
    if sel then B.fill(x, yy, 1, 3, C.yellow) end
    bitmap(x + 2, yy, ICONS[key], pr and C.black or (sel and C.yellow or C.lightGray), bg)
    B.text(x + 6, yy + 1, label, pr and C.black or (sel and C.white or C.lightGray), bg)
    if key == "jobs" and #S.jobs > 0 then
      local n = tostring(#S.jobs)
      B.text(x + w - 2 - #n, yy + 1, " " .. n .. " ", C.black, S.jobs[1].state == "FAILED" and C.red or C.yellow)
    end
    region(k, x, yy, w, 3, function() go(key) end)
    yy = yy + 4
  end
  yy = yy + 1
  if yy + 13 < y + h then
    B.text(x + 1, yy, "SYSTEM", C.lightGray, C.blue); yy = yy + 1
    local cap, u = 0, 0
    for _, s in ipairs(mainStorages()) do cap = cap + s.cap; u = u + used(s) end
    B.text(x + 1, yy, "MAIN", C.white, C.blue)
    B.text(x + w - 5, yy, padL(round(u / max(1, cap) * 100) .. "%", 4), C.yellow, C.blue); yy = yy + 1
    bar(x + 1, yy, w - 2, u / max(1, cap), C.yellow, C.gray); yy = yy + 2
    local tOk = 0
    for _, t in ipairs(S.turtles) do if t.state ~= "ERROR" then tOk = tOk + 1 end end
    B.text(x + 1, yy, "Turtles", C.white, C.blue); B.text(x + w - 5, yy, padL(tOk .. "/6", 4), tOk < 6 and C.red or C.lime, C.blue); yy = yy + 1
    local inN, outN = 0, 0
    for _, s in ipairs(S.input) do inN = inN + s.n end
    for _, v in pairs(S.output) do outN = outN + v end
    B.text(x + 1, yy, "Input", C.white, C.blue); B.text(x + w - 6, yy, padL(kfmt(inN), 5), inN > 0 and C.lightBlue or C.lightGray, C.blue); yy = yy + 1
    B.text(x + 1, yy, "Output", C.white, C.blue); B.text(x + w - 6, yy, padL(kfmt(outN), 5), outN > 0 and C.white or C.lightGray, C.blue); yy = yy + 1
    B.text(x + 1, yy, "Queue", C.white, C.blue); B.text(x + w - 6, yy, padL(tostring(#S.jobs), 5), #S.jobs > 0 and C.yellow or C.lightGray, C.blue)
  end
  B.text(x + 1, y + h - 1, trunc("CC " .. W .. "x" .. H, w - 2), C.gray, C.blue)
end
local function drawTabs(y)
  local n = #TABS
  local w = floor(W / n)
  local x = 0
  for i, tab in ipairs(TABS) do
    local key = tab[1]
    local ww = (i == n) and (W - x) or w
    local sel, k = S.tab == key, "nav:" .. key
    local pr = isPressed(k)
    local bg = pr and C.yellow or (sel and C.gray or C.blue)
    B.fill(x, y, ww, 2, bg)
    local l = TABS_SHORT[key]
    B.text(x + floor((ww - #l) / 2), y, l, pr and C.black or (sel and C.yellow or C.lightGray), bg)
    if sel then B.fill(x, y + 1, ww, 1, C.yellow) end
    region(k, x, y, ww, 2, function() go(key) end)
    x = x + ww
  end
end
local function drawStatus(kinds, bg)
  local y = H - 1
  bg = bg or C.gray
  B.fill(0, y, W, 1, bg)
  local l
  for i = #S.log, 1, -1 do if not kinds or kinds[S.log[i].kind] then l = S.log[i] break end end
  local t = S.touchInfo and ("touch " .. S.touchInfo.x .. "," .. S.touchInfo.y) or "tap anywhere"
  if l then
    B.text(1, y, clockStr(l.tod), C.lightGray, bg)
    local tag = " " .. l.kind .. " "
    B.text(7, y, tag, C.black, LOGCOL[l.kind] or C.white)
    B.text(8 + #tag, y, trunc(l.text, W - 10 - #tag - #t - 2), C.white, bg)
  end
  B.text(W - #t - 1, y, t, C.lightGray, bg)
end
local function drawToasts()
  local now = rt()
  local keep = {}
  for _, t in ipairs(S.toasts) do if t.until_ > now then keep[#keep + 1] = t end end
  S.toasts = keep
  local y = H - 3
  for i = #S.toasts, 1, -1 do
    local t = S.toasts[i]
    local s = trunc(t.text, min(60, W - 6))
    local w = #s + 4
    local x = W - w - 1
    B.fill(x, y - 1, w, 3, C.black); B.fill(x, y - 1, 1, 3, t.col); B.text(x + 2, y, s, C.white, C.black)
    y = y - 4
    if y < 4 then break end
  end
end
local function drawKeyboard()
  local wide = W >= 110
  local kw, kh, gap = wide and 8 or 6, (wide and H >= 50) and 3 or 2, 1
  local rows = {"1234567890", "QWERTYUIOP", "ASDFGHJKL", "ZXCVBNM"}
  local bw = 10 * (kw + gap) + 1
  local bh = #rows * (kh + gap) + kh + gap + 4
  local x0, y0 = floor((W - bw) / 2), H - bh - 2
  region("kb:panel", x0 - 1, y0 - 1, bw + 2, bh + 2, function() end)
  B.fill(x0 - 1, y0 - 1, bw + 2, bh + 2, C.gray); B.fill(x0, y0, bw, bh, C.blue)
  local tgt = (S.kb.target == "items") and S.iv or S.cv
  B.text(x0 + 1, y0 + 1, "SEARCH", C.yellow, C.blue)
  B.fill(x0 + 8, y0 + 1, bw - 9, 1, C.black)
  local cursor = (floor(rt() * 2.5) % 2 == 0) and "_" or " "
  B.text(x0 + 9, y0 + 1, trunc(tgt.search .. cursor, bw - 11), C.white, C.black)
  for ri, r in ipairs(rows) do
    local off = floor((10 - #r) * (kw + gap) / 2)
    for ci = 1, #r do
      local ch = r:sub(ci, ci)
      local x, y = x0 + 1 + off + (ci - 1) * (kw + gap), y0 + 3 + (ri - 1) * (kh + gap)
      button("kb:" .. ch, x, y, kw, kh, ch, {bg=C.gray, on=function()
        if #tgt.search < 24 then tgt.search = tgt.search .. ch:lower(); tgt.page = 0 end end})
    end
  end
  local yb = y0 + 3 + #rows * (kh + gap)
  local q = floor((bw - 2 - 3 * gap) / 4)
  button("kb:space", x0 + 1, yb, q, kh, "SPACE", {on=function() tgt.search = tgt.search .. " "; tgt.page = 0 end})
  button("kb:del", x0 + 1 + (q + gap), yb, q, kh, "DELETE", {on=function() tgt.search = tgt.search:sub(1, -2); tgt.page = 0 end})
  button("kb:clr", x0 + 1 + 2 * (q + gap), yb, q, kh, "CLEAR", {fg=C.orange, on=function() tgt.search = ""; tgt.page = 0 end})
  button("kb:done", x0 + 1 + 3 * (q + gap), yb, bw - 2 - 3 * (q + gap), kh, "DONE", {bg=C.lime, fg=C.black, on=function() S.kb.open = false end})
end

---------------------------------------------------------------------
-- Screens
---------------------------------------------------------------------
local function kpi(x, y, w, label, value, sub, col)
  B.fill(x, y, w, 6, C.blue)
  B.text(x + 2, y + 1, trunc(label, w - 3), C.lightGray, C.blue)
  bigText(x + 2, y + 2, value, col, C.blue)
  B.text(x + 2, y + 4, trunc(sub, w - 3), C.lightGray, C.blue)
end
local function totalItems() local n = 0 for _, v in pairs(S.tot) do n = n + v end return n end
local function jobProgress(j)
  local d, t = 0, 0
  for _, s in ipairs(j.steps) do d = d + s.done; t = t + s.crafts end
  return t > 0 and d / t or 0
end
local function jobEta(j)
  local e = 0
  for _, s in ipairs(j.steps) do if s.done < s.crafts then e = e + stepSecs({m=s.m, crafts=s.crafts - s.done}) end end
  return e
end
local function onlineCount() local n = 0 for _, s in ipairs(S.storages) do if s.online then n = n + 1 end end return n end
local function busyTurtles() local n = 0 for _, t in ipairs(S.turtles) do if t.task then n = n + 1 end end return n end

local function scrHome(x, y, w, h, wide)
  local cap, u = 0, 0
  for _, s in ipairs(mainStorages()) do cap = cap + s.cap; u = u + used(s) end
  local fill = u / max(1, cap)
  local tiles = {
    {"STORED ITEMS", kfmt(totalItems()), onlineCount() .. " storages online", C.white},
    {"ITEM TYPES", tostring(S.totN), "across all storage", C.white},
    {"MAIN FILL", round(fill * 100) .. "%", kfmt(u) .. " of " .. kfmt(cap), fill > 0.85 and C.red or C.yellow},
    {"CRAFTED TODAY", kfmt(S.craftedToday), #S.history .. " jobs in history", C.lime},
  }
  local per = wide and 4 or 2
  local tw = floor((w - (per - 1)) / per)
  for i, t in ipairs(tiles) do
    local col = (i - 1) % per
    local tx = x + col * (tw + 1)
    kpi(tx, y + floor((i - 1) / per) * 7, (col == per - 1) and (w - (per - 1) * (tw + 1)) or tw, t[1], t[2], t[3], t[4])
  end
  local yy = y + (wide and 7 or 14)
  local leftW = wide and floor(w * 0.58) or w
  local rightX, rightW = x + leftW + 1, w - leftW - 1
  -- ACTIVE CRAFT
  local jh = wide and 12 or 6
  local jx, jw, jy = wide and rightX or x, wide and rightW or w, yy
  local j = S.jobs[1]
  local meta = "idle"
  if j then meta = (j.state == "FAILED") and "FAILED" or (round(jobProgress(j) * 100) .. "%") end
  panel(jx, jy, jw, jh, "Active craft", meta, (j and j.state == "FAILED") and C.red or C.lightGray)
  if j then
    B.text(jx + 1, jy + 2, trunc(iName(j.item) .. "  x" .. j.qty, jw - 2), C.white, C.blue)
    bar(jx + 1, jy + 3, jw - 2, jobProgress(j), j.state == "FAILED" and C.red or C.yellow)
    local st, si
    for i, s in ipairs(j.steps) do if s.done < s.crafts then st, si = s, i break end end
    if j.state == "FAILED" then B.text(jx + 1, jy + 4, trunc(j.err or "", jw - 2), C.red, C.blue)
    elseif st then B.text(jx + 1, jy + 4, trunc("Step " .. si .. "/" .. #j.steps .. "  " .. iName(st.item) .. " on " .. MACH[st.m].name, jw - 2), C.lightGray, C.blue) end
    if wide then
      B.text(jx + 1, jy + 6, "ETA", C.lightGray, C.blue); B.text(jx + 5, jy + 6, "~" .. math.ceil(jobEta(j)) .. "s", C.white, C.blue)
      if #S.jobs > 1 then B.text(jx + 12, jy + 6, (#S.jobs - 1) .. " queued", C.lightGray, C.blue) end
      button("home:openjob", jx + 1, jy + jh - 4, jw - 2, 3, "OPEN JOBS", {on=function() go("jobs") end})
    else
      button("home:openjob", jx + jw - 12, jy + 1, 11, 1, "OPEN", {on=function() go("jobs") end})
    end
  else
    B.text(jx + 1, jy + 2, trunc("Nothing crafting. Quick craft:", jw - 2), C.lightGray, C.blue)
    local q = {{"create:andesite_alloy", 64}, {"create:shaft", 64}, {"create:cogwheel", 16}}
    if wide then
      for i, qq in ipairs(q) do
        button("home:q" .. i, jx + 1, jy + 3 + (i - 1) * 3, jw - 2, 2, iName(qq[1]) .. " x" .. qq[2],
          {on=function() queueCraft(qq[1], qq[2]); go("jobs") end})
      end
    else
      local bw = floor((jw - 4) / 3)
      for i, qq in ipairs(q) do
        button("home:q" .. i, jx + 1 + (i - 1) * (bw + 1), jy + 3, bw, 2, iName(qq[1]),
          {on=function() queueCraft(qq[1], qq[2]); go("jobs") end})
      end
    end
  end
  if not wide then yy = yy + jh + 1 end
  if wide then
    -- STORAGE
    local sh = 12
    panel(x, yy, leftW, sh, "Storage", kfmt(u) .. " / " .. kfmt(cap) .. " items in MAIN")
    local ry = yy + 2
    for _, s in ipairs(S.storages) do
      if s.role == "MAIN" then
        local f = used(s) / s.cap
        B.text(x + 1, ry, padR(s.name, 10), s.online and C.white or C.red, C.blue)
        if s.online then
          bar(x + 12, ry, leftW - 30, f, f > 0.85 and C.red or (f > 0.6 and C.orange or C.yellow))
          B.text(x + leftW - 17, ry, padL(round(f * 100) .. "%", 4), C.white, C.blue)
          B.text(x + leftW - 12, ry, padL(kfmt(used(s)), 10), C.lightGray, C.blue)
        else
          B.fill(x + 12, ry, leftW - 30, 1, C.blue, CH_CHK, C.red)
          B.text(x + leftW - 17, ry, " OFFLINE ", C.white, C.red)
        end
        ry = ry + 2
      end
    end
    local restN, ru = 0, 0
    for _, s in ipairs(S.storages) do if s.role == "REST" and s.online then restN = restN + 1; ru = ru + used(s) end end
    B.text(x + 1, ry, "REST", C.lightBlue, C.blue)
    B.text(x + 12, ry, trunc(restN .. " storages, " .. kfmt(ru) .. " items waiting for AUTO", leftW - 14), C.lightGray, C.blue)
    yy = yy + sh + 1
    -- MACHINES
    local mh = 9
    panel(x, yy, leftW, mh, "Machines", busyTurtles() .. " turtles busy")
    local cx = x + 1
    B.text(cx, yy + 2, "Crafty Turtles", C.lightGray, C.blue)
    for i, t in ipairs(S.turtles) do
      local col = (t.state == "ERROR") and C.red or ((t.state == "IDLE") and C.green or C.cyan)
      B.text(cx + (i - 1) * 6, yy + 3, " T" .. (i - 1) .. "  ", C.black, col)
      B.text(cx + (i - 1) * 6, yy + 4, padR(t.state == "IDLE" and "idle" or t.state:lower(), 5), t.state == "ERROR" and C.red or C.lightGray, C.blue)
    end
    local c = S.c21
    cx = x + 38
    B.text(cx, yy + 2, "Crafter 21 A", C.lightGray, C.blue)
    B.text(cx, yy + 3, " " .. padR(c.state, 9) .. " ", C.black, c.state == "IDLE" and C.green or C.purple)
    B.text(cx, yy + 4, c.relay and "relay ON" or "relay off", c.relay and C.red or C.lightGray, C.blue)
    cx = x + 55
    B.text(cx, yy + 2, "Blasters A", C.lightGray, C.blue)
    for i, b in ipairs(S.basins) do
      local hot = b.item and ((b.heat > 0.6 and C.yellow) or (b.heat > 0.2 and C.orange) or C.red) or C.gray
      B.put(cx + (i - 1) * 2, yy + 3, " ", nil, hot)
    end
    B.text(cx, yy + 4, S.blast.task and "heating" or "idle", S.blast.task and C.orange or C.lightGray, C.blue)
    B.text(x + 1, yy + 6, trunc("Tap here for turtle slots, crafter layout and basin heat", leftW - 2), C.gray, C.blue)
    region("home:mach", x, yy, leftW, mh, function() go("mach") end)
    -- THROUGHPUT
    panel(rightX, yy, rightW, mh, "Items moved / s", tostring(S.hist[#S.hist] or 0), C.white)
    local mx = spark(rightX + 1, yy + 2, rightW - 2, mh - 3, S.hist, C.cyan, C.blue)
    B.text(rightX + 1, yy + mh - 1, trunc("last 72 s  peak " .. mx, rightW - 2), C.lightGray, C.blue)
    yy = yy + mh + 1
  end
  -- ATTENTION + ACTIVITY
  local rest = y + h - yy
  if rest < 4 then return end
  local al = alerts()
  local aw, ax = wide and rightW or w, wide and rightX or x
  local ah = wide and rest or min(rest, max(4, min(#al, 4) + 2))
  panel(ax, yy, aw, ah, "Needs attention", #al > 0 and (#al .. " open") or "all clear", #al > 0 and C.orange or C.lime)
  if #al == 0 then B.text(ax + 1, yy + 2, "Nothing needs attention.", C.lime, C.blue) end
  local per = wide and 2 or 1
  for i = 1, min(#al, floor((ah - 2) / per)) do
    local a = al[i]
    local ry = yy + 2 + (i - 1) * per
    local col = a.sev == "crit" and C.red or C.orange
    B.put(ax + 1, ry, CH_DOT, col, C.blue)
    B.text(ax + 3, ry, trunc(a.text, aw - 4), C.white, C.blue)
    if wide then B.text(ax + 3, ry + 1, trunc(a.sub, aw - 4), C.lightGray, C.blue) end
    region("home:al" .. i, ax, ry, aw, per, function() go(a.tab) end)
  end
  if wide or rest - ah > 3 then
    local lx, ly = x, wide and yy or (yy + ah + 1)
    local lw, lh = wide and leftW or w, wide and rest or (rest - ah - 1)
    panel(lx, ly, lw, lh, "Activity", "live")
    local first = max(1, #S.log - (lh - 2) + 1)
    for i = first, #S.log do
      local l = S.log[i]
      local ry = ly + 2 + (i - first)
      B.text(lx + 1, ry, clockStr(l.tod), C.gray, C.blue)
      B.text(lx + 7, ry, padR(l.kind, 6), LOGCOL[l.kind] or C.white, C.blue)
      B.text(lx + 14, ry, trunc(l.text, lw - 15), C.white, C.blue)
    end
  end
end

local function itemsList()
  local v = S.iv
  local cat, q = CATS[v.cat], v.search:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local list = {}
  for id, n in pairs(S.tot) do
    local it = ITEMS[id]
    if it and (cat == "All" or it.cat == cat) and (q == "" or it.name:lower():find(q, 1, true) or id:find(q, 1, true)) then
      list[#list + 1] = {id=id, n=n, it=it}
    end
  end
  table.sort(list, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.it.name < b.it.name end)
  return list
end
local function withdraw(id, n)
  local take = min(n, have(id))
  if take <= 0 then toast("None stored", C.red) return end
  local got = removeStock(id, take)
  S.output[id] = (S.output[id] or 0) + got; S.outputAt = S.t; moved(got)
  log("OUTPUT", iName(id) .. " x" .. got .. " > barrel_74")
  toast("Withdrew " .. iName(id) .. " x" .. got, C.white)
end
local function searchBar(x, y, w, target)
  local v = (target == "items") and S.iv or S.cv
  local k = "srch:" .. target
  local pr = isPressed(k)
  B.fill(x, y, w, 2, pr and C.yellow or C.black)
  B.text(x + 1, y, "SEARCH", pr and C.black or C.yellow, nil)
  B.text(x + 1, y + 1, trunc(v.search ~= "" and v.search or "tap to type", w - 6), v.search ~= "" and C.white or C.gray, nil)
  region(k, x, y, w - 4, 2, function() S.kb.open = true; S.kb.target = target end)
  if v.search ~= "" then button(k .. ":x", x + w - 4, y, 4, 2, "X", {fg=C.orange, on=function() v.search = ""; v.page = 0 end}) end
end
local function catChips(x, y, w)
  local v = S.iv
  local cx = x
  for i = v.catOff, #CATS do
    local l = CATS[i]
    if cx + #l + 2 > x + w - 3 then break end
    local sel = v.cat == i
    button("cat:" .. i, cx, y, #l + 2, 2, l, {bg=sel and C.yellow or C.gray, fg=sel and C.black or C.lightGray,
      on=function() v.cat = i; v.page = 0 end})
    cx = cx + #l + 3
  end
  button("cat:more", x + w - 3, y, 3, 2, CH_R, {on=function() v.catOff = v.catOff % #CATS + 1 end})
end
local function pager(x, y, w, page, pages, set, key)
  local bw = min(14, floor((w - 12) / 2))
  button(key .. ":prev", x, y, bw, 3, CH_L .. " PREV", {disabled=page <= 0, on=function() set(page - 1) end})
  local t = "PAGE " .. (page + 1) .. " / " .. max(1, pages)
  B.fill(x + bw, y, w - 2 * bw, 3, C.black)
  B.text(x + floor((w - #t) / 2), y + 1, t, C.lightGray, C.black)
  button(key .. ":next", x + w - bw, y, bw, 3, "NEXT " .. CH_R, {disabled=page >= pages - 1, on=function() set(page + 1) end})
end
local itemDetail
local function scrItems(x, y, w, h, wide)
  local v = S.iv
  local list = itemsList()
  local detailW = wide and 44 or 0
  local lw = w - (detailW > 0 and detailW + 1 or 0)
  if not wide and v.sel then itemDetail(x, y, w, h, false) return end
  local sw = min(40, lw)
  searchBar(x, y, sw, "items")
  if lw > 60 then catChips(x + sw + 1, y, lw - sw - 1) else catChips(x, y + 3, lw) end
  local ly = y + ((lw > 60) and 3 or 6)
  local lh = h - (ly - y) - 4
  local tw = wide and 27 or 22
  local cols = max(1, floor((lw + 1) / (tw + 1)))
  local tW = floor((lw - (cols - 1)) / cols)
  local rows = max(1, floor((lh + 1) / 3))
  local per = cols * rows
  local pages = max(1, math.ceil(#list / per))
  v.page = clamp(v.page, 0, pages - 1)
  if #list == 0 then B.text(x + 1, ly + 1, 'No items match "' .. v.search .. '".', C.lightGray, nil) end
  local maxN = 1
  for _, r in ipairs(list) do if r.n > maxN then maxN = r.n end end
  for i = 1, per do
    local r = list[v.page * per + i]
    if not r then break end
    local cx = x + ((i - 1) % cols) * (tW + 1)
    local cy = ly + floor((i - 1) / cols) * 3
    local sel, k = v.sel == r.id, "it:" .. r.id
    local pr = isPressed(k)
    local bg = pr and C.yellow or (sel and C.gray or C.blue)
    B.fill(cx, cy, tW, 2, bg); B.fill(cx, cy, 1, 2, r.it.col)
    B.text(cx + 2, cy, trunc(r.it.name, tW - 3), pr and C.black or C.white, bg)
    local ns = fmt(r.n)
    B.text(cx + tW - 1 - #ns, cy + 1, ns, pr and C.black or C.yellow, bg)
    bar(cx + 2, cy + 1, max(0, tW - #ns - 5), math.log(r.n + 1) / math.log(maxN + 1), sel and C.lightGray or C.cyan, sel and C.blue or C.gray, true)
    local id = r.id
    region(k, cx, cy, tW, 2, function() v.sel = id end)
  end
  pager(x, y + h - 3, lw, v.page, pages, function(p) v.page = p end, "ip")
  if wide then
    if v.sel then itemDetail(x + lw + 1, y, detailW, h, true)
    else
      panel(x + lw + 1, y, detailW, h, "Item")
      B.text(x + lw + 3, y + 3, "Tap an item to see where it", C.lightGray, C.blue)
      B.text(x + lw + 3, y + 4, "is stored and withdraw it.", C.lightGray, C.blue)
    end
  end
end
itemDetail = function(x, y, w, h, wide)
  local v = S.iv
  local id = v.sel
  local it = ITEMS[id]
  if not it then v.sel = nil return end
  panel(x, y, w, h, "Item", it.cat)
  local yy = y + 2
  if not wide then button("it:back", x + 1, yy, 10, 2, CH_L .. " BACK", {on=function() v.sel = nil end}); yy = yy + 3 end
  B.fill(x + 1, yy, 1, 2, it.col)
  B.text(x + 3, yy, trunc(it.name, w - 4), C.white, C.blue)
  B.text(x + 3, yy + 1, trunc(id, w - 4), C.lightGray, C.blue)
  yy = yy + 3
  bigText(x + 3, yy, fmt(have(id)), C.yellow, C.blue)
  B.text(x + 3, yy + 2, "in storage  stack " .. it.stack, C.lightGray, C.blue)
  yy = yy + 4
  B.text(x + 1, yy, "WHERE", C.lightGray, C.blue); yy = yy + 1
  local locs = {}
  for _, s in ipairs(S.storages) do if s.online and (s.inv[id] or 0) > 0 then locs[#locs + 1] = s end end
  table.sort(locs, function(a, b) return a.inv[id] > b.inv[id] end)
  local tot = max(1, have(id))
  for i = 1, min(6, #locs) do
    local s = locs[i]
    local n = s.inv[id]
    B.text(x + 1, yy, padR(s.name, 14), s.role == "MAIN" and C.white or C.lightBlue, C.blue)
    bar(x + 16, yy, w - 27, n / tot, s.role == "MAIN" and C.yellow or C.lightBlue, C.gray, true)
    B.text(x + w - 10, yy, padL(fmt(n), 9), C.lightGray, C.blue)
    yy = yy + 1
  end
  yy = yy + 1
  B.text(x + 1, yy, "WITHDRAW TO OUTPUT BARREL", C.lightGray, C.blue); yy = yy + 1
  local opts = {{"1", 1}, {"16", 16}, {"64", 64}, {"ALL", have(id)}}
  local bw = floor((w - 5) / 4)
  for i, o in ipairs(opts) do
    local amount = o[2]
    button("wd:" .. o[1], x + 1 + (i - 1) * (bw + 1), yy, (i == 4) and (w - 2 - 3 * (bw + 1)) or bw, 3, o[1],
      {disabled=have(id) <= 0, on=function() withdraw(id, amount) end})
  end
  yy = yy + 4
  if RECIPES[id] and ROLE ~= "brain" then
    B.text(x + 1, yy, trunc("Recipe known - craft it from the Brain monitor", w - 2), C.lime, C.blue)
    yy = yy + 2
  elseif RECIPES[id] then
    button("it:craft", x + 1, yy, w - 2, 3, "CRAFT MORE " .. CH_R, {bg=C.yellow, fg=C.black, on=function()
      S.cv.sel = id; S.cv.detail = true; S.cv.qty = min(64, S.cv.qty); S.cv.planPage = 0; go("craft") end})
    yy = yy + 4
  else
    local ex = EXTERNAL[id]
    B.text(x + 1, yy, trunc(ex and ("Made by " .. ex) or "No recipe loaded", w - 2), C.orange, C.blue)
    B.text(x + 1, yy + 1, trunc(ex and "Build that machine to craft it here" or "Comes from a farm or the world", w - 2), C.lightGray, C.blue)
    yy = yy + 3
  end
  local outN = 0
  for _, n in pairs(S.output) do outN = outN + n end
  if y + h - 2 > yy then B.text(x + 1, y + h - 2, trunc("barrel_74 holds " .. fmt(outN) .. " item(s)", w - 2), C.lightGray, C.blue) end
end

local function recipeList()
  local v = S.cv
  local q = v.search:lower():gsub("^%s+", ""):gsub("%s+$", "")
  local out = {}
  for _, id in ipairs(RECIPE_IDS) do
    if q == "" or iName(id):lower():find(q, 1, true) or id:find(q, 1, true) then
      local rd = S.ready[id] and true or false
      if v.filter == "ALL" or ((v.filter == "READY") == rd) then out[#out + 1] = id end
    end
  end
  return out
end
local function cell(x, y, id, w, h, count)
  if not id then B.fill(x, y, w, h, C.black) return end
  B.fill(x, y, w, h, C.gray); B.fill(x, y, w, 1, iCol(id))
  local sh = iSh(id)
  B.text(x + floor((w - #sh) / 2), y + 1, trunc(sh, w), C.white, C.gray)
  if count and h > 2 then local cs = "x" .. count; B.text(x + w - 1 - #cs, y + 2, cs, C.yellow, C.gray) end
end
local function recipeGrid(x, y, w, id)
  local r = RECIPES[id]
  if r.m == "B" then
    local cw = 10
    cell(x, y, r.input, cw, 3)
    B.text(x + cw + 1, y + 1, CH_R, C.orange, C.blue)
    B.fill(x + cw + 3, y, 14, 3, C.black)
    B.text(x + cw + 4, y, "BLASTERS A", C.orange, C.black)
    B.text(x + cw + 4, y + 1, "11 basins", C.lightGray, C.black)
    B.text(x + cw + 4, y + 2, "lava fan", C.lightGray, C.black)
    B.text(x + cw + 18, y + 1, CH_R, C.orange, C.blue)
    cell(x + cw + 20, y, id, cw, 3, r.out)
    return 4
  end
  if r.m == "C" then
    local cw = min(6, floor((w - 12) / 5))
    for yy = 1, 5 do for xx = 1, 5 do
      if not ((yy == 1 or yy == 5) and (xx == 1 or xx == 5)) then
        cell(x + (xx - 1) * (cw + 1), y + (yy - 1) * 2, r.g[yy][xx] or nil, cw, 2)
      end
    end end
    B.text(x + 5 * (cw + 1) + 1, y + 4, CH_R, C.purple, C.blue)
    cell(x + 5 * (cw + 1) + 3, y + 3, id, 8, 3, r.out)
    return 11
  end
  local cw, ch = 7, 3
  for yy = 1, 3 do for xx = 1, 3 do
    local v = r.g[yy] and r.g[yy][xx] or nil
    cell(x + (xx - 1) * (cw + 1), y + (yy - 1) * ch, v or nil, cw, ch)
  end end
  B.text(x + 3 * (cw + 1) + 1, y + 4, CH_R, C.cyan, C.blue)
  cell(x + 3 * (cw + 1) + 3, y + 3, id, 8, 3, r.out)
  return 9
end
local function craftDetail(x, y, w, h, wide)
  local v = S.cv
  local id = v.sel
  local r = RECIPES[id]
  if not r then return end
  local m = MACH[r.m]
  panel(x, y, w, h, iName(id), m.name, m.col)
  local yy = y + 2
  if not wide then button("cd:back", x + 1, yy, 10, 2, CH_L .. " BACK", {on=function() v.detail = false end}); yy = yy + 3 end
  local gh = recipeGrid(x + 2, yy, min(w - 4, 70), id)
  local fx = x + ((r.m == "C") and 50 or ((r.m == "B") and 46 or 42))
  if wide and fx < x + w - 24 then
    B.text(fx, yy, "MAKES", C.lightGray, C.blue); B.text(fx + 8, yy, r.out .. " per craft", C.white, C.blue)
    B.text(fx, yy + 1, "ROUTE", C.lightGray, C.blue); B.text(fx + 8, yy + 1, trunc(m.name, w - (fx - x) - 10), m.col, C.blue)
    B.text(fx, yy + 2, "STORED", C.lightGray, C.blue); B.text(fx + 8, yy + 2, fmt(have(id)), C.yellow, C.blue)
    B.text(fx, yy + 4, "PER CRAFT", C.lightGray, C.blue)
    local ing = ingredients(r)
    for i = 1, min(5, #ing) do
      B.text(fx, yy + 4 + i, trunc(ing[i][2] .. "x " .. iName(ing[i][1]), w - (fx - x) - 2), TAGS[ing[i][1]] and C.lightBlue or C.white, C.blue)
    end
  end
  yy = yy + gh + 1
  -- amount
  B.text(x + 1, yy, "AMOUNT", C.lightGray, C.blue)
  local p = plan(id, v.qty)
  local ax, ay = x + 1, yy + 1
  local bw = wide and 6 or 5
  for _, a in ipairs({{"-64", -64}, {"-8", -8}, {"-1", -1}}) do
    local d = a[2]
    button("q:" .. a[1], ax, ay, bw, 3, a[1], {on=function() v.qty = clamp(v.qty + d, 1, 4096); v.planPage = 0 end})
    ax = ax + bw + 1
  end
  B.fill(ax, ay, 12, 3, C.black)
  bigText(ax + 1 + max(0, floor((12 - #tostring(v.qty) * 2) / 2)), ay, tostring(v.qty), C.yellow, C.black)
  ax = ax + 13
  for _, a in ipairs({{"+1", 1}, {"+8", 8}, {"+64", 64}}) do
    local d = a[2]
    button("q:" .. a[1], ax, ay, bw, 3, a[1], {on=function() v.qty = clamp(v.qty + d, 1, 4096); v.planPage = 0 end})
    ax = ax + bw + 1
  end
  if ax + 7 <= x + w - 1 then
    button("q:max", ax, ay, min(9, x + w - 1 - ax), 3, "MAX", {bg=C.cyan, fg=C.black, on=function()
      local n = maxCraft(id)
      if n > 0 then v.qty = n; toast("Max with current stock: " .. n, C.cyan) else toast("Not enough materials for even one", C.red) end
    end})
  end
  yy = ay + 4
  -- plan
  local tags, seen = {}, {}
  for _, s in ipairs(p.steps) do local t = MACH[s.m].tag; if not seen[t] then seen[t] = true; tags[#tags + 1] = t end end
  B.text(x + 1, yy, "PLAN", C.lightGray, C.blue)
  local sum = #p.steps .. " step" .. (#p.steps == 1 and "" or "s") .. "  " .. table.concat(tags, ", ") .. "  ~" .. math.ceil(p.eta) .. "s"
  B.text(x + 7, yy, trunc(sum, w - 9), C.white, C.blue)
  yy = yy + 1
  local startH = 3
  local listH = y + h - yy - startH - 2
  local rows = flattenPlan(p.root)
  local perPage = max(1, listH)
  local pages = max(1, math.ceil(#rows / perPage))
  v.planPage = clamp(v.planPage, 0, pages - 1)
  B.fill(x + 1, yy, w - 2, listH, C.black)
  for i = 1, perPage do
    local n = rows[v.planPage * perPage + i]
    if not n then break end
    local ry = yy + i - 1
    local ind = min(n.depth * 2, 16)
    local nx = x + 2 + ind
    local col, tag, tcol, icon, icol
    if n.miss > 0 then col, tag, tcol, icon, icol = C.red, "MISSING " .. n.miss, C.red, CH_DOT, C.red
    elseif n.craft then col, tag, tcol, icon, icol = C.white, "CRAFT " .. n.craft.crafts .. "x " .. MACH[n.craft.m].tag, MACH[n.craft.m].col, CH_R, C.yellow
    else
      local ps = {}
      for _, pk in ipairs(n.picks or {}) do ps[#ps + 1] = iSh(pk[1]) end
      col, tag, tcol, icon, icol = C.lightGray, "stock" .. (#ps > 0 and (" (" .. table.concat(ps, "+") .. ")") or ""), C.green, CH_DIA, C.green
    end
    B.put(nx, ry, icon, icol, C.black)
    B.text(nx + 2, ry, trunc(iName(n.sel), max(4, w - 34 - ind)), col, C.black)
    B.text(x + w - 29, ry, padL("x" .. fmt(n.q), 8), C.white, C.black)
    B.text(x + w - 20, ry, padR(tag, 18), tcol, C.black)
  end
  if pages > 1 then
    button("pp:up", x + w - 5, yy, 3, 2, CH_U, {disabled=v.planPage <= 0, on=function() v.planPage = v.planPage - 1 end})
    button("pp:dn", x + w - 5, yy + listH - 2, 3, 2, CH_D, {disabled=v.planPage >= pages - 1, on=function() v.planPage = v.planPage + 1 end})
  end
  -- start
  local sy = y + h - startH - 1
  if p.ok then
    local label = (#S.jobs > 0) and ("ADD TO QUEUE  (" .. #S.jobs .. " ahead)") or ("START CRAFT  " .. iName(id) .. " x" .. v.qty)
    local qty = v.qty
    button("craft:start", x + 1, sy, w - 2, startH, label, {bg=C.lime, fg=C.black, on=function()
      local first = #S.jobs == 0
      if queueCraft(id, qty) and first then go("jobs") end
    end})
  else
    local m0 = p.missing[1]
    button("craft:start", x + 1, sy, w - 2, startH,
      {"CAN'T START: missing " .. missingText(p), EXTERNAL[m0.id] or "Raw resource - needs a farm or more stock"},
      {disabled=true, dbg=C.black})
    B.fill(x + 1, sy, 1, startH, C.red)
  end
end
local function scrCraft(x, y, w, h, wide)
  local v = S.cv
  local lw = wide and 44 or w
  if wide or not v.detail then
    local list = recipeList()
    searchBar(x, y, lw, "craft")
    local fx = x
    local fbw = floor((lw - 2) / 3)
    for _, f in ipairs({"ALL", "READY", "MISSING"}) do
      button("cf:" .. f, fx, y + 3, fbw, 2, f, {bg=v.filter == f and C.yellow or C.gray, fg=v.filter == f and C.black or C.lightGray,
        on=function() v.filter = f; v.page = 0 end})
      fx = fx + fbw + 1
    end
    local ly = y + 6
    local rows = max(1, floor((h - 6 - 4 + 1) / 3))
    local pages = max(1, math.ceil(#list / rows))
    v.page = clamp(v.page, 0, pages - 1)
    for i = 1, rows do
      local id = list[v.page * rows + i]
      if not id then break end
      local r = RECIPES[id]
      local cy = ly + (i - 1) * 3
      local sel, k = v.sel == id, "rc:" .. id
      local pr = isPressed(k)
      local bg = pr and C.yellow or (sel and C.gray or C.blue)
      B.fill(x, cy, lw, 2, bg)
      local rd = S.ready[id]
      B.fill(x, cy, 1, 2, rd and C.lime or C.red)
      B.text(x + 2, cy, trunc(iName(id), lw - 14), pr and C.black or C.white, bg)
      B.text(x + 2, cy + 1, trunc("makes " .. r.out .. "  " .. (rd and "ready" or "missing items"), lw - 14), pr and C.black or (rd and C.lime or C.red), bg)
      local tg = MACH[r.m].tag
      B.text(x + lw - #tg - 3, cy, " " .. tg .. " ", C.black, MACH[r.m].col)
      region(k, x, cy, lw, 2, function() v.sel = id; v.detail = true; v.planPage = 0 end)
    end
    pager(x, y + h - 3, lw, v.page, pages, function(p) v.page = p end, "cp")
    if not wide then return end
  end
  local dx, dw = wide and (x + lw + 1) or x, wide and (w - lw - 1) or w
  craftDetail(dx, y, dw, h, wide)
end

local function histPanel(x, y, w, h)
  if h < 4 then return end
  panel(x, y, w, h, "History")
  for i = 1, min(#S.history, h - 2) do
    local r = S.history[i]
    local ry = y + 1 + i
    B.put(x + 1, ry, r.ok and CH_DIA or CH_DOT, r.ok and C.lime or C.red, C.blue)
    B.text(x + 3, ry, trunc(iName(r.item) .. " x" .. r.qty, w - 20), C.white, C.blue)
    B.text(x + w - 16, ry, padL(r.ok and ("%.1fs"):format(r.secs) or trunc(r.msg or "", 14), 15), r.ok and C.lightGray or C.red, C.blue)
  end
end
local function scrJobs(x, y, w, h, wide)
  local j = S.jobs[1]
  local lw = wide and floor(w * 0.62) or w
  local rx, rw = x + lw + 1, w - lw - 1
  local topH = wide and h or min(h, 22)
  if not j then
    panel(x, y, lw, 8, "Current craft", "idle")
    B.text(x + 2, y + 2, "Nothing is crafting right now.", C.white, C.blue)
    B.text(x + 2, y + 3, "Pick a recipe in CRAFT, or use a quick craft.", C.lightGray, C.blue)
    button("jobs:gocraft", x + 2, y + 5, 20, 2, "OPEN CRAFT " .. CH_R, {bg=C.yellow, fg=C.black, on=function() go("craft") end})
    histPanel(x, y + 9, lw, h - 9)
  else
    local failed = j.state == "FAILED"
    panel(x, y, lw, topH, "Current craft #" .. j.id, j.state, failed and C.red or ((j.state == "STOPPING") and C.orange or C.yellow))
    local yy = y + 2
    B.text(x + 2, yy, trunc(iName(j.item), lw - 20), C.white, C.blue)
    bigText(x + lw - 16, yy, "x" .. j.qty, C.yellow, C.blue)
    yy = yy + 1
    local el = (j.ended or S.t) - (j.started > 0 and j.started or S.t)
    B.text(x + 2, yy, ("elapsed %.1fs"):format(el) .. (failed and "" or ("   eta ~" .. math.ceil(jobEta(j)) .. "s")), C.lightGray, C.blue)
    yy = yy + 2
    bar(x + 2, yy, lw - 4, jobProgress(j), failed and C.red or C.yellow, C.gray)
    B.text(x + 2, yy + 1, round(jobProgress(j) * 100) .. "%", C.white, C.blue)
    yy = yy + 3
    if failed then
      local lines = wrapWords(j.err or "Failed", lw - 6)
      while #lines > 4 do table.remove(lines) end
      B.fill(x + 2, yy, lw - 4, #lines + 2, C.black); B.fill(x + 2, yy, 1, #lines + 2, C.red)
      B.text(x + 4, yy, "CRAFT FAILED", C.red, C.black)
      for i, l in ipairs(lines) do B.text(x + 4, yy + i, l, C.white, C.black) end
      yy = yy + #lines + 3
      local bw = floor((lw - 6) / 3)
      button("job:retry", x + 2, yy, bw, 3, "RETRY", {bg=C.yellow, fg=C.black, on=function()
        j.state = "QUEUED"; j.err = nil; j.ended = nil; log("PLAN", "Retrying " .. iName(j.item)) end})
      confirmButton("job:clear", x + 3 + bw, yy, bw, 3, "CLEAR CRAFTERS", "TAP TO CONFIRM", clearCrafters, {bg=C.orange, fg=C.black})
      button("job:dismiss", x + 4 + 2 * bw, yy, lw - 4 - 2 * (bw + 1), 3, "DISMISS", {on=function()
        pushHistory({item=j.item, qty=j.qty, ok=false, secs=(j.ended or S.t) - j.started, msg=j.err})
        table.remove(S.jobs, 1) end})
      yy = yy + 4
    end
    B.text(x + 2, yy, "STEPS", C.lightGray, C.blue); yy = yy + 1
    for i, s in ipairs(j.steps) do
      if yy >= y + topH - 5 then break end
      local done = s.done >= s.crafts
      local run = not done and s.state == "RUN"
      local icol = done and C.lime or (run and (failed and C.red or C.yellow) or C.gray)
      B.put(x + 2, yy, done and CH_DIA or (run and CH_R or CH_DOT), icol, C.blue)
      B.text(x + 4, yy, trunc(i .. ". " .. iName(s.item), lw - 40), done and C.lightGray or C.white, C.blue)
      B.text(x + lw - 34, yy, " " .. MACH[s.m].tag .. " ", C.black, MACH[s.m].col)
      bar(x + lw - 20, yy, 10, s.done / max(1, s.crafts), done and C.lime or C.yellow, C.gray)
      B.text(x + lw - 9, yy, padL(s.done .. "/" .. s.crafts, 8), C.lightGray, C.blue)
      yy = yy + 1
    end
    if not failed then
      local bw = floor((lw - 5) / 2)
      local by = y + topH - 4
      confirmButton("job:stop", x + 2, by, bw, 3, (j.state == "STOPPING") and "STOPPING..." or "STOP AFTER BATCH", "TAP AGAIN TO STOP",
        function() j.state = "STOPPING"; log("SYSTEM", "Stop requested") end)
      confirmButton("job:clear2", x + 3 + bw, by, lw - 4 - bw - 1, 3, "CLEAR CRAFTERS", "TAP TO CONFIRM", clearCrafters)
    end
    if not wide then return end
  end
  if not wide then return end
  -- workers
  local wh = min(16, floor(h / 2))
  panel(rx, y, rw, wh, "Workers")
  local yy = y + 2
  for _, t in ipairs(S.turtles) do
    local col = (t.state == "ERROR") and C.red or ((t.state == "IDLE") and C.green or C.cyan)
    B.text(rx + 1, yy, padR(t.name, 9), C.white, C.blue)
    B.text(rx + 11, yy, " " .. padR(t.state, 8) .. " ", C.black, col)
    if t.task then B.text(rx + 22, yy, trunc(iName(t.task.step.item) .. " x" .. t.task.b, rw - 23), C.lightGray, C.blue) end
    yy = yy + 1
  end
  B.text(rx + 1, yy, padR("crafter21", 9), C.white, C.blue)
  B.text(rx + 11, yy, " " .. padR(S.c21.state, 8) .. " ", C.black, S.c21.state == "IDLE" and C.green or C.purple); yy = yy + 1
  B.text(rx + 1, yy, padR("blasters", 9), C.white, C.blue)
  B.text(rx + 11, yy, " " .. padR(S.blast.task and "HEATING" or "IDLE", 8) .. " ", C.black, S.blast.task and C.orange or C.green)
  -- queue
  local qy, qh = y + wh + 1, min(10, h - wh - 1)
  panel(rx, qy, rw, qh, "Queue", max(0, #S.jobs - 1) .. " waiting")
  if #S.jobs <= 1 then B.text(rx + 1, qy + 2, "Queue is empty.", C.lightGray, C.blue) end
  for i = 2, min(#S.jobs, 1 + floor((qh - 2) / 2)) do
    local jj = S.jobs[i]
    local ry = qy + 2 + (i - 2) * 2
    B.text(rx + 1, ry, trunc((i - 1) .. ". " .. iName(jj.item) .. " x" .. jj.qty, rw - 8), C.white, C.blue)
    button("qx:" .. jj.id, rx + rw - 5, ry, 4, 2, "X", {fg=C.red, on=function()
      for k, q in ipairs(S.jobs) do if q == jj then table.remove(S.jobs, k) break end end
      toast("Removed from queue", C.orange) end})
  end
  if j then histPanel(rx, qy + qh + 1, rw, h - wh - qh - 2) end
end

local function drawTurtles(x, y, w, h, wide)
  local cols = wide and 3 or 2
  local cw = floor((w - 2) / cols)
  local chh = wide and 11 or 7
  panel(x, y, w, h, "Crafty Turtles", wide and "wired modem ch 43100 / reply 43200+id" or "ch 43100")
  for i, t in ipairs(S.turtles) do
    local cx = x + 1 + ((i - 1) % cols) * cw
    local cy = y + 2 + floor((i - 1) / cols) * (chh + 1)
    local ww = cw - 1
    if cy + chh <= y + h then
      B.fill(cx, cy, ww, chh, C.black)
      local col = (t.state == "ERROR") and C.red or ((t.state == "IDLE") and C.green or C.cyan)
      B.text(cx + 1, cy, trunc(t.name .. "  #" .. t.id, ww - 12), C.white, C.black)
      B.text(cx + ww - 11, cy, " " .. padR(t.state, 9) .. " ", C.black, col)
      local sw, step = wide and 4 or 3, wide and 2 or 1
      for s = 1, 16 do
        local sx = cx + 1 + ((s - 1) % 4) * (sw + 1)
        local sy = cy + 2 + floor((s - 1) / 4) * step
        local it = t.inv[s]
        if it then
          B.fill(sx, sy, sw, 1, iCol(it.id)); B.text(sx, sy, trunc(iSh(it.id), sw), C.black, nil)
          if wide then B.text(sx, sy + 1, trunc("x" .. it.n, sw), C.lightGray, C.black) end
        else
          B.fill(sx, sy, sw, 1, GRID_SLOTS[s] and C.gray or C.blue)
          if s == 16 then B.text(sx, sy, trunc("out", sw), C.lightGray, nil) end
        end
      end
      local ix = cx + 1 + 4 * (sw + 1) + 1
      local tw = cx + ww - ix - 1
      if tw > 3 then
        B.text(ix, cy + 2, trunc(t.task and iName(t.task.step.item) or "idle", tw), t.task and C.white or C.lightGray, C.black)
        if t.task then
          B.text(ix, cy + 3, trunc("batch x" .. t.task.b, tw), C.lightGray, C.black)
          local ph = {"LOADING", "CRAFTING", "STORING"}
          local pi = 0
          for k, p in ipairs(ph) do if p == t.task.phase then pi = k end end
          if wide then
            for k, p in ipairs(ph) do
              local mark = (k < pi) and "+ " or ((k == pi) and (CH_R .. " ") or "  ")
              B.text(ix, cy + 4 + k, trunc(mark .. p:lower(), tw), (k < pi) and C.green or ((k == pi) and C.yellow or C.gray), C.black)
            end
          else
            B.text(ix, cy + 4, trunc(CH_R .. " " .. t.task.phase:lower(), tw), C.yellow, C.black)
          end
        elseif t.state == "ERROR" then B.text(ix, cy + 3, trunc(t.err or "error", tw), C.red, C.black)
        else B.text(ix, cy + 3, trunc("made " .. fmt(t.made), tw), C.gray, C.black) end
      end
    end
  end
end
local function drawC21(x, y, w, h, wide)
  local c = S.c21
  panel(x, y, w, h, "Crafter 21 A", wide and "relay 503  out item_vault_148" or "relay 503")
  local cw2 = wide and 7 or 6
  local ox, oy = x + 2, y + 2
  local idx = 0
  for ry = 0, 4 do for rx = 0, 4 do
    if not ((ry == 0 or ry == 4) and (rx == 0 or rx == 4)) then
      idx = idx + 1
      local v = c.cells[idx]
      local px, py = ox + rx * (cw2 + 1), oy + ry * 2
      local bg = v and iCol(v) or C.gray
      if c.state == "CRAFTING" and floor(c.flash * 8 + idx) % 3 == 0 then bg = C.yellow end
      if c.state == "PULSE" then bg = C.red end
      B.fill(px, py, cw2, 1, bg)
      B.text(px, py, trunc(v and iSh(v) or tostring(193 + idx), cw2), (v or c.state ~= "IDLE") and C.black or C.lightGray, nil)
    end
  end end
  local ix = ox + 5 * (cw2 + 1) + 1
  if ix < x + w - 10 then
    B.text(ix, oy, "STATE", C.lightGray, C.blue)
    B.text(ix, oy + 1, " " .. padR(c.state, 9) .. " ", C.black, c.state == "IDLE" and C.green or C.purple)
    B.text(ix, oy + 3, "RELAY", C.lightGray, C.blue)
    B.text(ix, oy + 4, c.relay and " ON  " or " off ", c.relay and C.white or C.lightGray, c.relay and C.red or C.gray)
    B.text(ix, oy + 6, "IDS", C.lightGray, C.blue)
    B.text(ix, oy + 7, "194-214", C.white, C.blue)
  end
  local ny = oy + 11
  if ny + 3 < y + h then
    B.text(x + 1, ny, trunc("Loads 1 item per crafter, then pulses the relay.", w - 2), C.lightGray, C.blue)
    B.text(x + 1, ny + 1, trunc("Output lands in item_vault_148, then moves to MAIN.", w - 2), C.lightGray, C.blue)
  end
end
local function drawBlasters(x, y, w, h)
  panel(x, y, w, h, "Blasters A", "11 basins, lava fans")
  local cols = max(1, floor((w - 1) / 8))
  for i, b in ipairs(S.basins) do
    local px = x + 1 + ((i - 1) % cols) * 8
    local py = y + 2 + floor((i - 1) / cols) * 5
    if py + 4 <= y + h then
      local heat = b.item and b.heat or 0
      local flames = {CH_U, "^", CH_U}
      local fl = b.item and flames[floor(rt() * 8 + i) % 3 + 1] or " "
      B.fill(px, py, 7, 4, C.black)
      B.text(px, py, trunc((b.name:gsub("basin_", "B")), 7), C.white, C.black)
      B.text(px, py + 1, b.item and trunc(iSh(b.item) .. " " .. b.count, 7) or "empty", b.item and C.white or C.gray, C.black)
      local hc = (heat > 0.66 and C.yellow) or (heat > 0.33 and C.orange) or (b.item and C.red) or C.gray
      B.fill(px, py + 3, 7, 1, hc, fl, C.black)
    end
  end
end
local function scrMach(x, y, w, h, wide)
  if wide then
    local th = 2 * 12 + 1
    drawTurtles(x, y, w, th, true)
    local yy = y + th + 1
    local rest = y + h - yy
    local lw = floor(w * 0.52)
    drawC21(x, yy, lw, rest, true)
    drawBlasters(x + lw + 1, yy, w - lw - 1, rest)
    return
  end
  local subs = {{"t", "TURTLES"}, {"c", "CRAFTER 21"}, {"b", "BLASTERS"}}
  local sub = S.mv.sub
  local bw = floor((w - 2) / 3)
  for i, s in ipairs(subs) do
    local k = s[1]
    button("ms:" .. k, x + (i - 1) * (bw + 1), y, (i == 3) and (w - 2 * (bw + 1)) or bw, 2, s[2],
      {bg=sub == k and C.yellow or C.gray, fg=sub == k and C.black or C.lightGray, on=function() S.mv.sub = k end})
  end
  local yy, hh = y + 3, h - 3
  if sub == "t" then drawTurtles(x, yy, w, hh, false) elseif sub == "c" then drawC21(x, yy, w, hh, false) else drawBlasters(x, yy, w, hh) end
end

local function startDefrag()
  if #S.jobs > 0 then toast("Defrag is locked while crafting", C.red) return end
  S.defrag = {active=true, t=0, acc=0, log={"SCAN MAIN: 4 storages"}, moved=0, freed=0}
  log("DEFRAG", "Defrag started")
end
local function scrStore(x, y, w, h, wide)
  local lw = wide and floor(w * 0.62) or w
  panel(x, y, lw, wide and h or min(h, #S.storages * 3 + 3), "Storages", #S.storages .. " connected")
  local yy = y + 2
  for _, s in ipairs(S.storages) do
    if yy + 2 > y + h - (wide and 0 or 4) then break end
    local f = used(s) / s.cap
    B.text(x + 1, yy, " " .. s.role .. " ", C.black, s.role == "MAIN" and C.yellow or C.lightBlue)
    B.text(x + 8, yy, trunc(s.name, 18), s.online and C.white or C.red, C.blue)
    if s.mult > 1 then B.text(x + 27, yy, " x" .. s.mult .. " ", C.black, C.purple) end
    if s.note then B.text(x + 27, yy, " " .. s.note .. " ", C.black, C.gray) end
    if s.online then
      bar(x + 8, yy + 1, lw - 32, f, (f > 0.85 and C.red) or (f > 0.6 and C.orange) or (s.role == "MAIN" and C.yellow or C.lightBlue))
      B.text(x + lw - 23, yy + 1, padL(round(f * 100) .. "%", 4), C.white, C.blue)
      B.text(x + lw - 18, yy + 1, padL(kfmt(used(s)), 7), C.lightGray, C.blue)
      B.text(x + lw - 10, yy + 1, padL(slotsUsed(s) .. "/" .. s.slots, 9), C.gray, C.blue)
    else
      B.fill(x + 8, yy + 1, lw - 32, 1, C.blue, CH_CHK, C.red)
      B.text(x + lw - 23, yy + 1, " OFFLINE  modem missing ", C.white, C.red)
    end
    yy = yy + 3
  end
  local function toggleAuto() S.auto.on = not S.auto.on; toast("AUTO balance " .. (S.auto.on and "on" or "off"), C.lime) end
  if not wide then
    local by, bw = y + h - 3, floor((w - 1) / 2)
    button("st:auto", x, by, bw, 3, "AUTO " .. (S.auto.on and "ON" or "OFF"), {bg=S.auto.on and C.lime or C.gray, fg=S.auto.on and C.black or C.white, on=toggleAuto})
    button("st:defrag", x + bw + 1, by, w - bw - 1, 3, S.defrag.active and "DEFRAGGING..." or "DEFRAG MAIN",
      {bg=C.magenta, fg=C.black, disabled=S.defrag.active, on=startDefrag})
    return
  end
  local rx, rw = x + lw + 1, w - lw - 1
  panel(rx, y, rw, 14, "Auto balance", S.auto.on and "on" or "off", S.auto.on and C.lime or C.lightGray)
  local lines = {"Moves REST storage into MAIN", "after 20 s with no touches.", "Runs in the background and", "never changes your screen."}
  for i, l in ipairs(lines) do B.text(rx + 1, y + 1 + i, trunc(l, rw - 2), C.lightGray, C.blue) end
  local idleFor = max(0, S.t - S.lastTouch)
  local st, sc
  if #S.jobs > 0 then st, sc = "Paused while crafting", C.orange
  elseif idleFor > 20 then st, sc = "Active now", C.lime
  else st, sc = "Starts in " .. math.ceil(20 - idleFor) .. "s", C.white end
  B.text(rx + 1, y + 7, trunc(st, rw - 2), sc, C.blue)
  button("st:auto", rx + 1, y + 10, rw - 2, 3, S.auto.on and "TURN AUTO OFF" or "TURN AUTO ON",
    {bg=S.auto.on and C.gray or C.lime, fg=S.auto.on and C.white or C.black, on=toggleAuto})
  local dy, dh = y + 15, h - 15
  local d = S.defrag
  panel(rx, dy, rw, dh, "Defrag", d.active and "running" or "MAIN only", d.active and C.magenta or C.lightGray)
  local lh = dh - 7
  B.fill(rx + 1, dy + 2, rw - 2, lh, C.black)
  if #d.log == 0 then B.text(rx + 2, dy + 2, trunc("Merges partial stacks to free slots.", rw - 4), C.gray, C.black) end
  local first = max(1, #d.log - lh + 1)
  for i = first, #d.log do
    local l = d.log[i]
    B.text(rx + 2, dy + 2 + (i - first), trunc(l, rw - 4), (l:sub(1, 4) == "DONE") and C.lime or C.magenta, C.black)
  end
  B.text(rx + 1, dy + dh - 5, trunc("moved " .. fmt(d.moved) .. "  freed " .. d.freed .. " slots", rw - 2), C.lightGray, C.blue)
  confirmButton("st:defrag", rx + 1, dy + dh - 4, rw - 2, 3, d.active and "DEFRAGGING..." or "START DEFRAG", "TAP TO CONFIRM", startDefrag,
    {bg=C.magenta, fg=C.black, disabled=d.active})
end

local function scrFarms(x, y, w, h, wide)
  local res = {}
  for _, id in ipairs(ITEM_ORDER) do if ITEMS[id].target > 0 then res[#res + 1] = ITEMS[id] end end
  table.sort(res, function(a, b)
    local fa, fb = have(a.id) / a.target, have(b.id) / b.target
    if fa ~= fb then return fa < fb end
    return a.name < b.name
  end)
  local lw = wide and floor(w * 0.6) or w
  panel(x, y, lw, h, "Farm resources", "stock vs target")
  local bw = wide and max(6, lw - 60) or max(6, lw - 35)
  local hdr = padR("RESOURCE", 18) .. padR("LEVEL", bw) .. (wide and (padL("STOCK", 9) .. padL("TARGET", 8) .. " STATUS   USED BY") or (padL("STOCK", 7) .. " STATUS"))
  B.text(x + 1, y + 1, trunc(hdr, lw - 2), C.lightGray, C.blue)
  local rows = max(1, h - 6)
  local pages = max(1, math.ceil(#res / rows))
  S.fv.page = clamp(S.fv.page, 0, pages - 1)
  for i = 1, rows do
    local it = res[S.fv.page * rows + i]
    if not it then break end
    local ry = y + 1 + i
    local n = have(it.id)
    local f = n / it.target
    local st, sc
    if f < 0.2 then st, sc = "CRIT", C.red elseif f < 0.5 then st, sc = "LOW", C.orange elseif f < 1 then st, sc = "OK", C.yellow else st, sc = "FULL", C.lime end
    B.fill(x + 1, ry, 1, 1, it.col)
    B.text(x + 3, ry, trunc(it.name, 15), C.white, C.blue)
    bar(x + 19, ry, bw - 1, min(1, f), sc, C.gray, true)
    if wide then
      B.text(x + 19 + bw, ry, padL(fmt(n), 9), C.white, C.blue)
      B.text(x + 28 + bw, ry, padL(fmt(it.target), 8), C.lightGray, C.blue)
      B.text(x + 37 + bw, ry, " " .. padR(st, 4) .. " ", C.black, sc)
      B.text(x + 45 + bw, ry, padL(it.usedBy > 0 and (it.usedBy .. " rec") or "", 9), C.lightGray, C.blue)
    else
      B.text(x + 19 + bw, ry, padL(kfmt(n), 7), C.white, C.blue)
      B.text(x + 27 + bw, ry, " " .. padR(st, 4) .. " ", C.black, sc)
    end
  end
  pager(x + 1, y + h - 4, lw - 2, S.fv.page, pages, function(p) S.fv.page = p end, "fp")
  if not wide then return end
  local rx, rw = x + lw + 1, w - lw - 1
  panel(rx, y, rw, h, "Production chains", "items that need a 2nd machine")
  local yy = y + 2
  for _, ch in ipairs(CHAINS) do
    if yy + 3 > y + h then break end
    local out, inp, mach, ok, n = unpack(ch)
    B.text(rx + 1, yy, trunc(out, rw - 14), C.white, C.blue)
    B.text(rx + rw - 12, yy, ok and " CONNECTED " or " NOT BUILT ", C.black, ok and C.lime or C.red)
    B.text(rx + 1, yy + 1, trunc(inp .. " " .. CH_R .. " " .. mach, rw - 2), C.lightGray, C.blue)
    B.text(rx + 1, yy + 2, trunc("unlocks ~" .. n .. " recipes", rw - 2), C.gray, C.blue)
    yy = yy + 4
  end
end

local SCREENS = {home=scrHome, items=scrItems, craft=scrCraft, jobs=scrJobs, mach=scrMach, store=scrStore, farms=scrFarms}

local function brainFrame()
  UI.regions = {}
  B.clear(C.black)
  local wide = W >= 110
  drawHeader(wide)
  local cx, cy, cw, ch
  if wide then drawSidebar(0, 1, 16, H - 2); cx, cy, cw, ch = 18, 2, W - 19, H - 4
  else drawTabs(1); cx, cy, cw, ch = 1, 4, W - 2, H - 5 end
  local ok, err = pcall(SCREENS[S.tab], cx, cy, cw, ch, wide)
  if not ok then B.text(cx, cy, trunc("Screen error: " .. tostring(err), cw), C.red, C.black) end
  drawStatus()
  if S.kb.open then drawKeyboard() end
  drawToasts()
end

---------------------------------------------------------------------
-- STORAGE screen (7 wide x 3 tall = 143x38)
---------------------------------------------------------------------
local function storageFrame()
  UI.regions = {}
  B.clear(C.black)
  local cap, u = 0, 0
  for _, s in ipairs(mainStorages()) do cap = cap + s.cap; u = u + used(s) end
  B.fill(0, 0, W, 1, C.gray)
  B.text(0, 0, " VAULT STORAGE ", C.black, C.yellow)
  B.text(16, 0, kfmt(totalItems()) .. " items   " .. S.totN .. " types   MAIN " .. round(u / max(1, cap) * 100) .. "% full", C.white, C.gray)
  local inN, outN = 0, 0
  for _, s in ipairs(S.input) do inN = inN + s.n end
  for _, v in pairs(S.output) do outN = outN + v end
  local right = ("input %s   output %s   Day %d %s "):format(kfmt(inN), kfmt(outN), S.day, clockStr())
  B.text(W - #right, 0, right, C.lightGray, C.gray)
  -- one tile per storage: name, fill %, bar
  local n = #S.storages
  local cw = floor((W - 1) / n)
  for i, s in ipairs(S.storages) do
    local x = 1 + (i - 1) * cw
    local f = used(s) / s.cap
    B.fill(x, 1, cw - 1, 2, C.blue)
    B.text(x + 1, 1, trunc(s.name, cw - 7), s.online and (s.role == "MAIN" and C.white or C.lightBlue) or C.red, C.blue)
    if s.online then
      local pct = round(f * 100) .. "%"
      B.text(x + cw - 2 - #pct, 1, pct, C.lightGray, C.blue)
      bar(x + 1, 2, cw - 3, f, (f > 0.85 and C.red) or (f > 0.6 and C.orange) or (s.role == "MAIN" and C.yellow or C.lightBlue), C.gray, true)
    else
      B.text(x + 1, 2, trunc(" OFFLINE ", cw - 3), C.white, C.red)
    end
  end
  scrItems(1, 4, W - 2, H - 5, W >= 110)
  drawStatus({INPUT=true, OUTPUT=true, AUTO=true, SYSTEM=true, ERROR=true})
  if S.kb.open then drawKeyboard() end
  drawToasts()
end

---------------------------------------------------------------------
-- FACTORY GAUGE BOARD (7 wide x 6 tall = 143x81)
-- Each panel is one production line. Inputs sit on the top row,
-- products below them; grey pipes show which items feed which.
---------------------------------------------------------------------
local F = {}
F.PANELS = {
  {title="Wood", outputs={"minecraft:oak_planks","minecraft:oak_slab","minecraft:stick","minecraft:crafting_table",
                          "minecraft:chest","minecraft:barrel","minecraft:torch"}},
  {title="Andesite", outputs={"minecraft:iron_nugget","create:andesite_alloy","create:shaft","create:cogwheel",
                              "create:large_cogwheel","create:basin","create:hand_crank","create:depot","create:mechanical_drill"}},
  {title="Iron", outputs={"minecraft:iron_block","minecraft:iron_bars","minecraft:hopper","create:propeller",
                          "create:encased_fan","create:mechanical_press","create:item_vault","create:whisk"}},
  {title="Blasters A", outputs={"minecraft:stone","minecraft:smooth_stone","minecraft:glass","minecraft:glass_pane","minecraft:brick"}},
  {title="Redstone", outputs={"minecraft:redstone_torch","minecraft:piston"}},
  {title="Crafter 21 A", outputs={"create:crushing_wheel"}},
  {title="Missing machines", external=true,
   outputs={"create:iron_sheet","create:copper_sheet","create:andesite_casing","create:brass_casing"}},
}
F.EXT = {
  ["create:iron_sheet"]={"minecraft:iron_ingot"}, ["create:copper_sheet"]={"minecraft:copper_ingot"},
  ["create:andesite_casing"]={"create:andesite_alloy","minecraft:oak_log"},
  ["create:brass_casing"]={"create:brass_ingot","minecraft:oak_log"},
}
F.TARGETS = {
  ["minecraft:oak_planks"]=512, ["minecraft:oak_slab"]=64, ["minecraft:stick"]=256, ["minecraft:crafting_table"]=8,
  ["minecraft:chest"]=32, ["minecraft:barrel"]=16, ["minecraft:torch"]=128, ["minecraft:iron_nugget"]=256,
  ["create:andesite_alloy"]=512, ["create:shaft"]=128, ["create:cogwheel"]=64, ["create:large_cogwheel"]=32,
  ["create:basin"]=8, ["create:hand_crank"]=4, ["create:depot"]=8, ["create:mechanical_drill"]=4,
  ["minecraft:iron_block"]=32, ["minecraft:iron_bars"]=64, ["minecraft:hopper"]=8, ["create:propeller"]=8,
  ["create:encased_fan"]=16, ["create:mechanical_press"]=4, ["create:item_vault"]=16, ["create:whisk"]=4,
  ["minecraft:stone"]=2000, ["minecraft:smooth_stone"]=512, ["minecraft:glass"]=1000, ["minecraft:glass_pane"]=128,
  ["minecraft:brick"]=256, ["minecraft:redstone_torch"]=32, ["minecraft:piston"]=16, ["create:crushing_wheel"]=4,
}
F.GW, F.GH, F.GX, F.LH = 6, 3, 7, 5
F.DARK = {[C.white]=true,[C.orange]=true,[C.magenta]=true,[C.lightBlue]=true,[C.yellow]=true,[C.lime]=true,
          [C.pink]=true,[C.lightGray]=true,[C.cyan]=true,[C.blue]=true,[C.brown]=true}
F.layout = nil
function F.ing(id)
  local tg = TAGS[id]
  if not tg then return id end
  for _, m in ipairs(tg.members) do if RECIPES[m] then return m end end
  return tg.members[1]
end
function F.inputs(id, external)
  if external then return F.EXT[id] or {} end
  local r = RECIPES[id]
  if not r then return {} end
  local out, seen = {}, {}
  for _, ing in ipairs(ingredients(r)) do
    local m = F.ing(ing[1])
    if not seen[m] then seen[m] = true; out[#out + 1] = m end
  end
  return out
end
function F.target(id) return S.ftarget[id] or F.TARGETS[id] or (ITEMS[id] and ITEMS[id].target) or 0 end
function F.statusCol(f)
  if f >= 1 then return C.lime elseif f >= 0.5 then return C.yellow elseif f >= 0.2 then return C.orange end
  return C.red
end
function F.build(width)
  local panels, px, py, rowH = {}, 1, 2, 0
  for _, pd in ipairs(F.PANELS) do
    local isOut, nodes, order = {}, {}, {}
    for _, id in ipairs(pd.outputs) do isOut[id] = true end
    local function add(id)
      if not nodes[id] then nodes[id] = {id=id, isOut=isOut[id] == true, external=pd.external}; order[#order + 1] = id end
    end
    for _, id in ipairs(pd.outputs) do for _, ing in ipairs(F.inputs(id, pd.external)) do add(ing) end end
    for _, id in ipairs(pd.outputs) do add(id) end
    local function layerOf(id, depth)
      local nd = nodes[id]
      if nd.layer then return nd.layer end
      if not nd.isOut or depth > 12 then nd.layer = 0 return 0 end
      local L = 0
      for _, ing in ipairs(F.inputs(id, pd.external)) do
        if nodes[ing] and ing ~= id then L = max(L, layerOf(ing, depth + 1) + 1) end
      end
      nd.layer = max(1, L)
      return nd.layer
    end
    local layers, maxL = {}, 0
    for _, id in ipairs(order) do
      local L = layerOf(id, 0)
      layers[L] = layers[L] or {}
      layers[L][#layers[L] + 1] = nodes[id]
      if L > maxL then maxL = L end
    end
    for L = 0, maxL do layers[L] = layers[L] or {} end
    local edges = {}
    for _, id in ipairs(order) do
      if nodes[id].isOut then
        for _, ing in ipairs(F.inputs(id, pd.external)) do
          if nodes[ing] and ing ~= id then edges[#edges + 1] = {from=nodes[ing], to=nodes[id]} end
        end
      end
    end
    -- order each row by the average position of connected items (fewer crossing pipes)
    local function setIdx(L) for i, nd in ipairs(layers[L]) do nd.idx = i / (#layers[L] + 1) end end
    for L = 0, maxL do setIdx(L) end
    local function bary(nd, up)
      local s, c = 0, 0
      for _, e in ipairs(edges) do
        if up and e.to == nd then s = s + e.from.idx; c = c + 1
        elseif not up and e.from == nd then s = s + e.to.idx; c = c + 1 end
      end
      return c > 0 and s / c or nd.idx
    end
    local function sortLayer(L, up)
      local ly = layers[L]
      for _, nd in ipairs(ly) do nd.b = bary(nd, up) end
      table.sort(ly, function(a, b) if a.b ~= b.b then return a.b < b.b end return a.id < b.id end)
      setIdx(L)
    end
    for _ = 1, 2 do
      for L = 1, maxL do sortLayer(L, true) end
      sortLayer(0, false)
    end
    local maxCount = 1
    for L = 0, maxL do if #layers[L] > maxCount then maxCount = #layers[L] end end
    local w = max(#pd.title + 8, maxCount * F.GX + 3)
    local h = (maxL + 1) * F.LH + 1
    if px > 1 and px + w > width - 1 then px = 1; py = py + rowH + 1; rowH = 0 end
    local p = {title=pd.title, external=pd.external, x=px, y=py, w=w, h=h, order=order, nodes=nodes, edges=edges, layers=layers, maxL=maxL}
    for L = 0, maxL do
      local ly = layers[L]
      local off = floor((maxCount - #ly) * F.GX / 2)
      for i, nd in ipairs(ly) do nd.gx = px + 2 + off + (i - 1) * F.GX; nd.gy = py + 2 + L * F.LH end
    end
    panels[#panels + 1] = p
    px = px + w + 1
    if h > rowH then rowH = h end
  end
  -- every product shown on the board, in board order (used by auto-stock and the summary)
  local products, seen, consumers = {}, {}, {}
  for _, p in ipairs(panels) do
    for _, id in ipairs(p.order) do
      if p.nodes[id].isOut and not p.external and not seen[id] then seen[id] = true; products[#products + 1] = id end
    end
    for _, e in ipairs(p.edges) do
      consumers[e.from.id] = consumers[e.from.id] or {}
      local list = consumers[e.from.id]
      if not contains(list, e.to.id) then list[#list + 1] = e.to.id end
    end
  end
  return {panels=panels, bottom=py + rowH, width=width, products=products, consumers=consumers}
end
function F.activeItem()
  local j = S.jobs[1]
  if not j or j.state ~= "RUNNING" then return nil end
  for _, s in ipairs(j.steps) do if s.done < s.crafts then return s.item end end
  return nil
end
-- wooden plate with a gold border, like the panels on a Create factory board
function F.plate(x, y, w, h, title, meta)
  B.fill(x, y, w, h, C.yellow)
  for yy = y + 1, y + h - 2 do B.fill(x + 1, yy, w - 2, 1, ((yy - y) % 3 == 0) and C.brown or C.blue) end
  if title then B.text(x + 2, y, " " .. title:upper() .. " ", C.white, C.black) end
  if meta then
    local m = " " .. trunc(meta, max(1, w - #title - 10)) .. " "
    B.text(x + w - 2 - #m, y, m, C.black, C.yellow)
  end
end
function F.drawGauge(nd, active)
  local x, y, id = nd.gx, nd.gy, nd.id
  local GW = F.GW
  local blink = floor(rt() * 4) % 2 == 0
  local frame = C.yellow
  if nd.external and nd.isOut then frame = C.red end
  if active == id then frame = blink and C.orange or C.white end
  if S.fsel == id then frame = C.white end
  local sh = iSh(id)
  B.fill(x, y, GW, 1, frame)
  B.text(x + floor((GW - #sh) / 2), y, sh, (frame == C.red) and C.white or C.black, frame)
  local col = iCol(id)
  B.fill(x, y + 1, GW, 1, col)
  local n = have(id)
  local cs = (n < 10000) and fmt(n) or kfmt(n)
  B.text(x + floor((GW - #cs) / 2), y + 1, trunc(cs, GW), F.DARK[col] and C.black or C.white, col)
  local tg = F.target(id)
  if tg > 0 then bar(x, y + 2, GW, n / tg, F.statusCol(n / tg), C.black)
  else B.fill(x, y + 2, GW, 1, C.gray) end
  if nd.isOut and not nd.external and S.keep[id] ~= false then B.put(x + GW - 1, y + 2, "\7", C.white, nil) end
  region("g:" .. id .. ":" .. x .. ":" .. y, x, y, GW, F.GH, function() S.fsel = id end)
end
function F.drawPanel(p, active)
  local stocked, total = 0, 0
  for _, id in ipairs(p.order) do
    if p.nodes[id].isOut then
      total = total + 1
      local tg = F.target(id)
      if tg > 0 and have(id) >= tg then stocked = stocked + 1 end
    end
  end
  F.plate(p.x, p.y, p.w, p.h, p.title, p.external and "no machine" or (stocked .. "/" .. total))
  -- pipes: each cell remembers which directions it connects (up/down/left/right)
  local cells = {}
  local function mark(x, y, u, d, l, r, pri)
    local k = y * 1000 + x
    local c = cells[k]
    if not c then c = {x=x, y=y, pri=0}; cells[k] = c end
    c.u = c.u or u; c.d = c.d or d; c.l = c.l or l; c.r = c.r or r
    if pri > c.pri then c.pri = pri end
  end
  local function seg(x0, y0, x1, y1, pri)
    if x0 == x1 then
      local a, b = min(y0, y1), max(y0, y1)
      for y = a, b do mark(x0, y, y > a, y < b, false, false, pri) end
    else
      local a, b = min(x0, x1), max(x0, x1)
      for x = a, b do mark(x, y0, false, false, x > a, x < b, pri) end
    end
  end
  for _, e in ipairs(p.edges) do
    local pri = (p.external and 2) or ((e.to.id == active) and 3) or 1
    local sx, sy = e.from.gx + 2, e.from.gy + F.GH
    local tx, by = e.to.gx + 2, e.to.gy - 1
    if by >= sy then
      seg(sx, sy, sx, by, pri); seg(sx, by, tx, by, pri)
      mark(sx, sy, true, false, false, false, pri)
      mark(tx, by, false, true, false, false, pri)
    end
  end
  local phase = floor(rt() * 6)
  for _, c in pairs(cells) do
    local ch = tele(c.u, false, c.u or c.d or c.l or c.r, c.r, c.d, false)
    local col = C.gray
    if c.pri == 2 then col = C.red
    elseif c.pri == 3 then col = ((c.x + c.y + phase) % 3 == 0) and C.white or C.orange end
    B.put(c.x, c.y, ch, col, nil)
  end
  for _, id in ipairs(p.order) do F.drawGauge(p.nodes[id], active) end
end
function F.summary()
  local total, stocked, low, missing = 0, 0, 0, 0
  local seen = {}
  for _, p in ipairs(F.layout.panels) do
    for _, id in ipairs(p.order) do
      local nd = p.nodes[id]
      if not seen[id] then
        seen[id] = true; total = total + 1
        if nd.external and nd.isOut then missing = missing + 1
        else
          local tg = F.target(id)
          if tg > 0 then if have(id) >= tg then stocked = stocked + 1 else low = low + 1 end end
        end
      end
    end
  end
  return total, stocked, low, missing
end
function F.detail(x, y, w, h)
  local id = S.fsel
  F.plate(x, y, w, h, "Gauge", iName(id))
  local tg = F.target(id)
  local n = have(id)
  local yy = y + 2
  B.text(x + 2, yy, trunc(iName(id), w - 4), C.black, nil)
  B.text(x + 2, yy + 1, trunc(id, w - 4), C.gray, nil)
  yy = yy + 3
  local cw = bigText(x + 2, yy, fmt(n), C.black, C.blue)
  B.text(x + 4 + cw, yy + 1, tg > 0 and ("/ " .. fmt(tg) .. " target") or "no target set", C.gray, nil)
  yy = yy + 3
  local f = tg > 0 and n / tg or 0
  if tg > 0 then bar(x + 2, yy, w - 4, f, F.statusCol(f), C.black) end
  yy = yy + 2
  local r = RECIPES[id]
  local status, scol
  if EXTERNAL[id] then status, scol = "NO MACHINE: " .. EXTERNAL[id], C.red
  elseif not r then status, scol = "RAW: comes from a farm or the world", C.gray
  elseif tg <= 0 then status, scol = "No target - not kept in stock", C.gray
  elseif n >= tg then status, scol = "STOCKED", C.green
  else status, scol = "BELOW TARGET: needs " .. fmt(tg - n), C.red end
  B.text(x + 2, yy, trunc(status, w - 4), scol, nil); yy = yy + 2
  if r then
    local parts = {}
    for _, ing in ipairs(ingredients(r)) do parts[#parts + 1] = ing[2] .. "x " .. iName(ing[1]) end
    B.text(x + 2, yy, "MADE BY", C.gray, nil); B.text(x + 11, yy, trunc(MACH[r.m].name .. ", makes " .. r.out, w - 13), C.black, nil); yy = yy + 1
    B.text(x + 2, yy, "FROM", C.gray, nil); B.text(x + 11, yy, trunc(table.concat(parts, ", "), w - 13), C.black, nil); yy = yy + 1
  end
  local cons = F.layout.consumers[id] or {}
  if #cons > 0 then
    local names = {}
    for _, c in ipairs(cons) do names[#names + 1] = iName(c) end
    B.text(x + 2, yy, "FEEDS", C.gray, nil); B.text(x + 11, yy, trunc(table.concat(names, ", "), w - 13), C.black, nil)
  end
  -- buttons
  local by = y + h - 4
  local bw = floor((w - 4 - 4) / 5)
  local step = (tg >= 1000 and 500) or (tg >= 200 and 64) or (tg >= 32 and 16) or 4
  local canMake = r ~= nil
  button("f:make16", x + 2, by, bw, 3, "MAKE +16", {bg=C.black, disabled=not canMake, dbg=C.brown, on=function() queueCraft(id, 16, true) end})
  button("f:make64", x + 3 + bw, by, bw, 3, "MAKE +64", {bg=C.black, disabled=not canMake, dbg=C.brown, on=function() queueCraft(id, 64, true) end})
  button("f:tminus", x + 4 + 2 * bw, by, bw, 3, "TARGET -", {bg=C.gray, on=function() S.ftarget[id] = max(0, tg - step) end})
  button("f:tplus", x + 5 + 3 * bw, by, bw, 3, "TARGET +", {bg=C.gray, on=function() S.ftarget[id] = tg + step end})
  local keep = S.keep[id] ~= false
  button("f:keep", x + 6 + 4 * bw, by, w - 8 - 4 * bw, 3, keep and "KEEP: ON" or "KEEP: OFF",
    {bg=keep and C.green or C.gray, disabled=not canMake, dbg=C.brown, on=function() S.keep[id] = not keep end})
end
function F.production(x, y, w, h)
  F.plate(x, y, w, h, "Production", S.autoStock and "auto-stock on" or "auto-stock off")
  local yy = y + 2
  local j = S.jobs[1]
  if j then
    B.text(x + 2, yy, trunc(iName(j.item) .. " x" .. j.qty .. (j.stock and "  (stock)" or "  (output)"), w - 4), C.black, nil)
    yy = yy + 1
    bar(x + 2, yy, w - 4, jobProgress(j), j.state == "FAILED" and C.red or C.green, C.black); yy = yy + 1
    local st, si
    for i, s in ipairs(j.steps) do if s.done < s.crafts then st, si = s, i break end end
    local line = (j.state == "FAILED") and ("FAILED: " .. (j.err or "")) or (st and ("Step " .. si .. "/" .. #j.steps .. ": " .. iName(st.item) .. " on " .. MACH[st.m].name) or "Finishing")
    B.text(x + 2, yy, trunc(line, w - 4), j.state == "FAILED" and C.red or C.gray, nil)
  else
    B.text(x + 2, yy, "Idle - every kept gauge is stocked or waiting.", C.gray, nil)
  end
  yy = yy + 2
  B.text(x + 2, yy, "TURTLES", C.gray, nil); yy = yy + 1
  for i, t in ipairs(S.turtles) do
    local col = (t.state == "ERROR") and C.red or ((t.state == "IDLE") and C.green or C.cyan)
    B.text(x + 2 + (i - 1) * 7, yy, " T" .. (i - 1) .. "   ", F.DARK[col] and C.black or C.white, col)
    B.text(x + 2 + (i - 1) * 7, yy + 1, padR(t.state == "IDLE" and "idle" or t.state:lower(), 6), C.black, nil)
  end
  yy = yy + 3
  local c = S.c21
  B.text(x + 2, yy, "CRAFTER 21", C.gray, nil)
  B.text(x + 14, yy, " " .. padR(c.state, 9) .. " ", C.white, c.state == "IDLE" and C.green or C.magenta)
  yy = yy + 1
  B.text(x + 2, yy, "BLASTERS", C.gray, nil)
  for i, b in ipairs(S.basins) do
    local hot = b.item and ((b.heat > 0.6 and C.yellow) or (b.heat > 0.2 and C.orange) or C.red) or C.black
    B.put(x + 14 + (i - 1) * 2, yy, " ", nil, hot)
  end
  yy = yy + 2
  B.text(x + 2, yy, "QUEUE", C.gray, nil); yy = yy + 1
  if #S.jobs <= 1 then B.text(x + 2, yy, "empty", C.gray, nil) end
  for i = 2, min(#S.jobs, 5) do
    B.text(x + 2, yy, trunc((i - 1) .. ". " .. iName(S.jobs[i].item) .. " x" .. S.jobs[i].qty, w - 4), C.black, nil); yy = yy + 1
  end
  button("f:auto", x + 2, y + h - 4, w - 4, 3, S.autoStock and "AUTO-STOCK: ON" or "AUTO-STOCK: OFF",
    {bg=S.autoStock and C.green or C.gray, on=function() S.autoStock = not S.autoStock; toast("Auto-stock " .. (S.autoStock and "on" or "off"), C.lime) end})
end
function F.legend(x, y, w, h)
  F.plate(x, y, w, h, "How to read")
  local sample = {id="create:shaft", gx=x + 3, gy=y + 2, isOut=true}
  local saveSel = S.fsel; S.fsel = nil
  F.drawGauge(sample, nil)
  UI.regions[#UI.regions] = nil
  S.fsel = saveSel
  B.text(x + 11, y + 2, "item", C.black, nil)
  B.text(x + 11, y + 3, "amount stored", C.black, nil)
  B.text(x + 11, y + 4, "stock vs target", C.black, nil)
  local rows = {
    {C.lime, "at or above target"}, {C.yellow, "below target"}, {C.orange, "low"}, {C.red, "critical"},
    {C.white, "white frame: selected"}, {C.red, "red frame: no machine yet"},
    {C.orange, "orange pipe: crafting now"}, {C.gray, "grey pipe: recipe link"},
  }
  local yy = y + 7
  for _, r in ipairs(rows) do
    if yy >= y + h - 1 then break end
    B.fill(x + 2, yy, 2, 1, r[1]); B.text(x + 5, yy, trunc(r[2], w - 7), C.black, nil); yy = yy + 1
  end
  if yy + 2 < y + h then
    B.put(x + 2, yy + 1, "\7", C.white, C.black)
    B.text(x + 5, yy + 1, trunc("dot: kept in stock", w - 7), C.black, nil)
  end
end
function F.frame()
  UI.regions = {}
  if not F.layout or F.layout.width ~= W then F.layout = F.build(W) end
  B.clear(C.black)
  for y = 1, H - 2 do if y % 4 == 0 then B.fill(0, y, W, 1, C.purple) end end
  -- header
  B.fill(0, 0, W, 1, C.black)
  B.text(0, 0, " FACTORY ", C.black, C.yellow)
  local total, stocked, low, missing = F.summary()
  B.text(11, 0, ("%d gauges   %d stocked   %d below target   %d need a machine"):format(total, stocked, low, missing), C.white, C.black)
  local right = ("Day %d %s "):format(S.day, clockStr())
  B.text(W - #right, 0, right, C.lightGray, C.black)
  local active = F.activeItem()
  if active then
    local s = " CRAFTING " .. iName(active):upper() .. " "
    B.text(W - #right - #s - 2, 0, s, C.black, C.orange)
  end
  for _, p in ipairs(F.layout.panels) do F.drawPanel(p, active) end
  -- info row under the board
  local iy = F.layout.bottom + 1
  local ih = H - 1 - iy
  if ih >= 12 then
    local dw = floor((W - 4) * 0.42)
    local pw = floor((W - 4) * 0.33)
    F.detail(1, iy, dw, ih)
    F.production(2 + dw, iy, pw, ih)
    F.legend(3 + dw + pw, iy, W - 4 - dw - pw, ih)
  end
  drawStatus({PLAN=true, CRAFT=true, TURTLE=true, C21=true, BLAST=true, ERROR=true, OUTPUT=true}, C.black)
  drawToasts()
end
-- Keep-stocked gauges: when one drops below target, queue a craft that stays in storage.
AUTOSTOCK = function(dt)
  if not S.autoStock or #S.jobs > 0 or not F.layout then return end
  S.autoStockAcc = S.autoStockAcc + dt
  if S.autoStockAcc < 6 then return end
  S.autoStockAcc = 0
  for _, id in ipairs(F.layout.products) do
    if S.keep[id] ~= false and RECIPES[id] then
      local tg, n = F.target(id), have(id)
      if tg > 0 and n < tg then
        local q = min(tg - n, 128)
        if plan(id, q).ok then
          log("PLAN", "Auto-stock: " .. iName(id) .. " " .. n .. "/" .. tg .. ", crafting " .. q)
          queueCraft(id, q, true)
          return
        end
      end
    end
  end
end

---------------------------------------------------------------------
-- Monitor setup, input, main loop
---------------------------------------------------------------------
local FRAMES = {brain=brainFrame, storage=storageFrame, factory=F.frame}
local function applyPalette()
  local pal = (ROLE == "factory") and PALETTES.factory or PALETTES.brain
  for i = 0, 15 do
    local c = 2 ^ i
    if S.palette == "brain" then mon.setPaletteColour(c, pal[i + 1])
    else mon.setPaletteColour(c, term.nativePaletteColour(c)) end
  end
  prevRows = {}
end
local function restoreMonitor()
  if not mon then return end
  for i = 0, 15 do local c = 2 ^ i; mon.setPaletteColour(c, term.nativePaletteColour(c)) end
  mon.setBackgroundColour(colours.black); mon.clear(); mon.setCursorPos(1, 1)
end
local function setupMonitor()
  if CONFIG.monitor then mon = peripheral.wrap(CONFIG.monitor); monName = CONFIG.monitor
  else mon = peripheral.find("monitor"); monName = mon and peripheral.getName(mon) end
  if not mon then error("No monitor found. Attach the advanced monitor.", 0) end
  if not mon.isColour() then error("This needs an ADVANCED (gold) monitor.", 0) end
  mon.setTextScale(CONFIG.textScale)
  local w, h = mon.getSize()
  local want = ARGS[1] or CONFIG.role
  if want == "brain" or want == "storage" or want == "factory" then ROLE = want
  elseif h >= 75 then ROLE = "factory"
  elseif h <= 45 then ROLE = "storage"
  else ROLE = "brain" end
  B.resize(w, h)
end
local function refreshReady()
  if ROLE ~= "brain" then return end
  if S.t - S.readyAt < 1 then return end
  S.readyAt = S.t
  for _, id in ipairs(RECIPE_IDS) do S.ready[id] = plan(id, 1).ok end
end
local function reset()
  local keepPal, keepSpeed = S and S.palette or CONFIG.palette, S and S.speed or 1
  S = freshState()
  S.palette, S.speed = keepPal, keepSpeed
  recount()
  log("SYSTEM", "Vault " .. ROLE .. " screen started. 8 storages, 6 turtles, Crafter 21 A, Blasters A")
  log("SYSTEM", "Multiplier sync: 8 storages checked, 1 boosted (backpack_3 x16)")
  log("INPUT", "Oak Log x64 > silo_46")
  log("AUTO", "Cobblestone x64 chest_12 > silo_45")
end
local function hit(x, y)
  for i = #UI.regions, 1, -1 do
    local g = UI.regions[i]
    if x >= g.x and y >= g.y and x < g.x + g.w and y < g.y + g.h then return g end
  end
  return nil
end
local function drawTerminal()
  term.setBackgroundColour(colours.black); term.clear()
  term.setCursorPos(1, 1); term.setTextColour(colours.yellow); print("VAULT UI - " .. ROLE:upper() .. " screen (demo)")
  term.setTextColour(colours.lightGrey)
  print(("Monitor: %s  %dx%d chars"):format(monName or "?", W, H))
  print(("Palette: %s   Speed: %dx"):format(S.palette, S.speed))
  print(("silo_46: %s"):format(S.storages[4].online and "online" or "UNPLUGGED"))
  print("")
  term.setTextColour(colours.white)
  print("Touch the monitor to use it.")
  print("")
  print("D  drop items into input barrel")
  print("F  fail the next turtle batch")
  print("U  unplug / replug silo_46")
  print("P  switch palette")
  print("S  change speed (1x / 3x / 8x)")
  print("R  reset demo")
  print("Q  quit")
  if S.touchInfo then
    term.setTextColour(colours.lightGrey); print("")
    print(("last touch %d,%d -> %s"):format(S.touchInfo.x, S.touchInfo.y, S.touchInfo.key or "nothing"))
  end
end
local function render() FRAMES[ROLE](); B.flush() end

local function onKey(k)
  if k == keys.d then
    for _ = 1, 6 do
      local id = ITEM_ORDER[math.random(1, #ITEM_ORDER)]
      if ITEMS[id].stack == 64 then S.input[#S.input + 1] = {id=id, n=math.random(16, 64)} end
    end
    toast("Stacks dropped into barrel_73", C.lightBlue)
  elseif k == keys.f then
    S.failNext = true; toast("Next turtle batch will time out", C.red)
    if #S.jobs == 0 then queueCraft("create:shaft", 128, ROLE == "factory"); go("jobs") end
  elseif k == keys.u then
    local s = S.storages[4]; s.online = not s.online; recount()
    log(s.online and "SYSTEM" or "ERROR", s.name .. (s.online and " reconnected" or " disconnected - peripheral detached"))
    toast(s.name .. (s.online and " back online" or " went offline"), s.online and C.lime or C.red)
  elseif k == keys.p then
    S.palette = (S.palette == "brain") and "cc" or "brain"; applyPalette()
  elseif k == keys.s then
    S.speed = (S.speed == 1 and 3) or (S.speed == 3 and 8) or 1
  elseif k == keys.r then
    reset(); toast("Demo reset", C.yellow)
  elseif k == keys.q then
    return false
  end
  drawTerminal()
  return true
end

local function main()
  setupMonitor()
  reset()
  applyPalette()
  mon.setBackgroundColour(colours.black); mon.clear()
  drawTerminal()
  render()
  local timer = os.startTimer(CONFIG.frame)
  local last = os.clock()
  while true do
    local ev = {os.pullEventRaw()}
    local e = ev[1]
    if e == "terminate" then break
    elseif e == "timer" and ev[2] == timer then
      local now = os.clock()
      local dt = min(0.5, now - last); last = now
      local sdt = dt * S.speed
      S.t = S.t + sdt
      local left = sdt
      while left > 0 do local st = min(0.1, left); simJobs(st); simWorld(st); left = left - st end
      refreshReady()
      render()
      timer = os.startTimer(CONFIG.frame)
    elseif e == "monitor_touch" and ev[2] == monName then
      local x, y = ev[3] - 1, ev[4] - 1
      local g = hit(x, y)
      S.lastTouch = S.t
      S.touchInfo = {x=ev[3], y=ev[4], key=g and g.key or nil}
      if g then
        UI.pressed = g.key; UI.pressedAt = rt()
        local ok, err = pcall(g.fn)
        if not ok then toast("Error: " .. tostring(err), C.red) end
      end
      S.readyAt = -9; refreshReady()
      render(); drawTerminal()
    elseif e == "monitor_resize" and ev[2] == monName then
      local w, h = mon.getSize(); B.resize(w, h); render()
    elseif e == "key" then
      if not onKey(ev[2]) then break end
    end
  end
end

local ok, err = pcall(main)
restoreMonitor()
term.setBackgroundColour(colours.black); term.setTextColour(colours.white); term.clear(); term.setCursorPos(1, 1)
if not ok then printError(err) else print("Vault UI demo stopped.") end
