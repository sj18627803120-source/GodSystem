-- Pure rules for the melee impact effect.  This module intentionally knows
-- nothing about inventory, events, zombies or networking.
GodSystemEquipmentImpact = GodSystemEquipmentImpact or {}
local P = GodSystemEquipmentImpact

P.Maximum = 10
P.Curve = {
    [1]={ attacks=10, radius=1.5, targets=4 }, [2]={ attacks=9, radius=1.5, targets=4 },
    [3]={ attacks=8, radius=2.0, targets=5 }, [4]={ attacks=7, radius=2.0, targets=5 },
    [5]={ attacks=6, radius=2.5, targets=6 }, [6]={ attacks=6, radius=2.5, targets=7 },
    [7]={ attacks=5, radius=3.0, targets=7 }, [8]={ attacks=5, radius=3.0, targets=8 },
    [9]={ attacks=5, radius=3.5, targets=9 }, [10]={ attacks=5, radius=3.5, targets=10 },
}

function P.rule(level)
    level=tonumber(level)
    return level and P.Curve[level] or nil
end

function P.state(record)
    local source=record and record.effectState and record.effectState.impact
    local count=source and tonumber(source.attackCount) or 0
    local ready=source and source.ready==true or false
    local revision=source and tonumber(source.stateRevision) or 0
    count=count and count==math.floor(count) and math.max(0,count) or 0
    revision=revision and revision==math.floor(revision) and math.max(0,revision) or 0
    return {attackCount=count,ready=ready,stateRevision=revision}
end

function P.reset(record)
    record.effectState=record.effectState or {}
    local old=P.state(record)
    record.effectState.impact={attackCount=0,ready=false,stateRevision=old.stateRevision+1}
    return record.effectState.impact
end

function P.advance(record,level)
    local rule=P.rule(level)
    if not rule then return nil end
    local state=P.state(record)
    if state.ready then return state,false end
    state.attackCount=math.min(rule.attacks,state.attackCount+1)
    state.ready=state.attackCount>=rule.attacks
    state.stateRevision=state.stateRevision+1
    record.effectState=record.effectState or {}; record.effectState.impact=state
    return state,true
end

function P.consume(record)
    return P.reset(record)
end

return P
