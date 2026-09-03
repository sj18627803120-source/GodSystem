GodSystemRangeRecycleDomain = GodSystemRangeRecycleDomain or {}

GodSystemRangeRecycleDomain.StageOrder = {
    "ground",
    "container",
    "corpseItems",
    "corpses",
}

local function clampInteger(value, minimum, maximum, fallback)
    local number = math.floor(tonumber(value) or fallback)
    if number < minimum then return minimum end
    if number > maximum then return maximum end
    return number
end

function GodSystemRangeRecycleDomain.buildSquareOrder(origin, radius)
    origin = type(origin) == "table" and origin or {}
    local x = math.floor(tonumber(origin.x) or 0)
    local y = math.floor(tonumber(origin.y) or 0)
    local z = math.floor(tonumber(origin.z) or 0)
    radius = clampInteger(radius, 0, 10, 5)
    local result = {}
    local radiusSquared = radius * radius
    for dx = -radius, radius do
        for dy = -radius, radius do
            local distanceSquared = dx * dx + dy * dy
            if distanceSquared <= radiusSquared then
                result[#result + 1] = {
                    x = x + dx,
                    y = y + dy,
                    z = z,
                    distanceSquared = distanceSquared,
                }
            end
        end
    end
    table.sort(result, function(a, b)
        if a.distanceSquared ~= b.distanceSquared then
            return a.distanceSquared < b.distanceSquared
        end
        if a.x ~= b.x then return a.x < b.x end
        return a.y < b.y
    end)
    return result
end

local function stageName(job)
    return GodSystemRangeRecycleDomain.StageOrder[job.stageIndex] or "verifying"
end

function GodSystemRangeRecycleDomain.progress(job, batchProcessed, batchPayout, batchTargets, batchInspected)
    return {
        jobId = job.id,
        status = job.status,
        stage = stageName(job),
        processed = job.processed,
        payout = job.payout,
        skipped = job.skipped,
        batchProcessed = batchProcessed or 0,
        batchPayout = batchPayout or 0,
        batchTargets = batchTargets or 0,
        batchInspected = batchInspected or 0,
        reason = job.reason,
    }
end

function GodSystemRangeRecycleDomain.newJob(spec)
    assert(type(spec) == "table", "range job spec is required")
    assert(type(spec.adapter) == "table", "range job adapter is required")
    assert(type(spec.adapter.nextCandidate) == "function", "adapter.nextCandidate is required")
    assert(type(spec.adapter.recycle) == "function", "adapter.recycle is required")
    local origin = spec.origin or {}
    local radius = clampInteger(spec.radius, 0, 10, 5)
    return {
        id = tostring(spec.id or "range-job"),
        playerId = spec.playerId,
        origin = {
            x = math.floor(tonumber(origin.x) or 0),
            y = math.floor(tonumber(origin.y) or 0),
            z = math.floor(tonumber(origin.z) or 0),
        },
        radius = radius,
        batchSize = clampInteger(spec.batchSize, 1, 20, 20),
        scanBudget = clampInteger(spec.scanBudget, 20, 2048, 256),
        filter = spec.filter,
        adapter = spec.adapter,
        squareOrder = GodSystemRangeRecycleDomain.buildSquareOrder(origin, radius),
        stageIndex = 1,
        squareIndex = 1,
        candidateCursor = nil,
        passProcessed = 0,
        processed = 0,
        payout = 0,
        skipped = 0,
        status = "running",
        reason = nil,
    }
end

function GodSystemRangeRecycleDomain.cancel(job, reason)
    if job.status == "running" then
        job.status = "cancelled"
        job.reason = tostring(reason or "cancelled")
    end
    return GodSystemRangeRecycleDomain.progress(job)
end

local function advanceSquare(job)
    job.squareIndex = job.squareIndex + 1
    job.candidateCursor = nil
end

local function advanceStage(job)
    job.stageIndex = job.stageIndex + 1
    job.squareIndex = 1
    job.candidateCursor = nil
end

local function resetPass(job)
    job.stageIndex = 1
    job.squareIndex = 1
    job.candidateCursor = nil
    job.passProcessed = 0
end

function GodSystemRangeRecycleDomain.step(job)
    if job.status ~= "running" then
        return GodSystemRangeRecycleDomain.progress(job)
    end

    local interrupted = nil
    if type(job.adapter.isInterrupted) == "function" then
        interrupted = job.adapter:isInterrupted(job)
    end
    if interrupted then
        return GodSystemRangeRecycleDomain.cancel(job, interrupted)
    end

    local batchProcessed = 0
    local batchPayout = 0
    local batchTargets = 0
    -- `scanBudget` is a work budget, not merely a square count.  Adapters may
    -- return the amount spent and a yielded flag when a nested scan reaches
    -- the limit; their cursor is then resumed on the next tick.
    local inspected = 0

    while batchTargets < job.batchSize and inspected < job.scanBudget do
        if type(job.adapter.isInterrupted) == "function" then
            interrupted = job.adapter:isInterrupted(job)
            if interrupted then
                job.status = "cancelled"
                job.reason = tostring(interrupted)
                break
            end
        end

        local stage = GodSystemRangeRecycleDomain.StageOrder[job.stageIndex]
        if not stage then
            if job.passProcessed > 0 then
                resetPass(job)
                return GodSystemRangeRecycleDomain.progress(job, batchProcessed, batchPayout, batchTargets, inspected)
            end
            job.status = "completed"
            job.reason = "empty"
            break
        end

        local coord = job.squareOrder[job.squareIndex]
        if not coord then
            advanceStage(job)
        else
            local square = coord
            if type(job.adapter.getSquare) == "function" then
                square = job.adapter:getSquare(coord, job)
            end
            local allowedSquare = square ~= nil
            if allowedSquare and type(job.adapter.canAccessSquare) == "function" then
                allowedSquare = job.adapter:canAccessSquare(job, square, coord) == true
            end
            if not allowedSquare then
                advanceSquare(job)
            else
                local remainingWork = math.max(1, job.scanBudget - inspected)
                local candidate, nextCursor, done, yielded, consumedWork = job.adapter:nextCandidate(
                    job,
                    stage,
                    square,
                    job.candidateCursor,
                    remainingWork
                )
                consumedWork = math.floor(tonumber(consumedWork) or 0)
                if consumedWork < 1 then consumedWork = 1 end
                inspected = math.min(job.scanBudget, inspected + consumedWork)
                if done == true then
                    advanceSquare(job)
                elseif yielded == true then
                    job.candidateCursor = nextCursor
                    break
                elseif candidate then
                    batchTargets = batchTargets + 1
                    job.candidateCursor = nextCursor
                    local allowedItem = true
                    if candidate.filterable ~= false and GodSystemRangeFilter and GodSystemRangeFilter.allows then
                        allowedItem = GodSystemRangeFilter.allows(job.filter, candidate.fullType)
                    end
                local outcome
                if not allowedItem then
                    job.skipped = job.skipped + 1
                    outcome = { removed = false, skipped = true }
                else
                    outcome = job.adapter:recycle(job, candidate, stage, square) or {}
                    if outcome.removed == true then
                            local payout = math.max(0, math.floor(tonumber(outcome.payout) or 0))
                            batchProcessed = batchProcessed + 1
                            batchPayout = batchPayout + payout
                            job.processed = job.processed + 1
                            job.passProcessed = job.passProcessed + 1
                            job.payout = job.payout + payout
                        else
                        job.skipped = job.skipped + 1
                    end
                end
                if type(job.adapter.afterCandidate) == "function" then
                    job.adapter:afterCandidate(job, candidate, outcome)
                end
                else
                    job.skipped = job.skipped + 1
                    job.candidateCursor = nextCursor
                end
            end
        end
    end

    return GodSystemRangeRecycleDomain.progress(job, batchProcessed, batchPayout, batchTargets, inspected)
end
