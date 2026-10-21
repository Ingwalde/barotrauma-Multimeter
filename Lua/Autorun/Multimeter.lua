-- Multimeter: hold the eg_multimeter item, point at a device and press use (LMB).
-- Shows supply, load and voltage of junction boxes and relays, charge of batteries,
-- and voltage / power draw of any other powered device.
--
-- Runs on the server in multiplayer (readings go to the user's chat) and on the
-- client in single player (readings appear as an on-screen message).

if CLIENT and Game.IsMultiplayer then return end

local LANG = "uk"         -- "uk" or "en"
local COOLDOWN = 1.0      -- seconds between readings per character
local IDENTIFIER = "eg_multimeter"

local TEXT = {
    en = {
        title = "Multimeter: %s",
        broken = "Broken (condition 0%). No power passes through.",
        supply = "Supply: %.0f kW | Load: %.0f kW",
        relay_supply = "Output grid supply: %.0f kW | Load: %.0f kW",
        relay_voltage = "Output voltage: %d%%",
        relay_off = "Status: relay is off. No power passes through.",
        relay_disconnected = "Status: relay output is not connected to a power grid.",
        voltage = "Voltage: %d%% (overload at %d%%)",
        voltage_dev = "Voltage: %d%% (needs %d%%)",
        draw = "Draw: %.0f kW (rated %.0f kW)",
        charge = "Charge: %d%% (%.0f / %.0f kW*min)",
        output = "Output: %.0f kW (max %.0f) | Recharge: %.0f / %.0f kW",
        condition = "Condition: %d%%",
        ok = "Status: OK",
        overload = "Status: OVERLOAD - the box is taking damage. Reduce reactor output or add load.",
        near = "Status: close to overload. Lower reactor output a little.",
        low = "Status: not enough power. Raise reactor output or switch something off.",
        nopower = "Status: no power.",
        notpowered = "Not an electrical device.",
        nothing = "Point at a device first (it should be highlighted).",
    },
    uk = {
        title = "Мультиметр: %s",
        broken = "Зламано (стан 0%). Струм не проходить.",
        supply = "Подача: %.0f кВт | Навантаження: %.0f кВт",
        relay_supply = "Подача у вихідній мережі: %.0f кВт | Навантаження: %.0f кВт",
        relay_voltage = "Вихідна напруга: %d%%",
        relay_off = "Статус: реле вимкнене. Струм не проходить.",
        relay_disconnected = "Статус: вихід реле не підключений до електромережі.",
        voltage = "Напруга: %d%% (перевантаження з %d%%)",
        voltage_dev = "Напруга: %d%% (потрібно %d%%)",
        draw = "Споживання: %.0f кВт (номінал %.0f кВт)",
        charge = "Заряд: %d%% (%.0f / %.0f кВт*хв)",
        output = "Віддача: %.0f кВт (макс %.0f) | Зарядка: %.0f / %.0f кВт",
        condition = "Стан: %d%%",
        ok = "Статус: норма",
        overload = "Статус: ПЕРЕВАНТАЖЕННЯ - коробка горить. Зменш потужність реактора або додай навантаження.",
        near = "Статус: близько до перевантаження. Трохи зменш потужність реактора.",
        low = "Статус: не вистачає живлення. Підніми потужність реактора або вимкни щось.",
        nopower = "Статус: немає живлення.",
        notpowered = "Це не електричний пристрій.",
        nothing = "Спершу наведи на пристрій (він має підсвітитися).",
    },
}

local function T(key) return (TEXT[LANG] or TEXT.en)[key] or TEXT.en[key] end
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
local function measure(item)
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

local function show(user, lines)
    if SERVER then
        for _, client in pairs(Client.ClientList) do
            if client.Character == user then
                for _, line in ipairs(lines) do
                    local msg = ChatMessage.Create("", line, ChatMessageType.Server, nil, nil)
                    msg.Color = COLOR
                    Game.SendDirectChatMessage(msg, client)
                end
                return
            end
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

    local target = user.FocusedItem
    if target == nil or target == item then
        show(user, { T("nothing") })
        return
    end

    local ok, result = pcall(measure, target)
    if ok then
        show(user, result)
    else
        print("[Multimeter] error: " .. tostring(result))
    end
end)

print("[Multimeter] loaded")
