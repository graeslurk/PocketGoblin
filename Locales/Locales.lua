-- Translations. All text the player sees goes through L["English text"];
-- anything without a translation for the client's language stays English.
--
-- To add a language: copy Locales/template.lua to Locales/<locale>.lua (for
-- example deDE.lua), fill it in and list it in PocketGoblin.toc after this
-- file. Regenerate the template with: node tools/localize.js template

local _, ns = ...

ns.L = setmetatable({}, {
    __index = function(_, english) return english end,
})

-- Called by a translation file: { ["English text"] = "translated text" }.
-- Only applies when the game runs in that language.
function ns.AddTranslations(locale, translations)
    if GetLocale() ~= locale then return end
    for english, translated in pairs(translations) do
        if translated ~= "" then rawset(ns.L, english, translated) end
    end
end
