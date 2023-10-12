---@diagnostic disable: param-type-mismatch
---@diagnostic disable: assign-type-mismatch
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields
local hasStarted = false

local minimumMiningTime = {}
local minimumMiningTimeTarget = {}

local function addDrillsOfDrills(data)
    local drill = data.created_entity
    if drill.prototype.group.name == "drills-of-drills" then
        local isRegistered
        for _, name in pairs(global.drillNames) do
            if name == drill.name then
                isRegistered = true
            end
        end
        if not isRegistered then 
            table.insert(global.drillNames, drill.name)
        end
        global.drills[drill.unit_number] = drill
        global.destroyedDrills[script.register_on_entity_destroyed(drill)] = drill.unit_number
        for category, supported in pairs(drill.prototype.resource_categories) do
            if supported then
                global.speedLimit[drill.unit_number] = math.min(global.speedLimit[drill.unit_number] or math.huge, 60 * minimumMiningTime[category] / math.max(1, drill.productivity_bonus))
            end
        end
    end
end

local function refreshSpeedLimits()
    for unitNumber, drill in pairs(global.drills) do
        for category, supported in pairs(drill.prototype.resource_categories) do
            if supported then
                global.speedLimit[unitNumber] = math.min(global.speedLimit[unitNumber], 60 * minimumMiningTime[category] / math.max(1, drill.productivity_bonus))
            end
        end
    end
end

local function removeDrillsOfDrills(data)
    if not global.destroyedDrills[data.registration_number] then return end -- it's not a drill of drills
    global.drills[global.destroyedDrills[data.registration_number]] = nil
end

local function restrictSpeed(priorityOnly, specificPlayer)
    local drills = global.drills
    if priorityOnly then
        drills = {}
        if not specificPlayer then
            for name, player in pairs(game.players) do -- Update drills around players more often, as they're more likely to overcap.
                if player.character then
                    local pos = player.character.position
                    local reachDistance = player.character.reach_distance + 1
                    local area = {{pos.x - reachDistance, pos.y - reachDistance}, {pos.x + reachDistance, pos.y + reachDistance}}
                    local priorityDrills = player.character.surface.find_entities_filtered{area = area, name = global.drillNames, type = "mining-drill"}
                    for _, drill in pairs(priorityDrills) do
                        drills[drill.unit_number] = drill
                    end
                end
            end
        else
            local player = specificPlayer
            if player.character then
                local pos = player.character.position
                local reachDistance = player.character.reach_distance + 1
                local area = {{pos.x - reachDistance, pos.y - reachDistance}, {pos.x + reachDistance, pos.y + reachDistance}}
                local priorityDrills = player.character.surface.find_entities_filtered{area = area, name = global.drillNames, type = "mining-drill"}
                for _, drill in pairs(priorityDrills) do
                    drills[drill.unit_number] = drill
                end
            end
        end
    end
    for unitNumber, drill in pairs(drills) do
        local shapeId = global.overcapShapes[unitNumber]
        if drill.prototype.mining_speed * (1 + drill.speed_bonus) > global.speedLimit[unitNumber] then
            drill.active = false
            if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
            shapeId = rendering.draw_sprite{
                sprite = "utility/danger_icon",
                surface = drill.surface,
                target = drill,
                x_scale = 1,
                y_scale = 1,
                target_offset = drill.prototype.alert_icon_shift
            }
            local pos = drill.position
            pos.x = pos.x + 1
            drill.surface.create_entity{name = "flying-text", position = pos, text = {"alerts.drill-jammed"}}
            global.overcapShapes[unitNumber] = shapeId
        elseif drill.prototype.mining_speed * (1 + drill.speed_bonus) <= global.speedLimit[unitNumber] then
            if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
            drill.active = true
        end
    end
end

local function blink()
    for index, shapeId in pairs(global.overcapShapes) do
        if not rendering.is_valid(shapeId) then
            global.overcapShapes[index] = nil
            return
        end
        rendering.set_visible(shapeId, not rendering.get_visible(shapeId))
    end
end

local function researched(data)
    local toUnlock = global.techSubgroupUnlocks[data.research.name] -- look up subgroups to unlock
    if not toUnlock then return end
    local recipeFilter = {}
    for _, subgroup in pairs(toUnlock) do
        table.insert(recipeFilter, {
            filter = "has-ingredient-item",
            elem_filters = {{
                filter = "subgroup",
                subgroup = subgroup
            }},
            mode = recipeFilter[1] and "or" or nil
        })
        table.insert(recipeFilter, {
            filter = "has-product-item",
            elem_filters = {{
                filter = "subgroup",
                subgroup = subgroup
            }},
            mode = "or"
        })
    end
    for name, _ in pairs(game.get_filtered_recipe_prototypes(recipeFilter)) do
        data.research.force.recipes[name].enabled = true
    end
    refreshSpeedLimits()
    restrictSpeed()
end

local function startup(data)
    if hasStarted then return end
    global.techSubgroupUnlocks = {}
    global.drills = {}
    global.drillNames = {}
    global.speedLimit = {}
    global.destroyedDrills = {}
    global.overcapShapes = {}
    do -- Create a global lookup table for the drills of drills unlocked by a given technology.
        local subgroups = game.item_group_prototypes["drills-of-drills"].subgroups
        local itemFilter = {}
        for _, subgroup in pairs(subgroups) do
            local elem = {}
            if itemFilter[1] then
                elem.mode = "and"
            end
            elem.filter = "subgroup"
            elem.subgroup = subgroup.name
            elem.invert = true
            table.insert(itemFilter, elem)
        end
        table.insert(itemFilter, {
            filter = "place-result",
            mode = "and",
            elem_filters = {{
                filter = "type",
                type = "mining-drill"
            }}
        })
        for name, _ in pairs(game.get_filtered_item_prototypes(itemFilter)) do
            local subgroupName = "drill-of-" .. name .. "s"
            local techFilter = {}
            for recipeName, _ in pairs(game.get_filtered_recipe_prototypes({{
                filter = "has-product-item",
                elem_filters = {{
                    filter = "name",
                    name = name
                }}
            }})) do
                table.insert(techFilter,{
                    filter = "unlocks-recipe",
                    recipe = recipeName,
                    mode = (techFilter[1]) and "or" or nil
                })
            end
            for techName, _ in pairs(game.get_filtered_technology_prototypes(techFilter)) do
                global.techSubgroupUnlocks[techName] = global.techSubgroupUnlocks[techName] or {}
                table.insert(global.techSubgroupUnlocks[techName], subgroupName)
            end
        end
    end
    do -- Re-create list of all drills of drills.
        for _, surface in pairs(game.surfaces) do
            for index, entity in pairs(surface.find_entities_filtered{type = "mining-drill"}) do
                if entity.prototype.group.name == "drills-of-drills" then
                    global.drills[entity.unit_number] = entity
                end
            end
        end
    end
    local resources = game.get_filtered_entity_prototypes{{filter = "type", type = "resource"}}
    for name, prototype in pairs(resources) do
        local category = prototype.resource_category or "basic-solid"
        local miningTime = prototype.mineable_properties and prototype.mineable_properties.mining_time or 1
        if (not minimumMiningTime[category]) or (minimumMiningTime[category] > miningTime) then -- store info about fastest ores of a type
            minimumMiningTime[category] = miningTime
            minimumMiningTimeTarget[category] = name
        end
    end
    
    for category, _ in pairs(game.resource_category_prototypes) do -- make sure every category, even if empty, has a value
        minimumMiningTime[category] = minimumMiningTime[category] or 1
    end
    
    restrictSpeed()
end

script.on_event(defines.events.on_research_finished, researched)
script.on_init(startup)
script.on_configuration_changed(startup)
script.on_event(defines.events.on_built_entity, addDrillsOfDrills, {{filter = "type", type = "mining-drill"}})
script.on_event(defines.events.on_entity_destroyed, removeDrillsOfDrills)
script.on_event(defines.events.on_player_cursor_stack_changed, function(data)
    local player = game.players[data.player_index]
    if player.opened_gui_type == defines.gui_type.entity then
        local entity = player.opened
        local unitNumber = entity.unit_number
        if unitNumber and global.drills[unitNumber] then
            local shapeId = global.overcapShapes[unitNumber]
            if entity.prototype.mining_speed * (1 + entity.speed_bonus) > global.speedLimit[unitNumber] then
                entity.active = false
                if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
                shapeId = rendering.draw_sprite{
                    sprite = "utility/danger_icon",
                    surface = entity.surface,
                    target = entity,
                    x_scale = 1,
                    y_scale = 1,
                    target_offset = entity.prototype.alert_icon_shift
                }
                local pos = entity.position
                pos.x = pos.x + 1
                entity.surface.create_entity{name = "flying-text", position = pos, text = {"alerts.drill-jammed"}}
                global.overcapShapes[unitNumber] = shapeId
            elseif entity.prototype.mining_speed * (1 + entity.speed_bonus) <= global.speedLimit[unitNumber] then
                if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
                entity.active = true
            end
        end
    end
end)
script.on_event(defines.events.on_player_fast_transferred, function(data)
    local entity = data.entity
    local unitNumber = entity.unit_number
    if unitNumber and global.drills[unitNumber] then
        local shapeId = global.overcapShapes[unitNumber]
        if entity.prototype.mining_speed * (1 + entity.speed_bonus) > global.speedLimit[unitNumber] then
            entity.active = false
            if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
            shapeId = rendering.draw_sprite{
                sprite = "utility/danger_icon",
                surface = entity.surface,
                target = entity,
                x_scale = 1,
                y_scale = 1,
                target_offset = entity.prototype.alert_icon_shift
            }
            local pos = entity.position
            pos.x = pos.x + 1
            entity.surface.create_entity{name = "flying-text", position = pos, text = {"alerts.drill-jammed"}}
            global.overcapShapes[unitNumber] = shapeId
        elseif entity.prototype.mining_speed * (1 + entity.speed_bonus) <= global.speedLimit[unitNumber] then
            if shapeId and rendering.is_valid(shapeId) then rendering.destroy(shapeId) end
            entity.active = true
        end
    end
end)
script.on_nth_tick(750, function() restrictSpeed(false) end)
script.on_nth_tick(150, function() restrictSpeed(true) end)
script.on_nth_tick(15, blink)