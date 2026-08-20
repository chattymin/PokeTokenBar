import Foundation
import Testing
@testable import PokeTokenBarShared

struct PhonePayloadTests {
    @Test func compactTokenFormatting() {
        #expect(TokenFormatter.compact(0) == "0")
        #expect(TokenFormatter.compact(999) == "999")
        #expect(TokenFormatter.compact(1_000) == "1K")
        #expect(TokenFormatter.compact(12_345) == "12.3K")
        #expect(TokenFormatter.compact(190_612_940) == "190.6M")
        #expect(TokenFormatter.compact(1_240_000_000) == "1.24B")
    }

    @Test func costFormatting() {
        #expect(TokenFormatter.cost(9.50) == "$9.50")
        #expect(TokenFormatter.costCompact(9.5) == "$9.5")
        #expect(TokenFormatter.costCompact(311) == "$311")
        #expect(TokenFormatter.costCompact(12_400) == "$12.4K")
    }

    @Test func percentFormatting() {
        #expect(TokenFormatter.percent(84.0) == "84%")
        #expect(TokenFormatter.percent(84.5) == "84.5%")
    }

    @Test func payloadCodableRoundTrip() throws {
        let payload = PhonePayload(
            todayTokens: 1_500_000,
            todayCost: 12.34,
            weekTokens: 10_000_000,
            monthTokens: 40_000_000,
            lastUpdated: Date(timeIntervalSince1970: 1700000000),
            serverVersion: "1.0",
            limits: PhoneLimitStatus(
                claude5h: PhoneLimitWindow(label: "5h", utilization: 65.0, resetsAt: nil),
                claudeWeekly: nil,
                codexPrimary: nil),
            companion: PhoneCompanionState(
                name: "Pikachu", speciesID: 25, isShiny: false, isEgg: false,
                progress: 0.42, stageText: "Stage 1/3", rarity: "common",
                dexCount: 12, eggProgress: 0, displayState: "working"),
            providers: [
                PhoneProviderSnapshot(id: "claude_code", displayName: "Claude", todayTokens: 1_000_000, todayCost: 10.0),
            ])

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PhonePayload.self, from: data)
        #expect(decoded.todayTokens == 1_500_000)
        #expect(decoded.companion?.name == "Pikachu")
        #expect(decoded.providers.count == 1)
    }
}
