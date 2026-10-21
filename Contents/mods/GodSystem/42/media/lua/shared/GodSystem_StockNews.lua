require "GodSystem_StockDefinitions"
GodSystemStockNews = GodSystemStockNews or {}
local N,D=GodSystemStockNews,GodSystemStockDefinitions
local function push(list,row,limit) list[#list+1]=row; while #list>limit do table.remove(list,1) end end
function N.initial()
    return {nextEvent=24, candidates={},history={},day=0,published=0,scheduleCount=0,sequence=0,behaviorDay=-1}
end
-- Public publication schedule only; never reveal pending events or draw RNG.
function N.status(n,h,c)
    local result={limit=c.news,sequence=n.sequence or 0}
    if not c.enabled or c.news==0 then return result end
    local day=math.floor(h/24)
    local count=n.day==day and math.min(n.scheduleCount or 0,c.news) or 0
    -- Before the day's schedule is drawn, only its first future slot is certain.
    -- Re-enabling news mid-day must not promise an unselected afternoon slot.
    if count==0 then
        result.pending=true
        if h<day*24+8 then result.nextHour=day*24+8 end
        return result
    end
    for i=1,count do
        local at=day*24+i*8
        if at>h then result.nextHour=at; return result end
    end
    result.nextHour=(day+1)*24+8
    return result
end
local function candidate(n,row)
    -- Repeated sector reports merge instead of accumulating unbounded work.
    if row.kind=="activity" then
        for i=#n.candidates,1,-1 do
            if n.candidates[i].kind==row.kind and n.candidates[i].industry==row.industry then table.remove(n.candidates,i) end
        end
    end
    push(n.candidates,row,16)
end
function N.prepare(job,random)
    local n,h,c=job.news,job.hour,job.config
    if n.rumor and h>=n.rumor.resolve then
        local r=n.rumor
        if r.truth then job.stocks[r.id].target=job.stocks[r.id].target+r.delta end
        job.stocks[r.id].sentimentTarget=0
        if r.published then candidate(n,{kind=r.truth and "confirmed" or "denied",id=r.id,hour=h,priority=1,expires=h+24})
        elseif r.truth then candidate(n,{kind="event",id=r.id,delta=r.delta,hour=h,priority=2,expires=h+24}) end
        n.rumor=nil
    end
    if h>=n.nextEvent then
        n.nextEvent=h+24+math.floor(random("events")*49)
        local eligible={}
        for i=1,#D.rows do
            local id=D.rows[i].id
            if not n.rumor or n.rumor.id~=id then
                if (job.stocks[id].eventUntil or 0)<=h then eligible[#eligible+1]=id end
            end
        end
        if #eligible>0 then
            local id=eligible[math.floor(random("events")*#eligible)+1]
            local delta=(0.02+random("events")*0.04)*(random("events")<0.5 and -1 or 1)
            if random("events")<0.2 and not n.rumor then
                local resolve=h+12+math.floor(random("events")*25)
                n.rumor={id=id,resolve=resolve,truth=random("events")<0.7,delta=delta}
                job.stocks[id].sentimentTarget=(delta<0 and -1 or 1)*(0.005+random("events")*0.015)
                candidate(n,{kind="rumor",id=id,delta=delta,hour=h,expires=resolve-1,priority=2})
                job.stocks[id].eventUntil=resolve
            else
                job.stocks[id].target=job.stocks[id].target+delta
                job.stocks[id].eventUntil=job.stocks[id].phaseUntil
                candidate(n,{kind="event",id=id,delta=delta,hour=h,priority=2,expires=h+24})
            end
        end
    end
    for i=1,#D.industries do
        local industry=D.industries[i]; local s=job.sectors[industry]
        if s.report then
            candidate(n,{kind="activity",industry=industry,hour=h,priority=3,expires=h+24})
            s.report=nil
        end
    end
    local day=math.floor((h-1)/24)
    if n.day~=day or n.scheduleCount==0 then
        n.day=day; n.published=0
        n.scheduleCount=c.news>0 and 1+math.floor(random("newsSchedule")*c.news) or 0
    end
    for i=#n.candidates,1,-1 do if n.candidates[i].expires<h then table.remove(n.candidates,i) end end
    if c.news==0 then return end
    local within=(h-1)%24+1
    local count=math.min(n.scheduleCount,c.news)
    local slot=within==8 or (count>=2 and within==16) or (count>=3 and within==24)
    if not slot or n.published>=count then return end
    local at=nil
    for i=1,#n.candidates do
        local row=n.candidates[i]
        if (row.kind~="activity" or n.behaviorDay~=day)
            and (not at or row.priority<n.candidates[at].priority) then at=i end
    end
    local row=at and table.remove(n.candidates,at) or {kind="observation",hour=h,
        id=D.rows[math.floor(random("newsText")*#D.rows)+1].id}
    if row.kind=="activity" then n.behaviorDay=day end
    if row.kind=="rumor" and n.rumor and n.rumor.id==row.id then n.rumor.published=true end
    n.sequence=n.sequence+1; row.sequence=n.sequence; row.publishedHour=h
    row.priority=nil; row.expires=nil
    push(n.history,row,64); n.published=n.published+1
end
return N
