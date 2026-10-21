-- Multimeter: hold the eg_multimeter item, point at a device and press use (LMB).
-- Shows supply, load and voltage of junction boxes and relays, charge of batteries,
-- and voltage / power draw of any other powered device.
--
-- Runs on the server in multiplayer (readings go to the user's chat) and on the
-- client in single player (readings appear as an on-screen message).

if CLIENT and Game.IsMultiplayer then return end

local COOLDOWN = 1.0      -- seconds between readings per character
local IDENTIFIER = "eg_multimeter"

local modPath = ...
local Strings = dofile(modPath .. "/Lua/Multimeter/Strings.lua")
local Language = dofile(modPath .. "/Lua/Multimeter/Language.lua")

local function translator(client)
    local messages = Strings[Language.current(client)] or Strings.en
    return function(key) return messages[key] or Strings.en[key] end
end

local function pct(x) return math.floor((x or 0) * 100 + 0.5) end

local function gridOf(powerTransfer, connectionName)
    for _, conn in pairs(powerTransfer.PowerConnections) do
        if (connectionName == nil or conn.Name == connectionName) and conn.Grid ~= nil then
            return conn.Grid
        end
    end
    return nil
end

-- Returns a list of lines describing the target item.
local function measure(item, T)
    local lines = { string.format(T("title"), item.Name) }

    local relay = item.GetComponentString("RelayComponent")
    local pt = relay or item.GetComponentString("PowerTransfer")
    if pt ~= nil then
        if item.Condition <= 0 then
            lines[#lines + 1] = T("broken")
            return lines
        end
        if relay ~= nil then
            -- Input and output are separate grids; input voltage does not describe
            -- the devices behind a disabled or power-limited relay.
            local grid = gridOf(relay, "power_out")
            if grid ~= nil then
                lines[#lines + 1] = string.format(T("relay_supply"), grid.Power, grid.Load)
                lines[#lines + 1] = string.format(T("relay_voltage"), pct(grid.Voltage))
            end
            lines[#lines + 1] = string.format(T("condition"), math.floor(item.ConditionPercentage + 0.5))
            if not relay.IsOn then
                lines[#lines + 1] = T("relay_off")
            elseif grid == nil then
                lines[#lines + 1] = T("relay_disconnected")
            elseif grid.Load > 0 and grid.Voltage <= 0.01 then
                lines[#lines + 1] = T("nopower")
            elseif grid.Load > 0 and grid.Voltage < 0.5 then
                lines[#lines + 1] = T("low")
            else
                lines[#lines + 1] = T("ok")
            end
            return lines
        end
        local grid = gridOf(pt)
        local voltage = pt.Voltage
        local load = grid and grid.Load or pt.PowerLoad
        -- voltage is supply / load, so without grid info the supply can be derived from it
        local supply = grid and grid.Power or load * voltage
        local limit = math.max(pt.OverloadVoltage, 1.0)
        lines[#lines + 1] = string.format(T("supply"), supply, load)
        lines[#lines + 1] = string.format(T("voltage"), pct(voltage), pct(limit))
        lines[#lines + 1] = string.format(T("condition"), math.floor(item.ConditionPercentage + 0.5))
        if pt.CanBeOverloaded and (pt.Overload or voltage > limit) then
            lines[#lines + 1] = T("overload")
        elseif pt.CanBeOverloaded and voltage > limit * 0.85 then
            lines[#lines + 1] = T("near")
        elseif load > 0 and voltage <= 0.01 then
            lines[#lines + 1] = T("nopower")
        elseif load > 0 and voltage < 0.5 then
            lines[#lines + 1] = T("low")
        else
            lines[#lines + 1] = T("ok")
        end
        return lines
    end

    local battery = item.GetComponentString("PowerContainer")
    if battery ~= nil then
        lines[#lines + 1] = string.format(T("charge"), math.floor(battery.ChargePercentage + 0.5), battery.Charge, battery.GetCapacity())
        lines[#lines + 1] = string.format(T("output"), battery.CurrPowerOutput, battery.MaxOutPut, battery.RechargeSpeed, battery.MaxRechargeSpeed)
        lines[#lines + 1] = string.format(T("condition"), math.floor(item.ConditionPercentage + 0.5))
        return lines
    end

    local powered = item.GetComponentString("Powered")
    if powered ~= nil then
        local voltage, minVoltage = powered.Voltage, powered.MinVoltage
        lines[#lines + 1] = string.format(T("voltage_dev"), pct(voltage), pct(minVoltage))
        lines[#lines + 1] = string.format(T("draw"), powered.CurrPowerConsumption, powered.PowerConsumption)
        lines[#lines + 1] = string.format(T("condition"), math.floor(item.ConditionPercentage + 0.5))
        if powered.PowerConsumption > 0 and voltage <= 0.01 then
            lines[#lines + 1] = T("nopower")
        elseif powered.PowerConsumption > 0 and voltage < minVoltage then
            lines[#lines + 1] = T("low")
        else
            lines[#lines + 1] = T("ok")
        end
        return lines
    end

    lines[#lines + 1] = T("notpowered")
    return lines
end

local COLOR = Color(120, 220, 255, 255)

local function show(client, lines)
    if SERVER then
        for _, line in ipairs(lines) do
            local msg = ChatMessage.Create("", line, ChatMessageType.Server, nil, nil)
            msg.Color = COLOR
            Game.SendDirectChatMessage(msg, client)
        end
    else
        GUI.AddMessage(table.concat(lines, "\n"), COLOR, 6.0)
    end
end

local lastUse = {}

Hook.Add("item.use", "multimeter.use", function(item, user, targetLimb, useTarget)
    if item == nil or user == nil then return end
    if string.lower(item.Prefab.Identifier.Value) ~= IDENTIFIER then return end

    -- Item.Use fires every frame while the button is held: throttle per character.
    local now = Timer.GetTime()
    local key = user.ID
    if lastUse[key] and now - lastUse[key] < COOLDOWN then return end
    lastUse[key] = now

    local client
    if SERVER then
        for _, connected in pairs(Client.ClientList) do
            if connected.Character == user then
                client = connected
                break
            end
        end
        if client == nil then return end
    end
    local T = translator(client)
    local target = user.FocusedItem
    if target == nil or target == item then
        show(client, { T("nothing") })
        return
    end

    local ok, result = pcall(measure, target, T)
    if ok then
        show(client, result)
    else
        print("[Multimeter] error: " .. tostring(result))
    end
end)

print("[Multimeter] loaded")
