import AppKit
import XCTest
@testable import PokeTokenBar

final class AgentURLHandlerTests: XCTestCase {
    /// The app reads the URL out of the GetURL Apple Event itself (not `application(_:open:)`).
    func testGetURLAppleEventCarriesTheAgentURL() throws {
        let appleEvent = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        appleEvent.setParam(NSAppleEventDescriptor(string: "poketokenbar://agent?state=done&message=ok"),
                            forKeyword: AEKeyword(keyDirectObject))
        let url = try XCTUnwrap(AppDelegate.url(fromGetURLEvent: appleEvent))
        XCTAssertEqual(AgentActivityEvent(url: url)?.activity, .done(message: "ok"))

        let empty = NSAppleEventDescriptor(
            eventClass: AEEventClass(kInternetEventClass), eventID: AEEventID(kAEGetURL),
            targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID))
        XCTAssertNil(AppDelegate.url(fromGetURLEvent: empty))
    }
}
