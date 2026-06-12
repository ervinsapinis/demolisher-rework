-- The diagonal head ladder (5 items) + building items.
--
-- Each head size has exactly one valid preservation:
--   small  -> mountable raw, spoils, cannot be preserved (drying ruins it)
--   medium -> must be embalmed (Gleba); raw form is a crafting material that spoils
--   big    -> must be cryo-preserved (Aquilo, with bioflux pre-treatment);
--             raw form is a crafting material that spoils
--
-- Raw heads use NATIVE spoilage: they rot in your pocket, in chests, anywhere.
-- Quality extends spoil time. Embalmed and cryo heads are stable.

local raw_spoil_ticks = math.floor(
    settings.startup["dr-raw-rot-hours"].value * 60 * 60 * 60)

local DEMOLISHER_ICON = "__space-age__/graphics/icons/%s-demolisher.png"
local DEAD_TINT       = {r = 0.50, g = 0.46, b = 0.50, a = 1.0}

data:extend{{
    type  = "item-subgroup",
    name  = "dr-heads",
    group = "intermediate-products",
    order = "zz-dr",
}}

local function head_icons(size, badge)
    local icons = {{
        icon      = string.format(DEMOLISHER_ICON, size),
        icon_size = 64,
        tint      = DEAD_TINT,
    }}
    if badge then
        icons[2] = {icon = badge, icon_size = 64, scale = 0.25, shift = {8, 8}}
    end
    return icons
end

local heads = {
    {name = "dr-head-small-raw",       size = "small",  badge = nil,
     order = "a-a", weight = 200 * 1000,  spoils = true},
    {name = "dr-head-medium-raw",      size = "medium", badge = nil,
     order = "b-a", weight = 500 * 1000,  spoils = true},
    {name = "dr-head-medium-embalmed", size = "medium",
     badge = "__space-age__/graphics/icons/bioflux.png",
     order = "b-b", weight = 500 * 1000,  spoils = false},
    {name = "dr-head-big-raw",         size = "big",    badge = nil,
     order = "c-a", weight = 1000 * 1000, spoils = true},
    {name = "dr-head-big-cryo",        size = "big",
     badge = "__space-age__/graphics/icons/ice.png",
     order = "c-b", weight = 1000 * 1000, spoils = false},
}

for _, h in pairs(heads) do
    local item = {
        type       = "item",
        name       = h.name,
        icons      = head_icons(h.size, h.badge),
        subgroup   = "dr-heads",
        order      = h.order,
        stack_size = 1,
        weight     = h.weight,
    }
    if h.spoils then
        item.spoil_ticks  = raw_spoil_ticks
        item.spoil_result = "spoilage"
    end
    data:extend{item}
end

-- Building items
local buildings = {
    {name = "dr-seismograph",  order = "d[radar]-b"},
    {name = "dr-effigy-small", order = "d[radar]-c"},
    {name = "dr-effigy-medium", order = "d[radar]-d"},
    {name = "dr-effigy-big",   order = "d[radar]-e"},
}
for _, b in pairs(buildings) do
    data:extend{{
        type         = "item",
        name         = b.name,
        icons        = {{icon = "__demolisher-rework__/graphics/icons/" .. b.name .. ".png", icon_size = 64}},
        subgroup     = "defensive-structure",
        order        = b.order,
        place_result = b.name,
        stack_size   = 10,
    }}
end
