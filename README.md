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
