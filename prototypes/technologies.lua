-- Technologies for the intel + deception arc.
--
-- dr-demolisher-ethology can be researched normally OR is completed instantly
-- by script the first time the force kills a demolisher (field studies).

data:extend{
    {
        type = "technology",
        name = "dr-seismic-monitoring",
        icons = {{
            icon      = "__base__/graphics/technology/radar.png",
            icon_size = 256,
            tint      = {r = 1.0, g = 0.78, b = 0.50, a = 1.0},
        }},
        prerequisites = {"metallurgic-science-pack"},
        unit = {
            count = 250,
            ingredients = {
                {"automation-science-pack",  1},
                {"logistic-science-pack",    1},
                {"chemical-science-pack",    1},
                {"metallurgic-science-pack", 1},
            },
            time = 30,
        },
        effects = {
            {type = "unlock-recipe", recipe = "dr-seismograph"},
        },
    },
    {
        type = "technology",
        name = "dr-demolisher-ethology",
        icons = {{
            icon      = "__space-age__/graphics/icons/small-demolisher.png",
            icon_size = 64,
        }},
        -- Hidden until the force kills its first demolisher (control.lua
        -- enables it): you cannot study what you have not dissected.
        enabled = false,
        prerequisites = {"metallurgic-science-pack"},
        unit = {
            count = 200,
            ingredients = {
                {"automation-science-pack",  1},
                {"logistic-science-pack",    1},
                {"chemical-science-pack",    1},
                {"metallurgic-science-pack", 1},
            },
            time = 30,
        },
        effects = {
            {type = "unlock-recipe", recipe = "dr-effigy-small"},
        },
    },
    {
        type = "technology",
        name = "dr-cadaver-embalming",
        icons = {{
            icon      = "__space-age__/graphics/icons/medium-demolisher.png",
            icon_size = 64,
            tint      = {r = 0.70, g = 1.00, b = 0.70, a = 1.0},
        }},
        prerequisites = {"dr-demolisher-ethology", "agricultural-science-pack"},
        unit = {
            count = 200,
            ingredients = {
                {"automation-science-pack",    1},
                {"logistic-science-pack",      1},
                {"chemical-science-pack",      1},
                {"agricultural-science-pack",  1},
            },
            time = 30,
        },
        effects = {
            {type = "unlock-recipe", recipe = "dr-effigy-medium"},
            {type = "unlock-recipe", recipe = "dr-head-medium-embalmed"},
        },
    },
    {
        type = "technology",
        name = "dr-cryogenic-taxidermy",
        icons = {{
            icon      = "__space-age__/graphics/icons/big-demolisher.png",
            icon_size = 64,
            tint      = {r = 0.60, g = 0.85, b = 1.00, a = 1.0},
        }},
        prerequisites = {"dr-cadaver-embalming", "cryogenic-science-pack"},
        unit = {
            count = 300,
            ingredients = {
                {"automation-science-pack", 1},
                {"logistic-science-pack",   1},
                {"chemical-science-pack",   1},
                {"cryogenic-science-pack",  1},
            },
            time = 45,
        },
        effects = {
            {type = "unlock-recipe", recipe = "dr-effigy-big"},
            {type = "unlock-recipe", recipe = "dr-head-big-cryo"},
        },
    },
}
