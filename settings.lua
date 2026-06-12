-- ─── Startup settings (require a new save) ────────────────────────────────────

data:extend{
    -- Territory size
    {
        type          = "int-setting",
        name          = "dr-territory-radius",
        setting_type  = "startup",
        default_value = 2,
        minimum_value = 1,
        maximum_value = 8,
        order         = "a-a",
    },
    -- Tier distribution
    {
        type          = "int-setting",
        name          = "dr-tier-chunk-stride",
        setting_type  = "startup",
        default_value = 18,
        minimum_value = 4,
        maximum_value = 64,
        order         = "a-b",
    },
    {
        type          = "int-setting",
        name          = "dr-territory-voronoi-size",
        setting_type  = "startup",
        default_value = 384,
        minimum_value = 64,
        maximum_value = 2048,
        order         = "a-c",
    },
    -- HP multipliers per tier
    {
        type          = "double-setting",
        name          = "dr-small-hp-mult",
        setting_type  = "startup",
        default_value = 1.5,
        minimum_value = 0.1,
        maximum_value = 10.0,
        order         = "b-a",
    },
    {
        type          = "double-setting",
        name          = "dr-medium-hp-mult",
        setting_type  = "startup",
        default_value = 1.5,
        minimum_value = 0.1,
        maximum_value = 10.0,
        order         = "b-b",
    },
    {
        type          = "double-setting",
        name          = "dr-big-hp-mult",
        setting_type  = "startup",
        default_value = 1.5,
        minimum_value = 0.1,
        maximum_value = 10.0,
        order         = "b-c",
    },
    -- Enrage duration on build trigger (prototype property → startup only)
    {
        type          = "int-setting",
        name          = "dr-enrage-seconds",
        setting_type  = "startup",
        default_value = 60,
        minimum_value = 5,
        maximum_value = 600,
        order         = "b-d",
    },
    -- Intel: hide the vanilla red territory overlay; all territory intel must
    -- then come from seismograph coverage (this mod re-renders red itself).
    {
        type          = "bool-setting",
        name          = "dr-hide-vanilla-territory",
        setting_type  = "startup",
        default_value = true,
        order         = "d-a",
    },
    -- Seismograph constant power draw (prototype property → startup only)
    {
        type          = "int-setting",
        name          = "dr-seismo-power-mw",
        setting_type  = "startup",
        default_value = 50,
        minimum_value = 1,
        maximum_value = 1000,
        order         = "d-b",
    },
    -- Raw head spoil time (item prototype property → startup only)
    {
        type          = "double-setting",
        name          = "dr-raw-rot-hours",
        setting_type  = "startup",
        default_value = 2.0,
        minimum_value = 0.1,
        maximum_value = 100.0,
        order         = "d-c",
    },
}

-- ─── Runtime-global settings (changeable mid-save) ────────────────────────────

data:extend{
    {
        type          = "int-setting",
        name          = "dr-grace-period-min",
        setting_type  = "runtime-global",
        default_value = 5,
        minimum_value = 0,
        maximum_value = 60,
        order         = "c-a",
    },
    {
        type          = "int-setting",
        name          = "dr-migration-delay-min",
        setting_type  = "runtime-global",
        default_value = 15,
        minimum_value = 0,
        maximum_value = 120,
        order         = "c-b",
    },
    {
        type          = "double-setting",
        name          = "dr-migration-chance",
        setting_type  = "runtime-global",
        default_value = 0.25,
        minimum_value = 0.0,
        maximum_value = 1.0,
        order         = "c-c",
    },
    {
        type          = "int-setting",
        name          = "dr-migration-interval-min",
        setting_type  = "runtime-global",
        default_value = 5,
        minimum_value = 1,
        maximum_value = 60,
        order         = "c-d",
    },

    -- ── Seismograph ──────────────────────────────────────────────────────────
    {
        type          = "int-setting",
        name          = "dr-seismo-radius-chunks",
        setting_type  = "runtime-global",
        default_value = 8,
        minimum_value = 2,
        maximum_value = 32,
        order         = "e-a",
    },

    -- ── Effigy ───────────────────────────────────────────────────────────────
    {
        type          = "double-setting",
        name          = "dr-head-drop-chance",
        setting_type  = "runtime-global",
        default_value = 0.75,
        minimum_value = 0.0,
        maximum_value = 1.0,
        order         = "f-a",
    },
    {
        type          = "double-setting",
        name          = "dr-silence-window-min",
        setting_type  = "runtime-global",
        default_value = 5.0,
        minimum_value = 0.0,
        maximum_value = 60.0,
        order         = "f-b",
    },
    {
        type          = "double-setting",
        name          = "dr-exposure-delay-factor",
        setting_type  = "runtime-global",
        default_value = 0.5,
        minimum_value = 0.0,
        maximum_value = 1.0,
        order         = "f-c",
    },
    {
        type          = "double-setting",
        name          = "dr-feed-per-min",
        setting_type  = "runtime-global",
        default_value = 1.0,
        minimum_value = 0.05,
        maximum_value = 60.0,
        order         = "f-d",
    },
    {
        type          = "int-setting",
        name          = "dr-cryo-power-mw",
        setting_type  = "runtime-global",
        default_value = 10,
        minimum_value = 1,
        maximum_value = 500,
        order         = "f-e",
    },

    -- ── Escalation ───────────────────────────────────────────────────────────
    {
        type          = "double-setting",
        name          = "dr-esc-distance-per-km",
        setting_type  = "runtime-global",
        default_value = 0.5,
        minimum_value = 0.0,
        maximum_value = 10.0,
        order         = "g-a",
    },
    {
        type          = "double-setting",
        name          = "dr-esc-per-kill",
        setting_type  = "runtime-global",
        default_value = 0.02,
        minimum_value = 0.0,
        maximum_value = 1.0,
        order         = "g-b",
    },
    {
        type          = "double-setting",
        name          = "dr-esc-kill-cap",
        setting_type  = "runtime-global",
        default_value = 2.0,
        minimum_value = 0.0,
        maximum_value = 50.0,
        order         = "g-c",
    },
}
