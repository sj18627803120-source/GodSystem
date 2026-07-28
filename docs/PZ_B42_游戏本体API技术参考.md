# Project Zomboid B42.19 游戏本体 API 技术参考

> 基于 Project Zomboid B42.19 游戏本体 `media/lua/` 调用点整理
> 生成日期：2026-07-27
> 用途：无游戏本体环境下 Mod 开发参考

> [!IMPORTANT]
> 本文是 API 导航与调用线索，不是官方接口契约。Lua 调用点只能证明某个版本的本体曾这样调用，
> 不能单独证明 Java 重载可被 Kahlua 调用、客户端与服务端都可用，或 MOD 能安全复用。
> 实现前仍须按“同版本本体 Lua → 同版本 Java/官方资料 → 最小实机测试”的顺序复验。
> 文中已经纠正本轮审阅发现的高风险旧写法；未逐项实机验证的长表仍应视为待核对线索。

---

## 一、Lua 目录结构

```
media/lua/
├── client/          # 仅客户端加载
│   ├── ISUI/        # 所有 UI 组件（ISPanel、ISButton、ISScrollingListBox…）
│   ├── Context/     # 右键菜单管理
│   ├── Chat/        # 聊天系统
│   ├── DebugUIs/    # 调试面板
│   ├── Foraging/    # 采集 UI
│   └── ...
├── server/          # 仅服务端加载（SP 启动时也加载）
│   ├── ClientCommands.lua  # 核心命令分发
│   ├── Map/         # 地图/全局对象
│   ├── Vehicles/    # 车辆逻辑
│   ├── Items/       # 物品生成
│   └── ...
├── shared/          # 两方都加载
│   ├── TimedActions/    # 所有 Timed Action 定义
│   ├── Util/LuaNet.lua  # 网络通信核心
│   ├── luautils.lua     # 通用工具函数
│   ├── Fluids/          # 流体系统
│   ├── Moveables/       # 可移动家具
│   ├── NPCs/            # NPC 系统
│   ├── Translate/       # 多语言翻译
│   └── ...
```

**Mod 开发约定**：Mod 内的 `media/lua/client/`、`server/`、`shared/` 与游戏同名目录对应加载。

---

## 二、核心全局函数

### 2.1 玩家获取

| 函数 | 签名 | 说明 |
|------|------|------|
| `getPlayer()` | `→ IsoPlayer` | 客户端获取当前玩家（SP同样可用） |
| `getSpecificPlayer(n)` | `(number) → IsoPlayer` | 读取本地玩家槽位（0=第一个）；不要把它当作专用服务器玩家解析器 |

```lua
-- 客户端获取当前玩家
local player = getPlayer()
local x, y, z = player:getX(), player:getY(), player:getZ()

-- OnClientCommand 已直接传入发送者 player；服务端不要再用本地槽位重新解析
function MyMod.OnClientCommand(module, command, player, args)
    local playerObj = player
end
```

### 2.2 环境判断

| 函数 | 说明 |
|------|------|
| `isClient()` | 当前是否 MP 客户端；SP 通常为 false |
| `isServer()` | 当前是否 MP 服务端权威环境；不能作为 SP 判断。SP 可加载 server Lua，但该值通常为 false |
| `getWorld()` | 获取世界对象 |
| `getGameTime()` | 获取游戏时间相关 |

### 2.3 物品实例化

```lua
-- 创建物品实例（不放入世界，仅用于检查属性/显示图标）
local item = instanceItem("Base.Axe")
local item = instanceItem("Moveables.Moveable")
```

---

## 三、核心对象 API

### 3.1 IsoPlayer（继承 IsoGameCharacter）

```lua
local player = getPlayer()

-- 位置
player:getX()                              -- → number
player:getY()                              -- → number
player:getZ()                              -- → number
player:getCurrentSquare()                  -- → IsoGridSquare

-- 编号
player:getPlayerNum()                      -- → number (0-based)

-- 背包
player:getInventory()                      -- → ItemContainer (主背包)

-- 手持物品
player:getPrimaryHandItem()                -- → InventoryItem | nil
player:getSecondaryHandItem()              -- → InventoryItem | nil

-- 状态
player:getStats()                          -- → Stats 对象
player:getBodyDamage()                     -- → BodyDamage
player:getMoodles()                        -- → Moodles
player:isDead()                            -- → boolean

-- 角色
player:getRole()                           -- → Role
player:getUsername()                       -- → string

-- 地图知识
player:getMapKnowledge()                   -- → MapKnowledge
```

### 3.2 IsoGameCharacter（玩家父类）

```lua
local char = getPlayer()  -- 或 getSpecificPlayer(0)

-- Timed Action
char:StartAction(action)                    -- 开始动作
char:setTimedActionToRetrigger(action)      -- 设置重试动作
char:setIsFarming(bool)                     -- 设置 farming 状态
char:getTimedActionTimeModifier()           -- → number (速度修正)

-- 动画
char:setOverrideHandModels(primary, secondary, resetModel)
char:setVariable(key, val)                  -- 设置动画变量

-- 说话
char:Say(message)                           -- 显示聊天
```

### 3.3 InventoryItem（物品实例）

```lua
local item = player:getPrimaryHandItem()

-- 类型
item:getType()                              -- → string (如 "Base.Axe")
item:isEquipped()                           -- → boolean

-- 状态
item:getCondition()                         -- → number
item:getUses()                              -- → number
item:getWeight()                            -- → number
item:getBloodLevel()                        -- → number

-- 标识
item:getID()                                -- → number (唯一ID)
item:getModData()                           -- → table (Mod 自定义数据表)

-- 容器
item:getItemContainer()                     -- → ItemContainer | nil
```

### 3.4 ItemContainer（物品容器）

```lua
local inv = player:getInventory()
local container = worldObj:getContainer()

-- 增删
container:AddItem(itemType)                -- 按类型名添加 → InventoryItem
container:AddItem(item)                    -- 添加已有物品
container:Remove(item)                     -- 移除物品
container:clear()                          -- 清空

-- 查询
container:getItems()                       -- → ArrayList<InventoryItem>
container:getAllItems()                    -- → table (递归)
container:contains(itemType)              -- → boolean
container:containsID(id)                  -- → boolean
container:getItem(itemType)               -- 按类型查找第一个 → InventoryItem

-- 容量
container:getCapacity()                    -- → number
container:getType()                        -- → string
container:getCanBeLocked()                -- → boolean
container:setExplored(bool)               -- 标记已探索

-- 所属
container:getOwner()                       -- → IsoObject | IsoPlayer
container:getSourceGrid()                  -- → IsoGridSquare
```

### 3.5 IsoGridSquare（格子）

```lua
local square = player:getCurrentSquare()

-- 对象查询
square:getObjects()                        -- → ArrayList<IsoObject>
square:getWorldObjects()                   -- → ArrayList<IsoObject>
square:getItems()                          -- → ArrayList 地面物品
square:getPlayers()                        -- → ArrayList 玩家
square:getZ()                              -- → number

-- 属性
square:getTile()                           -- → Tile
square:isCouldSee()                        -- → boolean
```

### 3.6 IsoObject / IsoThumpable（世界物品）

```lua
local obj = square:getObjects():get(0)

-- 基础
obj:getSquare()                            -- → IsoGridSquare
obj:getContainer()                         -- → ItemContainer | nil
obj:getModData()                           -- → table
obj:getSprite()                            -- → Sprite
obj:getType()                              -- → string

-- Thumpable 特有（门、窗、容器）
obj:isOpen()                               -- → boolean
obj:isLocked()                             -- → boolean
obj:isDestroyed()                          -- → boolean
obj:getThumpSound()                        -- → string
```

---

## 四、UI 系统

### 4.1 ISUIElement（基类）

所有 UI 组件继承自此。关键方法：

```lua
-- 构造
ISUIElement:new(x, y, width, height)

-- 层级
parent:addChild(child)
parent:removeChild(child)

-- 属性
el:setX(x) / el:setY(y) / el:setWidth(w) / el:setHeight(h)
el:setVisible(bool)
el:setAnchorLeft/Right/Top/Bottom(bool)

-- 渲染
el:render()                                -- 每帧调用
el:prerender()                             -- 渲染前
el:drawText(text, x, y, r, g, b, a, font) -- 必须传全部参数
el:drawRect(x, y, w, h, a, r, g, b)       -- 绘制矩形
el:drawTextureScaled(texture, x, y, w, h, a, r, g, b)

-- 输入
el:onMouseDown(x, y)
el:onMouseUp(x, y)
el:onMouseMove(dx, dy)
el:onMouseWheel(del)
```

### 4.2 ISPanel（面板）

```lua
ISPanel:new(x, y, width, height)
-- 继承 ISUIElement 所有方法，通常作为容器使用
```

### 4.3 ISButton（按钮）

```lua
local btn = ISButton:new(x, y, width, height, text, target, onClick)

btn:setImage(texture)                      -- 设置图标
btn:forceClick()                           -- 模拟点击
btn:setVisible(bool)
```

### 4.4 ISScrollingListBox（滚动列表）

```lua
local list = ISScrollingListBox:new(x, y, width, height)

-- 数据操作
list:addItem(name, data, tooltip)          -- 添加行
list:removeItemByIndex(index)              -- 删除行
list:removeItem(itemText)                  -- 按文本删除
list:clear()                               -- 清空列表
list:sort(comparator)                      -- 排序

-- 查询
list:getItemByIndex(index)                 -- → {text, item, tooltip}
list:getItemText()                         -- → table 全部文本
list.items[index]                          -- 直接访问

-- 选择
list.selected                              -- 当前选中行号 (1-based)
list:ensureVisible(index)                  -- 滚动到可见
list:setSelectedIndex(index)               -- 设置选中
list:setItemTextColor(index, r, g, b, a)   -- 设置行颜色
```

### 4.5 ISContextMenu（右键菜单）

```lua
-- 在 OnFillWorldObjectContextMenu 中使用
local playerObj = getSpecificPlayer(playerNum)

-- 添加菜单项
context:addOption(name, target, callback, param1, param2, ...)
--   name: 显示文本
--   target: 回调的 self 参数
--   callback: function(target, param1, param2, ...)
--   param1~10: 传递给回调的参数

-- 示例：添加子菜单
local subOption = context:addOption("子菜单")
local subMenu = ISContextMenu:getNew(subOption)
subMenu:addOption("操作1", playerObj, myFunc, arg1)
```

### 4.6 ISModalDialog（模态对话框）

```lua
ISModalDialog:new(x, y, width, height, text, yesno, target, onclick, player, param1, param2)
-- yesno=true: 显示是/否按钮
-- onclick(target, button, param1, param2): 回调，button.clicked 判断点击
```

### 4.7 ISRichTextPanel（富文本面板）

```lua
local panel = ISRichTextPanel:new(x, y, width, height)
panel:setText(text)                        -- 设置富文本
panel:addScrollBars()                      -- 添加滚动条
panel:paginate()                           -- 分页
```

### 4.8 ISTextEntryBox（文本输入框）

```lua
ISTextEntryBox:new(title, x, y, width, height)
-- 用于输入框，通常配合 ISModalDialog 使用
```

---

## 五、Timed Action 系统（多人核心）

### 5.1 ISBaseTimedAction 基类

位置：`shared/TimedActions/ISBaseTimedAction.lua`

```lua
-- 构造函数
ISBaseTimedAction:new(character)
-- 属性：
--   o.character      -- 执行的玩家
--   o.maxTime        -- 持续时间（需在子类设置）
--   o.stopOnWalk     -- 默认 true，移动时取消
--   o.stopOnRun      -- 默认 true，奔跑时取消
--   o.stopOnAim      -- 默认 true，瞄准时取消
--   o.caloriesModifier -- 卡路里消耗倍率

-- 生命周期（按执行顺序）
:isValidStart()       -- 检查是否可以开始（返回 false 阻止入队）
:isValid()            -- 持续检查是否有效
:waitToStart()        -- 等待开始
:start()              -- 开始执行
:update()             -- 每帧更新
:perform()            -- 完成后调用（调用 onCompleted → complete）
:stop()               -- 被中断
:isStarted()          -- 是否已开始
:getDuration()        -- 返回 maxTime
:setTime(time)        -- 设置持续时间

-- 动画
:setActionAnim(action, displayItemModels)           -- 设置动作动画
:setOverrideHandModels(primary, secondary, reset)   -- 设置手持模型
:setAnimVariable(key, val)                          -- 设置动画变量

-- 队列
:addAfter(action)      -- 在当前动作完成后追加
```

### 5.2 自定义 Timed Action 模板

```lua
-- 定义
MyAction = {}
MyAction.__index = MyAction

function MyAction:new(character, ...)
    local o = {}
    setmetatable(o, self)
    self.__index = self
    o.character = character
    o.maxTime = 100                    -- 持续时间（帧）
    o.stopOnWalk = true
    o.stopOnRun = true
    return o
end

function MyAction:isValid()
    return self.character:getPrimaryHandItem() ~= nil
end

function MyAction:perform()
    -- 客户端：播放动画效果
    -- 服务端：完成数据修改（权威操作）
    -- 基类 perform() 会自动调用 onCompleted → complete
    ISBaseTimedAction.perform(self)
end

function MyAction:complete()
    -- 在这里做实际的数据修改
    -- 服务端在此处进行权威结算
    return true
end

-- 入队
ISTimedActionQueue.add(MyAction:new(player, ...))
```

### 5.3 ISTimedActionQueue

```lua
ISTimedActionQueue.add(action)                  -- 入队
ISTimedActionQueue.getTimedActionQueue(char)    -- 获取角色队列
ISTimedActionQueue.addAfter(prevAction, action) -- 在指定动作后追加
```

---

## 六、网络通信

### 6.1 sendClientCommand（客户端→服务端）

```lua
-- 完整签名
sendClientCommand(player, module, command, args)
--   player: 玩家对象
--   module: 模块名（string）
--   command: 命令名（string）
--   args: 参数表（table）

-- 示例
sendClientCommand(getPlayer(), "ISLogSystem", "writeLog", {
    loggerName = "MyMod",
    logText = "some message"
})

-- 短形式（部分版本支持）
sendClientCommand(module, command, args)

-- 带可变参数的形式
sendClientCommandV(player, module, command, key1, val1, key2, val2, ...)
```

### 6.2 OnClientCommand（服务端接收）

```lua
-- 注册
if isServer() then
    Events.OnClientCommand.Add(MyMod.OnClientCommand)
end

-- 处理器签名
function MyMod.OnClientCommand(module, command, player, args)
    -- module: 模块名
    -- command: 命令名
    -- player: 发送者 (IsoPlayer)
    -- args: 参数表

    if module ~= "MyMod" then return end

    if command == "buyItem" then
        -- ⚠️ 必须重新解析对象，验证权限
        -- 不要在 args 中传递复杂对象引用，只传 ID/类型名
        local itemType = args.itemType
        local playerObj = player
        -- 权威验证和结算
    end
end
```

### 6.3 sendServerCommand（服务端→客户端）

```lua
sendServerCommand(player, module, command, args)
-- 向特定客户端发回数据
```

### 6.4 网络通信最佳实践

```
┌──────────┐  sendClientCommand()  ┌──────────┐
│  Client  │ ────────────────────→ │  Server  │
│          │                       │          │
│  perform │  (动画表现)            │ complete │  (权威结算)
│          │ ←──────────────────── │          │
└──────────┘  sendServerCommand()  └──────────┘
```

- 服务端 **必须** 重新解析对象、验证权限
- Handler 必须包 `pcall`，避免单个错误拖垮后续同步
- 参数中只传 ID/类型名，不传复杂对象引用
- 先按带 player 写法发送，失败再 fallback 到三参数写法

---

## 七、事件系统

### 7.1 事件注册/注销

```lua
-- 注册
Events.OnSomething.Add(handlerFunction)

-- 注销（需保存引用）
Events.OnSomething.Remove(handlerFunction)
```

### 7.2 常用事件分类

#### 游戏生命周期
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnGameBoot` | 游戏启动加载数据 | Shared |
| `Events.OnGameStart` | 进入游戏世界 | Shared |
| `Events.OnNewGame` | 新游戏创建 | Shared |
| `Events.OnLoad` | 加载存档 | Shared |
| `Events.OnServerStarted` | 服务端启动 | Server |

#### 玩家相关
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnCreatePlayer` | 玩家创建 | Shared |
| `Events.OnPlayerUpdate` | 玩家状态更新 | Shared |
| `Events.OnPlayerMove` | 玩家移动 | Server |
| `Events.OnPlayerDeath` | 玩家死亡 | Shared |

#### UI / 渲染
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnPreUIDraw` | UI 绘制前 | Client |
| `Events.OnPostUIDraw` | UI 绘制后 | Client |
| `Events.OnFillWorldObjectContextMenu` | 右键世界物品 | Client |
| `Events.OnKeyPressed` | 按键 | Client |

#### 物品 / 容器
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnItemAdded` | 物品添加到容器 | Shared |
| `Events.OnItemRemoved` | 物品从容器移除 | Shared |
| `Events.OnContainerUpdate` | 容器更新 | Shared |
| `Events.OnEquipPrimary` | 装备主手 | Shared |
| `Events.OnEquipSecondary` | 装备副手 | Shared |

#### 网络
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnClientCommand` | 收到客户端命令 | Server |
| `Events.OnServerCommand` | 收到服务端命令 | Client |

#### 定时器
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnTick` | 每帧 | Shared |
| `Events.EveryOneMinute` | 每分钟 | Shared |
| `Events.EveryTenMinutes` | 每十分钟 | Shared |
| `Events.EveryHours` | 每小时 | Shared |
| `Events.EveryDays` | 每天 | Shared |

#### 其他常用
| 事件 | 触发时机 | 环境 |
|------|---------|------|
| `Events.OnHitZombie` | 击中僵尸 | Shared |
| `Events.OnWeaponHitXp` | 武器命中经验 | Server |
| `Events.LevelPerk` | 技能升级 | Shared |
| `Events.AddXP` | 增加经验 | Server |
| `Events.OnObjectAdded` | 世界对象添加 | Shared |
| `Events.OnObjectRemoved` | 世界对象移除 | Shared |
| `Events.OnLoadMapZones` | 加载地图区域 | Shared |
| `Events.OnWeatherPeriodStart` | 天气周期开始 | Shared |
| `Events.OnWeatherPeriodComplete` | 天气周期结束 | Shared |

### 7.3 典型事件使用模式

```lua
-- 1. 右键菜单注入
Events.OnFillWorldObjectContextMenu.Add(function(playerNum, context, worldobjects, test)
    local playerObj = getSpecificPlayer(playerNum)
    local obj = worldobjects[1]
    if obj and obj:getContainer() then
        context:addOption("我的操作", playerObj, MyMod.onMyAction, obj)
    end
end)

-- 2. 游戏启动初始化
Events.OnGameStart.Add(function()
    -- 初始化 Mod 数据
end)

-- 3. 定时任务
Events.EveryDays.Add(function()
    -- 每日刷新
end)
```

---

## 八、ModData（自定义数据持久化）

```lua
-- 任何有 getModData() 的对象都可以挂载自定义数据
-- 包括：IsoPlayer、IsoObject、InventoryItem、IsoGridSquare

local player = getPlayer()
local modData = player:getModData()

-- 读写（直接当 table 用）
modData.MyMod_Balance = 1000
modData.MyMod_LastLogin = getGameTime():getWorldAgeHours()

-- 物品上的 ModData
local item = player:getPrimaryHandItem()
if item then
    item:getModData().MyMod_CustomTag = true
end

-- 世界对象上的 ModData
local obj = square:getWorldObjects():get(0)
if obj then
    obj:getModData().MyMod_IsMarked = true
end
```

**注意**：ModData 会随存档保存，键名建议加 Mod 前缀避免冲突。

---

## 九、物品系统

### 9.1 物品类型命名

```
Base.Axe              -- 原版物品
Base.WaterBottleFull  -- 带状态物品
Moveables.Moveable    -- 可移动家具
ModuleName.ItemName   -- Mod 自定义物品
```

### 9.2 物品创建与操作

```lua
-- 创建物品实例（不放入世界）
local item = instanceItem("Base.Axe")

-- 向容器添加物品
player:getInventory():AddItem("Base.Axe")
container:AddItem("Base.WaterBottleFull")

-- 移除物品
container:Remove(item)

-- 遍历容器
local items = container:getItems()
for i = 0, items:size() - 1 do
    local item = items:get(i)
    print(item:getType())
end
```

### 9.3 自定义物品定义

`media/scripts/` 下的 `.txt` 文件定义物品：

```
item MyCustomItem
{
    ItemType            = base:normal,
    Weight              = 0.5,
    Icon                = MyCustomIcon,
    WorldStaticModel    = Money,  -- 实体系统硬币需要此字段
}
```

B42 物品显示名通过 `ItemName_<Module>.<Item>` 翻译键提供，不要继续在脚本中使用旧版
`DisplayName`。注册型字段必须先在 `media/registries.lua` 中登记。

---

## 十、实用工具函数

### 10.1 文本与翻译

```lua
getText("IGUI_SomeKey")                  -- 获取翻译文本
getTextOrNull("IGUI_SomeKey")            -- 不存在返回 nil
```

### 10.2 数学与随机

```lua
ZombRand(max)                            -- 0 到 max-1 随机整数
ZombRand(min, max)                       -- min 到 max-1 随机整数
luautils.round(num, decimals)            -- 四舍五入
```

### 10.3 字符串

```lua
luautils.split(str, delimiter)           -- 分割字符串
string.gsub(str, "\n", "\n")            -- 替换换行符（UI 中常用）
```

### 10.4 颜色

```lua
-- 常用颜色常量
{ r=1, g=1, b=1, a=1 }     -- 白色
{ r=0, g=0, b=0, a=1 }     -- 黑色
{ r=1, g=0, b=0, a=1 }     -- 红色
{ r=0, g=1, b=0, a=1 }     -- 绿色
{ r=0.9, g=0.9, b=0.9, a=0.9 } -- 淡灰（列表选中色）
```

---

## 十一、Mod 开发关键模式

### 11.1 Server-Authoritative Economy（服务端权威结算）

```
客户端：发送请求 → sendClientCommand()
服务端：验证权限 → 查询库存 → 扣款 → 给物品 → sendServerCommand() 回包
客户端：接收回包 → 刷新 UI
```

### 11.2 Timed Action 标准模式

```
客户端：perform() → 播放动画
服务端：complete() → 权威数据修改
```

### 11.3 物品操作安全模式

```lua
-- 创建物品（服务端）
local item = player:getInventory():AddItem("Base.Axe")

-- 删除物品（服务端）
player:getInventory():Remove(item)

-- 转移物品（服务端）
player:getInventory():Remove(item)
targetContainer:AddItem(item)
```

### 11.4 属地判断

```lua
-- 检查物品是否在玩家背包中
local function isInPlayerInventory(item, player)
    return item:getContainer() == player:getInventory()
end

-- 检查容器是否属于玩家
local function isPlayerContainer(container)
    return container:getOwner():isInPlayerInventory()
end
```

---

## 十二、环境差异速查

| 操作 | MP 客户端 | MP 服务端 | SP |
|------|-----------|-----------|----|
| `getPlayer()` | 返回本地玩家 | 通常不可作为玩家解析器 | 返回本地玩家 |
| `getSpecificPlayer(0)` | 返回本地玩家槽位 | 不用于解析远端玩家 | 返回本地玩家槽位 |
| `sendClientCommand` | 发送到服务端 | 不适用 | 不应作为唯一业务路径 |
| `Events.OnClientCommand` | 不触发 | 接收客户端命令 | 不保证替代本地共享调用 |
| 物品创建/删除 | 只做表现或请求 | 权威操作并同步 | 走已验证的本地/共享结算路径 |
| ModData 读写 | 客户端显示缓存 | 权威持久状态 | 本地持久状态 |
| UI 创建 | 可用 | 不适用 | 可用 |
| Timed Action | 客户端表现 | 网络动作 `complete()` 权威结算 | 按同版本动作类型复验 |

B42.19 本体证据：`client/FeedingTrough/CFeedingTroughGlobalObject.lua` 明确把
`not isClient()` 视为单人已本地更新；`server/BuildRecipeCode/buildRecipeCode.lua` 在同一 server 文件内
用 `isServer()` 区分 MP 服务端与非服务端路径。因此“server 目录会在 SP 加载”不等于
“SP 的 `isServer()` 为 true”。

---

## 十三、已知陷阱

1. **UI drawText 必须传完整参数**：`drawText(text, x, y, r, g, b, a, font)`，缺参数会红字报错
2. **自定义物品 ItemType**：B42 应使用 `ItemType = base:normal`，非旧版的 `Type = Normal`
3. **实体系统硬币**：需要 `WorldStaticModel = Money` 防止 NPE
4. **OnClientCommand handler**：必须重新解析对象（通过 ID/类型名），不能直接使用客户端传来的对象引用
5. **OnClientCommand 分发**：必须包 `pcall`，避免单个 handler 报错阻塞后续
6. **sendClientCommand 版本差异**：先按 `sendClientCommand(player, module, command, args)` 发送，失败再 fallback 到三参数格式
7. **SP 环境**：server 文件可能加载，但 `isServer()` 不是 SP 判断；需要保留已验证的 SP 本地或共享路径

---

*本文档基于 B42.19 游戏本体 Lua 调用点整理。表中签名是开发导航，调用前仍须按环境和重载复验。*

---

## 十四、车辆系统 API

### 14.1 Vehicle（车辆对象）

```lua
local vehicle = player:getNearVehicle()  -- 或其他方式获取

-- 部件查询
vehicle:getPartById("Engine")              -- → VehiclePart
vehicle:getPartById("GloveBox")            -- 按 ID 获取部件
vehicle:getPartById("TruckBed")
vehicle:getPartById("GasTank")
vehicle:getPartById("TrunkDoor")
vehicle:getPartById("DoorFrontLeft")
vehicle:getPartById("HeadlightLeft")
vehicle:getPartByIndex(i)                  -- 按索引获取 (0-based)
vehicle:getPartCount()                     -- → number

-- 车辆属性
vehicle:getScriptName()                    -- → string (如 "Base.CarNormal")
vehicle:getModuleName()                    -- → string
vehicle:getId()                            -- → number (唯一ID)
vehicle:getKeyId()                         -- → number
vehicle:getMechanicalID()                  -- → number

-- 位置
vehicle:getX() / vehicle:getY() / vehicle:getZ()

-- 乘客
vehicle:getDriver()                        -- → IsoPlayer | nil
vehicle:getMaxPassengers()                 -- → number
vehicle:getPassengerDoor(seat)             -- → VehiclePart (0-based seat)

-- 状态
vehicle:isEngineRunning()                  -- → boolean
vehicle:isEngineWorking()                  -- → boolean
vehicle:isHotwired()                       -- → boolean
vehicle:hasKey()                           -- → boolean
vehicle:isKeysInIgnition()                 -- → boolean
vehicle:isAlarmed()                        -- → boolean
vehicle:isPreviouslyEntered()              -- → boolean

-- 快捷访问
vehicle:getBattery()                       -- → VehiclePart
vehicle:getEngine()                        -- → VehiclePart
vehicle:getGasTank()                       -- → VehiclePart

-- 区域
vehicle:isInArea(area, character)          -- 角色是否在车辆某区域
vehicle:getBloodIntensity(id)              -- 血迹强度
vehicle:getScript()                        -- → VehicleScript
```

### 14.2 VehiclePart（车辆部件）

```lua
local part = vehicle:getPartById("GloveBox")

-- 物品
part:getInventoryItem()                    -- → InventoryItem | nil (安装的物品)
part:setInventoryItem(item, mechanicsLevel) -- 安装物品到部件
part:getItemContainer()                    -- → ItemContainer | nil (部件容器)
part:getContainer()                        -- 同上

-- 类型
part:getId()                               -- → string (如 "GloveBox")
part:getPartType()                         -- → string
part:getArea()                             -- → string
part:getItemType()                         -- → string

-- 状态
part:getCondition()                        -- → number
part:getModData()                          -- → table
part:isLocked()                            -- → boolean
part:setLocked(bool)                       -- 设置锁定
part:getDoor()                             -- 门相关

-- 容器访问
part:getContainerAccess(character)         -- 角色是否可访问
```

### 14.3 车辆容器访问模式

```lua
-- 获取车辆容器并操作
local part = vehicle:getPartById("GloveBox")
local container = part:getItemContainer()
if container then
    container:AddItem("Base.Axe")
end

-- 后备箱
local trunk = vehicle:getPartById("TruckBed")
if trunk and trunk:getItemContainer() then
    -- 操作后备箱物品
end

-- 座椅容器
for seat = 0, vehicle:getMaxPassengers() - 1 do
    local part = vehicle:getPassengerDoor(seat)
    if part and part:getItemContainer() then
        -- 操作座椅物品
    end
end

-- 通过容器反查车辆
local container = srcContainer
if container:getParent() and instanceof(container:getParent(), "BaseVehicle") then
    local vehicle = container:getParent()
    local part = vehicle:getPartById(container:getType())
end
```

### 14.4 车辆命令（网络通信）

```lua
-- 客户端发送车辆命令
sendClientCommand(player, "vehicle", "repair", { vehicle = vehicleId, part = partId })
sendClientCommand(player, "vehicle", "setContainerContentAmount", args)

-- 服务端接收（VehicleCommands.lua 模式）
-- 注册: Events.OnClientCommand.Add(VehicleCommands.OnClientCommand)
-- 分发: module == 'vehicle' and Commands[command] then Commands[command](player, args)
```

---

## 十五、Traits 特质系统

### 15.1 玩家特质操作

```lua
local player = getPlayer()

-- 查询
player:hasTrait(CharacterTrait.BURGLAR)    -- 是否拥有指定特质
player:hasTrait(CharacterTrait.ILLITERATE)
player:hasTrait(CharacterTrait.DEXTROUS)
player:hasTrait(CharacterTrait.STRONG)
player:getCharacterTraits()                -- → CharacterTraits 对象
player:getCharacterTraits():getKnownTraits()  -- → ArrayList<string>

-- 运行时修改（需在服务端执行）
player:addTrait(traitName)                 -- 添加特质（string 类型名）
player:removeTrait(traitName)              -- 移除特质

-- 遍历已有特质
local traits = player:getCharacterTraits():getKnownTraits()
for i = 0, traits:size() - 1 do
    local trait = CharacterTraitDefinition.getCharacterTraitDefinition(traits:get(i))
    print(trait:getLabel(), trait:getType())
end
```

### 15.2 CharacterTraitDefinition（特质定义）

```lua
-- 获取所有特质定义
local allTraits = CharacterTraitDefinition.getTraits()  -- → ArrayList
for i = 0, allTraits:size() - 1 do
    local traitDef = allTraits:get(i)
end

-- 按类型名获取
local traitDef = CharacterTraitDefinition.getCharacterTraitDefinition("Burglar")

-- 属性
traitDef:getType()                         -- → string (如 "Burglar")
traitDef:getLabel()                        -- → string (显示名称)
traitDef:getDescription()                  -- → string (描述)
traitDef:getCost()                         -- → number (点数消耗)
traitDef:isPositive()                      -- → boolean
traitDef:isNegative()                      -- → boolean
traitDef:isFree()                          -- → boolean (职业赠送)
traitDef:getMutuallyExclusive()            -- → ArrayList<string> (互斥特质)
traitDef:getGrantedTraits()                -- → ArrayList<string> (附赠特质)
```

### 15.3 Profession（职业）

```lua
-- 职业定义
local profession = player:getProfession()
profession:getType()                       -- → string
profession:getLabel()                      -- → string
profession:getDescription()                -- → string
profession:getGrantedTraits()              -- → ArrayList<string>
```

### 15.4 常用 CharacterTrait 常量

```lua
CharacterTrait.BURGLAR       -- 盗贼
CharacterTrait.DEXTROUS      -- 灵巧
CharacterTrait.ALL_THUMBS    -- 笨拙
CharacterTrait.STRONG        -- 强壮
CharacterTrait.WEAK          -- 虚弱
CharacterTrait.BRAVE         -- 勇敢
CharacterTrait.COWARDLY      -- 胆小
CharacterTrait.DESENSITIZED  -- 麻木不仁
CharacterTrait.HEMOPHOBIC    -- 恐血症
CharacterTrait.ILLITERATE    -- 文盲
CharacterTrait.HANDY         -- 心灵手巧
CharacterTrait.INSOMNIAC     -- 失眠
CharacterTrait.NEEDS_LESS_SLEEP  -- 少睡
CharacterTrait.NEEDS_MORE_SLEEP  -- 多睡
```

---

## 十六、物品脚本完整定义格式

### 16.1 基础物品 (ItemType = base:normal)

```
item MyItemName
{
    DisplayCategory = Material,           -- 分类
    ItemType = base:normal,               -- B42 新格式
    Weight = 0.5,                         -- 重量
    Icon = MyIcon,                        -- 背包图标
    StaticModel = MyModel,                -- 3D 模型
    WorldStaticModel = MyWorldModel,      -- 世界掉落模型
    Tags = base:isfirefuel;base:isfiretinder,  -- 标签（分号分隔）
    CanHaveHoles = false,                 -- 是否有弹孔
    Insulation = 0.8,                     -- 隔热值
    WindResistance = 0.25,                -- 防风值
    ChanceToFall = 80,                    -- 从身上掉落概率
    BloodLocation = Head,                 -- 血迹位置
    BodyLocation = base:hat,              -- 穿戴位置
}
```

### 16.2 容器物品 (ItemType = base:container)

```
item Bag_GolfBag
{
    DisplayCategory = Bag,
    ItemType = base:container,
    Weight = 1.2,
    IconsForTexture = GolfBag_Blue;GolfBag_Green;GolfBag_Red;GolfBag_Purple,
    CanBeEquipped = base:back,            -- 可装备位置
    BodyLocation = base:back,
    Capacity = 18,                        -- 容量
    WeightReduction = 65,                 -- 减重百分比
    RunSpeedModifier = 0.95,              -- 跑速修正
    OpenSound = OpenBag,                  -- 打开音效
    CloseSound = CloseBag,                -- 关闭音效
    PutInSound = PutItemInBag,            -- 放入音效
    ReplaceInPrimaryHand = Model_RHand,   -- 右手手持模型
    ReplaceInSecondHand = Model_LHand,    -- 左手手持模型
    ClothingItem = Bag_GolfBag,           -- 服装模型
    AttachmentReplacement = Bag,          -- 附件替换
    WorldStaticModel = GolfBag_Ground,
    Tags = base:hasmetal,
}
```

### 16.3 服装 (ItemType = base:clothing)

```
item Dress_Knees
{
    DisplayCategory = Clothing,
    ItemType = base:clothing,
    Icon = DressShortWhite,
    BloodLocation = ShortsShort;Shirt,
    BodyLocation = base:dress,            -- 穿戴层级
    ClothingItem = Dress_Knees,           -- 服装模型名
    ClothingItemExtra = Dress_Knees_Extra, -- 额外服装模型
    FabricType = Cotton,                  -- 布料类型
    Insulation = 0.15,
    WindResistance = 0.1,
    WorldStaticModel = Dress_Short_Ground,
    Tags = base:canbedyed;base:ripclothingcotton;base:noragdoll,
}
```

### 16.4 常用属性速查

| 属性 | 用途 | 示例值 |
|------|------|--------|
| `ItemType` | 物品类型 | `base:normal`, `base:container`, `base:clothing`, `base:food`, `base:weapon`, `base:drainable`, `base:literature` |
| `DisplayCategory` | 分类 | `Material`, `Clothing`, `Bag`, `Weapon`, `Food`, `Tool` |
| `Weight` | 重量 | `0.5` |
| `Capacity` | 容器容量 | `18` |
| `WeightReduction` | 减重% | `65` |
| `CanBeEquipped` | 装备位置 | `base:back`, `base:belt` |
| `BodyLocation` | 穿戴位置 | `base:hat`, `base:dress`, `base:shirt` |
| `Condition` | 耐久 | `10` |
| `ConditionMax` | 最大耐久 | `10` |
| `IsBreakable` | 可损坏 | `true/false` |
| `Tags` | 标签 | `base:hasmetal;base:isfirefuel` |
| `hidden` | 隐藏物品 | `true/false` |
| `WorldRender` | 世界渲染 | `true/false` |
| `StaticModel` | 3D静态模型 | 模型名 |
| `WorldStaticModel` | 世界掉落模型 | 模型名 |
| `EatType` | 食用方式 | `CannedFood`, `FreshFood` |
| `HungerChange` | 饥饿变化 | `-30` |
| `ThirstChange` | 口渴变化 | `-20` |
| `IsCookable` | 可烹饪 | `true/false` |
| `IsFood` | 是食物 | `true/false` |
| `UseDelta` | 每次使用消耗 | `0.1` |
| `UseWhileEquipped` | 装备时使用 | `true/false` |
| `CanBandage` | 可包扎 | `true/false` |
| `BandagePower` | 包扎效果 | `4` |
| `LightDistance` | 光照距离 | `10` |
| `LightStrength` | 光照强度 | `0.6` |
| `TwoHandWeapon` | 双手武器 | `true/false` |
| `WeaponSprite` | 武器精灵 | `Axe` |
| `MinAngle` | 最小攻击角度 | `0.2` |
| `MaxDamage` | 最大伤害 | `1.5` |
| `MinDamage` | 最小伤害 | `0.5` |
| `MaxRange` | 最大攻击范围 | `1.6` |
| `WeaponLength` | 武器长度 | `0.35` |
| `RunSpeedModifier` | 跑速修正 | `0.95` |
| `CombatSpeedModifier` | 战斗速度修正 | `1.0` |

---

## 十七、Recipe 合成系统

### 17.1 配方定义格式

位置：`media/scripts/` 下的 `.txt` 文件

```
recipe RecipeName
{
    -- 输入材料
    item1,
    item2,
    [keep item1],           -- 保留物品（不消耗）

    -- 输出
    Result:ResultItem,
    Result:ResultItem2,

    -- 工具
    Tool:Base.Hammer,
    Tool:Base.Screwdriver,

    -- 技能要求
    skillRequired:Woodwork=5,
    skillRequired:Carpentry=2,

    -- 属性
    timedAction = Making,         -- 动作类型
    time = 30,                    -- 基础时间
    category = Packing,           -- 分类
    recipeGroup = OpenBox,        -- 分组
    Tags = InHandCraft;CanBeDoneInDark,  -- 标签
    NeedToBeLearn = true,         -- 需要学习
    OnCreate = MyMod.OnCreate,    -- 创建回调
    AllowBatchCraft = false,      -- 是否允许批量
    CanBeDoneFromFloor = true,    -- 地板合成
    NearItem = Base.Workbench,    -- 需要附近物品
    Prop1 = value,                -- 自定义参数
    Prop2 = value,
    Destroy = true,               -- 销毁输入物品
    luaTest = MyMod.testFunc,     -- 条件检查
}
```

### 17.2 配方输入格式

```
-- 基本输入
item Base.Plank,
item Base.Nails,

-- 保留输入物品
[keep Base.Hammer],
[keep Base.Screwdriver],

-- 多选一
[Base.Plank;Base.Log],
item 1 [Base.Plank;Base.Log],

-- 带数量
item 2 Base.Plank,
item 5 [Base.Nails;Base.Screws],

-- 可变输入（mapper）
item 1 [Base.Bullets9mmBox;Base.Bullets45Box] mappers[ammoTypes] flags[Prop2;AllowFavorite],

-- 工具
Tool:Base.Hammer,
Tool:Base.Screwdriver,

-- 液体
Drainable:Base.WaterBottle,
```

### 17.3 配方输出格式

```
-- 基本输出
Result:Base.Plank,
Result:Base.Nails=5,

-- 多输出
Result:Base.Plank,
Result:Base.Nails=5,

-- 可变输出
outputs
{
    item 50 Base.Bullets9mm,
    item 20 Base.Bullets45,
    item 50 Base.Bullets38,
    item 50 Base.Bullets357,
}
```

### 17.4 代码中操作配方

```lua
-- 获取配方
local recipe = RecipeManager.getDismantleRecipeFor(itemType)

-- 执行配方
RecipeManager.PerformMakeItem(recipe, item, character, nil)

-- 获取脚本物品
local scriptItem = ScriptManager.instance:getItem("Base.Axe")
local scriptItem = getScriptManager():FindItem("Base.Axe")

-- 按标签查找物品
local items = getScriptManager():getItemsTag("base:isfirefuel")
```

---

## 十八、Sound 音频系统

### 18.1 播放音效

```lua
-- Timed Action 中绑定音效（最常用）
function MyAction:new(character)
    -- ...
    o.sound = character:playSound("SoundName")
    -- 返回 sound 对象，action 结束时自动停止
end

-- 世界音效
getSoundManager():PlayWorldSound("Shoveling", square, 0, 10, 1, true)
-- 参数：音效名, 格子, 音量, 距离, 音调, 循环

-- UI 音效
getSoundManager():playUISound("UIObjectMenuEnter")
getSoundManager():playUISound("UIObjectMenuObjectRotateOutline")

-- 通过发射器
player:getEmitter():playSound("VehicleHotwireStart")
```

### 18.2 常用音效名参考

| 音效名 | 场景 |
|--------|------|
| `WaterCrops` | 浇水 |
| `Shoveling` | 铲土 |
| `SowSeeds` | 播种 |
| `HarvestCrops` | 收割 |
| `DigFurrowWithShovel` | 铲子挖沟 |
| `DigFurrowWithTrowel` | 小铲挖沟 |
| `DropSoilFromSandBag` | 施肥 |
| `CleanBloodVehicle` | 洗车 |
| `VehicleAddFuelFromGasPump` | 加油 |
| `VehicleAddFuelFromCanister` | 油桶加油 |
| `CanisterAddFuelSiphon` | 抽油 |
| `VehicleHotwireStart` | 短接启动 |
| `BlowTorch` | 喷灯 |
| `OpenBag` / `CloseBag` | 背包开关 |
| `PutItemInBag` | 放入背包 |
| `RemoveFishingNet` / `CheckFishingNet` | 渔网 |

---

## 十九、BodyDamage 身体伤害系统

### 19.1 基础 API

```lua
local player = getPlayer()
local bodyDamage = player:getBodyDamage()

-- 身体部位
local bodyParts = bodyDamage:getBodyParts()  -- → ArrayList<BodyPart>
local bodyPart = bodyDamage:getBodyPart(BodyPartType.FromIndex(i))

-- 部位属性
bodyPart:getType()                         -- → BodyPartType 枚举
bodyPart:getHealth()                       -- → number
bodyPart:isBleeding()                      -- → boolean
bodyPart:isInfected()                      -- → boolean
bodyPart:hasFracture()                     -- → boolean
bodyPart:getScratchCount()                 -- → number
```

### 19.2 BodyPartType 常用值

```lua
BodyPartType.Head
BodyPartType.Neck
BodyPartType.Torso_Upper
BodyPartType.Torso_Lower
BodyPartType.Hand_L
BodyPartType.Hand_R
BodyPartType.ForeArm_L
BodyPartType.ForeArm_R
BodyPartType.UpperArm_L
BodyPartType.UpperArm_R
BodyPartType.Groin
BodyPartType.UpperLeg_L
BodyPartType.UpperLeg_R
BodyPartType.LowerLeg_L
BodyPartType.LowerLeg_R
BodyPartType.Foot_L
BodyPartType.Foot_R

-- 转换
BodyPartType.ToIndex(bodyPartType)         -- → number
BodyPartType.FromIndex(index)              -- → BodyPartType
BodyPartType.ToString(bodyPartType)        -- → string
```

---

## 二十、Perks 技能系统

```lua
local player = getPlayer()

-- 技能等级
player:getPerkLevel(Perks.Mechanics)        -- → number
player:getPerkLevel(Perks.Electricity)
player:getPerkLevel(Perks.Carpentry)
player:getPerkLevel(Perks.Woodwork)

-- 增加经验
player:getXp():AddXP(Perks.Mechanics, 50)

-- 常用 Perks 常量
Perks.Mechanics
Perks.Electricity
Perks.Carpentry
Perks.Woodwork
Perks.MetalWelding
Perks.Cooking
Perks.Farming
Perks.Fishing
Perks.Trapping
Perks.Foraging
Perks.Aiming
Perks.Reloading
Perks.Sprinting
Perks.Lightfoot
Perks.Nimble
Perks.Sneak
Perks.Axe
Perks.Blunt
Perks.LongBlade
Perks.ShortBlade
Perks.Spear
Perks.Maintenance
```

---

## 二十一、Sandbox 沙盒选项

```lua
-- 读取沙盒设置
SandboxVars.MyMod.MyOption               -- 读取自定义 Mod 选项
SandboxVars.Lore.ProperZombies           -- 原版选项

-- Mod 沙盒定义
-- B42 Mod 使用 media/sandbox-options.txt，并同步提供对应翻译键
```
