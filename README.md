# Crafter

ComputerCraft (CC:Tweaked) storage + autocrafting for a Create modpack.

## vault_ui.lua - monitor screens (demo mode)

One program for three computers. It picks the screen from the size of the attached Advanced Monitor
(text scale 0.5):

| Monitor (wide x tall) | Characters | Screen |
|---|---|---|
| 7 x 5 | 143 x 67 | **Brain** - craft, jobs, machines, storage, farms |
| 7 x 3 | 143 x 38 | **Storage** - search, browse and withdraw items |
| 7 x 6 | 143 x 81 | **Factory** - gauge board of every production line |

All data is simulated for now, so each computer runs on its own.

On each computer:

```
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/vault_ui.lua vault_ui.lua
vault_ui
```

Force a screen with `vault_ui brain`, `vault_ui storage` or `vault_ui factory`.

Right-click the monitor to use it. Keys on the computer:
`D` drop items, `F` fail next turtle batch, `U` unplug/replug silo_46, `P` palette, `S` speed, `R` reset, `Q` quit.

## doors/ - keycard doors + factory door diagram

- `doors/door.lua` - door controller (doors 1-5, card level N opens doors 1..N).
- `doors/keycard.lua` - single-door keycard reader / card writer.
- `doors/door_board.lua` - live floor plan of all doors for a **6 wide x 2 tall** Advanced Monitor
  (121 x 24 at text scale 0.5): sliding doors, status lights, people walking through in their card
  colour, denied cards bouncing off, access feed, per-door details and card stats.

`door.lua` and `keycard.lua` are the original programs with one change: every log line is also
broadcast on rednet (protocol `factory_doors`) so the board can see it. Put a modem on every door
computer and on the board computer.

```
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/doors/door_board.lua door_board.lua
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/doors/door.lua door.lua
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/doors/keycard.lua keycard.lua
```

Without a modem (or with nothing heard for 20 s) the board plays a demo. Tap a door for details,
tap the DEMO/LIVE chip to toggle the demo. Room names, levels and keycard reader mapping are in
`CONFIG` at the top of `door_board.lua`.

## feeders/ - farm feeders

- `feeders/feeder.lua` - one small computer per farm. It empties the farm barrel (touching the
  computer) into the vault's input barrel (`minecraft:barrel_73`) over networking cable, and
  reports its name ("Andesite Farm"), items moved, rate and state on rednet (`vault_feeders`).
  The first run asks for the name and target and saves `feeder.cfg`; `feeder setup` changes it.
- `feeders/feeder_list.lua` - list every feeder on the network (terminal or monitor).
  `P` pauses all feeders, `R` resumes them.

```
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/feeders/feeder.lua startup.lua
wget https://raw.githubusercontent.com/Gustavo-DN/Crafter/claude/great-johnson-m11jes/feeders/feeder_list.lua feeder_list.lua
```
