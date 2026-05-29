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
}
