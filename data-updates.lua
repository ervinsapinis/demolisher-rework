-- Hide the vanilla red enemy-territory chart overlay.
--
-- With this on, the map shows NO territory information by default; all territory
-- intel (red occupied / yellow contested / violet effigy-held) is re-rendered by
-- control.lua, but only inside seismograph coverage. Fog of war for worms.
--
-- Enemy units themselves keep their map colour, so a charted worm still shows as
-- a red blip: you can see the animal, never the borders.

if settings.startup["dr-hide-vanilla-territory"].value then
    local chart = data.raw["utility-constants"]["default"].chart
    chart.default_enemy_territory_color = {0, 0, 0, 0}
end
