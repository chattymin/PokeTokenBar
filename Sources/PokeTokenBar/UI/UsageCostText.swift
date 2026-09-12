import SwiftUI

@MainActor
struct UsageCostText: View {
    let cost: UsageCost
    let l: L

    var body: some View {
        Text(cost.text(l))
    }
}
