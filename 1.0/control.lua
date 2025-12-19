---@diagnostic disable: param-type-mismatch
---@diagnostic disable: assign-type-mismatch
---@diagnostic disable: need-check-nil
---@diagnostic disable: missing-fields

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
        global.destroyedDrillsByUnitNumber[drill.unit_number] = script.register_on_entity_destroyed(drill)
        global.destroyedDrills[global.destroyedDrillsByUnitNumber[drill.unit_number]] = drill.unit_number
        for category, supported in pairs(drill.prototype.resource_categories) do
            if supported then
                global.speedLimit[drill.unit_number] = math.min(global.speedLimit[drill.unit_number] or math.huge, 60 * global.minimumMiningTime[category] / math.max(1, drill.productivity_bonus))
            end
        end
    end
end

local function refreshSpeedLimits()
    for unitNumber, drill in pairs(global.drills) do
        for category, supported in pairs(drill.prototype.resource_categories) do
            if supported then
                global.speedLimit[unitNumber] = math.min(global.speedLimit[unitNumber], 60 * global.minimumMiningTime[category] / math.max(1, drill.productivity_bonus))
            end
        end
    end
end

local function removeDrillsOfDrills(data)
    if not global.destroyedDrills[data.registration_number] then return end -- it's not a drill of drills
    global.destroyedDrillsByUnitNumber[global.destroyedDrills[data.registration_number]] = nil
    global.drills[global.destroyedDrills[data.registration_number]] = nil
    global.destroyedDrills[data.registration_number] = nil
end

local function restrictSpeed(priorityOnly, specificPlayer)
    if not global.drillNames[1] then return end -- there have been no drills of drills placed!
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
        if global.drills[unitNumber] then -- ensure the drill is a drill of drills
            local shapeId = global.overcapShapes[unitNumber]
            if not global.speedLimit[unitNumber] then refreshSpeedLimits() end
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
script.on_nth_tick(750, function() 
    restrictSpeed(false) 
end)
script.on_nth_tick(150, function() 
    restrictSpeed(true) 
end)
script.on_nth_tick(15, blink)

local function researched(data, isStartup)
    global.unlockedSubgroups[data.research.force.name] = global.unlockedSubgroups[data.research.force.name] or {} -- make sure the table has a value for the force
    local effects = data.research.effects
    for _, effect in pairs(effects) do
        if effect.type == "unlock-recipe" then
            local recipe = game.recipe_prototypes[effect.recipe]
            for _, product in pairs(recipe.products) do
                if product.type == "item" then
                    local productItem = game.item_prototypes[product.name]
                    if productItem.place_result and productItem.place_result.type == "mining-drill" then
                        local groupName = "drill-of-" .. productItem.place_result.name .. "s"
                        if game.item_subgroup_prototypes[groupName] then -- it has Drills of Drills!
                            local recipes = game.get_filtered_recipe_prototypes{
                                {
                                    filter = "has-product-item",
                                    elem_filters = {
                                        {
                                            filter = "subgroup",
                                            subgroup = groupName
                                        }
                                    }
                                },
                                {
                                    filter = "has-ingredient-item",
                                    elem_filters = {
                                        {
                                            filter = "subgroup",
                                            subgroup = groupName
                                        }
                                    },
                                    mode = "or"
                                }
                            }
                            for _, recipeToUnlock in pairs(recipes) do
                                data.research.force.recipes[recipeToUnlock.name].enabled = true
                            end
                            global.unlockedSubgroups[data.research.force.name][groupName] = global.unlockedSubgroups[data.research.force.name][groupName] or {}
                            for index, techName in pairs(global.unlockedSubgroups[data.research.force.name][groupName]) do -- prevent duplication
                                if techName == data.research.name then
                                    table.remove(global.unlockedSubgroups[data.research.force.name][groupName], index)
                                end
                            end
                            table.insert(global.unlockedSubgroups[data.research.force.name][groupName], data.research.name)
                        end
                    end
                end
            end
        end
    end
    global.technologyMap[data.research.name].researched = true
    if not isStartup then
        for _, prerequisite in pairs(global.technologyMap[data.research.name].prerequisites) do
            if not global.technologyMap[prerequisite].researched then -- Was a technology missed?
                data.research = data.research.force.technologies[prerequisite]
                researched(data)
            end
        end
    end
    refreshSpeedLimits()
    restrictSpeed()
end

script.on_event(defines.events.on_research_finished, researched)

local function unresearched(data)
    global.unlockedSubgroups[data.research.force.name] = global.unlockedSubgroups[data.research.force.name] or {}
    local effects = data.research.effects
    for _, effect in pairs(effects) do
        if effect.type == "unlock-recipe" then
            local recipe = game.recipe_prototypes[effect.recipe]
            for _, product in pairs(recipe.products) do
                if product.type == "item" then
                    local productItem = game.item_prototypes[product.name]
                    if productItem.place_result and productItem.place_result.type == "mining-drill" then
                        local groupName = "drill-of-" .. productItem.place_result.name .. "s"
                        if global.unlockedSubgroups[data.research.force.name][groupName] then -- it has Drills of Drills!
                            for index, name in pairs(global.unlockedSubgroups[data.research.force.name][groupName]) do
                                if name == data.research.name then
                                    table.remove(global.unlockedSubgroups[data.research.force.name][groupName], index)
                                end
                            end
                            if not table.unpack(global.unlockedSubgroups[data.research.force.name][groupName]) then -- if there are no sources unlocked
                                local recipes = game.get_filtered_recipe_prototypes{
                                    {
                                        filter = "has-product-item",
                                        elem_filters = {
                                            {
                                                filter = "subgroup",
                                                subgroup = groupName
                                            }
                                        }
                                    },
                                    {
                                        filter = "has-ingredient-item",
                                        elem_filters = {
                                            {
                                                filter = "subgroup",
                                                subgroup = groupName
                                            }
                                        },
                                        mode = "or"
                                    }
                                }
                                for _, recipeToLock in pairs(recipes) do
                                    data.research.force.recipes[recipeToLock.name].enabled = false
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    global.technologyMap[data.research.name].researched = false
    for _, dependency in pairs(global.technologyMap[data.research.name].dependencies) do
        if global.technologyMap[dependency].researched then -- a dependency was previously researched
            data.research = data.research.force.technologies[dependency]
            unresearched(data)
        end
    end
    refreshSpeedLimits()
    restrictSpeed()
end

script.on_event(defines.events.on_research_reversed, unresearched)

local function techReset(data)
    for _, technology in pairs(data.force.technologies) do
        if technology.enabled and technology.researched then
            local tbl = {
                research = technology,
                by_script = true,
                name = defines.events.on_research_finished,
                tick = game.tick
            }
            researched(tbl, true)
        end
    end
end

script.on_event(defines.events.on_technology_effects_reset, techReset)

local function startup(data)
    global.unlockedSubgroups = global.unlockedSubgroups or {}
    global.technologyMap = {}
    global.drills = global.drills or {}
    global.drillNames = global.drillNames or {}
    global.speedLimit = global.speedLimit or {}
    global.minimumMiningTime = global.minimumMiningTime or {}
    global.minimumMiningTimeTarget = global.minimumMiningTimeTarget or {}
    global.destroyedDrills = global.destroyedDrills or {}
    global.destroyedDrillsByUnitNumber = global.destroyedDrillsByUnitNumber or {}
    global.overcapShapes = global.overcapShapes or {}
    for name, technology in pairs(game.technology_prototypes) do -- rebuild tech map
        global.technologyMap[name] = global.technologyMap[name] or {prerequisites = {}, dependencies = {}, researched = false}
        for prereqName, _ in pairs(technology.prerequisites) do
            global.technologyMap[prereqName] = global.technologyMap[prereqName] or {prerequisites = {}, dependencies = {}, researched = false}
            table.insert(global.technologyMap[name].prerequisites, prereqName)
            table.insert(global.technologyMap[prereqName].dependencies, name)
        end
    end
    local resources = game.get_filtered_entity_prototypes{{filter = "type", type = "resource"}}
    for name, prototype in pairs(resources) do
        local category = prototype.resource_category or "basic-solid"
        local miningTime = prototype.mineable_properties and prototype.mineable_properties.mining_time or 1
        if (not global.minimumMiningTime[category]) or (global.minimumMiningTime[category] > miningTime) then -- store info about fastest ores of a type
            global.minimumMiningTime[category] = miningTime
            global.minimumMiningTimeTarget[category] = name
        end
    end
    for category, _ in pairs(game.resource_category_prototypes) do -- make sure every category, even if empty, has a value
        global.minimumMiningTime[category] = global.minimumMiningTime[category] or 1
    end
    do -- Re-create list of all drills of drills.
        for _, surface in pairs(game.surfaces) do
            for index, entity in pairs(surface.find_entities_filtered{type = "mining-drill"}) do
                if entity.prototype.group.name == "drills-of-drills" then
                    addDrillsOfDrills({created_entity = entity}) -- if it's already there, it'll overwrite the entity's existing entries and do nothing. If it's not, it'll create one for it.
                end
            end
        end
    end
    for _, force in pairs(game.forces) do
        local tbl = {
            force = force,
            name = defines.events.on_technology_effects_reset,
            tick = game.tick
        }
        techReset(tbl)
    end
    refreshSpeedLimits()
    restrictSpeed()
    for _, force in pairs(game.forces) do
        force.reset_technology_effects()
    end
end

script.on_init(startup)
script.on_configuration_changed(startup)