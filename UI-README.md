# GodSystem 正式终端 UI

2026-09-13 用户确认 3.6 UI 重制版通过并授权合入正式目录。当前开发源码是 `C:\APPS\Pzmodproject\GodSystem-main`，版本 `42.20_3.7`；后续开发从这里继续。`GodSystem-UI-test` 是此前测试来源，不再作为开发入口。

本次集成保留终端布局、商店图标网格、内嵌装备培养、手册、三档字体、窗口尺寸与偏好存档、自动装填机界面，以及 9 月 12 日的中文说明、装备改名和冲击修复。根目录 `UI-BASELINE-MANIFEST.json` 仅记录当初创建测试副本时的旧源码哈希，不是当前 3.7 的校验清单。历史过程见交接 87；当前交付与负重实现见交接 88。

## 维护入口

- 手册源：`tools/ui/terminal_guide.json`；生成器 `tools/ui/generate_terminal_guide.py`。当前包含 20 篇功能和全部 18 种声明物品。
- 界面文案：`tools/localization/godsystem_v11645_localization.yml`。负重英文补充源为 `godsystem_carry_en.yml`，由同一个本地化生成器维护。
- 色彩与文字：`GodSystem_TerminalDesign.lua`；字号和窗口预设：`GodSystem_TerminalPreferences.lua`。
- 页面适配：`GodSystem_TerminalShell.lua`；内嵌装备、手册、装填机分别使用对应的 Terminal 模块。
- 业务继续由原有 runtime/service 负责。负重页面使用共享状态结果；绘制时不扫描背包、不创建物品、不计算报价。

## 检查与预览

```powershell
python tools/localization/generate_godsystem_v11645_localization.py
python tools/ui/generate_terminal_guide.py
python tools/tests/run_lua_tests.py
python tools/tests/run_kahlua_tests.py --game "C:\APPS\Steam\steamapps\common\ProjectZomboid"
python tools/ui/check_terminal.py
python tools/ui/preview_terminal.py
./tools/Test-GodSystem.ps1
```

Python 命令需使用安装了测试 `lupa.lua51` 的解释器，依赖仅放在 `.test-runtime`。`ui-preview/index.html` 是真实 Lua 绘图指令的离线预览，使用示例数据和字体度量，不能作为游戏截图或新增功能的实机验收证据。

3.6 UI 已获用户确认；3.7 新负重仍需在当前游戏补丁验证购买、读档、重生、重连和 UCWF 共存。完整 MOD 位于本目录的 `Contents/mods/GodSystem`。本轮未自动安装到游戏、发布、推送或替换备份。
