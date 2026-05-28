-- Prototype tweaks for all three demolisher tiers
-- Vanilla values (from space-age/prototypes/entity/enemies.lua):
--   territory_radius = 4 (chunks)
--   small:  health=30000,  speed_multiplier=0.55, regen=40
--   medium: health=100000, speed_multiplier=0.60, regen=130
--   big:    health=300000, speed_multiplier=0.65, regen=400
--   enraged_duration = 1800 ticks (30 sec)

local demolishers = {
    "small-demolisher",
    "medium-demolisher",
    "big-demolisher",
}

for _, name in pairs(demolishers) do
    local d = data.raw["segmented-unit"][name]
    if d then
        d.territory_radius = 2          -- down from 4, tighter territory per worm
        d.enraged_duration = 3600       -- 60 sec instead of 30 — stays angry longer
    end
end

-- HP buff: head segment max_health only (body segments don't have separate HP)
-- The head entity drives territory ownership, so buff it
local head_hp = {
    ["small-demolisher"]  = 45000,   -- was 30000
    ["medium-demolisher"] = 150000,  -- was 100000
    ["big-demolisher"]    = 450000,  -- was 300000
}

for name, hp in pairs(head_hp) do
    local d = data.raw["segmented-unit"][name]
    if d then
        d.max_health = hp
    end
end

-- Invisible entity placed at contested territory chunk centers.
-- Empty sprite = invisible on the ground.
-- map_color = shows as yellow on the minimap.
-- 31×31 tile collision box = covers a full chunk on the minimap.
data:extend{{
    type               = "simple-entity",
    name               = "contested-territory-marker",
    flags              = {
        "placeable-neutral",
        "not-repairable",
        "not-blueprintable",
        "not-deconstructable",
        "not-selectable-in-game",
        "no-automated-item-removal",
        "no-automated-item-insertion",
    },
    collision_box      = {{-15.5, -15.5}, {15.5, 15.5}},
    collision_mask     = {layers = {}},
    selection_box      = {{-15.5, -15.5}, {15.5, 15.5}},
    icon               = "__core__/graphics/empty.png",
    icon_size          = 1,
    map_color          = {r = 0.9, g = 0.65, b = 0.0},
    picture            = {
        filename       = "__core__/graphics/empty.png",
        priority       = "extra-high",
        width          = 1,
        height         = 1,
    },
    subgroup           = "other",
    order              = "z[contested-marker]",
}}
