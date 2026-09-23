-- Bounded, short-lived local search used only after a Ready impact hits.
GodSystemImpactRuntime = GodSystemImpactRuntime or {}
local R=GodSystemImpactRuntime
R.__index=R
R.EntryBudget,R.TimeBudgetMs=64,2

function R.new(adapter)
    return setmetatable({a=adapter,jobs={},head=1,tail=0,metrics={jobs=0,objects=0,ticks=0,maxMs=0,applied=0,failed=0}},R)
end

function R:wake()
    if self.running then return end
    self.running=true; self.callback=self.callback or function() self:tick() end; self.a.attach(self.callback)
end

function R:queue(center,rule,token)
    if not center or not rule then return false end
    local radius=rule.radius
    -- Snapshot the point of impact; the struck zombie may move during the scan.
    -- Explicit queue bounds avoid Lua's undefined length for tables with holes.
    self.tail=self.tail+1
    self.jobs[self.tail]={center=center,cx=center:getX(),cy=center:getY(),rule=rule,token=token,x=math.floor(center:getX()-radius),
        y=math.floor(center:getY()-radius),minY=math.floor(center:getY()-radius),
        maxX=math.floor(center:getX()+radius),maxY=math.floor(center:getY()+radius),z=math.floor(center:getZ()),
        best={},visited={}}
    self.metrics.jobs=self.metrics.jobs+1; self:wake(); return true
end

local function insert(job,zombie,distance)
    local rows=job.best
    for _,row in ipairs(rows) do if row.object==zombie then return end end
    local at=#rows+1
    for n=1,#rows do if distance<rows[n].distance then at=n; break end end
    table.insert(rows,at,{object=zombie,distance=distance})
    if #rows>job.rule.targets then table.remove(rows) end
end

function R:consider(job,zombie)
    if not zombie or job.visited[zombie] or not self.a.valid(zombie) then return end
    job.visited[zombie]=true
    local dx,dy=zombie:getX()-job.cx,zombie:getY()-job.cy
    local distance=dx*dx+dy*dy
    if math.floor(zombie:getZ())==job.z and distance<=job.rule.radius*job.rule.radius then insert(job,zombie,distance) end
end

function R:step(job)
    if job.list and job.index<job.list:size() then
        local object=job.list:get(job.index); job.index=job.index+1; self.metrics.objects=self.metrics.objects+1
        self:consider(job,object); return true
    end
    job.list=nil; job.index=0
    if job.y>job.maxY then job.y=job.minY; job.x=job.x+1 end
    if job.x>job.maxX then return false end
    local square=self.a.square(job.x,job.y,job.z)
    job.list=square and square:getMovingObjects() or nil
    -- Advance even when an edge/unloaded square has no object list.
    job.y=job.y+1
    job.index=0
    return true
end

function R:finish(job)
    local applied={}
    for _,row in ipairs(job.best) do
        local zombie=row.object
        local dx,dy=zombie:getX()-job.cx,zombie:getY()-job.cy
        if self.a.valid(zombie) and math.floor(zombie:getZ())==job.z and dx*dx+dy*dy<=job.rule.radius*job.rule.radius then
            local ok,err=pcall(self.a.apply,zombie,job.token)
            if ok then applied[#applied+1]=row; self.metrics.applied=self.metrics.applied+1
            else
                self.metrics.failed=self.metrics.failed+1
                self.metrics.lastError=tostring(err)
                print("[GodSystem] Impact knockdown failed: "..tostring(err))
            end
        end
    end
    job.best=applied
    if self.a.finished then self.a.finished(job) end
end

function R:tick()
    local started=self.a.now(); local used=0
    while used<R.EntryBudget and self.jobs[self.head] do
        local job=self.jobs[self.head]
        if not self:step(job) then self:finish(job); self.jobs[self.head]=nil; self.head=self.head+1 end
        used=used+1
        if self.a.now()-started>=R.TimeBudgetMs then break end
    end
    if self.head>self.tail then self.jobs={}; self.head=1; self.tail=0; self.running=false; self.a.detach(self.callback) end
    self.metrics.ticks=self.metrics.ticks+1; self.metrics.maxMs=math.max(self.metrics.maxMs,self.a.now()-started)
end

function R:reset()
    self.jobs={}; self.head=1; self.tail=0
    if self.running then self.running=false; self.a.detach(self.callback) end
end

return R
