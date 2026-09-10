-- Exercise the production resolver with English results from the native
-- translator (missing/overridden CN keys), without changing global getText.
GodSystemApp={services={runtime={}}}
assert(loadstring(readSource("shared/GodSystem_Localization.lua")))()
assert(loadstring(readSource("shared/GodSystem_Localization_Override.lua")))()
assert(loadstring(readSource("client/GodSystem_ClientRuntime_Foundation.lua")))()
GodSystemClientRuntimeInstallers.GodSystem_ClientRuntime_Foundation(setmetatable({},{__index=_G}))
local resolve=GodSystemApp.services.runtime.text
local locale="CN"
Translator={getLanguage=function() return {name=function() return locale end} end}
getCore=function() return {} end
local nativeCalls=0
local nativeGetText=function(key) nativeCalls=nativeCalls+1; return "English from native translator" end
getText=nativeGetText
for _,language in ipairs({"CN","CH"}) do
    locale=language
    for _,key in ipairs({"Title","Equipment_Title","Equipment_Boost","NotifyMP_EquipmentInsufficientFunds"}) do
        assert(resolve(key,"English fallback")==GodSystemFallbackText.zh[key],language.." failed: "..key)
    end
end
assert(getText==nativeGetText,"must not replace the game's global translator")
assert(nativeCalls==0,"known Chinese keys must not be overwritten by English native fallback")
locale="EN"
assert(resolve("Title","English fallback")=="English from native translator")
locale="FR"
assert(resolve("Title","English fallback")=="English from native translator")
getText=function(key) return key end
assert(resolve("UnknownKey","Provided fallback")=="Provided fallback")
Translator=nil
assert(resolve("Equipment_Title","Equipment")==GodSystemFallbackText.zh.Equipment_Title)
print("Localization behavior groups passed: 1")
