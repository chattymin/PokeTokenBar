import Foundation

extension CompanionStore {
    /// The costumed Pokémon collected (`CostumeEntry.key`), as the Pokédex counts its own: every stage wearing its
    /// costume in the chain of a graduated record, never one sent off nor the one being raised (a friend's report of
    /// 2026-11-16: a "can't evolve" costume counted at its hatch, the Pokémon sent off at once kept it, and Home still
    /// said "New costume"). `shiny`, those of them graduated shiny.
    func ownedCostumeKeys() -> (all: Set<String>, shiny: Set<String>) {
        var all = Set<String>(), shiny = Set<String>()
        for record in state.dex where !record.isReleased {
            guard let code = record.costume else { continue }
            for entry in CostumeCatalog.stages(code: code, chain: record.chainOrder, form: record.form) {
                all.insert(entry.key)
                if record.isShiny { shiny.insert(entry.key) }
            }
        }
        return (all, shiny)
    }

    /// What a Costume Egg's draw leaves out: the costumes collected, and those the Pokémon raised will bring.
    func costumesTaken() -> Set<String> {
        var taken = ownedCostumeKeys().all
        if let mon = state.active, let code = mon.costume {
            taken.formUnion(CostumeCatalog.stages(code: code, chain: mon.plannedPathIDs, form: mon.form).map(\.key))
        }
        return taken
    }

    /// The month whose costumes the eggs earned now hold.
    var costumeMonth: Int { CostumeCatalog.month(ofDay: state.lastDate) ?? LocalUsageReader.gregorianCalendar().component(.month, from: currentDate) }

    /// The tokens still to use before the next Costume Egg.
    var tokensToNextCostumeEgg: Int { CostumeCatalog.tokensPerEgg - state.costumeEggTokens }
}
