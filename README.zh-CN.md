# StockFloat

[English](README.md)

一个 macOS 置顶悬浮小窗，实时显示你关注的股票的价格和涨跌幅。它停在屏幕右上角，在所有桌面和全屏应用上都可见，并且不会抢走键盘焦点。

- 支持美股、港股、A 股
- 接入长桥后，每只美股多一行显示盘前、盘后、夜盘价格
- 中英文界面
- 没有 Dock 图标，也没有菜单栏图标，所有操作都在小窗的右键菜单里

## 安装

需要 macOS 14 或更高版本。安装包同时支持 Apple 芯片和 Intel 芯片的 Mac。

1. 在 [Releases](../../releases) 页面下载 `StockFloat-<版本号>.zip`。
2. 解压，把 `StockFloat.app` 拖进「应用程序」文件夹。
3. 打开它。第一次打开请看下一节。

### 首次打开

StockFloat 没有经过 Apple 公证，所以第一次打开时会被 macOS 拦截。放行方法：

1. 打开一次 StockFloat，关掉弹出的警告。
2. 打开**系统设置 → 隐私与安全性**，滚动到**安全性**，在 StockFloat 那条提示旁点**仍要打开**。

或者在终端里去掉下载标记：

```sh
xattr -dr com.apple.quarantine /Applications/StockFloat.app
```

每次下载只需要做一次。

## 使用

右键小窗打开菜单：

- **设置…**：编辑标的列表和数据源。
- **绿涨红跌** / **红涨绿跌**：设置涨跌配色。
- **鼠标穿透**：点击会穿过小窗；按住 ⌥ 可以临时操作它。
- **开机启动**
- **语言**：在跟随系统、中文、English 之间切换。

拖动小窗可以移动位置，位置会被记住。

### 标的格式

在设置里每行写一个：

| 市场 | 格式 | 示例 |
| --- | --- | --- |
| 美股 | 股票代码 | `AAPL` |
| 港股 | `hk` 加 5 位数字 | `hk00700` |
| 沪市 | `sh` 加 6 位数字 | `sh600519` |
| 深市 | `sz` 加 6 位数字 | `sz000001` |

配置保存在 `~/.config/stock-float/config.json`。

## 数据源

| 数据源 | 市场 | 需要准备 | 实时性 |
| --- | --- | --- | --- |
| 腾讯（默认） | 美股、港股、A 股 | 无 | 美股约 20 秒一次快照 |
| 长桥 | 美股 | 长桥账户和它的 CLI | 逐笔推送，含盘前、盘后、夜盘 |
| Finnhub | 美股 | 免费的 API key | 逐笔推送，常规时段 |

腾讯的接口是非官方的，可能随时变动。

### 长桥

```sh
brew install --cask longbridge/tap/longbridge-terminal
longbridge auth login
```

然后在设置里打开**美股使用长桥行情**。账户需要有 US LV1 (OpenAPI) 行情权限。StockFloat 在后台运行 `longbridge serve`，自己不保存任何长桥凭证。

### Finnhub

把 [finnhub.io](https://finnhub.io) 的 key 填进设置。长桥开关关闭时，美股行情会用它。

## 从源码构建

需要 Xcode 16 或更高版本。

```sh
swift test
./scripts/bundle.sh             # 为本机构建 build/StockFloat.app
./scripts/bundle.sh --universal # 同时支持 Apple 芯片和 Intel
```

发布新版本（需要 GitHub CLI）：

```sh
./scripts/release.sh 0.1.0
```

## 免责声明

价格来自第三方数据源，可能有延迟或错误。本项目不构成任何投资建议。
