# Demolisher Rework

A Factorio Space Age mod that overhauls demolisher behaviour on Vulcanus.

**Requires:** Space Age DLC · Factorio 2.0.61+

---

## What it changes

### Territories
- `territory_radius` halved from 4 → 2 chunks — tighter, more numerous territories
- Enrage duration doubled from 30 s → 60 s

### HP (all tiers +50 %)
| Tier | Vanilla | Modded |
|---|---|---|
| Small | 30 000 | 45 000 |
| Medium | 100 000 | 150 000 |
| Big | 300 000 | 450 000 |

### Territory states
| State | Map colour | Meaning |
|---|---|---|
| Occupied | Red (vanilla) | Demolisher lives here |
| Contested | **Yellow** | Empty territory bordering an occupied one |
| Free | None | Empty with no occupied neighbours |

### Migration (repopulation)
Empty territories do **not** regenerate worms instantly. Instead:
1. A contested territory (yellow) is chosen.
2. The demolisher from a neighbouring occupied territory **clones itself** and begins walking toward the contested territory's centre.
3. If the migrant reaches the centre it claims the territory (red again).
4. Players can intercept and kill the migrant — preventing recapture.

### Build trigger
Placing any structure inside an occupied demolisher territory immediately enrages the resident demolisher.

---

## Console commands

| Command | Effect |
|---|---|
| `/dr-status` | Print queue depth, migrant count, and territory breakdown |
| `/dr-refresh` | Rebuild contested overlays and re-sync the migration queue |
| `/dr-repop-now` | Force all queued territories to dispatch migrants on the next tick |

---

## Compatibility

Modifies `small-demolisher`, `medium-demolisher`, and `big-demolisher` segmented-unit prototypes.  
Should be compatible with anything that does not also overwrite `territory_radius`, `enraged_duration`, or `max_health` on those prototypes.
