-- Deterministic special-effect rules. No events, inventory or native writes.
GodSystemEquipmentFreeze = GodSystemEquipmentFreeze or {}
local F = GodSystemEquipmentFreeze
F.Maximum = 0.8
F.EntryBudget, F.TimeBudgetMs = 64, 2
F.VisualMs, F.VisualLimit = 350, 32
function F.strength(level, cfg)
    return math.min(F.Maximum, math.max(0, level) * cfg.EquipmentGrowthPercent / 100)
end
function F.merge(old, strength, expires)
    return math.max(old and old.strength or 0, strength), math.max(old and old.expires or 0, expires)
end
function F.inside(x,y,z,cx,cy,cz,radius)
    local dx,dy=x-cx,y-cy
    return math.floor(z)==math.floor(cz) and dx*dx+dy*dy<=radius*radius
end
return F
