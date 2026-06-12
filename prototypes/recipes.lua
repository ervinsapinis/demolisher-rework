-- Recipes: buildings (steep tier scaling) + the two preservation crafts.
-- All disabled at start; unlocked by the technologies.

data:extend{
    {
        type        = "recipe",
        name        = "dr-seismograph",
        enabled     = false,
        energy_required = 10,
        ingredients = {
            {type = "item", name = "radar",              amount = 1},
            {type = "item", name = "tungsten-plate",     amount = 20},
            {type = "item", name = "tungsten-carbide",   amount = 10},
            {type = "item", name = "electronic-circuit", amount = 20},
        },
        results = {{type = "item", name = "dr-seismograph", amount = 1}},
    },
    -- The altars: the lie has a capital cost curve.
    {
        type        = "recipe",
        name        = "dr-effigy-small",
        enabled     = false,
        energy_required = 5,
        ingredients = {
            {type = "item", name = "tungsten-plate", amount = 10},
            {type = "item", name = "stone-brick",    amount = 20},
        },
        results = {{type = "item", name = "dr-effigy-small", amount = 1}},
    },
    {
        type        = "recipe",
        name        = "dr-effigy-medium",
        enabled     = false,
        energy_required = 15,
        ingredients = {
            {type = "item", name = "tungsten-plate", amount = 50},
            {type = "item", name = "stone-brick",    amount = 60},
            {type = "item", name = "steel-plate",    amount = 10},
        },
        results = {{type = "item", name = "dr-effigy-medium", amount = 1}},
    },
    {
        type        = "recipe",
        name        = "dr-effigy-big",
        enabled     = false,
        energy_required = 45,
        ingredients = {
            {type = "item", name = "tungsten-plate",   amount = 200},
            {type = "item", name = "stone-brick",      amount = 150},
            {type = "item", name = "tungsten-carbide", amount = 20},
        },
        results = {{type = "item", name = "dr-effigy-big", amount = 1}},
    },
    -- Embalming (Gleba): the planet of rot teaches you to stop rot.
    {
        type        = "recipe",
        name        = "dr-head-medium-embalmed",
        enabled     = false,
        energy_required = 10,
        category    = "crafting",
        ingredients = {
            {type = "item", name = "dr-head-medium-raw", amount = 1},
            {type = "item", name = "bioflux",            amount = 4},
        },
        results = {{type = "item", name = "dr-head-medium-embalmed", amount = 1}},
        allow_productivity = false,
    },
    -- Cryogenic taxidermy (Aquilo): bioflux pre-treatment, then the freeze.
    -- Made in a cryogenic plant. The head comes back colder and immortal.
    {
        type        = "recipe",
        name        = "dr-head-big-cryo",
        enabled     = false,
        energy_required = 30,
        category    = "cryogenics",
        ingredients = {
            {type = "item",  name = "dr-head-big-raw",   amount = 1},
            {type = "item",  name = "bioflux",           amount = 4},
            {type = "item",  name = "lithium-plate",     amount = 8},
            {type = "fluid", name = "fluoroketone-cold", amount = 20},
        },
        results = {
            {type = "item",  name = "dr-head-big-cryo", amount = 1},
            {type = "fluid", name = "fluoroketone-hot", amount = 20},
        },
        main_product       = "dr-head-big-cryo",
        allow_productivity = false,
    },
}
