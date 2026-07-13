# 第三方 MOD 本体汉化经验：KnoxSurvivors

时间：2026-06-28

目标 MOD：`C:\Users\Admin\Zomboid\mods\KnoxSurvivors`

## 当前结论

- 用户取消订阅后，直接修改本地 MOD 本体，不再使用单独汉化补丁入口。
- 保持 `id=KnoxSurvivors`，不要启用或恢复 `KnoxSurvivorsCN`。
- 不要把中文直接写入 Lua 桥接文件。Lua 文件保持 ASCII-only，中文放入 `Translate\CN`。
- B42 第三方 MOD 可能同时读取传统 `UI_CN.txt` 和 JSON 翻译文件，修改后要同步生成 `ui.json`。

## 稳定汉化结构

当前采用：

- `42\media\lua\client\KS_CN_LocalizationPatch.lua`
- `42\media\lua\shared\Translate\CN\UI_CN.txt`
- `42\media\lua\shared\Translate\CN\ui.json`
- `42\media\lua\shared\Translate\CN\Sandbox_CN.txt`
- `42\media\lua\shared\Translate\CN\sandbox.json`
- `42\media\lua\shared\Translate\CN\IG_UI_CN.txt`
- `42\media\lua\shared\Translate\CN\ig_ui.json`

Lua 桥接只做英文原文到 `getText("UI_KSCN_*")` 的映射，不直接包含中文。

## 这次剩余英文的根因

截图中指挥面板顶部仍显示：

- `Squad`
- `Base`
- `Jobs`
- `Gear`
- `Signs`
- `County`
- `[H] Help`

以及正文：

- `Survivors`
- `No recruited survivors yet. Go to Signs, listen, approach carefully, help, then ask them along.`

根因不是翻译文件未加载，而是 `KS_CommandPanelLayoutRedesign.lua` 会定义/覆盖 `KS.GetCommandPanelTabLabel()`。如果汉化桥接比它更早加载，顶部标签函数会被后续文件重新覆盖成英文。

修复方式：

- 在桥接中新增 `installTabLabelOverride()`，可重复安装 `KS.GetCommandPanelTabLabel()` 和 `KS.GetCommandPanelTabTooltip()`。
- 在 `patchKS()` 已经执行过的情况下，后续 `patchWhenReady()` 仍然重新安装标签函数。
- 在 `KSPlayerPanel:createChildren()`、`KSPlayerPanel:onTab()`、`KSPlayerPanel:refresh()` 包装后调用 `refreshPanelChrome()`，刷新已打开窗口的标题、顶部按钮和 tooltip。
- 对正文行继续走 `KSPlayerPanel.setLines()` 的逐行翻译。

## 验证要求

每次修改后运行：

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\Admin\Desktop\PJ\Test-KnoxSurvivorsLocalCN.ps1"
```

若存在 Lua 编译器，再运行：

```powershell
C:\Users\Admin\Tools\Lua51\luac.exe -p "C:\Users\Admin\Zomboid\mods\KnoxSurvivors\42\media\lua\client\KS_CN_LocalizationPatch.lua"
```

必须确认：

- `KS_CN_LocalizationPatch.lua` 仍是 ASCII-only。
- 翻译文件和 JSON 没有 `U+FFFD` 替换字符。
- `ui.json` 能被 JSON 解析。
- `UI_CN.txt` 和 `ui.json` 同时包含新增 key。

## 注意事项

- PowerShell 控制台显示中文乱码不等于文件损坏。判断文件是否损坏要用 UTF-8 读取和替换字符扫描。
- 对第三方 MOD 做本体汉化时，优先做最小桥接，不重写原 MOD 主逻辑。
- 硬编码右键菜单可以包 `ISContextMenu:addOption` / `addOptionOnTop`，但 UI 面板类更稳的是包装该 MOD 自己的 `setLines` / `setActions` / 标签函数。
- 如果发现“部分英文已经汉化，但某个页签/标题仍英文”，优先检查是否有后加载文件覆盖了汉化函数，而不是直接修改原 MOD 大量源码。
