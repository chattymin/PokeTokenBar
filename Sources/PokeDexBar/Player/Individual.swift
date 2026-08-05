import Foundation

/// 보유 개체 하나. 종(speciesID)이 아니라 개체가 단위다 — 같은 종을 여러 마리 가질 수 있고
/// 각자 이로치·성격·경험치·진화 단계가 따로 간다.
struct Individual: Identifiable, Codable, Sendable, Equatable {
    var id = UUID()
    /// 처음 만난 형태(스타터로 고르거나 부화한 종). 진화해도 바뀌지 않는다.
    var baseID: Int
    /// 지금 형태.
    var speciesID: Int
    /// 실제로 지나온 경로(baseID 로 시작). 분기 진화에서 어느 쪽으로 갔는지 남는다.
    var pathIDs: [Int]
    var shiny = false
    var nature: PokemonNature
    /// 현재 단계에서 쌓은 경험치. 진화하면 0으로 돌아가고 초과분만 이월한다.
    var exp = 0
    var obtainedAt: Date
    var grade: Grade

    /// 몇 번째 형태인가(0 = 아직 안 진화). 경로가 비어도 음수로 새지 않는다.
    var stageIndex: Int { max(0, pathIDs.count - 1) }
}
