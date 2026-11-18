import Foundation

/// The words of the Achievements and Stats screens (#183).
extension L {
    // MARK: Achievements

    /// Said once above the stones, instead of on each stone: what a stone gives and what it asks.
    func achievementsStonesIntro(eggs: Int, pokemon: Int) -> String {
        t("돌마다 그 타입이 확정으로 태어나는 알 \(eggs)개, 하나에 지금 포켓몬 하나와 바꿔요. 그 돌의 포켓몬 \(pokemon)마리를 졸업시키면 받아요.",
          "Each stone: \(eggs) eggs sure to hatch its type, each one for your current Pokémon. Graduate its \(pokemon) Pokémon to earn it.",
          "石ごとに、そのタイプが必ず生まれるタマゴが\(eggs)個。1個ごとにいまのポケモンと引き換えです。その石のポケモン\(pokemon)匹を卒業させると受け取れます。",
          "Cada piedra: \(eggs) huevos que eclosionan seguro su tipo, cada uno a cambio de tu Pokémon actual. Gradúa sus \(pokemon) Pokémon para obtenerla.",
          "Chaque pierre : \(eggs) œufs qui font éclore à coup sûr son type, chacun contre ton Pokémon actuel. Il faut diplômer ses \(pokemon) Pokémon.",
          "Cada pedra: \(eggs) ovos que com certeza chocam o tipo dela, cada um em troca do seu Pokémon atual. Forme os \(pokemon) Pokémon dela para ganhá-la.",
          "Jeder Stein: \(eggs) Eier, aus denen garantiert sein Typ schlüpft, jedes gegen dein aktuelles Pokémon. Verabschiede seine \(pokemon) Pokémon, um ihn zu erhalten.",
          "Каждый камень: \(eggs) яиц, из которых точно вылупится покемон его типа, каждое в обмен на текущего покемона. Выпустите его покемонов (\(pokemon)), чтобы получить его.")
    }

    /// Said once above the badges, instead of on each badge: how a region is claimed and what it gives.
    func achievementsBadgesIntro(_ percent: Double) -> String {
        let step = percentNumber(percent)
        return t("지방마다 그 타입의 포켓몬이 모두 졸업하면 받을 수 있고, 지방 하나마다 그 타입이 약점인 포켓몬이 \(step)% 더 빨리 성장합니다. 지방에 마우스를 올리면 개수가 보여요.",
                 "A region is claimed once all its Pokémon of the type have graduated; each makes Pokémon weak to that type grow \(step)% faster. Hover a region for its count.",
                 "地方ごとに、そのタイプのポケモンがすべて卒業すると受け取れます。1地方ごとに、そのタイプが弱点のポケモンが\(step)%早く育ちます。地方にカーソルを合わせると数が見えます。",
                 "Una región se reclama cuando todos sus Pokémon del tipo están graduados; cada una hace crecer un \(step)% más rápido a los Pokémon débiles a ese tipo. Pasa el cursor por una región para ver su cuenta.",
                 "Une région se récupère quand tous ses Pokémon du type sont diplômés ; chacune fait grandir de \(step) % les Pokémon faibles contre ce type. Survol d'une région : son compte.",
                 "Uma região é resgatada quando todos os Pokémon dela do tipo estão formados; cada uma faz os Pokémon vulneráveis a esse tipo crescerem \(step)% mais rápido. Passe o cursor numa região para ver a contagem.",
                 "Eine Region gibt es, sobald alle ihre Pokémon dieses Typs verabschiedet sind; jede lässt Pokémon mit dieser Schwäche \(step) % schneller wachsen. Fahre über eine Region für ihren Stand.",
                 "Регион можно получить, когда все его покемоны этого типа выпущены; каждый ускоряет рост покемонов, уязвимых к этому типу, на \(step)%. Наведите на регион, чтобы увидеть счёт.")
    }

    // MARK: Stats

    /// The fourth period of the Stats page: everything since install.
    var statsAllTime: String {
        t("전체", "All time", "全期間", "Todo", "Début", "Tudo", "Gesamt", "Всё время")
    }
    /// The bars' tab under a week or a month.
    var statsTabDays: String { t("일별", "Days", "日別", "Días", "Jours", "Dias", "Tage", "Дни") }
    /// The bars' tab under a year, one bar a month.
    var statsTabMonths: String { t("월별", "Months", "月別", "Meses", "Mois", "Meses", "Monate", "Месяцы") }
    /// Where the period's tokens went.
    var statsTabBreakdown: String {
        t("구성", "Breakdown", "内訳", "Reparto", "Répartition", "Divisão", "Aufteilung", "Структура")
    }
}
