import CloudKit
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
                claudeOpusWeekly: nil,
                claudeSonnetWeekly: nil,
                codexPrimary: nil,
                codexSecondary: nil,
                planDisplay: nil),
            companion: PhoneCompanionState(
                name: "Pikachu", speciesID: 25, isShiny: false, isEgg: false,
                progress: 0.42, stageText: "Stage 1/3", rarity: "common",
                dexCount: 12, eggProgress: 0, displayState: "working"),
            providers: [
                PhoneProviderSnapshot(id: "claude_code", displayName: "Claude", todayTokens: 1_000_000, todayCost: 10.0),
            ],
            bag: [
                PhoneBagItem(id: "rareCandy", name: "Rare Candy",
                             itemDescription: "Raises your Pokémon's EXP by 100M.",
                             count: 3, isPassive: false, effectHint: "",
                             iconName: "rare-candy", fallbackEmoji: "🍬"),
                PhoneBagItem(id: "shinyCharm", name: "Shiny Charm",
                             itemDescription: "While owned, raises the chance of hatching a shiny.",
                             count: 1, isPassive: true, effectHint: "Shiny rate ↑ · active",
                             iconName: "shiny-charm", fallbackEmoji: "✨"),
            ],
            dex: [
                PhoneDexSpecies(id: 25, name: "Pikachu", rarity: "common", isShiny: false, isRaising: false),
                PhoneDexSpecies(id: 143, name: "Snorlax", rarity: "rare", isShiny: true, isRaising: true),
            ])

        let data = try JSONEncoder().encode(payload)
        let decoded = try JSONDecoder().decode(PhonePayload.self, from: data)
        #expect(decoded.todayTokens == 1_500_000)
        #expect(decoded.companion?.name == "Pikachu")
        #expect(decoded.providers.count == 1)
        #expect(decoded.bag == payload.bag)
        #expect(decoded.dex == payload.dex)
    }

    /// Payloads published by older Macs lack `bag`/`dex` entirely. Decoding must
    /// succeed with empty collections — a decode failure would freeze the iPhone at
    /// its last cached payload until the Mac is updated.
    @Test func payloadDecodesWithoutBagAndDexFields() throws {
        let legacyJSON = """
        {
          "todayTokens": 1000,
          "todayCost": 1.5,
          "weekTokens": 10000,
          "monthTokens": 40000,
          "lastUpdated": 1700000000,
          "serverVersion": "1.0",
          "limits": null,
          "companion": null,
          "providers": []
        }
        """
        let decoded = try JSONDecoder().decode(PhonePayload.self, from: Data(legacyJSON.utf8))
        #expect(decoded.todayTokens == 1000)
        #expect(decoded.bag.isEmpty)
        #expect(decoded.dex.isEmpty)
    }

    // MARK: - CloudKitSync

    private func minimalPayload(todayTokens: Int) -> PhonePayload {
        PhonePayload(
            todayTokens: todayTokens, todayCost: 1.5, weekTokens: 10, monthTokens: 100,
            lastUpdated: Date(timeIntervalSince1970: 1_700_000_000), serverVersion: "1.0",
            limits: nil, companion: nil, providers: [])
    }

    /// The single payload record must round-trip through the json field — the iPhone
    /// decodes exactly this field, so any encoding drift breaks sync silently.
    @Test func recordPayloadRoundTripsThroughJSONField() throws {
        let payload = minimalPayload(todayTokens: 51_917_894)
        let record = try CloudKitSync.makeRecord(payload)

        #expect(record.recordType == CloudKitSync.recordType)
        #expect(record.recordID == CloudKitSync.recordID)
        let json = try #require(record[CloudKitSync.payloadField] as? String)
        let decoded = try JSONDecoder().decode(PhonePayload.self, from: Data(json.utf8))
        #expect(decoded == payload)
        #expect(record[CloudKitSync.updatedField] as? Date != nil)
    }

    /// Save must be an etag-free overwrite (`.allKeys`). The previous fetch-then-insert
    /// implementation turned any transient fetch failure into a permanent
    /// "record to insert already exists" collision (2026-08-20 incident: 21 consecutive
    /// serverRecordChanged failures, iPhone frozen at a stale payload).
    @Test func saveOperationIsForceOverwriteWithoutPrefetch() throws {
        let record = try CloudKitSync.makeRecord(minimalPayload(todayTokens: 1))
        let operation = CloudKitSync.makeSaveOperation(record: record)

        #expect(operation.savePolicy == CKModifyRecordsOperation.RecordSavePolicy.allKeys)
        #expect(operation.recordsToSave?.count == 1)
        #expect(operation.recordIDsToDelete?.isEmpty == true)
    }
}
