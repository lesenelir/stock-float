<p align="center"><img src="docs/icon.png" width="128" alt="StockFloat"></p>

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

### Updates

StockFloat checks GitHub for a new release once a day. When one is out, the panel says so and the menu offers **Update to x.y.z**, which downloads it, replaces the app and relaunches it. Updates installed this way need no second approval. If the app cannot replace itself, for example when your account cannot write to Applications, the menu item opens the release page instead.

## Use

StockFloat shows a line-chart icon in the menu bar and, by default, an icon in the Dock. Click either, or right-click the panel, for the menu:

- **Settings…** edits the watch list and data sources.
- **Hide Panel** / **Show Panel**. Press **⌃⌥S** in any app to do the same; clicking the Dock icon or opening StockFloat again also brings a hidden panel back.
- **Appearance** sets the colors (green up, red up, or no color), the text size and the opacity.
- **Language** switches between System, 中文 and English.
- **Click-through** lets clicks pass through the panel; hold ⌥ to interact with it again.
- **Show in Dock** turns the Dock icon off or on; the menu bar icon stays either way.
- **Launch at login**

Drag the panel to move it; the position is remembered.

For US stocks, a second line appears outside the regular session: a sun icon for pre-market, a sunset for post-market and a moon for the overnight session, followed by that session's price and its change against the regular close.

A row fades when its price has not updated for 30 minutes, which is what a closed market, a lunch break or a lost connection all look like.

### Symbols

One per line in Settings:

| Market | Format | Example |
| --- | --- | --- |
| US | the ticker | `AAPL` |
| Hong Kong | `hk` + 5 digits | `hk00700` |
| Shanghai | `sh` + 6 digits | `sh600519` |
| Shenzhen | `sz` + 6 digits | `sz000001` |

Settings are stored in `~/.config/stock-float/config.json`. To change the shortcut, edit `hotkey` there (for example `"cmd+shift+9"`, or `""` for none) and restart the app.

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

The icon is built from `Resources/icon-source.png` by `scripts/make-icon.swift`; rerun it after changing the artwork.

To publish a release, tag a version; GitHub Actions builds the universal app and attaches it to the release:

```sh
./scripts/release.sh 0.2.0
```

## Disclaimer

Prices come from third-party sources and may be delayed or wrong. Nothing here is investment advice.

## License

[MIT](LICENSE)
