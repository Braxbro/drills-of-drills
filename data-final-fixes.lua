require("burner-drill-fix") -- burner drill textures in vanilla are wonky in the north direction and it bugs me
local resources = data.raw["resource"]
local minimumMiningTime = {}
local minimumMiningTimeTarget = {}
local prefix = "DoD"

data:extend{{
    type = "item-group",
    name = "drills-of-drills",
    icon = "__base__/graphics/icons/electric-mining-drill.png",
    icon_size = 64, icon_mipmaps = 4,
    order = "zz"
}}

local itemGroup = data.raw["item-group"]["drills-of-drills"]

for name, prototype in pairs(resources) do
    local category = prototype.category or "basic-solid"
    local miningTime = prototype.minable and prototype.minable.mining_time or 1
    if (not minimumMiningTime[category]) or (minimumMiningTime[category] > miningTime) then -- store info about fastest ores of a type
        minimumMiningTime[category] = miningTime
        minimumMiningTimeTarget[category] = name
    end
end

for category, _ in pairs(data.raw["resource-category"]) do -- make sure every category, even if empty, has a value
    minimumMiningTime[category] = minimumMiningTime[category] or 1
end

local drills = table.deepcopy(data.raw["mining-drill"]) -- don't create stuff based on DoD drills
local items = table.deepcopy(data.raw.item)
local function toEnergy(v, useJoules) -- undoes util.parse_energy()
    local energy_chars =
    {
        [""] = 1,
        k = 10 ^ 3,
        M = 10 ^ 6,
        G = 10 ^ 9,
        T = 10 ^ 12,
        P = 10 ^ 15,
        E = 10 ^ 18,
        Z = 10 ^ 21,
        Y = 10 ^ 24
    }
    local biggestChar
    for char, multiplier in pairs(energy_chars) do
        if v / multiplier >= 1 and ((not biggestChar) or multiplier > energy_chars[biggestChar]) then
            biggestChar = char
        end
    end
    v = v / energy_chars[biggestChar]
    if useJoules then
        return tostring(v) .. biggestChar .. "J"
    else
        return tostring(v * 60) .. biggestChar .. "W"
    end
end

local isStart = {}

for name, _ in pairs(drills) do
    isStart[name] = false
end

for _, recipe in pairs(data.raw["recipe"]) do
    recipe.enabled = recipe.enabled ~= false and true or false
    if recipe.enabled then
        if recipe.normal or recipe.expensive then
            recipe.normal = recipe.normal or recipe.expensive
            recipe.expensive = recipe.expensive or recipe.normal -- this is default behavior, just made explicit
            if recipe.normal.results then
                for _, product in pairs(recipe.normal.results) do
                    if product.type == "item" or type(product[1]) == "string" then
                        for drill, _ in pairs(isStart) do
                            if drill == (product.name or product[1]) then
                                isStart[drill] = true
                            end
                        end
                    end
                end
            else
                for drill, _ in pairs(isStart) do
                    if drill == recipe.normal.result then
                        isStart[drill] = true
                    end
                end
            end
        elseif recipe.results then
            for _, product in pairs(recipe.results) do
                if product.type == "item" or type(product[1]) == "string" then
                    for drill, _ in pairs(isStart) do
                        if drill == (product.name or product[1]) then
                            isStart[drill] = true
                        end
                    end
                end
            end
        end
    end
end

for name, prototype in pairs(drills) do
    local width = math.ceil( -- length of the entity on the x-axis
                (prototype.collision_box[2].x or prototype.collision_box[2][1]) -
                (prototype.collision_box[1].x or prototype.collision_box[1][1])
            )
    local height = math.ceil( -- length of the entity on the y-axis
                (prototype.collision_box[2].y or prototype.collision_box[2][2]) -
                (prototype.collision_box[1].y or prototype.collision_box[1][2])
            )
    if not (prototype.resource_searching_radius + .01 < (math.min(width, height) / 2)) then -- if it doesn't require exact placement on top of an ore
        log("Creating Drills of Drills for " .. name)
        data:extend{{
            group = "drills-of-drills",
            type = "item-subgroup",
            name = "drill-of-" .. name .. "s"
        }}
        data:extend{{
            group = "drills-of-drills",
            type = "item-subgroup",
            name = "drill-of-" .. name .. "s-upgrade"
        }}
        data:extend{{
            group = "drills-of-drills",
            type = "item-subgroup",
            name = "drill-of-" .. name .. "s-disassembly"
        }}
        local speed = prototype.mining_speed
        local minMiningTime = math.huge
        local fastestMine
        for _, category in pairs(prototype.resource_categories) do
            if minMiningTime > minimumMiningTime[category] then
                minMiningTime = minimumMiningTime[category]
                fastestMine = minimumMiningTimeTarget[category]
            end
        end
        local maxTier = math.floor(math.sqrt((60 * minMiningTime) / speed))
        if maxTier < 1 then
            log("Drill " .. name .. " can exceed 1 process per tick when mining " .. fastestMine .. ". ")
        end
        -- Tier 0 means the drill overcaps in optimal situations by itself.
        -- Tier N means a tier N+1 version of the drill would overcap in optimal situations.
        for tier = 2, maxTier do
            local newPrototype = table.deepcopy(prototype)
            --basic stats
            newPrototype.max_health = newPrototype.max_health * tier * tier
            newPrototype.mining_speed = newPrototype.mining_speed * tier * tier
            newPrototype.resource_searching_radius = ((newPrototype.resource_searching_radius + .01) * tier) - .01
            newPrototype.energy_usage = toEnergy(util.parse_energy(newPrototype.energy_usage) * tier * tier)
            if newPrototype.energy_source.emissions_per_minute then
                newPrototype.energy_source.emissions_per_minute = newPrototype.energy_source.emissions_per_minute * tier * tier
            end
            width = math.ceil( -- length of the entity on the x-axis
                (newPrototype.collision_box[2].x or newPrototype.collision_box[2][1]) - 
                (newPrototype.collision_box[1].x or newPrototype.collision_box[1][1])
            )
            height = math.ceil( -- length of the entity on the y-axis
                (newPrototype.collision_box[2].y or newPrototype.collision_box[2][2]) -
                (newPrototype.collision_box[1].y or newPrototype.collision_box[1][2])
            )
            local widthOffset = (width % 2 == 0) -- x-axis offset
            and math.floor(newPrototype.collision_box[1].x or newPrototype.collision_box[1][1])
            or math.floor((newPrototype.collision_box[1].x or newPrototype.collision_box[1][1]) * 2) / 2
            local heightOffset = (height % 2 == 0) -- y-axis offset
            and math.floor(newPrototype.collision_box[1].y or newPrototype.collision_box[1][2])
            or math.floor((newPrototype.collision_box[1].y or newPrototype.collision_box[1][2]) * 2) / 2
            local size = { -- size of the entity on the grid
                {
                    widthOffset, heightOffset
                },{
                    width + widthOffset, height + heightOffset
                }
            }
            --fix fluidboxes
            local fluidIn = newPrototype.input_fluid_box
            local fluidOut = newPrototype.output_fluid_box
            local offset, internalOffset, externalOffset
            if fluidIn then
                for _, connection in pairs(fluidIn.pipe_connections) do
                    if connection.position then
                        offset = connection.position
                        internalOffset = {
                            math.min(
                                math.max(
                                    offset[1],
                                    size[1].x or size[1][1]
                                ),
                                size[2].x or size[2][1]
                            ),
                            math.min(
                                math.max(
                                    offset[2],
                                    size[1].y or size[1][2]
                                ),
                                size[2].y or size[2][2]
                            )
                        }
                        externalOffset = {
                            offset[1] - internalOffset[1], offset[2] - internalOffset[2]
                        }
                        connection.position = { internalOffset[1] * tier + externalOffset[1],
                            internalOffset[2] * tier + externalOffset[2] }
                    else
                        for index, vector in pairs(connection.positions) do
                            offset = vector
                            internalOffset = {
                                math.min(
                                    math.max(
                                        offset[1],
                                        size[1].x or size[1][1]
                                    ),
                                    size[2].x or size[2][1]
                                ),
                                math.min(
                                    math.max(
                                        offset[2],
                                        size[1].y or size[1][2]
                                    ),
                                    size[2].y or size[2][2]
                                )
                            }
                            externalOffset = {
                                offset[1] - internalOffset[1], offset[2] - internalOffset[2]
                            }
                            connection.positions[index] = { internalOffset[1] * tier + externalOffset[1],
                                internalOffset[2] * tier + externalOffset[2] }
                        end
                    end
                end
            end
            if fluidOut then
                for _, connection in pairs(fluidOut.pipe_connections) do
                    if connection.position then
                        offset = connection.position
                        internalOffset = {
                            math.min(
                                math.max(
                                    offset[1],
                                    size[1].x or size[1][1]
                                ),
                                size[2].x or size[2][1]
                            ),
                            math.min(
                                math.max(
                                    offset[2],
                                    size[1].y or size[1][2]
                                ),
                                size[2].y or size[2][2]
                            )
                        }
                        externalOffset = {
                            offset[1] - internalOffset[1], offset[2] - internalOffset[2]
                        }
                        connection.position = { internalOffset[1] * tier + externalOffset[1],
                            internalOffset[2] * tier + externalOffset[2] }
                    else
                        for index, vector in pairs(connection.positions) do
                            offset = vector
                            internalOffset = {
                                math.min(
                                    math.max(
                                        offset[1],
                                        size[1].x or size[1][1]
                                    ),
                                    size[2].x or size[2][1]
                                ),
                                math.min(
                                    math.max(
                                        offset[2],
                                        size[1].y or size[1][2]
                                    ),
                                    size[2].y or size[2][2]
                                )
                            }
                            externalOffset = {
                                offset[1] - internalOffset[1], offset[2] - internalOffset[2]
                            }
                            connection.positions[index] = { internalOffset[1] * tier + externalOffset[1],
                                internalOffset[2] * tier + externalOffset[2] }
                        end
                    end
                end
            end
            --bounding boxes and related values
            offset = newPrototype.vector_to_place_result
            internalOffset = {
                math.min(
                    math.max(
                        offset[1],
                        size[1].x or size[1][1]
                    ),
                    size[2].x or size[2][1]
                ),
                math.min(
                    math.max(
                        offset[2],
                        size[1].y or size[1][2]
                    ),
                    size[2].y or size[2][2]
                )
            }
            externalOffset = {
                offset[1] - internalOffset[1], offset[2] - internalOffset[2]
            }
            newPrototype.vector_to_place_result = { internalOffset[1] * tier + externalOffset[1],
                internalOffset[2] * tier + externalOffset[2] }
            local bBoxes = {
                "collision_box", "map_generator_bounding_box", "selection_box", "drawing_box", "sticker_box",
                "hit_visualization_box"
            }
            for _, property in pairs(bBoxes) do
                if newPrototype[property] then
                    local bBox = newPrototype[property]
                    local buffer = {
                        {
                            (size[1].x or size[1][1]) - (bBox[1].x or bBox[1][1]),
                            (size[1].y or size[1][2]) - (bBox[1].y or bBox[1][2])
                        },
                        {
                            (size[2].x or size[2][1]) - (bBox[2].x or bBox[2][1]),
                            (size[2].y or size[2][2]) - (bBox[2].y or bBox[2][2])
                        }
                    }
                    newPrototype[property] = {
                        {
                            (size[1].x or size[1][1]) * tier - (buffer[1].x or buffer[1][1]),
                            (size[1].y or size[1][2]) * tier - (buffer[1].y or buffer[1][2])
                        },
                        {
                            (size[2].x or size[2][1]) * tier - (buffer[2].x or buffer[2][1]),
                            (size[2].y or size[2][2]) * tier - (buffer[2].y or buffer[2][2])
                        }
                    }
                end
            end
            --rescale graphics
            local directions = {"north", "south", "east", "west"}
            local function scaleAnimation(anim)
                if anim.north then -- it's an Animation4Way
                    for _, direction in pairs(directions) do
                        if anim[direction] then
                            scaleAnimation(anim[direction])
                        end
                    end
                elseif anim.layers then -- it's using layers
                    for _, animation in pairs(anim.layers) do
                        scaleAnimation(animation)
                    end
                else -- it's a normal animation
                    anim.scale = (anim.scale or 1) * tier
                    anim.shift = anim.shift or {}
                    anim.shift[1] = (anim.shift[1] or 0) * tier
                    anim.shift[2] = (anim.shift[2] or 0) * tier
                    if anim.hr_version then
                        anim.hr_version.scale = (anim.hr_version.scale or 1) * tier
                        anim.hr_version.shift = anim.hr_version.shift or {}
                        anim.hr_version.shift[1] = (anim.hr_version.shift[1] or 0) * tier
                        anim.hr_version.shift[2] = (anim.hr_version.shift[2] or 0) * tier
                    end
                end
            end
            if newPrototype.graphics_set then
                local function scaleMiningDrillGraphicsSet(mdgs)
                    if mdgs.animation then 
                        scaleAnimation(mdgs.animation)
                    end
                    if mdgs.idle_animation then
                        scaleAnimation(mdgs.idle_animation)
                    end
                    if mdgs.working_visualisations then
                        for _, working_visualisation in pairs(mdgs.working_visualisations) do
                            if working_visualisation.animation then scaleAnimation(working_visualisation.animation) else
                                for _, direction in pairs(directions) do
                                    if working_visualisation[direction .. "_animation"] then 
                                        scaleAnimation(working_visualisation[direction .. "_animation"])
                                    end
                                    if working_visualisation[direction .. "_position"] then
                                        working_visualisation[direction .. "_position"][1] =
                                            working_visualisation[direction .. "_position"][1] * tier
                                        working_visualisation[direction .. "_position"][2] =
                                            working_visualisation[direction .. "_position"][2] * tier
                                    end
                                end
                            end
                        end
                    end
                    if mdgs.shift_animation_waypoints and (mdgs.shift_animation_waypoint_stop_duration or mdgs.shift_animation_transition_duration) then
                        for _, direction in pairs(directions) do
                            for _, vector in pairs(mdgs.shift_animation_waypoints[direction]) do
                                vector[1] = vector[1] * tier
                                vector[2] = vector[2] * tier
                            end
                        end
                    end
                end
                if newPrototype.graphics_set then 
                    newPrototype.graphics_set = table.deepcopy(newPrototype.graphics_set)
                    scaleMiningDrillGraphicsSet(newPrototype.graphics_set)
                end
                if newPrototype.wet_mining_graphics_set then 
                    newPrototype.wet_mining_graphics_set = table.deepcopy(newPrototype.wet_mining_graphics_set)
                    scaleMiningDrillGraphicsSet(newPrototype.wet_mining_graphics_set) 
                end
            else
                if newPrototype.animations then 
                    newPrototype.animations = table.deepcopy(newPrototype.animations)
                    scaleAnimation(newPrototype.animations)
                end
            end
            local function scaleSprite(sprite)
                local directions8Way = table.pack("north_east", "north_west", "south_east", "south_west", table.unpack(directions))
                directions8Way["n"] = nil
                if sprite.sheets then
                    if sprite.sheets[1] then
                        for _, sheet in pairs(sprite.sheets) do
                            sheet.scale = (sheet.scale or 1) * tier
                            sheet.shift = sheet.shift or {}
                            sheet.shift[1] = (sheet.shift[1] or 0) * tier
                            sheet.shift[2] = (sheet.shift[2] or 0) * tier
                            if sheet.hr_version then
                                sheet.hr_version.scale = (sheet.hr_version.scale or 1) * tier
                                sheet.hr_version.shift = sheet.hr_version.shift or {}
                                sheet.hr_version.shift[1] = (sheet.hr_version.shift[1] or 0) * tier
                                sheet.hr_version.shift[2] = (sheet.hr_version.shift[2] or 0) * tier
                            end
                        end
                    else
                        local sheet =  sprite.sheets
                        sheet.scale = (sheet.scale or 1) * tier
                        sheet.shift = sheet.shift or {}
                        sheet.shift[1] = (sheet.shift[1] or 0) * tier
                        sheet.shift[2] = (sheet.shift[2] or 0) * tier
                        if sheet.hr_version then
                            sheet.hr_version.scale = (sheet.hr_version.scale or 1) * tier
                            sheet.hr_version.shift = sheet.hr_version.shift or {}
                            sheet.hr_version.shift[1] = (sheet.hr_version.shift[1] or 0) * tier
                            sheet.hr_version.shift[2] = (sheet.hr_version.shift[2] or 0) * tier
                        end
                    end
                elseif sprite.sheet then
                    sprite.sheet.scale = (sprite.sheet.scale or 1) * tier
                    sprite.sheet.shift = sprite.sheet.shift or {}
                    sprite.sheet.shift[1] = (sprite.sheet.shift[1] or 0) * tier
                    sprite.sheet.shift[2] = (sprite.sheet.shift[2] or 0) * tier
                    if sprite.sheet.hr_version then
                        sprite.sheet.hr_version.scale = (sprite.sheet.hr_version.scale or 1) * tier
                        sprite.sheet.hr_version.shift = sprite.sheet.hr_version.shift or {}
                        sprite.sheet.hr_version.shift[1] = (sprite.sheet.hr_version.shift[1] or 0) * tier
                        sprite.sheet.hr_version.shift[2] = (sprite.sheet.hr_version.shift[2] or 0) * tier
                    end
                elseif sprite.north then
                    for _, direction in pairs(directions8Way) do -- this will work for both Sprite4Ways and Sprite8Ways
                        if sprite[direction] then scaleSprite(sprite[direction]) end
                    end
                elseif sprite.layers then
                    for _, layer in pairs(sprite.layers) do scaleSprite(layer) end
                else
                    sprite.scale = (sprite.scale or 1) * tier
                    sprite.shift[1] = (sprite.shift[1] or 0) * tier
                    sprite.shift[2] = (sprite.shift[2] or 0) * tier
                    if sprite.hr_version then
                        sprite.hr_version.scale = (sprite.hr_version.scale or 1) * tier
                        sprite.hr_version.shift[1] = (sprite.hr_version.shift[1] or 0) * tier
                        sprite.hr_version.shift[2] = (sprite.hr_version.shift[2] or 0) * tier
                    end
                end
            end
            if newPrototype.base_picture then 
                newPrototype.base_picture = table.deepcopy(newPrototype.base_picture)
                scaleSprite(newPrototype.base_picture)
            end
            if newPrototype.circuit_wire_connection_points then
                for _, connectionPoint in pairs(newPrototype.circuit_wire_connection_points) do
                    for _, wires in pairs(connectionPoint) do
                        for _, vector in pairs(wires) do
                            vector[1] = vector[1] * tier
                            vector[2] = vector[2] * tier
                        end
                    end
                end
            end
            if newPrototype.circuit_connector_sprites then
                local function scaleCircuitConnectorSprites(CCSprites)
                    scaleSprite(CCSprites.led_red)
                    scaleSprite(CCSprites.led_green)
                    scaleSprite(CCSprites.led_blue)
                    if CCSprites.led_light[1] then -- it's an array of lights
                        for _, light in pairs(CCSprites.led_light) do
                            local vector = light.shift
                            if vector then
                                vector[1] = vector[1] * tier
                                vector[2] = vector[2] * tier
                            end
                            light.size = light.size * tier
                            if light.picture then scaleSprite(light.picture) end
                        end
                    else
                        local light = CCSprites.led_light
                        local vector = light.shift
                        if vector then
                            vector[1] = vector[1] * tier
                            vector[2] = vector[2] * tier
                        end
                        light.size = light.size * tier
                        if light.picture then scaleSprite(light.picture) end
                    end
                    if CCSprites.connector_main then 
                        scaleSprite(CCSprites.connector_main)
                    end
                    if CCSprites.connector_shadow then 
                        scaleSprite(CCSprites.connector_main)
                    end
                    if CCSprites.wire_pins then scaleSprite(CCSprites.wire_pins) end
                    if CCSprites.wire_pins_shadow then scaleSprite(CCSprites.wire_pins_shadow) end
                    if CCSprites.led_blue_off then scaleSprite(CCSprites.led_blue_off) end
                    local vector = CCSprites.blue_led_light_offset
                    if vector then
                        vector[1] = vector[1] * tier
                        vector[2] = vector[2] * tier
                    end
                    vector = CCSprites.red_green_led_light_offset
                    if vector then
                        vector[1] = vector[1] * tier
                        vector[2] = vector[2] * tier
                    end
                end
                newPrototype.circuit_connector_sprites = table.deepcopy(newPrototype.circuit_connector_sprites)
                for _, ccSprite in pairs(newPrototype.circuit_connector_sprites) do
                    scaleCircuitConnectorSprites(ccSprite)
                end
            end
            --new item
            local item = table.deepcopy(data.raw.item[name])
            if not item then -- can't guarantee the item name matches the entity name
                for _, foundItem in pairs(items) do
                    if foundItem.place_result == name then
                        item = table.deepcopy(foundItem)
                    end
                end
            end
            local baseItem = item.name
            item.name = prefix .. "-" .. item.name .. "-" .. tier
            item.place_result = prefix .. "-" .. newPrototype.name .. "-" .. tier
            item.stack_size = math.max(math.ceil(item.stack_size / (tier * tier)), 1)
            item.subgroup = "drill-of-" .. name .. "s"
            item.order = string.format("%0" .. string.len(tostring(maxTier)) .. "d", tier)
            item.localised_name = {"item-name-placeholders.drill-of-drills", tier * tier,
                prototype.localised_name or {"entity-name."..name}
            }
            --new name
            newPrototype.name = item.place_result
            newPrototype.minable.result = item.name
            newPrototype.subgroup = "drill-of-" .. name .. "s"
            newPrototype.order = string.format("%0" .. string.len(tostring(maxTier)) .. "d", tier)
            newPrototype.next_upgrade = newPrototype.next_upgrade and prefix .. "-" .. newPrototype.next_upgrade .. "-" .. tier
            newPrototype.localised_name = {"item-name-placeholders.drill-of-drills", tier * tier,
                prototype.localised_name or {"entity-name."..name}
            }
            --recipes
            if tier > 2 then
                local ingredientsTable = {}
                local craftTime = 1
                local drillTotal = tier * tier
                for i = (tier - 1), 1, -1 do
                    if drillTotal >= i * i then
                        if i == 1 then
                            table.insert(ingredientsTable, {baseItem, math.floor(drillTotal / (i * i))})
                            craftTime = math.floor(drillTotal / (i * i))
                        else
                            table.insert(ingredientsTable, {
                                prefix .. "-" .. baseItem .. "-" .. i, math.floor(drillTotal / (i * i))
                            })
                        end
                        drillTotal = drillTotal % (i * i)
                    end
                end
                data:extend{{
                    type = "recipe",
                    name = item.name .. "-upgrade",
                    subgroup = "drill-of-" .. name .. "s-upgrade",
                    ingredients = ingredientsTable,
                    result = item.name,
                    energy_required = craftTime,
                    enabled = isStart[name]
                }}
            end
            data:extend{{
                type = "recipe",
                name = item.name,
                subgroup = "drill-of-" .. name .. "s",
                ingredients = {{baseItem, tier * tier}},
                result = item.name,
                energy_required = tier * tier,
                enabled = isStart[name]
            }}
            data:extend{{
                type = "recipe",
                name = item.name .. "-disassembly",
                subgroup = "drill-of-" .. name .. "s-disassembly",
                ingredients = {{item.name, 1}},
                result = baseItem,
                result_count = tier * tier,
                energy_required = 10 * tier * tier,
                enabled = isStart[name],
                order = string.format("%0" .. string.len(tostring(maxTier)) .. "d", tier)
            }}
            --create item and drill
            data:extend { newPrototype, item }
            log("Created " .. newPrototype.name .. " and its recipes for drill" .. name .. "(" .. tier - 1 .. "/" .. maxTier - 1 .. ")")
        end
    end
end

for drill, prototype in pairs(data.raw["mining-drill"]) do
    if not drills[drill] then
        if prototype.next_upgrade and not data.raw["mining-drill"][prototype.next_upgrade] then
            prototype.next_upgrade = nil
        end
    end
end

log("Finished creating Drills of Drills.")