# StockFloat

[中文](README.zh-CN.md)

A small always-on-top panel for macOS that shows live prices and daily change for the stocks you follow. It floats in the top-right corner, stays visible on every desktop and over full-screen apps, and never takes focus.

- US stocks, Hong Kong stocks and A-shares
- A second line per stock for pre-market, post-market and overnight prices (with Longbridge)
- Chinese and English interface
- No Dock icon and no menu bar item; everything is in the panel's right-click menu

## Why

I trade US stocks, and while I'm vibe coding I want to know where the few I hold are trading. I used to check in two ways, and neither worked well:

- **Switching to my broker's app or a web page.** Every look meant leaving the window I was working in.
- **Keeping a quote window open.** It took up screen space, and other windows still covered it.

What I wanted was less than either: the handful of stocks I follow, their price and change, sitting in a corner of the screen where I can see them without clicking anything.

The built-in options did not fit either. The menu bar is tight on a MacBook with a notch, and showing more than one stock there means a dropdown, which is one more click. Desktop widgets refresh every few minutes at best. A terminal window cannot stay above other windows.

So StockFloat is a small panel that floats above everything else and does only this.

## Design choices

- **Always visible, never in the way.** The panel floats over every desktop and full-screen app, never takes keyboard focus, and can let clicks pass straight through it.
- **One glance.** One line per stock: name, price, change. No charts, news or order entry; the broker's app does those better.
- **No pretending to be live.** A price that looks live but is stale is worse than no price. The panel says so when a data source is disconnected, puts pre-market, post-market and overnight prices on their own labelled line, and the table below states how fresh each source is.
- **Small.** It runs all day, so it is native Swift: about 17 MB of memory and a 1.6 MB app.
- **No broker credentials.** The Longbridge login stays in Longbridge's own command-line tool; StockFloat only starts it and reads the quotes.

## Install

Requires macOS 14 or later. The download runs on both Apple silicon and Intel Macs.

1. Download `StockFloat-<version>.zip` from the [Releases](../../releases) page.
2. Unzip it and move `StockFloat.app` to your Applications folder.
3. Open it. See the next section for the first launch.

### First launch

StockFloat is not notarized by Apple, so macOS blocks it the first time you open it. To allow it:

1. Open StockFloat once and dismiss the warning.
2. Open **System Settings → Privacy & Security**, scroll to **Security**, and click **Open Anyway** next to the StockFloat message.

Or remove the download flag in a terminal:

```sh
xattr -dr com.apple.quarantine /Applications/StockFloat.app
```

You only need to do this once per download.

## Use

Right-click the panel for the menu:

- **Settings…** edits the watch list and data sources.
- **Green up, red down** / **Red up, green down** sets the colours.
- **Click-through** lets clicks pass through the panel; hold ⌥ to interact with it again.
- **Launch at login**
- **Language** switches between System, 中文 and English.

Drag the panel to move it; the position is remembered.

### Symbols

One per line in Settings:

| Market | Format | Example |
| --- | --- | --- |
| US | the ticker | `AAPL` |
| Hong Kong | `hk` + 5 digits | `hk00700` |
| Shanghai | `sh` + 6 digits | `sh600519` |
| Shenzhen | `sz` + 6 digits | `sz000001` |

Settings are stored in `~/.config/stock-float/config.json`.

## Data sources

| Source | Markets | Setup | Freshness |
| --- | --- | --- | --- |
| Tencent (default) | US, Hong Kong, A-shares | none | US prices are snapshots about every 20 seconds |
| Longbridge | US | a Longbridge account and its CLI | pushed trade by trade, plus pre-market, post-market and overnight |
| Finnhub | US | a free API key | pushed trade by trade, regular session |

Tencent's endpoint is unofficial and may change without notice.

### Longbridge

```sh
brew install --cask longbridge/tap/longbridge-terminal
longbridge auth login
```

Then turn on **Use Longbridge for US quotes** in Settings. Your account needs the US LV1 (OpenAPI) quote permission. StockFloat runs `longbridge serve` in the background and stores no Longbridge credentials itself.

### Finnhub

Paste a key from [finnhub.io](https://finnhub.io) into Settings. It is used for US quotes when Longbridge is off.

## Build from source

Requires Xcode 16 or later.

```sh
swift test
./scripts/bundle.sh             # build/StockFloat.app for this Mac
./scripts/bundle.sh --universal # Apple silicon and Intel
```

To publish a release, tag a version; GitHub Actions builds the universal app and attaches it to the release:

```sh
./scripts/release.sh 0.2.0
```

## Disclaimer

Prices come from third-party sources and may be delayed or wrong. Nothing here is investment advice.

## License

[MIT](LICENSE)
