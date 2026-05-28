-- Demolisher Rework - runtime logic (requires Factorio 2.0.61+ territory API)
-- Migration-only repopulation: worms physically walk from occupied to contested territory.

local SURFACE_NAME         = "vulcanus"
local MIGRATION_MIN_WAIT   = 600       -- TEST: 10 sec before first roll (production: 36000 = 10 min)
local MIGRATION_INTERVAL   = 600       -- TEST: check every 10 sec (production: 36000 = 10 min)
local MIGRATION_CHANCE     = 1.0       -- TEST: always migrate (production: 0.25)
local ARRIVAL_CHECK        = 300       -- check migrant proximity every 5 sec
local ARRIVAL_RADIUS       = 48        -- tiles — claim territory when this close to center
-- storage.migration_queue:  array of {territory=LuaTerritory, tick=uint}
-- storage.migrating_units:  array of {unit=LuaSegmentedUnit, target_territory=LuaTerritory, target_pos=MapPosition}
-- storage.contested_overlays: array of LuaEntity (contested-territory-marker)


-- ─── Init ─────────────────────────────────────────────────────────────────────

script.on_init(function()
    storage.migration_queue    = {}
    storage.migrating_units    = {}
    storage.contested_overlays = {}
end)

script.on_load(function()
    storage.migration_queue    = storage.migration_queue    or {}
    storage.migrating_units    = storage.migrating_units    or {}
    storage.contested_overlays = storage.contested_overlays or {}
end)

script.on_configuration_changed(function()
    storage.migration_queue    = storage.migration_queue    or {}
    storage.migrating_units    = storage.migrating_units    or {}
    storage.contested_overlays = storage.contested_overlays or {}
    local vulcanus = game.surfaces[SURFACE_NAME]
    if vulcanus then refresh_state(vulcanus) end
end)


-- ─── Helpers ──────────────────────────────────────────────────────────────────

function get_neighboring_territories(surface, territory)
    local result = {}
    for _, chunk in pairs(territory.get_chunks()) do
        for _, off in pairs({{-1,0},{1,0},{0,-1},{0,1}}) do
            local neighbor = surface.get_territory_for_chunk({
                x = chunk.x + off[1], y = chunk.y + off[2]
            })
            if neighbor and neighbor.valid and neighbor ~= territory then
                local found = false
                for _, e in pairs(result) do if e == neighbor then found = true; break end end
                if not found then table.insert(result, neighbor) end
            end
        end
    end
    return result
end

function is_contested(surface, territory)
    if #territory.get_segmented_units() > 0 then return false end
    for _, neighbor in pairs(get_neighboring_territories(surface, territory)) do
        if neighbor.valid and #neighbor.get_segmented_units() > 0 then return true end
    end
    return false
end

function get_territory_center(territory)
    local chunks = territory.get_chunks()
    if #chunks == 0 then return nil end
    local sx, sy = 0, 0
    for _, chunk in pairs(chunks) do
        sx = sx + (chunk.area.left_top.x + chunk.area.right_bottom.x) / 2
        sy = sy + (chunk.area.left_top.y + chunk.area.right_bottom.y) / 2
    end
    return {x = sx / #chunks, y = sy / #chunks}
end

function dist(a, b)
    return math.sqrt((a.x-b.x)^2 + (a.y-b.y)^2)
end

-- LuaSegmentedUnit has no .position — head is get_body_nodes()[1]
function get_head_pos(unit)
    if not unit or not unit.valid then return nil end
    local nodes = unit.get_body_nodes()
    if nodes and #nodes > 0 then return nodes[1] end
    return nil
end

function is_being_migrated(territory)
    for _, m in pairs(storage.migrating_units) do
        if m.target_territory == territory then return true end
    end
    return false
end


-- ─── State refresh: overlays + migration queue ────────────────────────────────

function refresh_state(surface)
    -- Destroy old overlays
    for _, obj in pairs(storage.contested_overlays) do
        if obj and obj.valid then obj.destroy() end
    end
    storage.contested_overlays = {}

    -- Rebuild contested set and draw overlays
    local contested_set = {}
    for _, territory in pairs(surface.get_territories()) do
        if territory.valid and is_contested(surface, territory) then
            contested_set[territory] = true
            for _, chunk in pairs(territory.get_chunks()) do
                local cx = chunk.area.left_top.x + 16
                local cy = chunk.area.left_top.y + 16
                local marker = surface.create_entity{
                    name     = "contested-territory-marker",
                    position = {x = cx, y = cy},
                    force    = "neutral",
                }
                if marker then table.insert(storage.contested_overlays, marker) end
            end
        end
    end

    -- Sync migration queue
    local new_queue = {}
    local queued    = {}
    for _, entry in pairs(storage.migration_queue) do
        local t = entry.territory
        if t and t.valid and contested_set[t] then
            table.insert(new_queue, entry)
            queued[t] = true
        end
    end
    for territory in pairs(contested_set) do
        if not queued[territory] then
            table.insert(new_queue, {territory = territory, tick = game.tick})
        end
    end
    storage.migration_queue = new_queue
end


-- ─── Territory state events ───────────────────────────────────────────────────

script.on_event(defines.events.on_segmented_unit_died, function(e)
    local unit = e.segmented_unit
    if unit.surface.name ~= SURFACE_NAME then return end

    -- If this was a migrating unit, remove it from tracking
    local new_migrating = {}
    for _, m in pairs(storage.migrating_units) do
        if m.unit ~= unit then table.insert(new_migrating, m) end
    end
    storage.migrating_units = new_migrating

    refresh_state(unit.surface)
    game.print("[DR] unit died, state refreshed")
end)

script.on_event(defines.events.on_segmented_unit_created, function(e)
    local unit = e.segmented_unit
    if unit.surface.name ~= SURFACE_NAME then return end
    refresh_state(unit.surface)
end)


-- ─── Migration: roll for sending a worm from occupied to contested ─────────────

script.on_nth_tick(MIGRATION_INTERVAL, function()
    local vulcanus = game.surfaces[SURFACE_NAME]
    if not vulcanus then return end

    local to_remove = {}
    for i, entry in pairs(storage.migration_queue) do
        local target = entry.territory
        if not target or not target.valid then goto skip end
        if #target.get_segmented_units() > 0 then goto skip end          -- already occupied
        if game.tick - entry.tick < MIGRATION_MIN_WAIT then goto skip end -- too soon
        if is_being_migrated(target) then goto skip end                   -- already en route
        if math.random() > MIGRATION_CHANCE then goto skip end

        -- Find an occupied neighbor to migrate from
        local source = nil
        for _, neighbor in pairs(get_neighboring_territories(vulcanus, target)) do
            if neighbor.valid and #neighbor.get_segmented_units() > 0 then
                source = neighbor; break
            end
        end
        if not source then goto skip end

        local source_units = source.get_segmented_units()
        if #source_units == 0 then goto skip end

        local target_center = get_territory_center(target)
        if not target_center then goto skip end

        -- Clone at source worm's CURRENT head position, no territory assigned yet
        local origin = source_units[1]
        local origin_pos = get_head_pos(origin)
        if not origin_pos then goto skip end

        local migrant = origin.clone{
            position = origin_pos
            -- territory intentionally omitted — worm has no territory during travel
        }

        if not migrant then goto skip end

        -- Send it walking toward the contested territory center
        migrant.activity_mode = defines.segmented_unit_activity_mode.full
        migrant.set_ai_state({
            type        = defines.segmented_unit_ai_state.investigating,
            destination = target_center
        })

        table.insert(storage.migrating_units, {
            unit             = migrant,
            target_territory = target,
            target_pos       = target_center
        })

        game.print(string.format("[DR] migrant dispatched toward (%.0f, %.0f)",
            target_center.x, target_center.y))

        table.insert(to_remove, i)
        ::skip::
    end

    table.sort(to_remove, function(a, b) return a > b end)
    for _, i in pairs(to_remove) do table.remove(storage.migration_queue, i) end
end)


-- ─── Arrival check: claim territory when migrant reaches center ───────────────

script.on_nth_tick(ARRIVAL_CHECK, function()
    local vulcanus = game.surfaces[SURFACE_NAME]
    if not vulcanus then return end

    local remaining = {}
    for _, m in pairs(storage.migrating_units) do
        local unit = m.unit
        if not unit or not unit.valid then
            -- Migrant was killed — put territory back in queue if still contested
            if m.target_territory and m.target_territory.valid
            and is_contested(vulcanus, m.target_territory) then
                table.insert(storage.migration_queue, {
                    territory = m.target_territory,
                    tick      = game.tick
                })
            end
            goto continue
        end

        local head = get_head_pos(unit)
        if head and dist(head, m.target_pos) <= ARRIVAL_RADIUS then
            -- Arrived — claim the territory
            unit.territory = m.target_territory
            game.print("[DR] territory claimed!")
            -- refresh_state called via on_segmented_unit_created if territory triggers it
            -- but territory assignment may not fire that event, so call manually
            refresh_state(vulcanus)
            goto continue
        end

        table.insert(remaining, m)  -- still traveling
        ::continue::
    end
    storage.migrating_units = remaining
end)


-- ─── Build trigger: construction in occupied territory enrages the worm ───────

script.on_event(defines.events.on_built_entity, function(e)
    local entity = e.entity
    if entity.surface.name ~= SURFACE_NAME then return end
    if entity.force.name == "enemy" then return end

    local territory = entity.surface.get_territory_for_chunk({
        x = math.floor(entity.position.x / 32),
        y = math.floor(entity.position.y / 32)
    })
    if not territory or not territory.valid then return end

    local units = territory.get_segmented_units()
    if #units == 0 then return end

    for _, unit in pairs(units) do
        if unit.valid then
            unit.activity_mode = defines.segmented_unit_activity_mode.full
            unit.set_ai_state({
                type             = defines.segmented_unit_ai_state.enraged_at_nothing,
                last_damage_time = game.tick,
                destination      = entity.position
            })
        end
    end
end)


-- ─── Commands ─────────────────────────────────────────────────────────────────

commands.add_command("dr-status", "Demolisher Rework: territory state", function()
    local p = game.player
    local vulcanus = game.surfaces[SURFACE_NAME]
    p.print(string.format("[DR] migration_queue=%d  migrating=%d",
        #storage.migration_queue, #storage.migrating_units))
    for i, m in pairs(storage.migrating_units) do
        local alive = m.unit and m.unit.valid
        local head = alive and get_head_pos(m.unit) or nil
        local d = head and math.floor(dist(head, m.target_pos)) or "?"
        p.print(string.format("  migrant[%d] alive=%s dist_to_center=%s", i, tostring(alive), tostring(d)))
    end
    if vulcanus then
        local occupied, empty, cont = 0, 0, 0
        for _, t in pairs(vulcanus.get_territories()) do
            if t.valid then
                if #t.get_segmented_units() > 0 then occupied = occupied + 1
                else
                    empty = empty + 1
                    if is_contested(vulcanus, t) then cont = cont + 1 end
                end
            end
        end
        p.print(string.format("[DR] territories: %d occupied | %d empty (%d contested, %d free)",
            occupied, empty, cont, empty - cont))
    end
end)

commands.add_command("dr-refresh", "Demolisher Rework: rebuild overlays and sync queue", function()
    local vulcanus = game.surfaces[SURFACE_NAME]
    if not vulcanus then game.player.print("[DR] Vulcanus not loaded"); return end
    refresh_state(vulcanus)
    game.player.print("[DR] refreshed — " .. #storage.migration_queue .. " contested territories in queue")
end)

commands.add_command("dr-repop-now", "Demolisher Rework: force all contested territories to dispatch migrants now", function()
    local vulcanus = game.surfaces[SURFACE_NAME]
    if not vulcanus then game.player.print("[DR] Vulcanus not loaded"); return end
    -- Force minimum wait to 0 by backdating all queue entries
    for _, entry in pairs(storage.migration_queue) do
        entry.tick = 0
    end
    game.player.print("[DR] all queue entries backdated — migration will roll on next interval")
end)
