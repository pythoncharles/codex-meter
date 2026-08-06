先关闭旧版本，再启动已经构建好的应用：

```bash
pkill -x CodexMeter 2>/dev/null || true

open /Users/fushan/Desktop/Myself/codex-meter/.build/CodexMeter.app
```

以后代码修改后，只需重新打包：

```bash
cd /Users/fushan/Desktop/Myself/codex-meter

zsh Scripts/build-app.sh
open .build/CodexMeter.app
```

也可以执行：

```bash
open .build
```

然后直接双击 `CodexMeter.app`，或者把它拖到“应用程序”目录，以后像普通 macOS 应用一样启动。

用已经通过编译、签名检查和 `.app` 启动验证。当前是本机临时签名，可在你的 Mac 上运行；若要发给其他人，需要正式开发者签名和公证。