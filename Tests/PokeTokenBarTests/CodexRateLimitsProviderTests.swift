import XCTest
@testable import PokeTokenBar

final class CodexRateLimitsProviderTests: XCTestCase {
    private let nestedChatGPTBinary =
        "/Applications/ChatGPT.app/Contents/Resources/codex-cli/CodexCLI.app/Contents/MacOS/codex"
    private let legacyChatGPTBinary = "/Applications/ChatGPT.app/Contents/Resources/codex"

    func testDefaultCandidatesSupportCurrentAndLegacyChatGPTBundles() {
        // Use the production defaults: injected fake CLI paths missed this packaging change.
        let candidates = CodexRateLimitsProvider().binaryCandidates
        XCTAssertTrue(candidates.contains(nestedChatGPTBinary))
        XCTAssertTrue(candidates.contains(legacyChatGPTBinary))
    }

    func testDedicatedInstallsPrecedeBothChatGPTBundleLayouts() throws {
        let candidates = CodexRateLimitsProvider().binaryCandidates
        for bundledBinary in [nestedChatGPTBinary, legacyChatGPTBinary] {
            let bundledIndex = try XCTUnwrap(candidates.firstIndex(of: bundledBinary))
            for dedicatedBinary in [
                "/Applications/Codex.app/Contents/Resources/codex",
                "\(FileManager.default.homeDirectoryForCurrentUser.path)/.codex/bin/codex",
                "/opt/homebrew/bin/codex",
                "/usr/local/bin/codex",
            ] {
                let dedicatedIndex = try XCTUnwrap(candidates.firstIndex(of: dedicatedBinary))
                XCTAssertLessThan(dedicatedIndex, bundledIndex)
            }
        }
    }
}
