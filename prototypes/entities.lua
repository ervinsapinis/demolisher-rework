-- Seismograph station, three territorial effigies, and the hidden power drain.
-- All entities use the AI-generated art in graphics/entity/.
--
-- Scale math: rendered tiles = px * scale / 32. Each effigy's visual width
-- slightly overhangs its collision footprint (Factorio convention), and the
-- sprite is shifted north so the monument base sits on the south edge.

local util = require("util")

-- ── Seismograph Station (3x3, radar prototype) ───────────────────────────────
-- Charts (almost) nothing: it listens, it doesn't see. Detection logic lives
-- in control.lua; the entity exists to be placed, powered, and eaten by worms.

local seismo = util.table.deepcopy(data.raw.radar.radar)
seismo.name      = "dr-seismograph"
seismo.icon      = nil
seismo.icon_size = nil
seismo.icons     = {{icon = "__demolisher-rework__/graphics/icons/dr-seismograph.png", icon_size = 64}}
seismo.minable    = {mining_time = 0.3, result = "dr-seismograph"}
seismo.max_health = 500
seismo.energy_usage = settings.startup["dr-seismo-power-mw"].value .. "MW"
seismo.energy_per_sector                      = "1000GJ"
seismo.energy_per_nearby_scan                 = "1MJ"
seismo.max_distance_of_sector_revealed        = 0
seismo.max_distance_of_nearby_sector_revealed = 1
-- Static sprite (single direction) replacing the spinning radar dish.
-- 982x888 px, scale 0.117 -> 3.59 x 3.25 tiles on a 3x3 footprint.
seismo.pictures = {
    layers = {{
        filename        = "__demolisher-rework__/graphics/entity/seismograph.png",
        priority        = "high",
        width           = 982,
        height          = 888,
        direction_count = 1,
        scale           = 0.117,
        shift           = {0, -0.1},
    }},
}

-- ── Territorial effigies (3 tiers) ────────────────────────────────────────────
-- Containers; behaviour scripted in control.lua. The prototype picture is the
-- EMPTY monument; the mounted state is drawn as a runtime sprite overlay.
--
--   tier  name              footprint  slots  mounts
--   1     dr-effigy-small   3x3        1      raw small head (rots)
--   2     dr-effigy-medium  4x4        3      embalmed medium head (+feed)
--   3     dr-effigy-big     6x6        1      cryo big head (+power)

local function make_effigy(spec)
    local e = util.table.deepcopy(data.raw.container["steel-chest"])
    e.name      = spec.name
    e.icon      = nil
    e.icon_size = nil
    e.icons     = {{icon = "__demolisher-rework__/graphics/icons/" .. spec.name .. ".png", icon_size = 64}}
    e.minable        = {mining_time = 0.5, result = spec.name}
    e.max_health     = spec.health
    e.inventory_size = spec.slots
    e.inventory_type = "with_filters_and_bar"
    e.collision_box  = {{-spec.cbox, -spec.cbox}, {spec.cbox, spec.cbox}}
    e.selection_box  = {{-spec.sbox, -spec.sbox}, {spec.sbox, spec.sbox}}
    e.picture = {
        layers = {{
            filename = "__demolisher-rework__/graphics/entity/" .. spec.empty_file,
            priority = "high",
            width    = spec.empty_w,
            height   = spec.empty_h,
            scale    = spec.scale_empty,
            shift    = spec.shift_empty,
        }},
    }
    return e
end

local effigy_small = make_effigy{
    name = "dr-effigy-small", health = 400, slots = 1,
    cbox = 1.35, sbox = 1.5,                       -- 3x3
    empty_file = "effigy-small-empty.png",
    empty_w = 800, empty_h = 917,
    scale_empty = 0.148, shift_empty = {0, -0.35}, -- 3.70 x 4.24 tiles
}

local effigy_medium = make_effigy{
    name = "dr-effigy-medium", health = 700, slots = 3,
    cbox = 1.85, sbox = 2.0,                       -- 4x4
    empty_file = "effigy-medium-empty.png",
    empty_w = 939, empty_h = 1091,
    scale_empty = 0.167, shift_empty = {0, -0.55}, -- 4.90 x 5.69 tiles
}

local effigy_big = make_effigy{
    name = "dr-effigy-big", health = 1200, slots = 1,
    cbox = 2.85, sbox = 3.0,                       -- 6x6
    empty_file = "effigy-big-empty.png",
    empty_w = 940, empty_h = 1120,
    scale_empty = 0.248, shift_empty = {0, -1.0},  -- 7.29 x 8.68 tiles
}

-- Mounted-state overlay sprites, drawn by control.lua over the empty monument.
-- Scale/shift baked into the prototype so the draw call needs no offsets.
local mounted = {
    {name = "dr-effigy-small-mounted",  file = "effigy-small-mounted.png",
     w = 938,  h = 1113, scale = 0.126, shift = {0, -0.4}},
    {name = "dr-effigy-medium-mounted", file = "effigy-medium-mounted.png",
     w = 937,  h = 1112, scale = 0.167, shift = {0, -0.6}},
    {name = "dr-effigy-big-mounted",    file = "effigy-big-mounted.png",
     w = 941,  h = 1121, scale = 0.248, shift = {0, -1.0}},
}
for _, m in pairs(mounted) do
    data:extend{{
        type     = "sprite",
        name     = m.name,
        filename = "__demolisher-rework__/graphics/entity/" .. m.file,
        width    = m.w,
        height   = m.h,
        scale    = m.scale,
        shift    = m.shift,
    }}
end

-- ── Hidden power interface for the big (cryo) effigy ─────────────────────────
-- Created/destroyed by script underneath the effigy when a cryo head is
-- socketed. The draw is baked into the prototype's energy_usage (the standard,
-- reliable consumer-EEI pattern) rather than poked at runtime, so it actually
-- registers as a grid load. Buffer holds ~5 s so a brownout drains gradually.

local cryo_mw   = settings.startup["dr-cryo-power-mw"].value
local buffer_mj = math.max(1, math.floor(cryo_mw * 5))   -- ~5 seconds of draw

local eei = util.table.deepcopy(
    data.raw["electric-energy-interface"]["electric-energy-interface"])
eei.name                = "dr-effigy-power"
eei.localised_name      = {"entity-name.dr-effigy-power"}
eei.flags               = {"not-on-map", "not-blueprintable", "not-deconstructable",
                           "placeable-off-grid", "not-flammable", "not-upgradable"}
eei.hidden              = true
eei.selectable_in_game  = false
eei.minable             = nil
eei.max_health          = 1
eei.collision_mask      = {layers = {}}
eei.energy_source       = {
    type              = "electric",
    buffer_capacity   = buffer_mj .. "MJ",
    usage_priority    = "secondary-input",
    input_flow_limit  = (cryo_mw * 2) .. "MW",
    output_flow_limit = "0W",
}
eei.energy_usage        = cryo_mw .. "MW"
eei.energy_production   = "0W"   -- base editor EEI defaults to producing; we only consume
eei.picture             = nil
eei.pictures            = nil
eei.animation           = nil
eei.animations          = nil
eei.continuous_animation = nil
eei.light               = nil

data:extend{seismo, effigy_small, effigy_medium, effigy_big, eei}
