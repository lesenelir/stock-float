import Foundation
import Testing

@testable import StockFloat

// Trimmed from live responses captured on 2026-10-02.
private let fixture = """
  v_usAAPL="200~苹果~AAPL.OQ~333.27~330.32~333.26~15844548~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~0~~2026-10-02 12:49:20~2.95~0.89~334.54~330.61~USD";
  v_r_hk00700="100~腾讯控股~00700~421.200~431.000~422.000~19108045.0~0~0~421.200~0~0~0~0~0~0~0~0~0~421.200~0~0~0~0~0~0~0~0~0~19108045.0~2026/10/02 16:08:10~-9.800~-2.27~425.000~419.800";
  v_sh600519="1~贵州茅台~600519~1258.62~1235.58~1239.53~38331~21633~16698~1258.62~14~1258.44~1~1258.16~1~1258.05~2~1258.00~41~1258.65~2~1258.66~3~1258.68~1~1258.69~2~1258.75~80~~20260930161458~23.04~1.86";
  v_pv_none_match="1";
  v_usHALT="200~停牌~HALT.N~0.00~12.50~0.00";
  """

@Test func parsesEveryMarket() {
  let quotes = TencentProvider.parse(fixture)

  #expect(
    quotes == [
      // Each time is local to its market: 12:49:20 New York, 16:08:10 Hong Kong, 16:14:58 Shanghai.
      Quote(
        symbol: "usAAPL", name: "苹果", price: 333.27, prevClose: 330.32,
        time: Date(timeIntervalSince1970: 1_790_959_760)),
      Quote(
        symbol: "hk00700", name: "腾讯控股", price: 421.2, prevClose: 431,
        time: Date(timeIntervalSince1970: 1_790_928_490)),
      Quote(
        symbol: "sh600519", name: "贵州茅台", price: 1258.62, prevClose: 1235.58,
        time: Date(timeIntervalSince1970: 1_790_756_098)),
    ])
}

@Test func unreadableTimesAreLeftOut() {
  #expect(TencentProvider.time("", in: .us) == nil)
  #expect(TencentProvider.time("2026-10-02", in: .us) == nil)
  #expect(TencentProvider.parse("v_usAAPL=\"200~苹果~AAPL.OQ~333.27~330.32\";").first?.time == nil)
}

@Test func changePercentMatchesTheFeed() throws {
  let apple = try #require(TencentProvider.parse(fixture).first)

  #expect(String(format: "%+.2f%%", apple.changePercent) == "+0.89%")
}

@Test func requestsRealTimeHongKongQuotes() throws {
  let symbols = try ["usAAPL", "hk00700", "sz000001"].map { try #require(StockSymbol(id: $0)) }

  #expect(TencentProvider.url(for: symbols)?.absoluteString == "https://qt.gtimg.cn/q=usAAPL,r_hk00700,sz000001")
}

@Test func ignoresGarbage() {
  #expect(TencentProvider.parse("").isEmpty)
  #expect(TencentProvider.parse("<html>502</html>").isEmpty)
  #expect(TencentProvider.parse("v_usAAPL=\"200~苹果\";").isEmpty)
}
