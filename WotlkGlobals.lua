-- WotLK global compatibility helpers
-- Restore a few globals that older code and embedded libraries expect.

if type(getglobal) ~= "function" then
  getglobal = function(name)
    return _G[name]
  end
end

if type(setglobal) ~= "function" then
  setglobal = function(name, value)
    _G[name] = value
  end
end

if type(mod) ~= "function" then
  mod = math.mod or math.fmod
end

-- Wrath clients do not expose the older plural-hour format string that Bagshui
-- expects. Reuse the singular template so existing string.format() call sites
-- keep working until a more thorough localization pass is needed.
if type(_G.INT_SPELL_DURATION_HOURS_P1) ~= "string" then
  _G.INT_SPELL_DURATION_HOURS_P1 = _G.INT_SPELL_DURATION_HOURS or "%d hrs"
end
