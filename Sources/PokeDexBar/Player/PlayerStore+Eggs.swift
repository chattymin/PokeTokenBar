import Foundation

/// 알 뽑기. 종 추첨은 여기서 하지 않는다 — 후보(베이스 인덱스)를 받아오는 일이 네트워크라서
/// 호출부가 굴리고, 스토어는 그 결과로 값을 치르고 슬롯을 채운다.
extension PlayerStore {
    var freeSlots: Int { max(0, state.slots - state.eggs.count) }

    var canDraw: Bool { state.wallet >= EggBalance.drawPrice && freeSlots > 0 }

    /// 등급과 이로치 여부를 굴린다. 주입한 rng 를 쓰므로 시드가 같으면 결과도 같다.
    func rollGradeAndShiny() -> (grade: Grade, shiny: Bool) {
        let gradeRoll = Double(nextRandomUnit())
        let shinyRoll = Double(nextRandomUnit())
        return (EggBalance.rollGrade(gradeRoll),
                EggBalance.rollShiny(shinyRoll, hasCharm: state.ownsShinyCharm))
    }

    /// 값을 치르고 알을 슬롯에 넣는다. 재화가 모자라거나 빈 슬롯이 없으면 아무것도 하지 않고 nil.
    @discardableResult
    func startEgg(grade: Grade, speciesID: Int, shiny: Bool) -> Egg? {
        guard canDraw else { return nil }
        let started = currentDate()
        // 알을 빨리 깨우는 아이를 이미 데리고 있으면 처음부터 절반으로 시작한다.
        let full = EggBalance.duration(grade)
        let span = HatchSpeedup.present(in: state.box) ? full * HatchSpeedup.multiplier : full
        let egg = Egg(grade: grade, speciesID: speciesID, shiny: shiny,
                      startedAt: started, hatchesAt: started.addingTimeInterval(span))
        mutate {
            $0.spentTokens += EggBalance.drawPrice
            $0.eggs.append(egg)
        }
        return egg
    }
}
