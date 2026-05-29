# Demolisher Rework

A Factorio Space Age mod that overhauls demolisher behaviour on Vulcanus.

**Requires:** Space Age DLC · Factorio 2.0.61+

---

## What it changes

### Territory states
| State | Map colour | Meaning |
|---|---|---|
| Occupied | Red (vanilla) | Demolisher lives here |
| Contested | **Yellow hazard stripes** | Empty territory bordering an occupied one — repopulation pending |
| Free | None | Empty, no occupied neighbours |

### Three-phase repopulation
When a resident demolisher dies its territory does **not** repopulate instantly. Instead:

1. **Cooling** — a grace period (default 5 min) during which nothing happens and no overlay appears. Gives players time to work in the area without immediately triggering a counter-attack.
2. **Contested** — after the grace period the territory enters the queue and shows the yellow hazard-stripe minimap overlay.
3. **Migration** — after a configurable delay a demolisher from a neighbouring occupied territory clones itself and walks toward the contested territory's centre. The overlay persists until it arrives. Killing the migrant resets the delay and a new one will eventually be dispatched. To permanently stop recapture you must also eliminate the neighbouring occupied territories.

### Build trigger
Placing any structure inside an occupied demolisher territory immediately enrages the resident demolisher.

---

## Configuration

Everything is adjustable in **Mod Settings** — no console commands required.

### Runtime settings (can be changed mid-save)
| Setting | Default | Description |
|---|---|---|
| Grace period | 5 min | How long a territory stays in cooling before becoming contested |
| Migration delay | 10 min | How long a contested territory waits before dispatching a migrant |
| Migration interval | 5 min | Minimum time between successive migration dispatches |
| Migration chance | 100 % | Probability that a contested territory actually sends a migrant each cycle |

### Startup settings (require a restart)
| Setting | Default | Description |
|---|---|---|
| Territory radius | 2 chunks | Radius of each demolisher territory (vanilla default: 4) |
| Enrage duration | 60 s | How long a demolisher stays enraged (vanilla default: 30 s) |
| Small HP multiplier | 1.5× | Applied to the 30 000 vanilla base |
| Medium HP multiplier | 1.5× | Applied to the 100 000 vanilla base |
| Big HP multiplier | 1.5× | Applied to the 300 000 vanilla base |

---

## Debug commands

These are intended for testing and troubleshooting only — normal gameplay does not require them.

| Command | Effect |
|---|---|
| `/dr-status` | Print queue depth, migrant count, and territory breakdown to the console |
| `/dr-refresh` | Rebuild contested overlays and re-sync the migration queue |
| `/dr-repop-now` | Force all queued territories to dispatch migrants immediately |

---

## Compatibility

Modifies `small-demolisher`, `medium-demolisher`, and `big-demolisher` segmented-unit prototypes.
Compatible with anything that does not also overwrite `territory_radius`, `enraged_duration`, or `max_health` on those same prototypes.
