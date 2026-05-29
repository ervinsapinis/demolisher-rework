-- Prototype tweaks for all three demolisher tiers.
-- All values driven by mod startup settings.
-- Vanilla base values:
--   small:  health=30000,  speed_multiplier=0.55, regen=40,  territory_radius=4, enraged_duration=1800
--   medium: health=100000, speed_multiplier=0.60, regen=130, territory_radius=4, enraged_duration=1800
--   big:    health=300000, speed_multiplier=0.65, regen=400, territory_radius=4, enraged_duration=1800

local radius        = settings.startup["dr-territory-radius"].value
local enrage_ticks  = settings.startup["dr-enrage-seconds"].value * 60

local hp_mult = {
    ["small-demolisher"]  = settings.startup["dr-small-hp-mult"].value,
    ["medium-demolisher"] = settings.startup["dr-medium-hp-mult"].value,
    ["big-demolisher"]    = settings.startup["dr-big-hp-mult"].value,
}

local base_hp = {
    ["small-demolisher"]  = 30000,
    ["medium-demolisher"] = 100000,
    ["big-demolisher"]    = 300000,
}

for name, base in pairs(base_hp) do
    local d = data.raw["segmented-unit"][name]
    if d then
        d.territory_radius = radius
        d.enraged_duration = enrage_ticks
        d.max_health       = math.floor(base * hp_mult[name])
    end
end

-- Minimap overlay sprites for contested territories.
-- 2048x2048 px, scale=0.5 covers exactly one 32x32-tile chunk.
-- The stripe period is 64 tiles (2 chunks). Two phase variants are needed
-- because 64 doesn't divide 32: phase-0 for chunks where (cx-cy) is even,
-- phase-1 for odd. Together they produce seamless \ stripes at vanilla scale.
for _, phase in ipairs{0, 1} do
    data:extend{{
        type     = "sprite",
        name     = "dr-contested-chunk-" .. phase,
        filename = "__demolisher-rework__/graphics/contested-chunk-" .. phase .. ".png",
        size     = 2048,
        scale    = 0.5,
    }}
end
