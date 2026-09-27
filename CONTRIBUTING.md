# 参与 GodSystem 开发

感谢愿意帮助改进模组。即使以前没有开发过 Project Zomboid 模组，也可以先从能复现的问题或界面文字开始。提交前请说明实际测试过的环境，避免把自动测试结果当作游戏实测。

## 提交方式

1. 在 [GitHub 仓库](https://github.com/sj18627803120-source/GodSystem)点击 **Fork**，从 `main` 创建自己的分支。
2. 修改后向本仓库的 `main` 提交 **Pull request**。请写清：问题与复现步骤、修改内容、对应游戏版本、单人／房主／专用服务器中实际测过哪些场景，以及尚未验证的场景。截图或发生当次的日志有助于定位问题。
3. 如果尚不确定怎么改，可以先通过 GitHub **Issues** 描述建议或报错，再讨论实现方式。PR 会先审查和测试，不会自动进入创意工坊版本。

请保持修改范围集中，不修改 Mod ID、Workshop ID 或存档键。第三方 MOD 的代码、图片和其他素材不要直接复制进仓库；参考其行为时请注明来源。使用 AI 辅助可以，但提交人仍需阅读改动、验证关键行为，并说明未验证的部分。

## 本地验证

目标环境为 Project Zomboid B42.20.4、Lua 5.1/Kahlua。仓库根目录执行：

```powershell
python tools/tests/run_lua_tests.py
python tools/tests/run_kahlua_tests.py --game "D:\SteamLibrary\steamapps\common\ProjectZomboid"
pwsh tools/Test-GodSystem.ps1
```

把 `--game` 后的路径换成自己的游戏安装路径。测试环境或工具不齐全时，请在 PR 中如实说明。修改界面文字时应编辑 `tools/localization` 下的源文件并运行相应生成器；不要只改一份已生成的翻译文件。架构和存档／多人权限边界见[工程文档](docs/开发技术支援/GodSystem_工程文档.md)，当前开发状态见[交接入口](docs/GodSystem_DevHandoff_CN/00_继续开发入口.md)。
