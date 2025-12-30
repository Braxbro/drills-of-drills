-- bring forward a bunch of data from data stage so I don't have to fetch it again
local drillRegistry = prototypes.mod_data["drills-of-drills-registry"].data
local speedLimits = prototypes.mod_data["drills-of-drills-speed-limits"].data
local meld = require("meld")

local drillNames = {}
for name, baseName in pairs(drillRegistry) do
    table.insert(drillNames, name)
end

local function startup(data)
    storage.drills = storage.drills or {}
    storage.destroyedDrills = storage.destroyedDrills or {}
    storage.destroyedDrillsByUnitNumber = storage.destroyedDrillsByUnitNumber or {}
    storage.drillCount = 0
    for unit_number, drill in pairs(storage.drills) do
        if drill.valid then
            storage.drillCount = storage.drillCount + 1
        else
            storage.drills[unit_number] = nil
            storage.destroyedDrills[storage.destroyedDrillsByUnitNumber[unit_number]] = nil
            storage.destroyedDrillsByUnitNumber[unit_number] = nil
        end
    end
    storage.restriction_cycle = 0
end

script.on_init(startup)
script.on_configuration_changed(startup)

local function addDrillsOfDrills(onBuiltData)
    local drill = onBuiltData.entity
    if drillRegistry[drill.name] then 
        storage.drills[drill.unit_number] = drill
        local reg, unit = script.register_on_object_destroyed(drill)
        storage.destroyedDrills[reg] = unit
        storage.destroyedDrillsByUnitNumber[unit] = reg
        storage.drillCount = storage.drillCount + 1
    end
end

local function removeDrillsOfDrills(onDestroyData)
    local drill = storage.destroyedDrills[onDestroyData.registration_number]
    if not drill then return end -- not a drill of drills
    storage.drills[drill] = nil
    storage.destroyedDrillsByUnitNumber[drill] = nil
    storage.destroyedDrills[onDestroyData.registration_number] = nil
    storage.drillCount = storage.drillCount - 1
end

script.on_event(defines.events.on_built_entity, addDrillsOfDrills, {{filter = "type", type = "mining-drill"}})
script.on_event(defines.events.on_object_destroyed, removeDrillsOfDrills)

local function getSpeedLimit(drill)
    -- non-Drills of Drills are not speed limited by Drills of Drills.
    if not drillRegistry[drill.name] then return nil end
    -- don't restrict speed of drills that have yet to select a mining_target.
    if not drill.mining_target then return nil end
    local speedLimit = speedLimits[drill.mining_target.name]
    local maxItemSpeed
    local maxFluidSpeed = speedLimit.maxFluidSpeed
    if drillRegistry[drill.name].stack then
        maxItemSpeed = speedLimit.maxStackedSpeed
    else
        maxItemSpeed = speedLimit.maxUnstackedSpeed
    end
    return math.min(maxItemSpeed, maxFluidSpeed)
end

local function restrictSpeed(priorityOnly, specificPlayer)
    if storage.drillCount <= 0 then return end -- only restrict speed if there's something to restrict
    local toRestrict = storage.drills
    if priorityOnly then
        toRestrict = {}
        local function getNearbyDrills(player)
            if not player.character then return {} end
            local found = {}
            local pos = player.character.position
            local reachDistance = player.character.reach_distance * 2
            local area = {
                {pos.x - reachDistance, pos.y - reachDistance}, 
                {pos.x + reachDistance, pos.y + reachDistance}
            }
            local priorityDrills = player.character.surface.find_entities_filtered{
                area = area, name = drillNames, type = "mining-drill"
            }
            for _, drill in pairs(priorityDrills) do
                found[drill.unit_number] = drill
            end
            return found
        end

        if not specificPlayer then
            for name, player in pairs(game.connected_players) do
                meld.meld(toRestrict, getNearbyDrills(player))
            end
        else
            toRestrict = getNearbyDrills(specificPlayer)
        end
    end
    for unitNumber, drill in pairs(toRestrict) do
        -- drill's overcapped
        if (
            drill.prototype.mining_speed * (1 + drill.speed_bonus) > (getSpeedLimit(drill) or math.huge)
        ) then
            drill.active = false
            drill.custom_status = {
                diode = defines.entity_status_diode.red,
                label = {"alerts.drill-jammed"}
            }
        else
            drill.active = true
            drill.custom_status = nil
        end
    end
end

-- Enforce restrictions upon drills near players every 5 seconds, 
-- and enforce restrictions upon all drills every 30 seconds
script.on_nth_tick(300, function()
    restrictSpeed(storage.restriction_cycle ~= 0)
    storage.restriction_cycle = (storage.restriction_cycle + 1) % 6
end)

script.on_event(defines.events.on_player_cursor_stack_changed,
    function(data)
        local player = game.players[data.player_index]
        restrictSpeed(true, player)
    end
)
script.on_event(defines.events.on_player_fast_transferred,
    function(data)
        local player = game.players[data.player_index]
        restrictSpeed(true, player)
    end
)