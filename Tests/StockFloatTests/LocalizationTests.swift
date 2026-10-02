import Testing

@testable import StockFloat

@Test(arguments: [
  (LanguageSetting.system, ["zh-Hans-CN", "en-CN"], Language.zh),
  (.system, ["en-CN", "zh-Hans-CN"], .en),
  (.system, ["ja-JP"], .en),
  (.system, [], .en),
  (.zh, ["en-CN"], .zh),
  (.en, ["zh-Hans-CN"], .en),
])
func resolvesTheLanguage(setting: LanguageSetting, preferred: [String], language: Language) {
  #expect(setting.resolved(preferred: preferred) == language)
}

@Test func wordsOutagesInBothLanguages() {
  let zh = Strings(language: .zh)
  let en = Strings(language: .en)

  #expect(zh.outage(.unreachable) == "连接中断，价格可能已过期")
  #expect(en.outage(.unreachable) == "Disconnected. Prices may be stale.")
  #expect(zh.outage(.longbridgeMissing) == "未找到 longbridge 命令，请先安装长桥 CLI")
  #expect(en.outage(.longbridgeMissing) == "longbridge command not found. Install the Longbridge CLI.")
  #expect(zh.outage(.longbridgeLoggedOut) == "长桥未登录，请在终端运行 longbridge auth login")
  #expect(en.outage(.longbridgeLoggedOut) == "Not logged in to Longbridge. Run longbridge auth login in a terminal.")
  // The CLI's own message is passed through untranslated.
  #expect(zh.outage(.longbridge("no quote access")) == "长桥：no quote access")
  #expect(en.outage(.longbridge("no quote access")) == "Longbridge: no quote access")
}

@Test func namesEachLanguageInItself() {
  for strings in [Strings(language: .zh), Strings(language: .en)] {
    #expect(strings.name(of: .zh) == "中文")
    #expect(strings.name(of: .en) == "English")
  }
  #expect(Strings(language: .zh).name(of: .system) == "跟随系统")
  #expect(Strings(language: .en).name(of: .system) == "System")
}

@Test func listsUnrecognizedSymbolsWithTheLanguagesSeparator() {
  #expect(Strings(language: .zh).unrecognized(["a b", "苹果"]) == "无法识别：a b、苹果")
  #expect(Strings(language: .en).unrecognized(["a b", "苹果"]) == "Not recognized: a b, 苹果")
}

@Test func namesTheAppearanceChoices() {
  let zh = Strings(language: .zh)
  let en = Strings(language: .en)

  #expect(Config.UpColor.allCases.map(zh.name(of:)) == ["绿涨红跌", "红涨绿跌", "不着色"])
  #expect(Config.UpColor.allCases.map(en.name(of:)) == ["Green up, red down", "Red up, green down", "No color"])
  #expect(Config.TextSize.allCases.map(zh.name(of:)) == ["小", "中", "大"])
  #expect(Config.TextSize.allCases.map(en.name(of:)) == ["Small", "Medium", "Large"])
}
