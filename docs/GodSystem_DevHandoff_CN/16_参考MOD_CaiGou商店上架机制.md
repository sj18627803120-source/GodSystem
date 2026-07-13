# 参考 MOD：CaiGou's Shop V2 上架机制

参考路径：`C:\Users\Admin\Desktop\PJ\File\CaiGou's Shop`

## 结论

这个 MOD 对 GodSystem 有帮助，但不是直接照搬到当前“卖掉并上架选中”功能。

GodSystem 当前的上架逻辑是：把物品卖掉，然后按 `fullType` 解锁到商城，之后玩家买回的是新生成的同类物品。

CaiGou's Shop 的上架逻辑更像玩家交易所：把玩家真实物品序列化成一组属性数据，服务端保存，其他玩家购买时再按这些属性还原物品。它适合后续做“寄售真实物品”“玩家市场”“保留耐久/食物状态/剩余使用次数的上架”，但复杂度和多人数据压力都更高。

## 关键文件

- `42\media\lua\client\UI\CGTradingPostUI.lua`
  - 玩家交易所 UI。
  - 使用拖拽框接收玩家要上架的物品。
  - 展示交易所列表、分类、卖家、价格。

- `42\media\lua\client\UI\CGShopTextBoxTrading.lua`
  - 上架确认/购买查看弹窗。
  - 上架时遍历物品，调用 `CGShopUtil.getItemAttributes(item)` 打包属性。
  - 客户端发送 `tradingPostList`，参数里包含 `tradingPostItem` 和真实物品 `itemIDs`。

- `42\media\lua\shared\CGShopUtil.lua`
  - `getItemAttributes(item)`：记录物品显示名、fullType、modData、分类、耐久、食物状态、可消耗剩余量、媒体索引等。
  - `restoreItemAttr(item, attr)`：购买时重新创建物品并尽量恢复属性。

- `42\media\lua\server\CGShopServer.lua`
  - 服务端处理 `tradingPostList`、`tradingPostBuy`、`tradingPostBuyAll`。
  - 上架时服务端用 `playerInv:getItemWithID(itemID)` 重新确认真实物品存在，再删除物品并同步容器。
  - 购买时服务端创建物品、恢复属性、加入买家背包、给卖家加钱、从上架包里移除已售物品。

## 值得借鉴的点

- 客户端可以负责整理显示数据，但服务端必须按 `itemID` 重新验证玩家背包里真的有这个物品。
- 删除真实物品后调用 `sendRemoveItemFromContainer()`，发放物品后调用 `sendAddItemToContainer()`，这和我们现有多人同步经验一致。
- 每个上架包和每个单件物品都用 UUID 标识，购买单件时能准确从包里删除对应物品。
- 上架前做保守限制：不允许液体容器、媒体、家具、黑名单物品、破洞/补丁衣物、有武器部件的枪、0 耐久物品等。
- 限制上架包大小。它的文档明确提到玩家上架堆叠物品过多会导致服务端数据过大，后续应该单独同步交易所数据，而不是每次下发整个服务端数据。

## 对 GodSystem 的建议

- 短期不建议把现有“卖掉并上架选中”改成真实物品寄售。当前功能低风险、好理解、数据量小，适合继续作为普通商城解锁。
- 如果后续新增“玩家交易所”或“真实物品寄售”，可以参考 CaiGou's Shop 的数据结构：

```text
listing = {
    uuid = "...",
    seller = "playerName",
    price = 100,
    items = {
        {
            uuid = "...",
            fullType = "Base.Axe",
            displayName = "...",
            condition = 8,
            conditionMax = 10,
            usedDelta = 0.5,
            modData = {...}
        }
    }
}
```

- GodSystem 应保留自己的轻同步原则：打开 UI 同步、关键操作同步、低频后台同步。不要学习 CaiGou 的全量 `CGShopServerData` 频繁下发方式。
- 如果做真实寄售，必须先实现上架数量上限、每名玩家上架总量上限、黑名单、服务端按 itemID 删除、购买时还原失败回滚、交易所分页。

## 与当前功能的关系

当前 GodSystem 的“卖掉并上架选中”只需要继续保证：

- 只处理系统腰包内选中物品。
- 出售成功后按 `fullType` 解锁商城条目。
- 不保存被卖出那件物品的个体属性。
- 多人模式由服务器验证系统腰包和真实物品后执行。

CaiGou's Shop 主要作为后续高级交易所设计参考，不作为当前功能的直接替换方案。
