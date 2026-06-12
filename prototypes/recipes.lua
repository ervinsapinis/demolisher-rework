-- Recipes: buildings + head preservation chains.
-- All disabled at start; unlocked by the technologies in technologies.lua.

local SIZES = {"small", "medium", "big"}

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
    {
        type        = "recipe",
        name        = "dr-effigy",
        enabled     = false,
        energy_required = 5,
        ingredients = {
            {type = "item", name = "tungsten-plate", amount = 10},
            {type = "item", name = "stone-brick",    amount = 20},
        },
        results = {{type = "item", name = "dr-effigy", amount = 1}},
    },
}

-- Embalming (Gleba): raw head + bioflux -> embalmed head.
-- The planet of rot teaches you to stop rot.
for _, size in pairs(SIZES) do
    data:extend{{
        type        = "recipe",
        name        = "dr-head-" .. size .. "-embalmed",
        enabled     = false,
        energy_required = 10,
        category    = "crafting",
        ingredients = {
            {type = "item", name = "dr-head-" .. size .. "-raw", amount = 1},
            {type = "item", name = "bioflux",                    amount = 4},
        },
        results = {{type = "item", name = "dr-head-" .. size .. "-embalmed", amount = 1}},
        allow_productivity = false,
    }}
end

-- Cryogenic taxidermy (Aquilo): embalmed head + lithium + cold fluoroketone.
-- Made in a cryogenic plant. The head comes back colder and immortal.
for _, size in pairs(SIZES) do
    data:extend{{
        type        = "recipe",
        name        = "dr-head-" .. size .. "-cryo",
        enabled     = false,
        energy_required = 30,
        category    = "cryogenics",
        ingredients = {
            {type = "item",  name = "dr-head-" .. size .. "-embalmed", amount = 1},
            {type = "item",  name = "lithium-plate",                   amount = 8},
            {type = "fluid", name = "fluoroketone-cold",               amount = 20},
        },
        results = {
            {type = "item",  name = "dr-head-" .. size .. "-cryo", amount = 1},
            {type = "fluid", name = "fluoroketone-hot",            amount = 20},
        },
        main_product       = "dr-head-" .. size .. "-cryo",
        allow_productivity = false,
    }}
end
