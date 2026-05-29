-- Demolisher Rework - runtime logic (Factorio 2.0.61+ territory API)
--
-- Territory lifecycle:
--   occupied (red) → [worm dies] → cooling (no overlay, grace period)
--                  → contested (yellow overlay, migration delay)
--                  → migrant dispatched (yellow persists, worm travels)
--                  → occupied again (red) once migrant arrives

local SURFACE_NAME   = "vulcanus"
local CHECK_INTERVAL = 300    -- heartbeat every 5 sec (fixed)
local ARRIVAL_RADIUS = 48     -- tiles: claim territory when head is this close to center

local FILL_COLOR   = {r = 0.0, g = 0.0, b = 0.0, a = 0.0}  -- dark amber fill (background between stripes)
local STRIPE_COLOR = {r = 1.000, g = 0.698, b = 0.400, a = 1.0}  -- bright yellow tint for stripe sprite
local BORDER_COLOR = {r = 1.000, g = 0.698, b = 0.400, a = 1.0}  -- bright yellow border lines
-- Stripe pattern is baked into graphics/contested-chunk.png (2048px, scale=0.5 → 32×32 tile chunk).
-- Period = 16 tiles, fill ≈ 42 %. To change spacing/fill regenerate the PNG with gen_sprite.py.


-- ─── Runtime setting accessors (ticks at 60 UPS) ─────────────────────────────

local function grace_ticks()
    return settings.global["dr-grace-period-min"].value * 3600
end

local function delay_ticks()
    return settings.global["dr-migration-delay-min"].value * 3600
end

local function interval_ticks()
    return settings.global["dr-migration-interval-min"].value * 3600
end

local function migration_chance()
    return settings.global["dr-migration-chance"].value
end


-- ─── Storage layout ───────────────────────────────────────────────────────────
--
-- storage.cooling             {territory, emptied_tick}[]
-- storage.migration_queue     {territory, contested_tick}[]   ← shown in yellow
-- storage.migrating_units     {unit, target_territory, target_pos}[]
-- storage.contested_renders   LuaRenderObject[]
-- storage.next_migration_tick uint

script.on_init(function()
    storage.cooling             = {}
    storage.migration_queue     = {}
    storage.migrating_units     = {}
    storage.contested_renders   = {}
    storage.next_migration_tick = 0
end)

-- on_load must NOT write to storage — fires on every load of an existing save.
script.on_load(function() end)

script.on_configuration_changed(function()
    -- Full reinit: old saves may have differently-structured entries (e.g. v0.1.0
    -- used {territory, tick} in migration_queue; v0.2.0 expects {territory, contested_tick}).
    -- Stale entries with wrong field names cause silent arithmetic-on-nil errors in the
    -- heartbeat that stop all migration logic from running.
    storage.cooling             = {}
    storage.migration_queue     = {}
    storage.migrating_units     = {}
    storage.contested_renders   = {}
    storage.next_migration_tick = 0
    local s = game.surfaces[SURFACE_NAME]
    if s then refresh_overlay(s) end
end)


-- ─── Helpers ──────────────────────────────────────────────────────────────────

local function get_head_pos(unit)
    if not unit or not unit.valid then return nil end
    local nodes = unit.get_body_nodes()
    return (nodes and #nodes > 0) and nodes[1] or nil
end

local function dist(a, b)
    return math.sqrt((a.x - b.x)^2 + (a.y - b.y)^2)
end

local function get_neighbors(surface, territory)
    local result, seen = {}, {}
    for _, chunk in pairs(territory.get_chunks()) do
        for _, off in pairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            local n = surface.get_territory_for_chunk{x = chunk.x + off[1], y = chunk.y + off[2]}
            if n and n.valid and n ~= territory and not seen[n] then
                seen[n] = true
                result[#result + 1] = n
            end
        end
    end
    return result
end

local function is_occupied(territory)
    return territory and territory.valid and #territory.get_segmented_units() > 0
end

local function is_contested(surface, territory)
    if is_occupied(territory) then return false end
    for _, n in pairs(get_neighbors(surface, territory)) do
        if is_occupied(n) then return true end
    end
    return false
end

local function territory_center(territory)
    local chunks = territory.get_chunks()
    if #chunks == 0 then return nil end
    local sx, sy = 0, 0
    for _, c in pairs(chunks) do
        sx = sx + (c.area.left_top.x + c.area.right_bottom.x) * 0.5
        sy = sy + (c.area.left_top.y + c.area.right_bottom.y) * 0.5
    end
    return {x = sx / #chunks, y = sy / #chunks}
end

local function in_list(list, key, value)
    for _, e in pairs(list) do
        if e[key] == value then return true end
    end
    return false
end

-- Removes migration_queue / migrating_units entries whose territory no longer
-- needs an overlay: either it was re-occupied, or the player cleared all of its
-- occupied neighbours so it is no longer contested.
-- Orphaned migrants are killed so they don't wander.
-- Returns true if anything changed (overlay must be refreshed).
local function prune_stale(surface)
    local dirty = false

    local function needs_overlay(t)
        return t and t.valid and not is_occupied(t) and is_contested(surface, t)
    end

    local q2 = {}
    for _, e in pairs(storage.migration_queue) do
        if needs_overlay(e.territory) then q2[#q2+1] = e
        else dirty = true end
    end
    storage.migration_queue = q2

    local m2 = {}
    for _, m in pairs(storage.migrating_units) do
        if needs_overlay(m.target_territory) then
            m2[#m2+1] = m
        else
            if m.unit and m.unit.valid then m.unit.die() end
            dirty = true
        end
    end
    storage.migrating_units = m2

    return dirty
end


-- ─── Minimap overlay (render_mode = "chart") ─────────────────────────────────
--
-- Territories shown in yellow = those in migration_queue + migrating_units targets.
-- Cooling territories (grace period, not yet contested) get NO overlay.

function refresh_overlay(surface)
    -- Destroy previous renders
    for _, obj in pairs(storage.contested_renders) do
        if obj and obj.valid then obj.destroy() end
    end
    storage.contested_renders = {}

    -- Collect territories that should have an overlay
    local to_draw, seen = {}, {}
    for _, e in pairs(storage.migration_queue) do
        local t = e.territory
        if t and t.valid and not seen[t] then
            seen[t] = true; to_draw[#to_draw + 1] = t
        end
    end
    for _, m in pairs(storage.migrating_units) do
        local t = m.target_territory
        if t and t.valid and not seen[t] then
            seen[t] = true; to_draw[#to_draw + 1] = t
        end
    end

    if #to_draw == 0 then return end

    -- Remove territories that haven't been explored yet (no charted chunks).
    -- Prevents yellow overlay appearing in the black unexplored area.
    local player_force = game.forces["player"]
    if player_force then
        local charted = {}
        for _, t in ipairs(to_draw) do
            for _, chunk in pairs(t.get_chunks()) do
                if player_force.is_chunk_charted(surface, chunk) then
                    charted[#charted + 1] = t
                    break
                end
            end
        end
        to_draw = charted
    end
    if #to_draw == 0 then return end

    -- Build chunk→territory-index map.
    -- cs[x][y] = index into to_draw.  Used to:
    --   (a) detect outer edges  (neighbour absent)
    --   (b) detect inter-territory edges  (neighbour belongs to a different territory)
    local cs = {}
    for ti, t in ipairs(to_draw) do
        for _, chunk in pairs(t.get_chunks()) do
            if not cs[chunk.x] then cs[chunk.x] = {} end
            cs[chunk.x][chunk.y] = ti
        end
    end

    local renders = storage.contested_renders
    for ti, territory in ipairs(to_draw) do
        for _, chunk in pairs(territory.get_chunks()) do
            -- Never draw overlay on unexplored chunks — the territory may extend beyond
            -- the visible map, but the overlay must stay inside the charted area.
            if player_force and not player_force.is_chunk_charted(surface, chunk) then
                goto continue_chunk
            end

            local lt = chunk.area.left_top
            local rb = chunk.area.right_bottom
            local cx, cy = chunk.x, chunk.y

            -- Filled chunk rectangle (subtle amber background)
            renders[#renders + 1] = rendering.draw_rectangle{
                color        = FILL_COLOR,
                filled       = true,
                left_top     = lt,
                right_bottom = rb,
                surface      = surface,
                render_mode  = "chart",
            }

            -- Diagonal hazard stripes (\ direction, 64-tile period, vanilla scale).
            -- The period is 2 chunks wide, so two phase variants are pre-rendered:
            --   phase 0 (dr-contested-chunk-0): stripe through main diagonal
            --   phase 1 (dr-contested-chunk-1): stripe through off-diagonal half
            -- Selecting by (cx-cy) % 2 makes adjacent chunks seamless with no
            -- geometry code at all. Lua % is always non-negative for positive divisor.
            local phase = (cx - cy) % 2
            renders[#renders + 1] = rendering.draw_sprite{
                sprite      = "dr-contested-chunk-" .. phase,
                target      = {x = (lt.x + rb.x) * 0.5, y = (lt.y + rb.y) * 0.5},
                surface     = surface,
                tint        = STRIPE_COLOR,
                render_mode = "chart",
            }

            -- Border on any edge where the neighbour is absent or belongs to a different territory
            local w = 0.25  -- slight corner overlap to avoid seams
            local function edge(nx, ny)
                local nti = cs[nx] and cs[nx][ny]
                return not nti or nti ~= ti
            end
            if edge(cx, cy - 1) then
                renders[#renders + 1] = rendering.draw_line{
                    color = BORDER_COLOR, width = 64,
                    from = {lt.x - w, lt.y}, to = {rb.x + w, lt.y},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx, cy + 1) then
                renders[#renders + 1] = rendering.draw_line{
                    color = BORDER_COLOR, width = 64,
                    from = {lt.x - w, rb.y}, to = {rb.x + w, rb.y},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx - 1, cy) then
                renders[#renders + 1] = rendering.draw_line{
                    color = BORDER_COLOR, width = 64,
                    from = {lt.x, lt.y - w}, to = {lt.x, rb.y + w},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx + 1, cy) then
                renders[#renders + 1] = rendering.draw_line{
                    color = BORDER_COLOR, width = 64,
                    from = {rb.x, lt.y - w}, to = {rb.x, rb.y + w},
                    surface = surface, render_mode = "chart",
                }
            end

            ::continue_chunk::
        end
    end
end


-- ─── Events ───────────────────────────────────────────────────────────────────

-- Resident worm died → territory enters cooling phase.
-- Migrant deaths are handled in the heartbeat arrival-check instead.
-- NOTE: unit.territory may be nil if the engine clears it before the event fires.
-- The heartbeat does a periodic scan to catch anything missed here.
script.on_event(defines.events.on_segmented_unit_died, function(e)
    local unit = e.segmented_unit
    if not unit or not unit.valid then return end
    if unit.surface.name ~= SURFACE_NAME then return end

    -- Skip tracked migrants (heartbeat re-queues their target territory)
    if in_list(storage.migrating_units, "unit", unit) then return end

    -- Try to get territory from the unit; fall back to position-based lookup
    local territory = unit.territory
    if not territory or not territory.valid then
        local pos = get_head_pos(unit)
        if pos then
            territory = unit.surface.get_territory_for_chunk{
                x = math.floor(pos.x / 32),
                y = math.floor(pos.y / 32),
            }
        end
    end
    if not territory or not territory.valid then return end

    -- Confirm territory is now empty (dead unit is already removed)
    if #territory.get_segmented_units() > 0 then return end

    -- Add to cooling if not already tracked
    if not in_list(storage.cooling,         "territory",        territory)
    and not in_list(storage.migration_queue, "territory",        territory)
    and not in_list(storage.migrating_units, "target_territory", territory) then
        storage.cooling[#storage.cooling + 1] = {
            territory    = territory,
            emptied_tick = game.tick,
        }
    end

    -- A death in territory X may free territories that were contested only because
    -- X was occupied. Prune them immediately so the overlay updates at once.
    prune_stale(unit.surface)
    refresh_overlay(unit.surface)
end)

-- New unit created → if it has a territory, clear that territory from all queues.
-- Covers world-gen spawns and the migrant-claims-territory moment if the engine
-- fires this event for territory reassignment (belt-and-suspenders).
script.on_event(defines.events.on_segmented_unit_created, function(e)
    local unit = e.segmented_unit
    if not unit or not unit.valid then return end
    if unit.surface.name ~= SURFACE_NAME then return end

    local territory = unit.territory
    if not territory or not territory.valid then return end  -- migrant clone, skip

    local function purge(list, key)
        local keep = {}
        for _, entry in pairs(list) do
            if entry[key] ~= territory then keep[#keep + 1] = entry end
        end
        return keep
    end

    storage.cooling         = purge(storage.cooling,         "territory")
    storage.migration_queue = purge(storage.migration_queue, "territory")
    storage.migrating_units = purge(storage.migrating_units, "target_territory")

    refresh_overlay(unit.surface)
end)

-- Building placed inside an occupied territory → immediately enrage the resident.
script.on_event(defines.events.on_built_entity, function(e)
    local entity = e.entity
    if entity.surface.name ~= SURFACE_NAME then return end
    if entity.force.name == "enemy" then return end

    local territory = entity.surface.get_territory_for_chunk{
        x = math.floor(entity.position.x / 32),
        y = math.floor(entity.position.y / 32),
    }
    if not territory or not territory.valid then return end

    for _, unit in pairs(territory.get_segmented_units()) do
        if unit.valid then
            unit.activity_mode = defines.segmented_unit_activity_mode.full
            unit.set_ai_state{
                type             = defines.segmented_unit_ai_state.enraged_at_nothing,
                last_damage_time = game.tick,
                destination      = entity.position,
            }
        end
    end
end)


-- ─── Heartbeat: cooling → contested → dispatch → arrival ─────────────────────

script.on_nth_tick(CHECK_INTERVAL, function()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end

    local tick          = game.tick
    local grace         = grace_ticks()
    local delay         = delay_ticks()
    local chance        = migration_chance()
    local overlay_dirty = false

    -- 0. Drop stale overlay entries (territory re-occupied or no longer contested)
    if prune_stale(surface) then overlay_dirty = true end

    -- 0b. Fallback scan: catch contested territories the died-event missed
    --    (e.g. unit.territory was nil at event time, or stale storage after upgrade)
    for _, t in pairs(surface.get_territories()) do
        if not t.valid                                                    then goto next_scan end
        if is_occupied(t)                                                 then goto next_scan end
        if not is_contested(surface, t)                                   then goto next_scan end
        if in_list(storage.cooling,         "territory",        t)        then goto next_scan end
        if in_list(storage.migration_queue, "territory",        t)        then goto next_scan end
        if in_list(storage.migrating_units, "target_territory", t)        then goto next_scan end
        -- Untracked contested territory — enter cooling
        storage.cooling[#storage.cooling + 1] = {territory = t, emptied_tick = tick}
        ::next_scan::
    end

    -- 1. Graduate cooling → migration_queue once grace period expires
    local new_cooling = {}
    for _, entry in pairs(storage.cooling) do
        local t = entry.territory
        if not t or not t.valid or is_occupied(t) then goto next_cool end  -- stale

        if tick - entry.emptied_tick >= grace then
            -- Grace expired: promote to contested (if it still borders occupied land)
            if is_contested(surface, t)
            and not in_list(storage.migration_queue, "territory",        t)
            and not in_list(storage.migrating_units, "target_territory", t) then
                storage.migration_queue[#storage.migration_queue + 1] = {
                    territory      = t,
                    contested_tick = tick,
                }
                overlay_dirty = true
            end
            -- Don't keep in cooling either way — grace is done
        else
            new_cooling[#new_cooling + 1] = entry  -- still cooling
        end
        ::next_cool::
    end
    storage.cooling = new_cooling

    -- 2. Migration roll (fires at most once per interval_ticks)
    if tick >= storage.next_migration_tick then
        storage.next_migration_tick = tick + interval_ticks()

        local to_remove = {}
        for i, entry in pairs(storage.migration_queue) do
            local target = entry.territory
            if not target or not target.valid           then to_remove[#to_remove+1]=i; goto next_q end
            if is_occupied(target)                      then to_remove[#to_remove+1]=i; goto next_q end
            if tick - entry.contested_tick < delay      then                            goto next_q end
            if in_list(storage.migrating_units,
                       "target_territory", target)      then                            goto next_q end
            if math.random() > chance                   then                            goto next_q end

            -- Find an occupied neighbour to clone from
            local source
            for _, nb in pairs(get_neighbors(surface, target)) do
                if is_occupied(nb) then source = nb; break end
            end
            if not source then goto next_q end

            local src_units = source.get_segmented_units()
            if #src_units == 0 then goto next_q end

            local center     = territory_center(target)
            if not center then goto next_q end

            local origin_pos = get_head_pos(src_units[1])
            if not origin_pos then goto next_q end

            local migrant = src_units[1].clone{position = origin_pos}
            if not migrant then goto next_q end

            -- Send migrant walking toward contested territory center
            migrant.activity_mode = defines.segmented_unit_activity_mode.full
            migrant.set_ai_state{
                type        = defines.segmented_unit_ai_state.investigating,
                destination = center,
            }

            storage.migrating_units[#storage.migrating_units + 1] = {
                unit             = migrant,
                target_territory = target,
                target_pos       = center,
            }
            -- Yellow overlay persists — territory moves from queue to migrating_units
            to_remove[#to_remove + 1] = i
            ::next_q::
        end

        table.sort(to_remove, function(a, b) return a > b end)
        for _, i in pairs(to_remove) do table.remove(storage.migration_queue, i) end
    end

    -- 3. Arrival / death check for active migrants
    local remaining = {}
    for _, m in pairs(storage.migrating_units) do
        local unit = m.unit
        if not unit or not unit.valid then
            -- Migrant was killed. Return territory to migration_queue with a fresh timer
            -- so it stays contested and a new migrant will be sent after the delay.
            if m.target_territory and m.target_territory.valid
            and not is_occupied(m.target_territory)
            and not in_list(storage.migration_queue, "territory", m.target_territory) then
                storage.migration_queue[#storage.migration_queue + 1] = {
                    territory      = m.target_territory,
                    contested_tick = tick,  -- delay resets — player bought time
                }
            end
            overlay_dirty = true
        else
            local head = get_head_pos(unit)
            if head and dist(head, m.target_pos) <= ARRIVAL_RADIUS then
                -- Migrant arrived: claim the territory
                unit.territory = m.target_territory
                overlay_dirty  = true
                -- Unit is NOT added to remaining → removed from migrating_units
            else
                remaining[#remaining + 1] = m  -- still travelling
            end
        end
    end
    storage.migrating_units = remaining

    if overlay_dirty then refresh_overlay(surface) end
end)


-- ─── Commands ─────────────────────────────────────────────────────────────────

commands.add_command("dr-status", "Demolisher Rework: show current territory state", function()
    local p    = game.player
    local s    = game.surfaces[SURFACE_NAME]
    local tick = game.tick

    p.print(string.format(
        "[DR] cooling=%d  contested=%d  migrants=%d",
        #storage.cooling, #storage.migration_queue, #storage.migrating_units))

    p.print(string.format(
        "[DR] settings: grace=%.0fmin  delay=%.0fmin  interval=%.0fmin  chance=%.0f%%",
        grace_ticks()/3600, delay_ticks()/3600, interval_ticks()/3600, migration_chance()*100))

    local next_roll_ticks = storage.next_migration_tick - tick
    p.print(string.format(
        "[DR] next migration roll in %.1f min",
        math.max(0, next_roll_ticks) / 3600))

    for i, e in pairs(storage.cooling) do
        local left = math.max(0, (e.emptied_tick + grace_ticks()) - tick)
        p.print(string.format("  cool[%d]  %.1f min until contested", i, left / 3600))
    end
    for i, e in pairs(storage.migration_queue) do
        local left = math.max(0, (e.contested_tick + delay_ticks()) - tick)
        p.print(string.format("  queue[%d]  %.1f min until dispatch", i, left / 3600))
    end
    for i, m in pairs(storage.migrating_units) do
        local alive = m.unit and m.unit.valid
        local head  = alive and get_head_pos(m.unit) or nil
        local d     = head and math.floor(dist(head, m.target_pos)) or "?"
        p.print(string.format("  migrant[%d]  alive=%s  dist_to_center=%s", i, tostring(alive), tostring(d)))
    end

    if s then
        local occupied, empty, cont = 0, 0, 0
        for _, t in pairs(s.get_territories()) do
            if t.valid then
                if is_occupied(t) then occupied = occupied + 1
                else
                    empty = empty + 1
                    if is_contested(s, t) then cont = cont + 1 end
                end
            end
        end
        p.print(string.format(
            "[DR] territories: %d occupied | %d empty (%d contested, %d free)",
            occupied, empty, cont, empty - cont))
    end
end)

commands.add_command("dr-refresh", "Demolisher Rework: rebuild minimap overlay", function()
    local s = game.surfaces[SURFACE_NAME]
    if not s then game.player.print("[DR] Vulcanus not loaded"); return end
    refresh_overlay(s)
    game.player.print("[DR] overlay rebuilt  queue=" .. #storage.migration_queue
        .. "  migrants=" .. #storage.migrating_units)
end)

commands.add_command("dr-repop-now", "Demolisher Rework: zero all timers and force immediate migration", function()
    -- Backdate migration roll timer
    storage.next_migration_tick = 0
    -- Backdate contested entries so they pass the delay check
    for _, entry in pairs(storage.migration_queue) do
        entry.contested_tick = 0
    end
    -- Backdate cooling entries so they graduate immediately
    for _, entry in pairs(storage.cooling) do
        entry.emptied_tick = 0
    end
    game.player.print("[DR] all timers zeroed — will execute on next heartbeat (~5 sec)")
end)
