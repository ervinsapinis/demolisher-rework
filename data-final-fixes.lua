-- Override Vulcanus demolisher noise expressions with configured values.
-- Runs last (data-final-fixes stage) so it wins over any other mod that
-- modifies these expressions in data or data-updates.
--
-- Vanilla defaults:
--   demolisher_territory_radius      = 384 (Voronoi grid cell size in tiles)
--   demolisher_variation_expression  = "floor(clamp(distance / (18*32) - 0.25, 0, 4)) + (-99 * no_enemies_mode)"
--     → tier changes every 18 chunks (576 tiles) from the starting area
--       tier 0 = small  (0 – 720 tiles)
--       tier 1 = medium (720 – 1296 tiles)
--       tier 2 = big    (1296+ tiles)

local stride_tiles = settings.startup["dr-tier-chunk-stride"].value * 32
local voronoi_size = settings.startup["dr-territory-voronoi-size"].value

-- Tier-distribution expression
local var_expr = data.raw["noise-expression"]["demolisher_variation_expression"]
if var_expr then
    var_expr.expression = string.format(
        "floor(clamp(distance / %d - 0.25, 0, 4)) + (-99 * no_enemies_mode)",
        stride_tiles
    )
end

-- Voronoi grid size (geographic territory spacing)
local radius_expr = data.raw["noise-expression"]["demolisher_territory_radius"]
if radius_expr then
    radius_expr.expression = voronoi_size
end
