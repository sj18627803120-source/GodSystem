# 神级系统 v1.16.55 Workshop 上传包说明

上传时选择本目录，也就是包含 `workshop.txt`、`preview.png`、`Contents` 的这一层。

正确结构：

```text
GodSystemWorkshopUpload_v1.16.55\workshop.txt
GodSystemWorkshopUpload_v1.16.55\preview.png
GodSystemWorkshopUpload_v1.16.55\Contents\mods\GodSystem\mod.info
GodSystemWorkshopUpload_v1.16.55\Contents\mods\GodSystem\42\mod.info
GodSystemWorkshopUpload_v1.16.55\Contents\mods\GodSystem\42\media\...
```

## 本次更新

- v1.16.55：系统空间终端改用原版项链槽；左侧导航改为自适应紧凑分页；悬浮入口改为黑金图标；同伴降低移动速度、增加停顿并允许在不可见区域继续活动，同时扩大灵视范围、缩短守护冷却；同伴和属性升级后保留选中项；车辆修复模块价格修正为5000，并统一走服务端修复流程。
- v1.16.54：修复系统空间终端独立穿戴位置，终端最高 Lv.8、容量49；统一终端页面、商城与快捷操作名称；属性页增加“升到下一级”确认；分类和说明行不再可选；左侧导航均衡分页；守护与过载爆裂增加可见特效。保留 v1.16.53 的属性经验、车辆修复模块和同伴攻击特效。
- v1.16.48：新增原生沙盒默认配置；修复多人理财在线进度不增长；快捷栏拆分腰包回收和腰包回收并上架；隐藏旧回收页，并在原版库存右键菜单提供精确实例的回收、回收并上架和仅上架。
- v1.16.52：浮游机器人改为直接绘制的蓝色双层菱形，使用红色方向传感器和青色双帧推进器；移除 16 张 PNG 与不兼容的 `SpriteRenderer.render(Texture,...)` 调用，统一复用 B42.19 已验证的 `renderline()`。保留蓝白照明、红色长光束、灵视和守护能力。
- v1.16.47：商店新增一次性“系统修复组件”和“耐久强化核心”。修复组件完整恢复当前右手物品的主耐久、头部耐久和锋利度；强化核心永久增加当前右手物品 2 点主耐久上限，并同步增加 2 点当前耐久。支持采用标准耐久接口的 MOD 物品，双手物品有效，两件道具不进入抽奖奖池。
- v1.16.46：银行新增每1游戏小时自动存入全部随身现金；任务页新增每1游戏小时自动提交全部完成任务。银行新增稳健、平衡、激进三个按累计在线24游戏小时结算的理财账户，首次日结后可赎回；停止创建新死期，旧死期存单继续支持支取。管理员可调整理财总开关、最低投入和三档概率/涨跌幅度。
- v1.16.45：腰包空间新增独立“仅回收 / 回收并上架”模式，手动选中、全部出售、快捷栏卖腰包和自动腰包回收统一跟随该模式；多人新增结构化中文提示和 YAML 本地化生成流程。
- v1.16.44: 修复 v1.16.43 银行借贷页面新增文本乱码。补齐 CN/CH 翻译表借贷条目的行尾逗号，并将借贷与管理员借贷配置的 Lua fallback 改为 UTF-8 字节转义，避免新增银行借贷文字在游戏内显示为乱码。
- v1.16.42: 治愈病毒采用 RaccoonCityB42 生化疫苗同类逻辑补齐感染统计清理：在单人本地执行和多人服务端执行时，除清除 BodyDamage 与身体部位感染外，还会把 `CharacterStat.ZOMBIE_INFECTION` 设为 0，避免只清进度但真实僵尸病毒状态残留。
- v1.16.41: 废弃并移除“压制病毒”医疗服务。v1.16.40 的压制实现会在感染标记仍存在时写入感染时间，实测可能瞬间触发死亡；本版医疗服务只保留“感染检查 / 治疗伤势 / 治愈病毒”。旧客户端或异常命令发送压制动作会被服务端拒绝，不再写入角色感染状态。
- v1.16.40: 医疗服务调整。“检查感染”保持原逻辑；“压制病毒”价格改为 200，只清空当前僵尸病毒进度，不再改死亡时长；“治愈病毒”价格改为 2000，会同时清除 BodyDamage 感染标记、感染进度和身体部位感染层。未感染时压制/治愈不扣费。
- v1.16.39: 回收页右键新增“仅上架”。该操作只把当前背包中真实存在的物品解锁到商城，不出售、不删除、不发放回收收益；费用为预计商城售价的 50%，最低 50 系统币，无封顶。多人模式由服务端验证物品、余额和上架资格后扣款并同步商城。
- v1.16.38: 快捷动作栏打开后会每 5 秒轻量刷新一次按钮状态；设置家园或生成/清除返回点后，不需要关闭重开快捷栏也会自动显示或隐藏回家/返回按钮。
- v1.16.37: Fixed medical service red errors caused by safe API probing calling missing B42 body-damage methods. The medical check/heal/cure flow now skips unavailable methods before calling them.

- v1.16.36：快捷悬浮窗改为直接动作栏，不再作为跳页面入口；当前只保留回家、返回、卖腰包、存现金四个常用动作。
- v1.16.36：回家/返回仍走确认、扣费、安全落点和多人传送确认流程；卖腰包复用系统腰包一键出售；存现金会把背包实体系统币全部存入银行活期，多人由服务端扫描真实现金后写入活期。
- v1.16.36：左侧主导航新增上翻/下翻按钮，中间只显示当前页完整功能按钮，玩家不用鼠标滚轮也能发现和切换后续功能。
- v1.16.35：升级页新增医疗服务。感染检查 50、压制感染 1000、治疗伤势 5000、清除病毒 10000；所有医疗服务都有确认弹窗，未感染时压制/清除不会扣费，无伤时治疗不会扣费。
- v1.16.35：多人医疗服务新增 `medicalService` 协议。服务端验证余额、扣系统币并应用身体状态，客户端在成功回包后做本地幂等同步，减少多人状态不生效的问题。
- v1.16.35：标题栏新增“快捷”按钮和快捷悬浮窗，可快速打开任务、抽奖、商城、回收、银行和家园。
- v1.16.35：左侧导航滚动改为只显示完整按钮，并按按钮高度对齐最大滚动量，修复底部按钮露出 UI 框的问题。
- v1.16.34：抽奖奖池新增 B42 脚本字段过滤。隐藏、废弃、伤口、僵尸伤害、身体绷带和测试/占位物品不会再进入独立抽奖候选池。
- v1.16.34：单人抽奖预览、多人服务端抽奖发奖和旧商店抽奖兼容路径统一调用 shared 过滤器；管理员单物品 `lottery` 开关仍保留，但不能强行放行隐藏/内部物品。
- v1.16.33：从 v1.16.31 稳定基线重新制作，废弃 v1.16.32 性能缓存路线。
- v1.16.33：抽奖从商店移出，左侧新增独立“抽奖”页；支持全种类、指定分类、抽 1 次、抽 10 次和自定义次数，抽中后直接发放物品。
- v1.16.33：默认全种类 100/次，分类价格 60/90/150/200/400，自定义上限 50；管理页可用中文调整抽奖开关、价格和上限。
- v1.16.33：多人抽奖由服务端验证余额、扣币、发物品并返回一次性结果弹窗；旧商店分类抽奖入口不再显示。
- v1.16.31：管理页改为中文显示名 + 英文内部键双标识；配置详情显示名称、内部键、类型、分组、范围、默认值、当前值和说明，搜索可匹配中文名、说明和内部键。
- v1.16.31：单物品覆盖详情新增填写示例和字段说明，继续使用 `Base.Axe|buy=500,sell=25,cat=weapon,shop=1,recycle=1,lottery=1` 格式；单人本地保存，多人由服务器保存并下发。
- v1.16.29：腰包页新增“卖掉并上架选中”，只处理系统腰包内选中物品，出售成功后同步解锁到商店；系统腰包兼容前戴/后戴转换；商店改为每页 20 件分页，分类抽奖移入分类菜单，购买/出售后尽量保留选中行和滚动位置。
- v1.16.28：调整多人击杀奖励提示文案。多人击杀奖励仍按每只僵尸 1 系统币批量结算，弹窗改为“击杀奖励合计 +N 系统币”，避免玩家误解为随机奖励。
- v1.16.27：修复多人模式分类抽奖反馈。服务端成功回包会携带抽中的物品、花费和购买价，客户端刷新后弹出结果窗口；多人解锁商品列表会优先使用本地化物品名，避免显示 `Base.xxx` 这类内部英文 ID。
- v1.16.26：主系统窗口重新支持右下角拖拽缩放，但始终保持 `1240x690` 设计比例；最小缩放为 75%，控件、列表、按钮和背景按比例同步缩放，并保存缩放比例。
- v1.16.25：基于 v1.16.23 稳定功能，保留活期优先支付；商城、传送、升级、腰包、天赋、抽奖和刷新任务等消费会先扣活期，不足再扣背包实体系统币；死期不参与直接支付。
- v1.16.23: Install a safe prerender path on all GodSystem scrolling lists, resyncing scrollbar geometry every frame so task, waist, shop, recycle, trait and detail lists do not turn black when scrolling is needed.
- v1.16.22: Sync reused `ISScrollingListBox` scrollbar geometry after fixed-layout relayouts, fixing long shop/recycle/trait lists turning black when scrollbars appear; task refresh button now uses a shorter non-truncated label.
- v1.16.21: Reset reused `ISScrollingListBox` scroll/smooth-scroll state when rebuilding pages, fixing shop/trait center-list black or invisible rows while right-side detail/right-click selection still worked.
- v1.16.20：回收/商城列表不再鼠标滑过自动选中，必须左键或右键点击才会选中；右键仍保留批量购买、卖 1、卖一半、全卖等菜单。
- v1.16.20：任务页待接取/进行中双列只保留一个高亮选中项，右侧详情和底部按钮跟随当前唯一选中项。
- v1.16.20：回收页加入搜索；商城购买和回收操作后尽量保留原选中物，不再无故跳回第一项。
- v1.16.20：银行死期新增“现金存死期”，可直接从背包系统币创建死期；原“活期转死期”仍保留。
- v1.16.19：散装弹药回收固定为 1 币，盒装、箱装、弹匣、弹药箱、弹带和容器不按散装弹药处理，用来降低盒装弹药拆开后套利。
- v1.16.18：任务页改为 `[类型][D1] 任务简称` 紧凑标题；进行中任务双行显示进度和剩余时间，右侧详情拆分说明、奖励、失败惩罚；未完成进行中任务可点“放弃任务”，等同失败。
- v1.16.18：死亡会让当前所有进行中任务失败；银行死亡惩罚改为只扣活期 30%；所有任务失败罚金先扣活期，不足再扣身上现金，且不会扣成负数。
- v1.16.17：修复固定暗金大面板任务页标题重叠问题；“待接取任务/进行中任务”列标题移到页面标题栏下方，任务列表同步下移，避免黄字和白色“任务”重叠。
- v1.16.16: Fixed 1240x690 dark-gold panel UI. Reworked top status bar, left navigation, list/detail panels and bottom action bar while keeping v1.16.13/v1.16.15 gameplay logic stable.
- v1.16.16：废弃失败的 v1.16.14 UI 实现，基于 v1.16.13/v1.16.15 稳定逻辑重制固定 1240x690 暗金大面板 UI；顶部状态栏、左侧大导航、任务双列、记录/说明单列、银行五动作和多人轻同步仍保留。
- v1.16.13：银行页新增手动“钱币整理”，只整理玩家当前可用的实体系统币并兑换为大面额；多人模式走服务端验证/删除/重发和结构化中文提示。
- v1.16.13：多人腰包自动回收改为客户端按 1 游戏小时触发，服务端只在收到命令时验证系统腰包并执行回收；若有关键命令正在等待回包则跳过本次触发，减少碰撞和后台空刷。
- v1.16.12：修复多人移动距离任务在服务端 state 覆盖后不计数或进度回退的问题；客户端可信保留移动距离进度，并在领取、提交、超时、死亡和后台同步前刷新移动采样。
- v1.16.11：修复多人模式购买天赋后附带技能等级不生效的问题；服务端购买成功后按 B42 同版本参考写法补发 `getXpBoosts()` 技能和 `getGrantedRecipes()` 配方，并恢复天赋页“刷新显示”按钮。
- v1.16.10：修复新增银行页中文乱码；修复诊断页打开时 `setVisible` 报错。
- v1.16.9：新增银行页。默认开放，现金可存入活期，活期可转入 1/3/7 天死期；死期按游戏时间计时，到期有利息，提前支取无息并扣 5% 本金。
- v1.16.9：新增死亡结算基础；后续 v1.16.18 调整为死亡扣除银行活期 30%，死期不直接扣除，且死亡会让所有进行中任务失败。
- v1.16.9：多人家园传送改为服务端先验证余额和安全落点，客户端实际传送成功后回执，服务端再扣费和保存出发点，避免“扣钱但没传送”。
- v1.16.9：多人天赋改造改为解析 B42 `CharacterTraitDefinition`，实际确认角色天赋变化后才扣费；扣费失败会回滚天赋。
- v1.16.6：新增共享协议文件，收拢客户端/服务端命令名和关键操作集合；多人关键操作增加 pending 锁，等待服务端 result/state 回包，减少重复点击和多余刷新。
- v1.16.6：服务端实体系统币扣除改为尽量精确扣币，必要时才找零，降低多人背包同步闪动。
- v1.16.6：新增诊断页，显示 SP/MP、stateSerial、pending、最后命令、客户端/服务端错误和命令计数，便于排查页面空白、提示缺失和同步问题。
- v1.16.7：多人关键操作增加 15 秒 pending 超时兜底；诊断页显示 pending 等待秒数、超时次数和最后超时命令。
- v1.16.9：修正击杀任务死亡重生后进度归零/卡 0；击杀任务改为独立累计进度，死亡只重设击杀基线。
- v1.16.9：系统币扣除增加失败回滚；多人余额改为递归扫描背包内子容器，减少系统币放进包中包后余额不对的问题。
- 一个 MOD 条目同时支持单人/多人：单人保留原本地逻辑，多人客户端发请求，服务端结算系统币、商城、回收、腰包、任务、传送和天赋。
- 根据 `YeseMarket` 与 `Server Shop 42.19` 参考，增强多人握手重试、客户端命令发送兼容和服务端命令异常保护。
- 修正打开 UI、来回切页时部分页面偶发空白的问题；多人模式下任务页只渲染服务器 state，不再在绘制过程中触发刷新。
- 记录和说明页改为单列文本页，隐藏不需要的详情栏，减少快速切页/缩放时内容变黑或丢失。
- 多人记录改为服务端保存结构化 code，客户端本地化显示，避免新记录继续乱码。
- 多人击杀奖励发币时增加客户端提示。
- 多人击杀奖励改为客户端同步击杀数给服务端，服务端按差值发放实体系统币，以稳定可用为优先。
- 主系统 UI 缩放布局重做：导航、列表、详情栏、任务双列、搜索框和底部按钮会按窗口尺寸重新计算，缩小时由最小尺寸限制兜底。
- 系统腰包新增自动回收开关：100 系统币解锁，之后可免费开关，每 1 游戏小时自动出售系统腰包第一层可回收物品，不解锁商城单品。
- 任务追踪窗口改为可右下角拖拽缩放，宽高会保存，进度列按窗口宽度动态显示。
- 家园/传送移除移动状态误判，不再因为站定后 UI 状态同步提示“移动中无法传送”；车内仍禁止传送。
- 返回出发点条目新增“删除出发点”按钮，可手动清空出发点，不扣系统币。
- 修复部分玩家在系统币发放时出现 `giveItem / giveCurrency` 红字的问题。
- 物品发放失败时会捕获异常并提示检查 MOD 安装结构，不再连续刷 Java 报错。
- 初始系统币发放失败时不会吞掉初始点数，修正安装后重进会继续尝试发放。
- 回收价格仍为购买价的 `1/20`，但低价物品恢复单件保底 1 币。
- 保留 v1.15.3 的 B42 系统币脚本修复，不依赖 `that DAMN Library`。

## 本地测试

- v1.16.41: 升级页医疗服务不应再显示“压制病毒”；管理员配置也不应再出现压制价格。治愈病毒仍应可用。
- v1.16.40: 检查感染仍只返回感染状态；压制病毒应只把感染进度清空但角色仍被判定感染；治愈病毒应真正移除感染状态，并且多人由服务端扣费后回包同步。
- v1.16.38: Open the shortcut bar, then set or clear home/return state; Home/Return buttons should refresh within 5 real seconds without reopening the shortcut bar.
- v1.16.36: Shortcut window should execute Home, Return, Sell Waist and Deposit Cash actions directly; left nav should expose page up/down controls.
- v1.16.28: MP zombie kill reward popup now says the amount is a batch total, avoiding the impression that per-kill rewards are random.
- v1.16.27: MP shop category lottery should show the unlocked item result popup, and unlocked shop rows should use localized item names instead of internal fullType IDs.
- v1.16.26: Main GodSystem window supports aspect-locked drag scaling with synchronized controls and saved scale.
- v1.16.25: Current-account-first payment for shop, teleport, upgrades, waist, traits, lottery and task refresh.
- v1.16.23: Task available/active lists, waist space, shop all-category, recycle, traits, and long detail/info pages should all remain visible when enough rows require scrolling.
- v1.16.22: Long shop all-category, recycle, and trait lists should render when scrollbars appear; task refresh button should show as a short readable refresh-cost label.
- v1.16.21: Shop and traits center list should remain visible after opening, switching pages, right-clicking, and refreshing detail.
- v1.16.20: Intentional click selection, recycle search, persistent selected shop rows after buying, single highlighted task row across dual lists, and fixed deposits from carried cash.
- v1.16.19: Loose ammo recycle value fixed to 1 coin.
- v1.16.18: Compact task rows, abandon-as-failure action, all-active-task death failure, 30% current-account death penalty, and bank-first task failure penalties.
- v1.16.17: Fixed task page header spacing in the fixed dark-gold panel UI.
- v1.16.16: Fixed 1240x690 dark-gold panel UI. Reworked top status bar, left navigation, list/detail panels and bottom action bar while keeping v1.16.13/v1.16.15 gameplay logic stable.
如果只做本地测试，从本包取出：

```text
Contents\mods\GodSystem
```

放到：

```text
C:\Users\<你的用户名>\Zomboid\mods\GodSystem
```

进入游戏后在 MOD 列表启用 `God System CN / 神级系统`。

如果仍提示系统币发放失败，请确认下面文件存在：

```text
GodSystem\42\media\scripts\GodSystem_Items.txt
```
