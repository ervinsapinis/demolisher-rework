-- Demolisher Rework - runtime logic (Factorio 2.0.61+ territory API)
--
-- Territory lifecycle:
--   occupied (red) -> [worm dies] -> cooling (no overlay, grace period)
--                  -> contested (yellow overlay, migration delay)
--                  -> migrant dispatched (yellow persists, worm travels)
--                  -> occupied again (red) once migrant arrives
--
-- v0.3.0 systems:
--   Seismograph coverage: all map overlays (red/yellow/violet) render only
--     inside the radius of a powered dr-seismograph. Migrants entering
--     coverage fire a one-time alert.
--   Effigies (3 tiers): a headed effigy makes neighbours up to its own tier
--     believe its territory is occupied. Small eats nothing (head just rots);
--     medium eats calcite + tungsten while there is an audience; big needs
--     constant power. When upkeep lapses on an otherwise-valid effigy a silence
--     window runs before the deception collapses ("exposure"): the territory is
--     queued at a reduced delay. An effigy that is undersized (a bigger worm
--     moved in next door) simply stops fooling anyone, with no silence window;
--     the migrant it can't deceive walks in and physically destroys it.
--   Escalation: demolishers gain effective HP with distance from the map
--     origin and with every demolisher killed (capped), via heal-back on
--     segment damage.

local SURFACE_NAME   = "vulcanus"
local CHECK_INTERVAL = 300    -- heartbeat every 5 sec (fixed)
local ARRIVAL_RADIUS = 48     -- tiles: claim territory when head is this close to center

-- Overlay tints (applied to the white chunk sprites at runtime)
local FILL_COLOR     = {r = 0.0,   g = 0.0,   b = 0.0,   a = 0.0}
local CONTESTED_TINT = {r = 1.000, g = 0.698, b = 0.400, a = 1.0}  -- #FFB266
local OCCUPIED_TINT  = {r = 1.000, g = 0.300, b = 0.250, a = 1.0}  -- red (replaces hidden vanilla)
local EFFIGY_TINT    = {r = 0.720, g = 0.450, b = 1.000, a = 1.0}  -- violet (your lies, on the map)
local BORDER_WIDTH   = 64

local TIER_RANK = {["small-demolisher"] = 1, ["medium-demolisher"] = 2, ["big-demolisher"] = 3}

-- The diagonal: one building per tier, one mountable head per building.
local EFFIGY_TIER    = {["dr-effigy-small"] = 1, ["dr-effigy-medium"] = 2, ["dr-effigy-big"] = 3}
local MOUNT_ITEM     = {"dr-head-small-raw", "dr-head-medium-embalmed", "dr-head-big-cryo"}
local MOUNTED_SPRITE = {"dr-effigy-small-mounted", "dr-effigy-medium-mounted", "dr-effigy-big-mounted"}

-- Effigy condition (reg.status) is tracked for /dr-status only; there is no
-- floating in-world text. The player reads effigy state from the world (mounted
-- vs empty sprite, a worm arriving to crush a failed one) and the map overlay.


-- --- Runtime setting accessors (ticks at 60 UPS) ------------------------------

local function grace_ticks()    return settings.global["dr-grace-period-min"].value * 3600 end
local function delay_ticks()    return settings.global["dr-migration-delay-min"].value * 3600 end
local function interval_ticks() return settings.global["dr-migration-interval-min"].value * 3600 end
local function migration_chance() return settings.global["dr-migration-chance"].value end

local function seismo_radius_chunks() return settings.global["dr-seismo-radius-chunks"].value end
local function head_drop_chance()     return settings.global["dr-head-drop-chance"].value end
local function silence_ticks()        return math.floor(settings.global["dr-silence-window-min"].value * 3600) end
local function exposure_factor()      return settings.global["dr-exposure-delay-factor"].value end
local function feed_per_min()         return settings.global["dr-feed-per-min"].value end
local function esc_dist_per_km()      return settings.global["dr-esc-distance-per-km"].value end
local function esc_per_kill()         return settings.global["dr-esc-per-kill"].value end
local function esc_kill_cap()         return settings.global["dr-esc-kill-cap"].value end

local hide_vanilla = settings.startup["dr-hide-vanilla-territory"].value


-- --- Storage layout ------------------------------------------------------------
--
-- storage.cooling             {territory, emptied_tick}[]
-- storage.migration_queue     {territory, contested_tick}[]   <- yellow
-- storage.migrating_units     {unit, target_territory, target_pos}[]
-- storage.contested_renders   LuaRenderObject[]
-- storage.next_migration_tick uint
-- storage.seismographs        {unit_number -> LuaEntity}
-- storage.effigies            {unit_number -> reg}; reg = {entity, tier, eei,
--                              feed_acc, suppressing, status, silence_until,
--                              territory, overlay}
-- storage.alerted             {unit}[]  migrants already announced
-- storage.kills               uint      lifetime demolisher kills (the grudge)
-- storage.coverage_sig        string    change detector for seismo network
-- storage.debug_reveal        bool      /dr-reveal: bypass coverage gating
-- storage.esc_off             bool      escalation API probe failed; disabled

local function init_storage()
    -- Destroy mounted-overlay render objects owned by existing effigies before
    -- the table is wiped, or they leak (persist orphaned across a config change
    -- / mod update).
    if storage.effigies then
        for _, reg in pairs(storage.effigies) do
            if reg.overlay and reg.overlay.valid then reg.overlay.destroy() end
        end
    end

    storage.cooling             = {}
    storage.migration_queue     = {}
    storage.migrating_units     = {}
    storage.contested_renders   = storage.contested_renders or {}
    storage.next_migration_tick = 0
    storage.seismographs        = {}
    storage.effigies            = {}
    storage.alerted             = {}
    storage.kills               = storage.kills or 0
    storage.coverage_sig        = ""
    storage.debug_reveal        = storage.debug_reveal or false
    storage.esc_off             = false
end

-- Rebuild entity registries from the world (used on init and config change).
local function rescan_entities()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end
    for _, ent in pairs(surface.find_entities_filtered{name = "dr-seismograph"}) do
        storage.seismographs[ent.unit_number] = ent
    end
    for name, tier in pairs(EFFIGY_TIER) do
        for _, ent in pairs(surface.find_entities_filtered{name = name}) do
            storage.effigies[ent.unit_number] = {
                entity = ent, tier = tier, feed_acc = 0, suppressing = false, status = "new",
            }
            pcall(function()
                local inv = ent.get_inventory(defines.inventory.chest)
                if inv then
                    inv.set_filter(1, MOUNT_ITEM[tier])
                    if tier == 2 then
                        inv.set_filter(2, "calcite")
                        inv.set_filter(3, "tungsten-plate")
                    end
                end
            end)
        end
    end
    -- Orphaned power interfaces (their effigy regs were just wiped): recreated
    -- on demand by the heartbeat, so clear them all.
    for _, ent in pairs(surface.find_entities_filtered{name = "dr-effigy-power"}) do
        ent.destroy()
    end
end

script.on_init(function()
    init_storage()
    rescan_entities()
end)

-- on_load must NOT write to storage - fires on every load of an existing save.
script.on_load(function() end)

script.on_configuration_changed(function()
    -- Full reinit of pipeline lists: old saves may have differently-structured
    -- entries; stale fields cause silent arithmetic-on-nil in the heartbeat.
    -- Kill counter survives (the grudge is eternal).
    init_storage()
    rescan_entities()
    local s = game.surfaces[SURFACE_NAME]
    if s then refresh_overlay(s) end
end)


-- --- Generic helpers -------------------------------------------------------------

local function get_head_pos(unit)
    if not unit or not unit.valid then return nil end
    local nodes = unit.get_body_nodes()
    return (nodes and #nodes > 0) and nodes[1] or nil
end

-- LuaSegmentedUnit has no .name; the prototype carries it. pcall-guarded so an
-- API difference degrades to "unknown unit" instead of a crash.
local function unit_name(unit)
    if not (unit and unit.valid) then return nil end
    local ok, name = pcall(function() return unit.prototype.name end)
    if ok and name then return name end
    local ok2, name2 = pcall(function() return unit.name end)
    if ok2 then return name2 end
    return nil
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

local function has_occupied_neighbor(surface, territory)
    for _, n in pairs(get_neighbors(surface, territory)) do
        if is_occupied(n) then return true end
    end
    return false
end

-- Highest tier rank among occupied neighbours (0 = no occupied neighbours)
local function max_neighbor_rank(surface, territory)
    local max_rank = 0
    for _, n in pairs(get_neighbors(surface, territory)) do
        if is_occupied(n) then
            for _, u in pairs(n.get_segmented_units()) do
                local r = TIER_RANK[unit_name(u) or ""] or 0
                if r > max_rank then max_rank = r end
            end
        end
    end
    return max_rank
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

local function territory_of_position(surface, pos)
    return surface.get_territory_for_chunk{
        x = math.floor(pos.x / 32),
        y = math.floor(pos.y / 32),
    }
end


-- --- Effigy suppression ----------------------------------------------------------

-- True if an active effigy is currently fooling the neighbours of this territory.
-- reg.suppressing and reg.territory are refreshed every heartbeat.
local function territory_suppressed(territory)
    for _, reg in pairs(storage.effigies) do
        if reg.suppressing and reg.territory == territory then return true end
    end
    return false
end

-- Suppression-aware contested check: an effigy-held territory is "occupied"
-- as far as the neighbours know.
local function is_contested(surface, territory)
    if is_occupied(territory) then return false end
    if territory_suppressed(territory) then return false end
    return has_occupied_neighbor(surface, territory)
end


-- --- Effigy state machine ---------------------------------------------------------

-- Native slot filters enforce the diagonal physically: the wrong head will
-- not go into the slot, same mechanism that keeps coal out of a lab.
-- Slot 1 = the tier's mountable head; medium adds 2 = calcite, 3 = tungsten.
local function setup_effigy_inventory(ent, tier)
    local inv = ent.get_inventory(defines.inventory.chest)
    if not inv then return end
    pcall(function()
        inv.set_filter(1, MOUNT_ITEM[tier])
        if tier == 2 then
            inv.set_filter(2, "calcite")
            inv.set_filter(3, "tungsten-plate")
        end
    end)
end

-- The deception collapsed with witnesses present: queue the territory at a
-- reduced migration delay. The neighbours noticed the silence.
local function expose_territory(surface, territory)
    if not (territory and territory.valid) then return false end
    if is_occupied(territory) then return false end
    if not has_occupied_neighbor(surface, territory) then return false end

    -- Pull it out of cooling: exposure skips the grace period entirely.
    local keep = {}
    for _, e in pairs(storage.cooling) do
        if e.territory ~= territory then keep[#keep + 1] = e end
    end
    storage.cooling = keep

    if not in_list(storage.migration_queue, "territory", territory)
    and not in_list(storage.migrating_units, "target_territory", territory) then
        local head_start = math.floor(delay_ticks() * (1 - exposure_factor()))
        storage.migration_queue[#storage.migration_queue + 1] = {
            territory      = territory,
            contested_tick = game.tick - head_start,
        }
        local c = territory_center(territory)
        if c then
            game.print(string.format(
                "[color=red][Effigy][/color] The deception has collapsed at [gps=%d,%d,%s]. The neighbours are coming sooner.",
                math.floor(c.x), math.floor(c.y), SURFACE_NAME))
        end
    end
    return true
end

local function destroy_effigy_reg(reg)
    if reg.eei and reg.eei.valid then reg.eei.destroy() end
    if reg.overlay and reg.overlay.valid then reg.overlay.destroy() end
end

-- Does this effigy currently have its tier's head socketed?
local function effigy_has_head(reg)
    local ent = reg.entity
    if not (ent and ent.valid) then return false end
    local inv = ent.get_inventory(defines.inventory.chest)
    return inv and inv.get_item_count(MOUNT_ITEM[reg.tier or EFFIGY_TIER[ent.name] or 1]) > 0
end

-- A headed effigy inside this territory, if any (the lie a migrant homes in on).
local function find_headed_effigy(surface, territory)
    for _, reg in pairs(storage.effigies) do
        local ent = reg.entity
        if ent and ent.valid
        and territory_of_position(surface, ent.position) == territory
        and effigy_has_head(reg) then
            return ent
        end
    end
    return nil
end

-- An arriving demolisher crushes any headed effigy in the territory it claims:
-- the fake is exposed and physically destroyed. Empty effigies are left alone.
local function crush_effigies_in(surface, territory)
    local victims = {}
    for _, reg in pairs(storage.effigies) do
        local ent = reg.entity
        if ent and ent.valid
        and territory_of_position(surface, ent.position) == territory
        and effigy_has_head(reg) then
            victims[#victims + 1] = ent
        end
    end
    for _, ent in pairs(victims) do
        if ent.valid then ent.die() end   -- on_entity_died cleans the registry
    end
    return #victims > 0
end

-- Per-heartbeat update of one effigy. Returns true if overlay state changed.
local function update_effigy(surface, un, reg, tick)
    local ent = reg.entity
    if not (ent and ent.valid) then
        -- Effigy was destroyed outside the tracked removal events
        local dirty = reg.suppressing and expose_territory(surface, reg.territory)
        destroy_effigy_reg(reg)
        storage.effigies[un] = nil
        return dirty or reg.suppressing
    end

    reg.territory = territory_of_position(surface, ent.position)

    local tier = reg.tier or EFFIGY_TIER[ent.name] or 1
    reg.tier = tier

    local inv      = ent.get_inventory(defines.inventory.chest)
    local has_head = inv and inv.get_item_count(MOUNT_ITEM[tier]) > 0

    local audience_rank = reg.territory and max_neighbor_rank(surface, reg.territory) or 0
    -- An effigy fools neighbours only up to its own tier. A bigger worm next
    -- door was never deceived; it will migrate in and physically destroy the
    -- effigy on arrival (see crush_effigies_in + migrant targeting). Big
    -- effigies (tier 3) can never be undersized.
    local big_enough = tier >= audience_rank

    -- Upkeep per tier: 1 = raw head, rot handled by native spoilage;
    -- 2 = embalmed, eats calcite + tungsten while there is an audience;
    -- 3 = cryo, constant power via the hidden interface.
    -- Skipped when undersized: no point feeding a lie nobody believes.
    local upkeep_ok, fail_status = false, "no-head"
    if has_head and not big_enough then
        fail_status = "undersized"
    elseif has_head then
        if tier == 1 then
            upkeep_ok = true
        elseif tier == 2 then
            if audience_rank == 0 then
                upkeep_ok = true   -- nobody listening, nothing consumed
            else
                reg.feed_acc = (reg.feed_acc or 0) + feed_per_min() * (CHECK_INTERVAL / 3600)
                local need = math.floor(reg.feed_acc)
                if need < 1 then
                    upkeep_ok = true
                elseif inv.get_item_count("calcite") >= need
                   and inv.get_item_count("tungsten-plate") >= need then
                    inv.remove({name = "calcite",        count = need})
                    inv.remove({name = "tungsten-plate", count = need})
                    reg.feed_acc = reg.feed_acc - need
                    upkeep_ok = true
                else
                    fail_status = "starving"
                end
            end
        elseif tier == 3 then
            -- The hidden interface draws the configured MW from the grid via its
            -- baked-in energy_usage; we only read its buffer to judge "powered".
            -- Created full so a freshly-socketed head reads powered immediately;
            -- a sustained brownout drains the ~5 s buffer, then "unpowered".
            if not (reg.eei and reg.eei.valid) then
                reg.eei = surface.create_entity{
                    name = "dr-effigy-power", position = ent.position, force = ent.force,
                }
                if reg.eei then
                    reg.eei.destructible = false
                    reg.eei.energy       = reg.eei.electric_buffer_size  -- start full
                end
            end
            if reg.eei and reg.eei.valid then
                if reg.eei.energy >= reg.eei.electric_buffer_size * 0.15 then
                    upkeep_ok = true
                else
                    fail_status = "unpowered"
                end
            else
                fail_status = "unpowered"
            end
        end
    end

    -- Power interface only exists while a head is socketed in a big effigy
    if (tier ~= 3 or not has_head) and reg.eei and reg.eei.valid then
        reg.eei.destroy()
        reg.eei = nil
    end

    -- Mounted-state visual: overlay sprite while a head is socketed
    if has_head then
        if not (reg.overlay and reg.overlay.valid) then
            reg.overlay = rendering.draw_sprite{
                sprite       = MOUNTED_SPRITE[tier],
                target       = ent,
                surface      = surface,
                render_layer = "object",
            }
        end
    elseif reg.overlay and reg.overlay.valid then
        reg.overlay.destroy()
        reg.overlay = nil
    end

    local was_suppressing = reg.suppressing
    local old_status      = reg.status
    local new_status

    if has_head and big_enough and upkeep_ok then
        reg.silence_until = nil
        reg.suppressing   = true
        new_status        = "active"
    elseif was_suppressing and big_enough then
        -- A valid effigy that just lost its upkeep (or had its head pulled):
        -- it keeps fooling the neighbours through a silence window, giving the
        -- player time to restock / re-power / re-socket before exposure.
        reg.silence_until = reg.silence_until or (tick + silence_ticks())
        if tick >= reg.silence_until then
            reg.suppressing   = false
            reg.silence_until = nil
            new_status        = "exposed"
            expose_territory(surface, reg.territory)
        else
            new_status = "silent"
        end
    else
        -- Empty, or undersized: no suppression, no silence window, no nagging.
        -- The territory is simply contested; migration will bring a worm that
        -- destroys the effigy when it arrives.
        reg.suppressing   = false
        reg.silence_until = nil
        new_status        = fail_status
    end

    reg.status = new_status

    -- One-time warning on degradation while still suppressing
    if new_status == "silent" and old_status ~= "silent" then
        local cause = "head lost"
        if has_head then
            cause = (fail_status == "starving") and "starving" or "no power"
        end
        game.print(string.format(
            "[color=orange][Effigy][/color] Effigy at [gps=%d,%d,%s] has gone silent (%s). The neighbours will notice.",
            math.floor(ent.position.x), math.floor(ent.position.y), SURFACE_NAME, cause))
    end

    return reg.suppressing ~= was_suppressing
end


-- --- Seismograph coverage ---------------------------------------------------------

-- List of {x, y, r2} for every powered seismograph; quality widens the radius.
local function active_seismographs()
    local list = {}
    local base = seismo_radius_chunks()
    for un, ent in pairs(storage.seismographs) do
        if not (ent and ent.valid) then
            storage.seismographs[un] = nil
        elseif ent.energy > 0 then
            local qlevel = 0
            local ok, q = pcall(function() return ent.quality end)
            if ok and q then qlevel = q.level end
            local r = (base + 2 * qlevel) * 32
            list[#list + 1] = {x = ent.position.x, y = ent.position.y, r2 = r * r, un = un, rc = base + 2 * qlevel}
        end
    end
    return list
end

local function coverage_signature(seismos)
    local parts = {}
    for _, s in pairs(seismos) do
        parts[#parts + 1] = s.un .. ":" .. s.rc
    end
    table.sort(parts)
    return table.concat(parts, ",")
end

local function make_covered_fn(seismos)
    if storage.debug_reveal then
        return function() return true end
    end
    return function(cx, cy)
        local px, py = cx * 32 + 16, cy * 32 + 16
        for _, s in pairs(seismos) do
            local dx, dy = px - s.x, py - s.y
            if dx * dx + dy * dy <= s.r2 then return true end
        end
        return false
    end
end

-- Territory-granularity detection: a seismograph hears the WORM, and the worm
-- patrols its whole territory, so hearing any part of it reveals the full
-- shape, even into uncharted darkness. The seismograph is a creature sense,
-- not a second radar.
local function territory_covered(territory, covered)
    for _, chunk in pairs(territory.get_chunks()) do
        if covered(chunk.x, chunk.y) then return true end
    end
    return false
end


-- --- Stale-entry pruning ------------------------------------------------------------

-- Queue entries: dropped when re-occupied, no longer contested, or suppressed
-- by an effigy (is_contested is suppression-aware).
-- Walking migrants: committed. They only die when orphaned outright (territory
-- re-occupied or ALL occupied neighbours gone). An effigy activating mid-flight
-- does NOT recall them: it heard the silence before the lie began.
local function prune_stale(surface)
    local dirty = false

    local q2 = {}
    for _, e in pairs(storage.migration_queue) do
        local t = e.territory
        if t and t.valid and not is_occupied(t) and is_contested(surface, t) then
            q2[#q2 + 1] = e
        else
            dirty = true
        end
    end
    storage.migration_queue = q2

    local m2 = {}
    for _, m in pairs(storage.migrating_units) do
        local t = m.target_territory
        if t and t.valid and not is_occupied(t) and has_occupied_neighbor(surface, t) then
            m2[#m2 + 1] = m
        else
            if m.unit and m.unit.valid then m.unit.die() end
            dirty = true
        end
    end
    storage.migrating_units = m2

    return dirty
end


-- --- Minimap overlay (render_mode = "chart") ----------------------------------------
--
-- Three layers, all gated by charted status AND seismograph coverage:
--   red    = occupied territories (only when vanilla red is hidden)
--   yellow = contested (migration queue + active migrant targets)
--   violet = effigy-held (your own lies, marked so you don't forget them)

function refresh_overlay(surface)
    for _, obj in pairs(storage.contested_renders) do
        if obj and obj.valid then obj.destroy() end
    end
    storage.contested_renders = {}

    local seismos = active_seismographs()
    local covered = make_covered_fn(seismos)

    -- Classify territories. Violet wins over yellow; occupied can't be either.
    -- Coverage is per-TERRITORY: hearing any part of a worm's patrol reveals
    -- the whole shape, charted or not. No charting requirement: seismic data
    -- does not need eyes.
    local entries, seen = {}, {}   -- entries: {territory, class}
    local function add(t, class)
        if t and t.valid and not seen[t] and territory_covered(t, covered) then
            seen[t] = true
            entries[#entries + 1] = {territory = t, class = class}
        end
    end

    for _, reg in pairs(storage.effigies) do
        if reg.suppressing then add(reg.territory, "effigy") end
    end
    for _, e in pairs(storage.migration_queue) do
        local t = e.territory
        if t and t.valid and not is_occupied(t) then add(t, "contested") end
    end
    for _, m in pairs(storage.migrating_units) do
        local t = m.target_territory
        if t and t.valid and not is_occupied(t) then add(t, "contested") end
    end
    if hide_vanilla then
        for _, t in pairs(surface.get_territories()) do
            if t.valid and is_occupied(t) then add(t, "occupied") end
        end
    end

    if #entries == 0 then return end

    -- chunk -> entry index, for border edge detection (all classes: red
    -- territories get borders too, so adjacent worms read as separate)
    local cs = {}
    for ei, entry in ipairs(entries) do
        for _, chunk in pairs(entry.territory.get_chunks()) do
            if not cs[chunk.x] then cs[chunk.x] = {} end
            cs[chunk.x][chunk.y] = ei
        end
    end

    local renders = storage.contested_renders
    for ei, entry in ipairs(entries) do
        local tint = (entry.class == "occupied" and OCCUPIED_TINT)
                  or (entry.class == "effigy"   and EFFIGY_TINT)
                  or CONTESTED_TINT

        for _, chunk in pairs(entry.territory.get_chunks()) do
            local cx, cy = chunk.x, chunk.y
            local lt = chunk.area.left_top
            local rb = chunk.area.right_bottom

            if FILL_COLOR.a > 0 then
                renders[#renders + 1] = rendering.draw_rectangle{
                    color = FILL_COLOR, filled = true,
                    left_top = lt, right_bottom = rb,
                    surface = surface, render_mode = "chart",
                }
            end

            -- Diagonal hazard stripes: pre-rendered sprites, 64-tile period.
            -- Two phase variants selected by (cx-cy) % 2 keep the pattern
            -- seamless across chunk boundaries with zero geometry code.
            renders[#renders + 1] = rendering.draw_sprite{
                sprite      = "dr-contested-chunk-" .. ((cx - cy) % 2),
                target      = {x = (lt.x + rb.x) * 0.5, y = (lt.y + rb.y) * 0.5},
                surface     = surface,
                tint        = tint,
                render_mode = "chart",
            }

            local w = 0.25
            local function edge(nx, ny)
                local nei = cs[nx] and cs[nx][ny]
                return not nei or nei ~= ei
            end
            if edge(cx, cy - 1) then
                renders[#renders + 1] = rendering.draw_line{
                    color = tint, width = BORDER_WIDTH,
                    from = {lt.x - w, lt.y}, to = {rb.x + w, lt.y},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx, cy + 1) then
                renders[#renders + 1] = rendering.draw_line{
                    color = tint, width = BORDER_WIDTH,
                    from = {lt.x - w, rb.y}, to = {rb.x + w, rb.y},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx - 1, cy) then
                renders[#renders + 1] = rendering.draw_line{
                    color = tint, width = BORDER_WIDTH,
                    from = {lt.x, lt.y - w}, to = {lt.x, rb.y + w},
                    surface = surface, render_mode = "chart",
                }
            end
            if edge(cx + 1, cy) then
                renders[#renders + 1] = rendering.draw_line{
                    color = tint, width = BORDER_WIDTH,
                    from = {rb.x, lt.y - w}, to = {rb.x, rb.y + w},
                    surface = surface, render_mode = "chart",
                }
            end
        end
    end
end


-- --- Events --------------------------------------------------------------------------

-- Resident worm died -> head drop, kill counter, instant ethology, cooling phase.
-- Migrant deaths are handled in the heartbeat arrival-check instead.
script.on_event(defines.events.on_segmented_unit_died, function(e)
    local unit = e.segmented_unit
    if not unit or not unit.valid then return end
    if unit.surface.name ~= SURFACE_NAME then return end

    local surface = unit.surface

    -- The grudge is eternal (escalation counter; migrants count too)
    local uname = unit_name(unit)
    if uname and TIER_RANK[uname] then
        storage.kills = storage.kills + 1

        -- Field studies: the first kill makes ethology RESEARCHABLE.
        -- You cannot study what you have not dissected.
        local force = game.forces["player"]
        if force then
            local tech = force.technologies["dr-demolisher-ethology"]
            if tech and not tech.enabled and not tech.researched then
                tech.enabled = true
                game.print("[color=yellow][Demolisher Rework][/color] Field observations recorded. Demolisher ethology is now available for research.")
            end
        end

        -- Head drop (skipped if the body is already gone and we have no position)
        local pos = get_head_pos(unit)
        if pos and math.random() < head_drop_chance() then
            local size = uname:match("^(%a+)%-demolisher$")
            local item = "dr-head-" .. size .. "-raw"
            local stack = {name = item, count = 1}
            local okq, q = pcall(function() return unit.quality end)
            if okq and q then stack.quality = q.name end
            local ok = pcall(function()
                surface.spill_item_stack{position = pos, stack = stack, allow_belts = false}
            end)
            if not ok then
                pcall(function()
                    surface.spill_item_stack{position = pos, stack = {name = item, count = 1}, allow_belts = false}
                end)
            end
        end
    end

    -- Skip tracked migrants (heartbeat re-queues their target territory)
    if in_list(storage.migrating_units, "unit", unit) then return end

    -- Try to get territory from the unit; fall back to position-based lookup
    local territory = unit.territory
    if not territory or not territory.valid then
        local pos = get_head_pos(unit)
        if pos then territory = territory_of_position(surface, pos) end
    end
    if not territory or not territory.valid then return end

    -- Confirm territory is now empty (dead unit is already removed)
    if #territory.get_segmented_units() > 0 then return end

    if not in_list(storage.cooling,          "territory",        territory)
    and not in_list(storage.migration_queue,  "territory",        territory)
    and not in_list(storage.migrating_units,  "target_territory", territory) then
        storage.cooling[#storage.cooling + 1] = {
            territory    = territory,
            emptied_tick = game.tick,
        }
    end

    -- A death in territory X may free territories that were contested only
    -- because X was occupied. Prune immediately so the overlay updates at once.
    prune_stale(surface)
    refresh_overlay(surface)
end)

-- New unit created -> if it has a territory, clear that territory from all queues.
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

-- Escalation: demolishers gain effective HP with distance from origin and
-- with the lifetime kill count, via heal-back on segment damage.
-- API access is probed defensively; on failure the feature self-disables.
script.on_event(defines.events.on_entity_damaged, function(e)
    if storage.esc_off then return end
    local ent = e.entity
    if not (ent and ent.valid) then return end
    if ent.surface.name ~= SURFACE_NAME then return end
    local fd = e.final_damage_amount
    if not fd or fd <= 0 then return end

    local ok, unit = pcall(function() return ent.segmented_unit end)
    if not ok then storage.esc_off = true; return end
    if not (unit and unit.valid) then return end
    if not TIER_RANK[unit_name(unit) or ""] then return end

    local p = ent.position
    local dist_km = math.sqrt(p.x * p.x + p.y * p.y) / 1000
    local factor  = 1 + esc_dist_per_km() * dist_km
                      + math.min(storage.kills * esc_per_kill(), esc_kill_cap())
    if factor <= 1.001 then return end

    local heal = fd * (1 - 1 / factor)
    local ok2 = pcall(function()
        local h = unit.health + heal
        -- max_health may not exist on LuaSegmentedUnit; clamp only if readable
        local okm, mh = pcall(function() return unit.max_health end)
        if okm and mh and h > mh then h = mh end
        unit.health = h
    end)
    if not ok2 then storage.esc_off = true end
end, {{filter = "type", type = "segment"}})

-- Registration of our buildings + build-trigger enrage.
local function register_built(ent)
    if not (ent and ent.valid) then return end
    if ent.name == "dr-seismograph" then
        storage.seismographs[ent.unit_number] = ent
        storage.coverage_sig = ""   -- force overlay refresh next heartbeat
    elseif EFFIGY_TIER[ent.name] then
        local tier = EFFIGY_TIER[ent.name]
        storage.effigies[ent.unit_number] = {
            entity = ent, tier = tier, feed_acc = 0, suppressing = false, status = "new",
        }
        setup_effigy_inventory(ent, tier)
    end
end

script.on_event(defines.events.on_built_entity, function(e)
    local entity = e.entity
    if entity.surface.name ~= SURFACE_NAME then return end
    if entity.force.name == "enemy" then return end

    register_built(entity)

    -- Building placed inside an occupied territory -> enrage the resident.
    local territory = territory_of_position(entity.surface, entity.position)
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

local built_filter = {{filter = "name", name = "dr-seismograph"},
                      {filter = "name", name = "dr-effigy-small"},
                      {filter = "name", name = "dr-effigy-medium"},
                      {filter = "name", name = "dr-effigy-big"}}

script.on_event(defines.events.on_robot_built_entity, function(e)
    if e.entity.surface.name ~= SURFACE_NAME then return end
    register_built(e.entity)
end, built_filter)

script.on_event(defines.events.script_raised_built, function(e)
    if e.entity.surface.name ~= SURFACE_NAME then return end
    register_built(e.entity)
end, built_filter)

script.on_event(defines.events.script_raised_revive, function(e)
    if e.entity.surface.name ~= SURFACE_NAME then return end
    register_built(e.entity)
end, built_filter)

-- Removal: any end of an actively-suppressing effigy is an immediate exposure
-- (no silence window: the structure itself is gone, the lie collapses at once).
-- Mined effigies still return their socketed head via normal container drops.
local function register_removed(ent)
    if not (ent and ent.valid) then return end
    if ent.name == "dr-seismograph" then
        storage.seismographs[ent.unit_number] = nil
        storage.coverage_sig = ""
    elseif EFFIGY_TIER[ent.name] then
        local reg = storage.effigies[ent.unit_number]
        if reg then
            if reg.suppressing then
                expose_territory(ent.surface, reg.territory)
            end
            destroy_effigy_reg(reg)
            storage.effigies[ent.unit_number] = nil
        end
    end
end

for _, ev in pairs{
    defines.events.on_entity_died,
    defines.events.on_player_mined_entity,
    defines.events.on_robot_mined_entity,
    defines.events.script_raised_destroy,
} do
    script.on_event(ev, function(e)
        register_removed(e.entity)
    end, built_filter)
end


-- --- Heartbeat: effigies -> pruning -> cooling -> dispatch -> arrival -> alerts ----

script.on_nth_tick(CHECK_INTERVAL, function()
    local surface = game.surfaces[SURFACE_NAME]
    if not surface then return end

    local tick          = game.tick
    local grace         = grace_ticks()
    local delay         = delay_ticks()
    local chance        = migration_chance()
    local overlay_dirty = false

    -- E. Effigy state machines (may fire exposures into the queue)
    for un, reg in pairs(storage.effigies) do
        if update_effigy(surface, un, reg, tick) then overlay_dirty = true end
    end

    -- 0. Drop stale overlay entries (re-occupied / no longer contested / suppressed)
    if prune_stale(surface) then overlay_dirty = true end

    -- 0b. Fallback scan: catch contested territories the died-event missed
    for _, t in pairs(surface.get_territories()) do
        if not t.valid                                                    then goto next_scan end
        if is_occupied(t)                                                 then goto next_scan end
        if not is_contested(surface, t)                                   then goto next_scan end
        if in_list(storage.cooling,         "territory",        t)        then goto next_scan end
        if in_list(storage.migration_queue, "territory",        t)        then goto next_scan end
        if in_list(storage.migrating_units, "target_territory", t)        then goto next_scan end
        storage.cooling[#storage.cooling + 1] = {territory = t, emptied_tick = tick}
        ::next_scan::
    end

    -- 1. Graduate cooling -> migration_queue once grace period expires
    local new_cooling = {}
    for _, entry in pairs(storage.cooling) do
        local t = entry.territory
        if not t or not t.valid or is_occupied(t) then goto next_cool end

        if tick - entry.emptied_tick >= grace then
            if is_contested(surface, t)
            and not in_list(storage.migration_queue, "territory",        t)
            and not in_list(storage.migrating_units, "target_territory", t) then
                storage.migration_queue[#storage.migration_queue + 1] = {
                    territory      = t,
                    contested_tick = tick,
                }
                overlay_dirty = true
            end
        else
            new_cooling[#new_cooling + 1] = entry
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
            if territory_suppressed(target)             then to_remove[#to_remove+1]=i; goto next_q end
            if tick - entry.contested_tick < delay      then                            goto next_q end
            if in_list(storage.migrating_units,
                       "target_territory", target)      then                            goto next_q end
            if math.random() > chance                   then                            goto next_q end

            local source
            for _, nb in pairs(get_neighbors(surface, target)) do
                if is_occupied(nb) then source = nb; break end
            end
            if not source then goto next_q end

            local src_units = source.get_segmented_units()
            if #src_units == 0 then goto next_q end

            local center = territory_center(target)
            if not center then goto next_q end

            -- If a headed effigy is fooling no one here (undersized / exposed),
            -- the migrant homes straight in on it and crushes it on arrival.
            local fake = find_headed_effigy(surface, target)
            local dest = (fake and fake.position) or center

            local origin_pos = get_head_pos(src_units[1])
            if not origin_pos then goto next_q end

            local migrant = src_units[1].clone{position = origin_pos}
            if not migrant then goto next_q end

            migrant.activity_mode = defines.segmented_unit_activity_mode.full
            migrant.set_ai_state{
                type        = defines.segmented_unit_ai_state.investigating,
                destination = dest,
            }

            storage.migrating_units[#storage.migrating_units + 1] = {
                unit             = migrant,
                target_territory = target,
                target_pos       = dest,
            }
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
            if m.target_territory and m.target_territory.valid
            and not is_occupied(m.target_territory)
            and not in_list(storage.migration_queue, "territory", m.target_territory) then
                storage.migration_queue[#storage.migration_queue + 1] = {
                    territory      = m.target_territory,
                    contested_tick = tick,  -- delay resets: player bought time
                }
            end
            overlay_dirty = true
        else
            local head = get_head_pos(unit)
            if head and dist(head, m.target_pos) <= ARRIVAL_RADIUS then
                unit.territory = m.target_territory
                crush_effigies_in(surface, m.target_territory)  -- the worm destroys the fake
                overlay_dirty  = true
            else
                remaining[#remaining + 1] = m
            end
        end
    end
    storage.migrating_units = remaining

    -- 4. Seismic alerts: one-time ping when a migrant enters coverage
    local seismos = active_seismographs()
    if #seismos > 0 and #storage.migrating_units > 0 then
        local covered = make_covered_fn(seismos)
        for _, m in pairs(storage.migrating_units) do
            local unit = m.unit
            if unit and unit.valid and not in_list(storage.alerted, "unit", unit) then
                local head = get_head_pos(unit)
                if head and covered(math.floor(head.x / 32), math.floor(head.y / 32)) then
                    storage.alerted[#storage.alerted + 1] = {unit = unit}
                    game.print(string.format(
                        "[color=orange][Seismograph][/color] Large seismic mass moving toward [gps=%d,%d,%s].",
                        math.floor(m.target_pos.x), math.floor(m.target_pos.y), SURFACE_NAME))
                    pcall(function() game.play_sound{path = "utility/alert_destroyed"} end)
                end
            end
        end
    end
    -- prune alert entries for dead/arrived migrants
    local alive_alerts = {}
    for _, a in pairs(storage.alerted) do
        if a.unit and a.unit.valid and in_list(storage.migrating_units, "unit", a.unit) then
            alive_alerts[#alive_alerts + 1] = a
        end
    end
    storage.alerted = alive_alerts

    -- 5. Coverage change detection (build/destroy/power flicker)
    local sig = coverage_signature(seismos)
    if sig ~= storage.coverage_sig then
        storage.coverage_sig = sig
        overlay_dirty = true
    end

    if overlay_dirty then refresh_overlay(surface) end
end)


-- --- Commands -------------------------------------------------------------------------

commands.add_command("dr-status", "Demolisher Rework: show current territory state", function()
    local p    = game.player
    local s    = game.surfaces[SURFACE_NAME]
    local tick = game.tick

    p.print(string.format(
        "[DR] cooling=%d  contested=%d  migrants=%d  kills=%d",
        #storage.cooling, #storage.migration_queue, #storage.migrating_units, storage.kills))

    p.print(string.format(
        "[DR] settings: grace=%.0fmin  delay=%.0fmin  interval=%.0fmin  chance=%.0f%%",
        grace_ticks()/3600, delay_ticks()/3600, interval_ticks()/3600, migration_chance()*100))

    local kill_term = math.min(storage.kills * esc_per_kill(), esc_kill_cap())
    p.print(string.format(
        "[DR] escalation: +%.0f%% EHP from kills (cap +%.0f%%), +%.0f%% per km from origin%s",
        kill_term * 100, esc_kill_cap() * 100, esc_dist_per_km() * 100,
        storage.esc_off and "  [DISABLED: API probe failed]" or ""))

    local active, total = 0, 0
    for _, ent in pairs(storage.seismographs) do
        if ent and ent.valid then
            total = total + 1
            if ent.energy > 0 then active = active + 1 end
        end
    end
    p.print(string.format("[DR] seismographs: %d active / %d built  (radius %d chunks)%s",
        active, total, seismo_radius_chunks(),
        storage.debug_reveal and "  [DEBUG REVEAL ON]" or ""))

    local n = 0
    for _, reg in pairs(storage.effigies) do
        n = n + 1
        local ent = reg.entity
        if ent and ent.valid then
            p.print(string.format("  effigy[%d]  tier=%d  status=%s  suppressing=%s  [gps=%d,%d,%s]",
                n, reg.tier or 0, reg.status or "?", tostring(reg.suppressing),
                math.floor(ent.position.x), math.floor(ent.position.y), SURFACE_NAME))
        end
    end

    local next_roll_ticks = storage.next_migration_tick - tick
    p.print(string.format("[DR] next migration roll in %.1f min", math.max(0, next_roll_ticks) / 3600))

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
    storage.next_migration_tick = 0
    for _, entry in pairs(storage.migration_queue) do entry.contested_tick = 0 end
    for _, entry in pairs(storage.cooling)         do entry.emptied_tick  = 0 end
    game.player.print("[DR] all timers zeroed - will execute on next heartbeat (~5 sec)")
end)

commands.add_command("dr-reveal", "Demolisher Rework: toggle debug overlay reveal (bypass seismograph coverage)", function()
    storage.debug_reveal = not storage.debug_reveal
    local s = game.surfaces[SURFACE_NAME]
    if s then refresh_overlay(s) end
    game.player.print("[DR] debug reveal " .. (storage.debug_reveal and "ON" or "OFF"))
end)
