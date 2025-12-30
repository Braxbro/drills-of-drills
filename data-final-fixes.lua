local prefix = "DoD"
local drills = table.deepcopy(data.raw["mining-drill"]) -- don't create stuff based on DoD drills

data:extend { {
    type = "item-group",
    name = "drills-of-drills",
    icon = "__base__/graphics/icons/electric-mining-drill.png",
    icon_size = 64, icon_mipmaps = 4,
    order = "zz"
} }

-- Send forward a bunch of data to control stage to avoid recalculations
data:extend{
    {
        type = "mod-data",
        name = "drills-of-drills-registry",
        data_type = "drills-of-drills.drill-registry",
        data = {}
    },
    {
        type = "mod-data",
        name = "drills-of-drills-speed-limits",
        data_type = "drills-of-drills.resource-speed-limit",
        data = {}
    }
}
local drillRegistry = data.raw["mod-data"]["drills-of-drills-registry"]
local speedLimits = data.raw["mod-data"]["drills-of-drills-speed-limits"]

local possiblePrototypes = {
        "item", "capsule", "gun", "item-with-entity-data", "item-with-label",
        "module", "rail-planner", "space-platform-starter-pack", "tool",
        "item-with-inventory", "item-with-tags", "selection-tool", "armor", "repair-tool",
        "blueprint-book", "blueprint", "copy-paste-tool", "deconstruction-item",
        "spidertron-remote", "upgrade-item"
    }
local function getItemByName(name)
    for _, prototype in pairs(possiblePrototypes) do
        local candidate = (data.raw[prototype] or {})[name]
        if candidate then return candidate end
    end
end

local function getItemByPlaceResult(placeResult)
    for _, prototype in pairs(possiblePrototypes) do
        local prototypes = (data.raw[prototype] or {})
        for name, item in pairs(prototypes) do
            if item.place_result == placeResult then
                return item
            end
        end
    end
end

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

local maxBeltSpeed = 0; -- find max belt speed
local maxBeltStackSize = 1;
local maxFluidThroughput = data.raw["utility-constants"]["default"].max_fluid_flow * 60;

for _, belt in pairs(data.raw["transport-belt"]) do
    local beltSpeed = belt.speed * 480
    if beltSpeed > maxBeltSpeed then
        maxBeltSpeed = beltSpeed
    end
end
if feature_flags["space_travel"] then
    -- this just grabs whatever the first utility constants prototype is
    maxBeltStackSize = data.raw["utility-constants"]["default"].max_belt_stack_size
end
log("Maximum current belt stack size is: " .. maxBeltStackSize)

local maxStackedBeltSpeed = maxBeltSpeed * maxBeltStackSize

local resources = data.raw["resource"]

local function getAdjustedStackRate(time, count, stack)
    return count / time * math.max(maxBeltStackSize / stack, 1)
end
local function getUnstackedRate(time, count)
    return count / time
end

-- this table will help pass speed limit info forward later
local outputRates = {}
local resourcesByCategory = {}
for _, resource in pairs(resources) do
    if resource.minable then
        local miningTime = resource.minable.mining_time
        local outputRate = {
            outputAdjusted = 0, -- whatever doesn't get overridden will be ignored
            outputUnstacked = 0,
            outputFluid = 0,
            outputSource = resource.name
        }
        if resource.minable.results then
            for _, result in pairs(resource.minable.results) do
                -- technically, only one output should be fluids since mining drills can only have one fluid output.
                if result.type == "item" then
                    -- reinitialize the output rate so that it isn't ignored
                    outputRate.outputAdjusted =
                        outputRate.outputAdjusted == math.huge and 0 or outputRate.outputAdjusted
                    outputRate.outputUnstacked =
                        outputRate.outputUnstacked == math.huge and 0 or outputRate.outputUnstacked

                    -- if amount is present, min and max are ignored; min and max are mandatory otherwise
                    -- min and max are averaged to get expected value
                    local amount = result.amount or (result.amount_min + result.amount_max) / 2
                    -- if probability is present, adjust for expected value
                    amount = result.probability and amount * result.probability or amount
                    -- If probability is less than 1 and min/max are used, gambler's ruin applies.
                    -- However, this can't be resolved. It's a result of theoretically infinite random outcomes.

                    outputRate.outputAdjusted = outputRate.outputAdjusted +
                        getAdjustedStackRate(
                            miningTime, amount,
                            getItemByName(result.name).stack_size
                        )
                    outputRate.outputUnstacked = outputRate.outputUnstacked +
                        getUnstackedRate(miningTime, amount)
                elseif result.type == "fluid" then
                    -- reinitialize the output rate so that it isn't ignored
                    outputRate.outputFluid =
                        outputRate.outputFluid == math.huge and 0 or outputRate.outputFluid
                    -- fluids don't care about stacking; they have their own limits
                    -- also everything about gambler's ruin also applies here
                    local amount = result.amount or (result.amount_min + result.amount_max) / 2
                    amount = result.probability and amount * result.probability or amount
                    -- the limit I'm using is adjusted to use seconds as its unit, rather than updates
                    -- in vanilla, the (theoretical) limit is 6000 units per second,
                    -- or 100 units per update per connection. however, jank may render this infeasible
                    -- it's still a good enough meterstick for my purposes though.

                    -- only one fluid output per drill, so this is safe
                    outputRate.outputFluid = amount / miningTime
                end
            end
        elseif resource.minable.result then
            outputRate.outputAdjusted =
                getAdjustedStackRate(
                    miningTime, resource.minable.count or 1,
                    getItemByName(resource.minable.result).stack_size
                )
            outputRate.outputUnstacked = getUnstackedRate(miningTime, resource.minable.count or 1)
        end
        -- resources have to have a category
        resource.category = resource.category or "basic-solid"
        resourcesByCategory[resource.category] = resourcesByCategory[resource.category] or {}
        table.insert(resourcesByCategory[resource.category], resource.name)
        outputRates[resource.name] = outputRate
    end
end

-- register speed limit info in mod_data object
for resource, outputRate in pairs(outputRates) do
    local maxSpeeds = {
        maxFluidSpeed = math.huge,
        maxUnstackedSpeed = math.huge,
        maxStackedSpeed = math.huge
    }
    if outputRate.outputFluid > 0 then
        maxSpeeds.maxFluidSpeed = maxFluidThroughput / outputRate.outputFluid
    end
    if outputRate.outputUnstacked > 0 then
        -- halved due to the fact that drills can only output to one lane
        maxSpeeds.maxUnstackedSpeed = (maxBeltSpeed / outputRate.outputUnstacked) / 2
    end
    -- items with stack size lower than max belt stack size will have lower throughput
    -- so their speed is adjusted first
    if outputRate.outputAdjusted > 0 then
        -- halved due to the fact that drills can only output to one lane
        maxSpeeds.maxStackedSpeed = (maxStackedBeltSpeed / outputRate.outputAdjusted) / 2
    end
    speedLimits.data[resource] = maxSpeeds
end

-- Don't need to check if drills are starter recipes,
-- because I can make them unlock based on crafting their non-Drills of Drills counterparts.
for name, prototype in pairs(drills) do
    -- skip drills that can't be placed normally
    if not getItemByPlaceResult(name) then goto skip_drill end
    local width = math.ceil( -- length of the entity on the x-axis
        (prototype.selection_box[2].x or prototype.selection_box[2][1]) -
        (prototype.selection_box[1].x or prototype.selection_box[1][1])
    )
    local height = math.ceil( -- length of the entity on the y-axis
        (prototype.selection_box[2].y or prototype.selection_box[2][2]) -
        (prototype.selection_box[1].y or prototype.selection_box[1][2])
    )
    -- if the drill doesn't require exact placement on a resource patch
    if not ((prototype.resource_searching_radius + .01) < (math.min(width, height) / 2)) then
        log("Creating Drills of Drills for " .. name)
        local subgroups = {
            {
                group = "drills-of-drills",
                type = "item-subgroup",
                name = "drill-of-" .. name .. "s"
            },
            {
                group = "drills-of-drills",
                type = "item-subgroup",
                name = "drill-of-" .. name .. "s-upgrade"
            },
            {
                group = "drills-of-drills",
                type = "item-subgroup",
                name = "drill-of-" .. name .. "s-disassembly"
            }
        }
        local speed = prototype.mining_speed
        local stack = prototype.drops_full_belt_stacks

        -- math.huge is treated as unset
        local maxItemSpeed = (prototype.vector_to_place_result and 0) or nil
        local maxFluidSpeed = (prototype.output_fluid_box and 0) or nil

        -- support cursed drills that mine both fluids and items, regardless of if it works
        for _, category in pairs(prototype.resource_categories) do
            for _, resource in pairs(resourcesByCategory[category]) do
                local itemSpeedToCompare = stack and
                    speedLimits.data[resource].maxStackedSpeed or
                    speedLimits.data[resource].maxUnstackedSpeed
                if maxItemSpeed and maxItemSpeed < itemSpeedToCompare then
                    maxItemSpeed = itemSpeedToCompare
                end
                local fluidSpeedToCompare = speedLimits.data[resource].maxFluidSpeed
                if maxFluidSpeed and maxFluidSpeed < fluidSpeedToCompare then
                    maxFluidSpeed = fluidSpeedToCompare
                end
            end
        end

        -- In 1.1, Drills of Drills used (1+t)^2 for drill scaling
        -- In 2.0, it will use (1+2t)^2 for drill scaling.
        -- This keeps centered aspects such as fluid connections and item outputs centered on tiles.
        local maxItemTier = maxItemSpeed and
            math.floor(((math.sqrt(maxItemSpeed / speed) - 1) / 2) + 1)
            or math.huge
        local maxFluidTier = maxFluidSpeed and
            math.floor(((math.sqrt(maxFluidSpeed / speed) - 1) / 2) + 1)
            or math.huge
        -- cap drill sizes to ensure they fit in a single chunk (and limit ridiculousness for slow drills)
        local maxSizeTier = (((math.floor(32 / math.max(width, height)) - 1) / 2) + 1)
        local maxTier = math.min(maxItemTier, maxFluidTier, maxSizeTier)
        if maxTier == math.huge then
            log("Drill " .. name .. " produces no output?")
            goto skip_drill
        elseif maxTier < 2 then
            log(
                "Cannot create Drills of Drills for " .. name ..
                "; tier 2 drills would exceed cap in all cases"
            )
        else
            local lastTech = nil
            for tier = 2, maxTier do
                local tierScale = (2 * (tier - 1)) + 1
                local tierSquared = tierScale * tierScale
                -- deepcopy prototype to copy over values that don't need changing
                local newPrototype = table.deepcopy(prototype)

                -- basic values without spatial components
                newPrototype.max_health = newPrototype.max_health * tierSquared
                newPrototype.mining_speed = newPrototype.mining_speed * tierSquared
                newPrototype.resource_searching_radius =
                    ((newPrototype.resource_searching_radius + .01) * tierScale) - .01
                newPrototype.energy_usage = toEnergy(util.parse_energy(newPrototype.energy_usage) * tierSquared)
                local energySource = newPrototype.energy_source
                if energySource.emissions_per_minute then
                    for pollutionType, value in pairs(
                        energySource.emissions_per_minute
                    ) do
                        energySource.emissions_per_minute[pollutionType] =
                            energySource.emissions_per_minute[pollutionType] * tierSquared
                    end
                end

                -- reference values for entity size
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
                    }, {
                        width + widthOffset, height + heightOffset
                    }
                }

                -- graphics helper functions
                local directions = { "north", "south", "east", "west" }

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
                        anim.scale = (anim.scale or 1) * tierScale
                        anim.shift = anim.shift or {}
                        anim.shift[1] = (anim.shift[1] or 0) * tierScale
                        anim.shift[2] = (anim.shift[2] or 0) * tierScale
                    end
                end

                local function scaleSprite(sprite)
                    local directions16Way = table.pack(
                        "north_north_east", "north_east", "east_north_east",
                        "east_south_east", "south_east", "south_south_east",
                        "south_south_west", "south_west", "west_south_west",
                        "west_north_west", "north_west", "north_north_west",
                        table.unpack(directions)
                    )
                    directions16Way["n"] = nil
                    if sprite.sheets then
                        if sprite.sheets[1] then
                            for _, sheet in pairs(sprite.sheets) do
                                sheet.scale = (sheet.scale or 1) * tierScale
                                sheet.shift = sheet.shift or {}
                                sheet.shift[1] = (sheet.shift[1] or 0) * tierScale
                                sheet.shift[2] = (sheet.shift[2] or 0) * tierScale
                            end
                        else
                            local sheet = sprite.sheets
                            sheet.scale = (sheet.scale or 1) * tierScale
                            sheet.shift = sheet.shift or {}
                            sheet.shift[1] = (sheet.shift[1] or 0) * tierScale
                            sheet.shift[2] = (sheet.shift[2] or 0) * tierScale
                        end
                    elseif sprite.sheet then
                        sprite.sheet.scale = (sprite.sheet.scale or 1) * tierScale
                        sprite.sheet.shift = sprite.sheet.shift or {}
                        sprite.sheet.shift[1] = (sprite.sheet.shift[1] or 0) * tierScale
                        sprite.sheet.shift[2] = (sprite.sheet.shift[2] or 0) * tierScale
                    elseif sprite.north then
                        -- this will work for both Sprite4Ways and Sprite16Ways
                        for _, direction in pairs(directions16Way) do
                            if sprite[direction] then scaleSprite(sprite[direction]) end
                        end
                    elseif sprite.layers then
                        for _, layer in pairs(sprite.layers) do scaleSprite(layer) end
                    else
                        sprite.scale = (sprite.scale or 1) * tierScale
                        sprite.shift[1] = (sprite.shift[1] or 0) * tierScale
                        sprite.shift[2] = (sprite.shift[2] or 0) * tierScale
                    end
                end

                local function scaleMiningDrillGraphicsSet(mdgs)
                    if mdgs.frozen_patch then
                        scaleSprite(mdgs.frozen_patch)
                    end
                    if mdgs.animation then
                        scaleAnimation(mdgs.animation)
                    end
                    if mdgs.idle_animation then
                        scaleAnimation(mdgs.idle_animation)
                    end
                    if mdgs.integration_patch then
                        scaleSprite(mdgs.integration_patch)
                    end
                    if mdgs.working_visualisations then
                        for _, working_visualisation in pairs(mdgs.working_visualisations) do
                            if working_visualisation.animation then
                                scaleAnimation(working_visualisation.animation)
                            else
                                for _, direction in pairs(directions) do
                                    if working_visualisation[direction .. "_animation"] then
                                        scaleAnimation(working_visualisation[direction .. "_animation"])
                                    end
                                    if working_visualisation[direction .. "_position"] then
                                        working_visualisation[direction .. "_position"][1] =
                                            working_visualisation[direction .. "_position"][1] * tierScale
                                        working_visualisation[direction .. "_position"][2] =
                                            working_visualisation[direction .. "_position"][2] * tierScale
                                    end
                                end
                            end
                        end
                    end
                    if mdgs.shift_animation_waypoints and (mdgs.shift_animation_waypoint_stop_duration or mdgs.shift_animation_transition_duration) then
                        for _, direction in pairs(directions) do
                            for _, vector in pairs(mdgs.shift_animation_waypoints[direction]) do
                                vector[1] = vector[1] * tierScale
                                vector[2] = vector[2] * tierScale
                            end
                        end
                    end
                end

                local function scaleCircuitConnectorSprites(CCSprites)
                    scaleSprite(CCSprites.led_red)
                    scaleSprite(CCSprites.led_green)
                    scaleSprite(CCSprites.led_blue)
                    if CCSprites.led_light[1] then -- it's an array of lights
                        for _, light in pairs(CCSprites.led_light) do
                            local vector = light.shift
                            if vector then
                                vector[1] = vector[1] * tierScale
                                vector[2] = vector[2] * tierScale
                            end
                            light.size = light.size * tierScale
                            if light.picture then scaleSprite(light.picture) end
                        end
                    else
                        local light = CCSprites.led_light
                        local vector = light.shift
                        if vector then
                            vector[1] = vector[1] * tierScale
                            vector[2] = vector[2] * tierScale
                        end
                        light.size = light.size * tierScale
                        if light.picture then scaleSprite(light.picture) end
                    end
                    if CCSprites.connector_main then
                        scaleSprite(CCSprites.connector_main)
                    end
                    if CCSprites.connector_shadow then
                        scaleSprite(CCSprites.connector_shadow)
                    end
                    if CCSprites.wire_pins then scaleSprite(CCSprites.wire_pins) end
                    if CCSprites.wire_pins_shadow then scaleSprite(CCSprites.wire_pins_shadow) end
                    if CCSprites.led_blue_off then scaleSprite(CCSprites.led_blue_off) end
                    local vector = CCSprites.blue_led_light_offset
                    if vector then
                        vector[1] = vector[1] * tierScale
                        vector[2] = vector[2] * tierScale
                    end
                    vector = CCSprites.red_green_led_light_offset
                    if vector then
                        vector[1] = vector[1] * tierScale
                        vector[2] = vector[2] * tierScale
                    end
                end

                -- fix fluidboxes
                local fluidIn = newPrototype.input_fluid_box
                local fluidOut = newPrototype.output_fluid_box
                local fluidEnergy = energySource.fluid_box
                local bounds = {
                    [defines.direction.north] = 
                        {0, newPrototype.selection_box[1].y or 
                        newPrototype.selection_box[1][2]},
                    [defines.direction.east] =
                        {newPrototype.selection_box[2].x or 
                        newPrototype.selection_box[2][1], 0},
                    [defines.direction.south] = 
                        {0, newPrototype.selection_box[2].y or 
                        newPrototype.selection_box[2][2]},
                    [defines.direction.west] =
                        {newPrototype.selection_box[1].x or 
                        newPrototype.selection_box[1][1], 0}
                }

                local function fixFluidBoxConnections(pipeConnections)
                    for _, connection in pairs(pipeConnections) do
                        if connection.connection_type ~= "linked" then
                            -- determines the direction the connection points
                            local direction = connection.direction
                            -- if position exists, ignore positions
                            local position = connection.position
                            if position then
                                local bound = bounds[direction]
                                -- standardize format
                                position = {
                                    position.x or position[1], position.y or position[2]
                                }
                                for coordinate, value in pairs(bound) do
                                    if value ~= 0 then
                                        position[coordinate] = value * tierScale -
                                            (value - position[coordinate])
                                    else
                                        position[coordinate] = position[coordinate] * tierScale
                                    end
                                end
                                connection.position = position
                            else
                                for index, position in pairs(connection.positions) do
                                    direction = (connection.direction + (index - 1) * 4) % 16
                                    local bound = bounds[direction]
                                    position = {
                                        position.x or position[1], position.y or position[2]
                                    }
                                    for coordinate, value in pairs(bound) do
                                        if value ~= 0 then
                                            position[coordinate] = value * tierScale -
                                                (value - position[coordinate])
                                        else
                                            position[coordinate] = position[coordinate] * tierScale
                                        end
                                    end
                                    connection.positions[index] = position
                                end
                            end
                            
                        end
                    end
                end

                if fluidIn and fluidIn.pipe_connections then
                    fixFluidBoxConnections(fluidIn.pipe_connections)
                end

                if fluidOut and fluidOut.pipe_connections then
                    fixFluidBoxConnections(fluidOut.pipe_connections)
                end

                if fluidEnergy and fluidEnergy.pipe_connections then
                    fixFluidBoxConnections(fluidEnergy.pipe_connections)
                end

                -- bounding boxes and related values
                local vtpr = newPrototype.vector_to_place_result
                vtpr = {
                    vtpr.x or vtpr[1], vtpr.y or vtpr[2]
                }
                local closestBound
                local dtpr
                for direction, bound in pairs(bounds) do
                    for coordinate, value in pairs(bound) do
                        if value ~= 0 then
                            local margin = math.abs(value - vtpr[coordinate])
                            if (not closestBound) or (margin < closestBound) then
                                closestBound = margin
                                dtpr = direction
                            end
                        end
                    end
                end
                for coordinate, value in pairs(bounds[dtpr]) do
                    if value ~= 0 then
                        newPrototype.vector_to_place_result[coordinate] =
                            value * tierScale -
                            (value - newPrototype.vector_to_place_result[coordinate])
                    else
                        newPrototype.vector_to_place_result[coordinate] =
                            newPrototype.vector_to_place_result[coordinate] * tierScale
                    end
                end
                local bBoxes = {
                    "collision_box", "map_generator_bounding_box", "selection_box", "sticker_box",
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
                                (size[1].x or size[1][1]) * tierScale - (buffer[1].x or buffer[1][1]),
                                (size[1].y or size[1][2]) * tierScale - (buffer[1].y or buffer[1][2])
                            },
                            {
                                (size[2].x or size[2][1]) * tierScale - (buffer[2].x or buffer[2][1]),
                                (size[2].y or size[2][2]) * tierScale - (buffer[2].y or buffer[2][2])
                            }
                        }
                    end
                end
                if newPrototype.drawing_box_vertical_extension then
                    newPrototype.drawing_box_vertical_extension =
                        newPrototype.drawing_box_vertical_extension * tierScale
                end

                -- rescale graphics
                if newPrototype.graphics_set then
                    if newPrototype.graphics_set then
                        -- should be unnecessary, but can never be too safe
                        newPrototype.graphics_set = table.deepcopy(newPrototype.graphics_set)
                        scaleMiningDrillGraphicsSet(newPrototype.graphics_set)
                    end
                    if newPrototype.wet_mining_graphics_set then
                        newPrototype.wet_mining_graphics_set = table.deepcopy(newPrototype.wet_mining_graphics_set)
                        scaleMiningDrillGraphicsSet(newPrototype.wet_mining_graphics_set)
                    end
                end

                if newPrototype.base_picture then
                    newPrototype.base_picture = table.deepcopy(newPrototype.base_picture)
                    scaleSprite(newPrototype.base_picture)
                end

                if newPrototype.integration_patch then
                    newPrototype.integration_patch = table.deepcopy(newPrototype.integration_patch)
                    scaleSprite(newPrototype.integration_patch)
                end

                if newPrototype.circuit_connector then
                    for _, ccDef in pairs(newPrototype.circuit_connector) do
                        if ccDef.sprites then
                            ccDef.sprites = table.deepcopy(ccDef.sprites)
                            scaleCircuitConnectorSprites(ccDef.sprites)
                        end
                        if ccDef.points then
                            for _, wirePos in pairs(ccDef.points) do
                                for _, vector in pairs(wirePos) do
                                    vector[1] = vector[1] * tierScale
                                    vector[2] = vector[2] * tierScale
                                end
                            end
                        end
                    end
                end

                -- new item
                local item = getItemByName(name)
                -- can't guarantee the item name matches the entity name, but it's a good enough guess sometimes
                if (not item) or item.place_result ~= name then
                    item = getItemByPlaceResult(name)
                end
                item = table.deepcopy(item)

                local baseItem = item.name
                item.name = prefix .. "-" .. item.name .. "-" .. (tier - 1)
                item.place_result = prefix .. "-" .. newPrototype.name .. "-" .. (tier - 1)
                item.stack_size = math.max(math.ceil(item.stack_size / (tierSquared)), 1)
                item.subgroup = "drill-of-" .. name .. "s"
                item.order = string.format("%0" .. string.len(tostring(maxTier)) .. "d", tierScale)
                item.localised_name = { "item-name-placeholders.drill-of-drills", tostring(tierSquared),
                    prototype.localised_name or { "entity-name." .. name }
                }
                -- new name
                newPrototype.name = item.place_result
                newPrototype.minable = {
                    mining_time = ((newPrototype.minable or {}).mining_time or 1) * tierScale,
                    result = item.name,
                    count = 1
                }
                newPrototype.subgroup = "drill-of-" .. name .. "s"
                newPrototype.order = string.format("%0" .. string.len(tostring(maxTier)) .. "d", tierScale)
                newPrototype.next_upgrade = newPrototype.next_upgrade
                    and prefix .. "-" .. newPrototype.next_upgrade .. "-" .. tier - 1
                newPrototype.localised_name = { "item-name-placeholders.drill-of-drills", tostring(tierSquared),
                    prototype.localised_name or { "entity-name." .. name }
                }

                -- recipes
                local nulliusPrefix = mods["nullius"] and "nullius-" or ""
                local recipes = {}
                if tier > 2 then
                    local ingredientsTable = {}
                    local craftTime = .25
                    local drillTotal = tierSquared
                    for i = (tier - 1), 1, -1 do
                        local iScale = (2 * (i - 1)) + 1
                        local iSquared = iScale * iScale
                        if drillTotal >= iSquared then
                            if i == 1 then
                                table.insert(ingredientsTable, { 
                                    type = "item",
                                    name = baseItem, 
                                    amount = math.floor(drillTotal / (iSquared))
                                })
                                craftTime = math.floor(drillTotal / (iSquared)) / 4
                            else
                                table.insert(ingredientsTable, {
                                    type = "item",
                                    name = prefix .. "-" .. baseItem .. "-" .. i - 1, 
                                    amount = math.floor(drillTotal / (iSquared))
                                })
                            end
                            drillTotal = drillTotal % (iSquared)
                        end
                    end
                    table.insert(recipes, {
                        type = "recipe",
                        name = item.name .. "-upgrade",
                        localised_name = {"", {"recipe-name-placeholders.upgrade"},
                            { "item-name-placeholders.drill-of-drills", tostring(tierSquared),
                                prototype.localised_name or { "entity-name." .. name }
                            }
                        },
                        subgroup = "drill-of-" .. name .. "s-upgrade",
                        ingredients = ingredientsTable,
                        results = {
                            {type = "item", name = item.name, amount = 1}
                        },
                        energy_required = craftTime,
                        enabled = false,
                        allow_as_intermediate = false,
                        order = nulliusPrefix ..
                            string.format("%0" .. string.len(tostring(maxTier)) .. "d", tierScale)
                    })
                end
                table.insert(recipes, {
                    type = "recipe",
                    name = item.name,
                    subgroup = "drill-of-" .. name .. "s",
                    ingredients = { 
                        {
                            type = "item",
                            name = baseItem,
                            amount = tierSquared
                        }
                    },
                    results = {
                        {type = "item", name = item.name, amount = 1}
                    },
                    energy_required = tierSquared / 4,
                    enabled = false,
                    order = nulliusPrefix ..
                        string.format("%0" .. string.len(tostring(maxTier)) .. "d", tierScale)
                })
                table.insert(recipes, {
                    type = "recipe",
                    name = item.name .. "-disassembly",
                    localised_name = {"", {"recipe-name-placeholders.disassembly"},
                        { "item-name-placeholders.drill-of-drills", tostring(tierSquared),
                            prototype.localised_name or { "entity-name." .. name }
                        }
                    },
                    subgroup = "drill-of-" .. name .. "s-disassembly",
                    ingredients = { 
                        {
                            type = "item",
                            name = item.name,
                            amount = 1
                        } 
                    },
                    results = {
                        {type = "item", name = baseItem, amount = tierSquared}
                    },
                    energy_required = 2.5 * tierSquared,
                    enabled = false,
                    allow_as_intermediate = false,
                    allow_intermediates = false,
                    order = nulliusPrefix ..
                        string.format("%0" .. string.len(tostring(maxTier)) .. "d", tierScale)
                })
                if mods["nullius"] then -- explicit nullius compat, because nullius makes some extra assumptions
                    local category = "medium-crafting" -- default to all crafters
                    if string.find(item.name, "nullius%-medium%-miner") then
                        category = "large-crafting"
                    elseif string.find(item.name, "nullius%-large%-miner") then
                        category = "huge-crafting"
                    end
                    for _, recipe in pairs(recipes) do
                        recipe.category = category
                    end
                end

                -- unlock tech
                local tech = {
                    type = "technology",
                    name = item.name,
                    localised_name = newPrototype.localised_name,
                    icons = newPrototype.icons,
                    icon = newPrototype.icon,
                    icon_size = newPrototype.icon_size,
                    research_trigger = {
                        type = "craft-item",
                        item = baseItem,
                        count = tierSquared
                    },
                    enabled = true,
                    hidden = false,
                    prerequisites = lastTech and {lastTech} or nil,
                    effects = {}
                }
                for _, recipe in pairs(recipes) do
                    table.insert(tech.effects, {
                        type = "unlock-recipe",
                        recipe = recipe.name
                    })
                end
                lastTech = tech.name

                -- create tech, item, and drill
                data:extend{ newPrototype, item, tech }
                data:extend( recipes )
                data:extend( subgroups )
                -- register drill for control stage
                drillRegistry.data[newPrototype.name] = {stack = stack}
                log("Created " .. newPrototype.name .. " and its recipes for drill" .. name .. "(" .. tier - 1 .. "/" .. maxTier - 1 .. ")")
            end
        end
    end
    ::skip_drill::
end

-- cleanup nonexistent upgrades due to DoD tier limits
for drill, prototype in pairs(data.raw["mining-drill"]) do
    if not drills[drill] then
        if prototype.next_upgrade and not data.raw["mining-drill"][prototype.next_upgrade] then
            prototype.next_upgrade = nil
        end
    end
end

log("Finished creating Drills of Drills.")