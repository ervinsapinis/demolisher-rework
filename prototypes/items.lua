-- Head items (3 sizes x 3 preservation tiers) + building items.
--
-- Raw heads use the NATIVE spoilage mechanic: they rot into spoilage after
-- dr-raw-rot-hours, whether in your inventory, a chest, or a socketed effigy.
-- Quality extends spoil time natively, so heads from high-quality worms last
-- longer. Embalmed and cryo heads do not spoil.
--
-- Icons are placeholders composed from Space Age demolisher corpse icons with
-- preservation tints (embalmed = green, cryo = ice blue).

local SIZES = {"small", "medium", "big"}

local WEIGHT = {           -- 1 rocket = 1,000,000 weight (1 t)
    small  = 200 * 1000,   -- 5 per rocket
    medium = 500 * 1000,   -- 2 per rocket
    big    = 1000 * 1000,  -- 1 per rocket: yes, a whole rocket for one head
}

local TINT = {
    raw      = nil,
    embalmed = {r = 0.70, g = 1.00, b = 0.70, a = 1.0},
    cryo     = {r = 0.60, g = 0.85, b = 1.00, a = 1.0},
}

local ORDER_SIZE = {small = "a", medium = "b", big = "c"}
local ORDER_PRES = {raw = "a", embalmed = "b", cryo = "c"}

local raw_spoil_ticks = math.floor(
    settings.startup["dr-raw-rot-hours"].value * 60 * 60 * 60)

data:extend{{
    type  = "item-subgroup",
    name  = "dr-heads",
    group = "intermediate-products",
    order = "zz-dr",
}}

for _, size in pairs(SIZES) do
    for _, pres in pairs{"raw", "embalmed", "cryo"} do
        local icon_def = {
            icon      = "__space-age__/graphics/icons/" .. size .. "-demolisher-remains.png",
            icon_size = 64,
        }
        if TINT[pres] then icon_def.tint = TINT[pres] end

        local item = {
            type       = "item",
            name       = "dr-head-" .. size .. "-" .. pres,
            icons      = {icon_def},
            subgroup   = "dr-heads",
            order      = ORDER_SIZE[size] .. "-" .. ORDER_PRES[pres],
            stack_size = 1,
            weight     = WEIGHT[size],
        }

        if pres == "raw" then
            item.spoil_ticks  = raw_spoil_ticks
            item.spoil_result = "spoilage"
        end

        data:extend{item}
    end
end

-- Building items
data:extend{
    {
        type         = "item",
        name         = "dr-seismograph",
        icons        = {{
            icon      = "__base__/graphics/icons/radar.png",
            icon_size = 64,
            tint      = {r = 1.0, g = 0.78, b = 0.50, a = 1.0},
        }},
        subgroup     = "defensive-structure",
        order        = "d[radar]-b[dr-seismograph]",
        place_result = "dr-seismograph",
        stack_size   = 10,
    },
    {
        type         = "item",
        name         = "dr-effigy",
        icons        = {{
            icon      = "__base__/graphics/icons/steel-chest.png",
            icon_size = 64,
            tint      = {r = 0.80, g = 0.55, b = 0.95, a = 1.0},
        }},
        subgroup     = "defensive-structure",
        order        = "d[radar]-c[dr-effigy]",
        place_result = "dr-effigy",
        stack_size   = 10,
    },
}
