local Language = {}

-- Names match the language attributes in Barotrauma's vanilla text packs.
Language.languages = {
    english = "en", ukrainian = "uk", german = "de", french = "fr",
    polish = "pl", russian = "ru", brazilianportuguese = "pt-BR",
    castilianspanish = "es", latinamericanspanish = "es-419",
    turkish = "tr", japanese = "ja", korean = "ko",
    simplifiedchinese = "zh-CN", traditionalchinese = "zh-TW",
}

local function normalized(value)
    return tostring(value):lower():gsub("[%s_%-]", "")
end

function Language.resolve(value)
    if value == nil then return "en" end
    if type(value) ~= "string" then
        local ok, identifier = pcall(function() return value.Value end)
        if ok and identifier ~= nil then value = identifier end
    end
    local name = normalized(value)
    if Language.languages[name] then return Language.languages[name] end
    for _, code in pairs(Language.languages) do
        if name == normalized(code) then return code end
    end
    return "en"
end

-- Read at measurement time, so changes never leak between players or go stale.
-- On servers, use the recipient's language, never the server's configuration.
function Language.current(client)
    local ok, value = pcall(function()
        if SERVER then return client.Language end
        return Game.Settings.CurrentConfig.Language
    end)
    return Language.resolve(ok and value or nil)
end

return Language
