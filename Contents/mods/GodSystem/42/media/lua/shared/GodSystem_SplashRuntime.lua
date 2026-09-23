-- Bounded, short-lived search and authoritative damage for melee splash.
GodSystemSplashRuntime=GodSystemSplashRuntime or {}
local R=GodSystemSplashRuntime
R.__index=R
R.EntryBudget,R.TimeBudgetMs,R.QueueLimit=64,2,32

function R.new(adapter)
    return setmetatable({a=adapter,jobs={},head=1,tail=0,pending=0,
        metrics={jobs=0,objects=0,ticks=0,maxMs=0,damaged=0,killed=0,failed=0,dropped=0,cancelled=0}},R)
end

function R:wake()
    if self.running then return end
    self.running=true
    self.callback=self.callback or function() self:tick() end
    self.a.attach(self.callback)
end

function R:queue(center,rule,token)
    if not center or not rule or type(token)~="table" then return false end
    token.directTargets=token.directTargets or {}
    if self.pending>=R.QueueLimit then self.metrics.dropped=self.metrics.dropped+1; return false end
    local x,y,z=center:getX(),center:getY(),center:getZ()
    if not x or not y or not z then return false end
    self.tail=self.tail+1
    self.jobs[self.tail]={center=center,cx=x,cy=y,z=math.floor(z),rule=rule,token=token,
        x=math.floor(x-rule.radius),y=math.floor(y-rule.radius),minY=math.floor(y-rule.radius),
        maxX=math.floor(x+rule.radius),maxY=math.floor(y+rule.radius),best={},visited={}}
    self.pending=self.pending+1
    self.metrics.jobs=self.metrics.jobs+1
    self:wake()
    return true
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
    if not zombie or job.visited[zombie] or job.token.directTargets[zombie] or not self.a.valid(zombie) then return end
    job.visited[zombie]=true
    local dx,dy=zombie:getX()-job.cx,zombie:getY()-job.cy
    if math.floor(zombie:getZ())==job.z and dx*dx+dy*dy<=job.rule.radius*job.rule.radius then
        insert(job,zombie,dx*dx+dy*dy)
    end
end

function R:step(job)
    if job.list and job.index<job.list:size() then
        local object=job.list:get(job.index)
        job.index=job.index+1
        self.metrics.objects=self.metrics.objects+1
        self:consider(job,object)
        return true
    end
    job.list=nil; job.index=0
    if job.y>job.maxY then job.y=job.minY; job.x=job.x+1 end
    if job.x>job.maxX then return false end
    local square=self.a.square(job.x,job.y,job.z)
    job.list=square and square:getMovingObjects() or nil
    job.y=job.y+1
    return true
end

function R:finish(job)
    for _,row in ipairs(job.best) do
        local zombie=row.object
        local dx,dy=zombie:getX()-job.cx,zombie:getY()-job.cy
        if self.a.valid(zombie) and not job.token.directTargets[zombie]
            and math.floor(zombie:getZ())==job.z and dx*dx+dy*dy<=job.rule.radius*job.rule.radius then
            local ok,result=pcall(self.a.apply,zombie,job.rule,job.token)
            if ok and result then
                self.metrics.damaged=self.metrics.damaged+1
                if result=="killed" then self.metrics.killed=self.metrics.killed+1 end
            else
                self.metrics.failed=self.metrics.failed+1
                if not ok then
                    self.metrics.lastError=tostring(result)
                    if not self.metrics.errorLogged then
                        self.metrics.errorLogged=true
                        print("[GodSystem] Splash damage failed: "..tostring(result))
                    end
                end
            end
        end
    end
end

function R:tick()
    local started=self.a.now()
    local used=0
    while used<R.EntryBudget and self.head<=self.tail do
        local job=self.jobs[self.head]
        if job and job.cancelled then
            self.jobs[self.head]=nil; self.pending=math.max(0,self.pending-1); self.head=self.head+1
        elseif job and not self:step(job) then
            self:finish(job)
            self.jobs[self.head]=nil; self.pending=math.max(0,self.pending-1); self.head=self.head+1
        elseif not job then
            self.head=self.head+1
        end
        used=used+1
        if self.a.now()-started>=R.TimeBudgetMs then break end
    end
    if self.head>self.tail then
        self.jobs={}; self.head=1; self.tail=0; self.pending=0
        self.running=false; self.a.detach(self.callback)
    end
    self.metrics.ticks=self.metrics.ticks+1
    self.metrics.maxMs=math.max(self.metrics.maxMs,self.a.now()-started)
end

function R:cancelPlayer(player)
    for index=self.head,self.tail do
        local job=self.jobs[index]
        if job and not job.cancelled and job.token.player==player then
            job.cancelled=true
            self.metrics.cancelled=self.metrics.cancelled+1
        end
    end
end

function R:reset()
    self.jobs={}; self.head=1; self.tail=0; self.pending=0
    if self.running then self.running=false; self.a.detach(self.callback) end
end

return R
