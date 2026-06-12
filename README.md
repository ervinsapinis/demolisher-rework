# Demolisher Rework

A Factorio Space Age mod that overhauls demolisher behaviour on Vulcanus: earned territory intel, a deception economy built on severed heads, and worms that get angrier the more of them you kill.

**Requires:** Space Age DLC · Factorio 2.0.61+

---

## Territory intel is earned, not given

By default the vanilla red territory overlay is **hidden** (startup setting). The planet keeps its secrets: you learn territory borders the way God intended, by getting chased.

Research **Seismic monitoring** and build **seismograph stations** to get it back. Within a station's detection radius (default 8 chunks, +2 per quality tier) the map shows:

| Overlay | Meaning |
|---|---|
| Red | Occupied territory: a demolisher lives here |
| Yellow stripes | Contested: empty, bordering an occupied territory, repopulation pending |
| Violet stripes | Effigy-held: your own lie, marked so you don't forget it |

Seismographs also raise a one-time alert when a migrating demolisher enters coverage. They draw massive constant power (default 50 MW): you are listening to a planet, and that costs. They chart almost nothing themselves: they listen, they don't see.

## Three-phase repopulation

When a resident demolisher dies the territory does not repopulate instantly:

1. **Cooling**: a grace period with no overlay. Breathing room.
2. **Contested**: the territory enters the migration queue, yellow stripes appear (within coverage).
3. **Migration**: a worm from a neighbouring occupied territory clones itself and walks over to claim it. Killing the migrant resets the delay; a new one will eventually come. To stop recapture permanently, clear the neighbours, or lie to them.

## The effigy: lie to the worms

Killed demolishers have a chance to drop their **head** (default 75%). Research **Demolisher ethology** (granted instantly on your first kill) to unlock the **territorial effigy**: socket a head and neighbouring demolishers believe the territory is occupied. No contested state, no migration, while the deception holds.

**The tier rule:** a head only fools demolishers of its own size or smaller. A small head does nothing against a big neighbour. Want peace next to a big demolisher? Go kill a big demolisher first.

**The preservation ladder** (each tier swaps the upkeep currency):

| Head | Tech | Upkeep | Fails when |
|---|---|---|---|
| Raw | drop | None, but it **rots** (native spoilage, default 2 h; quality extends it) | The timer runs out |
| Embalmed | Cadaver embalming (Gleba) | Eats calcite + tungsten plate while there is an audience | The feed runs dry |
| Cryo-preserved | Cryogenic taxidermy (Aquilo) | Constant power (default 10 MW), zero items | The lights go out |

When upkeep fails, a **silence window** (default 5 min) starts: refill, re-socket, or restore power in time and nobody notices. If the window expires, the deception is **exposed**: the territory is queued for migration at a reduced delay (default 50%). The neighbours noticed the silence, and they're coming sooner.

Effigies are containers: inserters can load heads and feed automatically. A floating status label warns of SILENT / STARVING / NO POWER / HEAD TOO SMALL states.

## Escalation: they remember

Demolishers gain effective HP:

- **By distance**: +50% per 1000 tiles from the map origin (default).
- **By grudge**: +2% per demolisher ever killed, capped at +200% (default). Every kill makes the next one harder, which quietly makes rent (effigies) the smart late-game play over war.

Both knobs go to zero if you want them off.

## Build trigger

Placing any structure inside an occupied territory immediately enrages the resident demolisher.

---

## Configuration

Everything above is adjustable in Mod Settings: timings, chances, radii, power draws, feed rates, escalation coefficients, HP multipliers, territory size, and the vanilla-overlay hiding. Startup settings are marked in their tooltips.

## Debug commands

For testing and troubleshooting only.

| Command | Effect |
|---|---|
| `/dr-status` | Full state dump: queues, migrants, effigies, seismographs, kill counter |
| `/dr-refresh` | Rebuild the minimap overlay |
| `/dr-repop-now` | Zero all timers, force immediate migration dispatch |
| `/dr-reveal` | Toggle debug reveal: bypass seismograph coverage gating |

## Compatibility

Modifies the three demolisher segmented-unit prototypes (`territory_radius`, `enraged_duration`, `max_health`) and, when the hardcore-intel setting is on, sets the chart `default_enemy_territory_color` to transparent. Compatible with anything that doesn't fight over those.

Graphics are placeholder tints of vanilla sprites for now (radar, steel chest, demolisher icons).
