-- Seismograph Station, Territorial Effigy, and the effigy's hidden power drain.
-- All graphics are placeholder clones of vanilla entities with tints.

local util = require("util")

-- ── Seismograph Station ───────────────────────────────────────────────────────
-- Radar clone that charts (almost) nothing: it listens, it doesn't see.
-- Detection logic (territory overlays, migrant alerts) is all in control.lua;
-- the entity itself exists to be placed, powered, and destroyed by worms.

local seismo = util.table.deepcopy(data.raw.radar.radar)
seismo.name      = "dr-seismograph"
seismo.icon      = nil
seismo.icon_size = nil
seismo.icons     = {{
    icon      = "__base__/graphics/icons/radar.png",
    icon_size = 64,
    tint      = {r = 1.0, g = 0.78, b = 0.50, a = 1.0},
}}
seismo.minable    = {mining_time = 0.3, result = "dr-seismograph"}
seismo.max_health = 500
seismo.energy_usage = settings.startup["dr-seismo-power-mw"].value .. "MW"
-- Effectively never complete distant sector scans, reveal nothing when one
-- would complete, keep only the station's own surroundings live.
seismo.energy_per_sector                      = "1000GJ"
seismo.energy_per_nearby_scan                 = "1MJ"
seismo.max_distance_of_sector_revealed        = 0
seismo.max_distance_of_nearby_sector_revealed = 1
-- Placeholder tint on the structure sprite (defensive: layer layout may vary)
if seismo.pictures and seismo.pictures.layers and seismo.pictures.layers[1] then
    seismo.pictures.layers[1].tint = {r = 1.0, g = 0.80, b = 0.55, a = 1.0}
end

-- ── Territorial Effigy ────────────────────────────────────────────────────────
-- A container: socket a head, optionally feed it (embalmed tier). All behaviour
-- is scripted in control.lua; inserters can load it like any chest.

local effigy = util.table.deepcopy(data.raw.container["steel-chest"])
effigy.name      = "dr-effigy"
effigy.icon      = nil
effigy.icon_size = nil
effigy.icons     = {{
    icon      = "__base__/graphics/icons/steel-chest.png",
    icon_size = 64,
    tint      = {r = 0.80, g = 0.55, b = 0.95, a = 1.0},
}}
effigy.minable        = {mining_time = 0.5, result = "dr-effigy"}
effigy.max_health     = 600
-- 3 slots: one head, one calcite, one tungsten plate (filters set by script)
effigy.inventory_size = 3
effigy.inventory_type = "with_filters_and_bar"
-- 4x4 footprint: this is a monument, not a chest
effigy.collision_box  = {{-1.85, -1.85}, {1.85, 1.85}}
effigy.selection_box  = {{-2.0, -2.0}, {2.0, 2.0}}
if effigy.picture and effigy.picture.layers then
    for i, layer in pairs(effigy.picture.layers) do
        layer.scale = (layer.scale or 1) * 4
        if i == 1 then
            layer.tint = {r = 0.75, g = 0.50, b = 0.90, a = 1.0}
        end
    end
end

-- ── Hidden power interface for cryo-tier effigies ─────────────────────────────
-- Created/destroyed by script underneath an effigy when a cryo head is socketed.
-- Buffer and usage are set at runtime from the dr-cryo-power-mw setting.

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
    buffer_capacity   = "60MJ",
    usage_priority    = "secondary-input",
    input_flow_limit  = "200MW",
    output_flow_limit = "0W",
}
eei.energy_usage        = "10MW"
-- Invisible: strip all graphics the debug entity ships with
eei.picture             = nil
eei.pictures            = nil
eei.animation           = nil
eei.animations          = nil
eei.continuous_animation = nil
eei.light               = nil

data:extend{seismo, effigy, eei}
