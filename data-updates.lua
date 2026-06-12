-- Hide the vanilla enemy-territory chart overlay (fill, stripes, AND borders).
--
-- The territory shader draws its stripes from default_enemy_territory_color but
-- its solid border from default_enemy_color, so both must be zeroed. Enemy unit
-- map blips would die with default_enemy_color, so the original red is first
-- copied into enemy_map_color on every enemy prototype that lacks one: you can
-- still see the animal, never the borders. (Technique from the hide-territory mod.)
--
-- All territory intel is then re-rendered by control.lua, gated by seismograph
-- coverage. Fog of war for worms.

if settings.startup["dr-hide-vanilla-territory"].value then
    local chart = data.raw["utility-constants"]["default"].chart
    local default_enemy_color = chart.default_enemy_color

    for _, unit_type in pairs{"unit-spawner", "segment", "segmented-unit", "spider-unit", "unit"} do
        for _, prototype in pairs(data.raw[unit_type] or {}) do
            if not prototype.enemy_map_color then
                prototype.enemy_map_color = default_enemy_color
            end
        end
    end

    chart.default_enemy_territory_color = {0, 0, 0, 0}
    chart.default_enemy_color           = {0, 0, 0, 0}
end
