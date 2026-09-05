# 仓库 Agent 说明（knowledge-reader-flutter）

本仓库是 `knowledge-suite` 的 Android 阅读客户端。设计事实来源是 `doc/` 下的两份文档，不是历史聊天记录：

- `doc/android-reader-design.md`：架构、离线包契约（`contentHash` 算法、manifest 字段、`packageBytes` 含义）、同步流程、错误矩阵、里程碑。
- `doc/rendering-layer.md`：sections → 原生 widget 的渲染规则与内联语法契约。

改行为时同步改文档；文档只写当前设计，不写"旧方案、改成什么"的历史叙述。

## 1 运行环境与命令

| 事项 | 约定 |
| --- | --- |
| Flutter/Dart | 用 Windows SDK：`C:\software\flutter\bin\flutter.bat`。WSL 里没有 Flutter，不要在 WSL 里执行 Flutter 命令 |
| 服务端（`../knowledge-suite`） | 在 WSL 里执行；先 `source ~/.nvm/nvm.sh`（node 由 nvm 提供，`bash -lc` 默认拿不到） |
| 所有命令 | **必须带超时**。PowerShell 用 `Start-Job` + `Wait-Job -Timeout`；WSL 用 `timeout N`。Flutter / Gradle / Docker 都可能长时间无输出 |
| adb | 用 `C:\software\Android\sdk\platform-tools\adb.exe`；WSL 的 PATH 里没有 adb，不要 `wsl adb ...` |
| PowerShell 执行策略 | 禁止 `npm.ps1`；需要 npm 时直接 `node node_modules/vitest/vitest.mjs` 或 `node <npm-cli.js>`，不要依赖 `npm` 脚本壳 |
| 控制台噪音 | 每条 PowerShell 命令开头那句 `profile.ps1 cannot be loaded ... execution policies` 是环境固有的，忽略即可，不要去"修"它 |
| 中文乱码 | 控制台常把中文显示成乱码，**不要据此判断文件编码**。要匹配中文（例如 uiautomator dump、API 响应）时，先把输出写到文件，再用 `Get-Content -Encoding UTF8` 读，或交给 WSL 的 `cat` / `rg` |
| 代理 | 环境里有 `HTTP_PROXY`/`ALL_PROXY` 指向本地 xray，且**经常不可用**，会让 pub/npm 报 `Got socket error`。执行 Flutter/npm 前先清空：`Remove-Item Env:HTTP_PROXY,Env:HTTPS_PROXY,Env:http_proxy,Env:https_proxy,Env:ALL_PROXY,Env:all_proxy -ErrorAction SilentlyContinue`；必要时设 `PUB_HOSTED_URL=https://pub.dev` |

常用命令：

```powershell
# 静态检查与单元测试（必跑）
flutter analyze
flutter test

# 设备上的端到端测试（需要 adb reverse，见第 5 节）
flutter test integration_test/app_test.dart -d emulator-5554

# 手动运行 / 可安装包
flutter run -d emulator-5554
flutter build apk --debug --dart-define=SERVER_BASE_URL=http://127.0.0.1:18765 --dart-define=SERVER_TOKEN=dev-token
```

## 2 产品约束（用户已明确，不要自行扩大范围）

- 只做 reader。不做网页剪藏、不做 AI 摘要、不做注解（高亮/笔记/书签）——这是 v1 的非目标。
- **不做增量同步**：目录同步固定为"全量快照 + `ETag`/`304`"，不要引入游标、`updatedSince`、删除墓碑。
- **不使用 WebView**：正文必须原生渲染 `DocumentSection`。
- 不使用 `flutter_markdown`（已 DISCONTINUED）。
- 离线包与内联语法是**契约**：改之前先改文档与共享语料，再改实现。

## 3 契约与语料

- 内联语法规范：`doc/rendering-layer.md` 第 4 章；共享语料在 `test/fixtures/inline/inline-spec.json`，`test/inline_parser_test.dart` 逐条断言。
- 内容指纹：`packageContentHash()`（`path\0sha256` 清单再哈希，排除 `manifest.json`）。`test/content_hash_test.dart` 里的期望值来自服务端实现，两端必须一致。
- 离线包结构、`manifest.json` 字段、`packageBytes` = 未压缩字节总和，见设计文档第 6 章。
- 修改契约后必须同时改：文档 → 语料/测试 → Dart 实现；涉及服务端产出的还要改 `knowledge-suite`。

## 4 已知坑（都是踩过的，避免重复）

### Flutter / Riverpod

- Riverpod 3.x 没有 `AsyncValue.valueOrNull`，用 `.value`。
- `AsyncNotifier` 自带 `update` 方法，自定义方法不要叫 `update`（会变成非法覆写），本仓库用 `save`。
- **不要在 notifier 里 `ref.invalidate` 依赖自己的 provider**：会抛 `CircularDependencyError`。依赖变化会自动传播，不需要手动失效。
- **`await` 之后不要依赖 `BuildContext`**：列表重建会让当前 widget 卸载，`context.mounted` 变 false，跳转会被静默吞掉。需要导航时在 `await` 之前取好 `GoRouter.of(context)` 或 `NavigatorState`。
- `const {}` 的运行时类型是 `_ConstMap<dynamic, dynamic>`，`as Map<String, dynamic>` 会抛。解析 JSON 用宽容转换（见 `_stringMap` 的写法）。
- `IntrinsicColumnWidth` 没有 `minWidth` 参数。
- `Text.rich` 渲染的内容 `Text.data` 为 null，测试里用扫描 `RichText.text.toPlainText()` 的 finder（integration test 里的 `richTextContaining`）。

### 路径与文件

- `itemId` 含 `:`（如 `url:sha256:…`），在 Windows 上不是合法路径字符。任何按 itemId 建的目录/文件名都必须走 `LibraryStore.encodePathSegment`。
- 状态文件一律"临时文件 + rename"原子写（`LibraryStore._writeJson`），不要直接覆盖写。
- 离线包解压必须走 `PackageExtractor`（拒绝绝对路径、`..`、符号链接），不要自己写 `extractArchiveToDisk`。
- 仓库行尾由 `.gitattributes`（`* text=auto eol=lf`）固定为 LF。不要把编辑器换行符设成 CRLF，否则 `git status` 会把整仓报成修改（曾出现 4742 行纯行尾假改动）。

### Android / 设备

- **`flutter test integration_test/...` 产出的 APK 不能当应用安装**：它的入口是 `flutter_test_listener.dart`，单独启动会一直停在启动画面等 VM service。手动体验请用 `flutter run` 或 `flutter build apk` 的产物。
- 明文 HTTP 只对 debug 开放（`android/app/src/debug/AndroidManifest.xml` 的 `usesCleartextTraffic`），release 保持 HTTPS 强制，不要把这个属性加进主清单。
- 单元测试里不能用 `path_provider` / `flutter_secure_storage` 等插件；`LibraryStore.open(rootOverride:, cacheOverride:)` 就是为此准备的注入点。
- 用 adb 盲操 UI 不可靠（软键盘遮挡、坐标漂移）。需要程序化验证时写 integration test，不要靠 `adb shell input tap`。

### Git

- 提交走 `git-dated-commit` CLI（`~/.local/bin/git-dated-commit`）：先 `inspect` 再 `plan`，用返回的 `effective_date` 提交；不要手工 `git commit --date` 或自造 Journal。
- 没有 staged 内容时停下来问用户，不要替用户决定暂存范围。
- 不要提交 `build/`、`.dart_tool/` 等产物（`.gitignore` 已覆盖，注意别用 `git add -f`）。

## 5 本地联调

服务端容器只发布在宿主机 `127.0.0.1:18765`，设备要通过端口反向前置访问：

```bash
adb reverse tcp:18765 tcp:18765
```

然后在应用内填写 `http://127.0.0.1:18765` 与令牌（默认 `dev-token`）。调试构建也支持内置配置：

```bash
flutter build apk --debug --dart-define=SERVER_BASE_URL=http://127.0.0.1:18765 --dart-define=SERVER_TOKEN=dev-token
```

已有配置优先，用户改过的不被覆盖。发布构建不要内置令牌。

启动/重建服务端（在 `../knowledge-suite`，WSL 内）：

```bash
source ~/.nvm/nvm.sh
cd /mnt/c/workspace/knowledge/knowledge-suite
make rebuild    # 构建插件 + 重建镜像 + 重启；服务端改动交付前必须执行
```

## 6 验证清单

改完代码按顺序验证，缺一不可：

1. `flutter analyze` —— 必须 `No issues found!`。
2. `flutter test` —— 单元与契约测试全过（含内联语料、内容指纹、解压安全、本地库安装/回收）。
3. 涉及端到端路径（配置、同步、下载、渲染）时：起服务端后跑 `flutter test integration_test/app_test.dart -d <device>`。
4. 涉及服务端契约（端点字段、`contentHash`、包结构）时：在 `knowledge-suite` 里跑服务端测试，并按该仓库 `AGENTS.md` 执行 `make rebuild`。

## 7 数据与清理

- 不要执行 `make clean-store` 或任何删除 `knowledge-store` 的命令，除非用户明确要求。
- 端到端测试要自建 fixture 并**自己清理**（用 `DELETE /api/items/:itemId?mode=purge`），不要把测试数据留在用户的目录里。
- 临时文件不要留在仓库；本环境删除被策略拦截时，把文件移到 `C:\workspace\_trash_knowledge_root\` 并告知用户。
