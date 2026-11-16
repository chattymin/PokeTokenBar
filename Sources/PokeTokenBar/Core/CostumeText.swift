import Foundation

/// The costumed Pokémon (`CostumeCatalog`): each month's event, the Costume Egg, the collection.
extension L {
    /// The event whose costumes come back that month.
    func costumeEventName(_ month: Int) -> String {
        switch month {
        case 1: t("새해", "New Year", "お正月", "Año Nuevo", "Nouvel An", "Ano-Novo", "Neujahr", "Новый год")
        case 2: t("밸런타인과 GO 투어", "Valentine's and GO Tour", "バレンタインとGOツアー", "San Valentín y GO Tour",
                  "Saint-Valentin et GO Tour", "Dia dos Namorados e GO Tour", "Valentinstag und GO Tour",
                  "День святого Валентина и GO Tour")
        case 3: t("파이 데이와 봄", "Pi Day and spring", "円周率の日と春", "Día de Pi y primavera", "Pi Day et printemps",
                  "Dia do Pi e primavera", "Pi-Tag und Frühling", "День числа пи и весна")
        case 4: t("부활절", "Easter", "イースター", "Pascua", "Pâques", "Páscoa", "Ostern", "Пасха")
        case 5: t("꽃피는 봄", "Spring in bloom", "花ざかりの春", "Primavera en flor", "Printemps en fleurs",
                  "Primavera florida", "Frühling in Blüte", "Цветущая весна")
        case 6: t("GO 페스트", "GO Fest", "GO Fest", "GO Fest", "GO Fest", "GO Fest", "GO Fest", "GO Fest")
        case 7: t("기념일", "Anniversary", "アニバーサリー", "Aniversario", "Anniversaire", "Aniversário", "Jubiläum",
                  "Годовщина")
        case 8: t("여름", "Summer", "夏", "Verano", "Été", "Verão", "Sommer", "Лето")
        case 9: t("패션 위크", "Fashion Week", "ファッションウィーク", "Semana de la Moda", "Semaine de la mode",
                  "Semana de Moda", "Modewoche", "Неделя моды")
        case 10: t("핼러윈", "Halloween", "ハロウィン", "Halloween", "Halloween", "Halloween", "Halloween", "Хэллоуин")
        case 11: t("가을 축제", "Autumn Festival", "秋のおまつり", "Festival de otoño", "Festival d'automne",
                   "Festival de outono", "Herbstfest", "Осенний фестиваль")
        default: t("겨울 축제", "Winter Holidays", "冬のおまつり", "Fiestas de invierno", "Fêtes d'hiver",
                   "Festas de inverno", "Winterfest", "Зимние праздники")
        }
    }

    /// The egg's name, its event's month told.
    func costumeEggName(_ month: Int) -> String {
        let event = costumeEventName(month)
        return t("코스튬 알 · \(event)", "Costume Egg · \(event)", "コスチュームのタマゴ・\(event)",
                 "Huevo disfrazado · \(event)", "Œuf costumé · \(event)", "Ovo fantasiado · \(event)",
                 "Kostüm-Ei · \(event)", "Костюмное яйцо · \(event)")
    }

    var costumeEggEarnedTitle: String {
        t("코스튬 알!", "A Costume Egg!", "コスチュームのタマゴ！", "¡Un huevo disfrazado!", "Un Œuf costumé !",
          "Um ovo fantasiado!", "Ein Kostüm-Ei!", "Костюмное яйцо!")
    }

    func costumeEggEarnedBody(event: String, count: Int) -> String {
        count > 1
            ? t("\(event) 코스튬 알 \(count)개가 가방에 들어왔어요.", "\(count) \(event) Costume Eggs are in your Bag.",
                "\(event)のコスチュームのタマゴが\(count)こ、バッグに入りました。",
                "\(count) huevos disfrazados de \(event) están en tu Bolsa.",
                "\(count) Œufs costumés \(event) sont dans ton Sac.", "\(count) ovos fantasiados de \(event) estão na sua Bolsa.",
                "\(count) Kostüm-Eier (\(event)) sind in deinem Beutel.", "\(count) костюмных яиц (\(event)) в твоей сумке.")
            : t("\(event) 코스튬 알이 가방에 들어왔어요.", "A \(event) Costume Egg is in your Bag.",
                "\(event)のコスチュームのタマゴがバッグに入りました。", "Un huevo disfrazado de \(event) está en tu Bolsa.",
                "Un Œuf costumé \(event) est dans ton Sac.", "Um ovo fantasiado de \(event) está na sua Bolsa.",
                "Ein Kostüm-Ei (\(event)) ist in deinem Beutel.", "Костюмное яйцо (\(event)) в твоей сумке.")
    }

    var costumesTitle: String {
        t("코스튬", "Costumes", "コスチューム", "Disfraces", "Costumés", "Fantasias", "Kostüme", "Костюмы")
    }
    var costumesButtonHint: String {
        t("코스튬 포켓몬: 달마다 돌아오는 컬렉션", "Costumed Pokémon: a collection coming back each month",
          "コスチュームのポケモン：毎月もどってくるコレクション", "Pokémon disfrazados: una colección que vuelve cada mes",
          "Pokémon costumés : une collection qui revient chaque mois", "Pokémon fantasiados: uma coleção que volta todo mês",
          "Kostümierte Pokémon: eine Sammlung, die jeden Monat zurückkommt",
          "Покемоны в костюмах: коллекция, которая возвращается каждый месяц")
    }
    var costumeNowBadge: String { t("이번 달", "This month", "今月", "Este mes", "Ce mois-ci", "Este mês", "Diesen Monat", "В этом месяце") }
    func costumeEventNow(_ event: String) -> String {
        t("이번 달 이벤트: \(event)", "This month's event: \(event)", "今月のイベント：\(event)", "Evento del mes: \(event)",
          "Événement du mois : \(event)", "Evento do mês: \(event)", "Event des Monats: \(event)", "Событие месяца: \(event)")
    }
    func costumeEggRule(_ rate: String) -> String {
        t("토큰 \(rate)마다 이번 달 코스튬 알 1개, 아직 없는 코스튬부터.",
          "A Costume Egg of this month every \(rate) tokens, the costumes you lack first.",
          "トークン\(rate)ごとに今月のコスチュームのタマゴを1こ。まだないコスチュームから。",
          "Un huevo disfrazado del mes cada \(rate) tokens, primero los disfraces que te faltan.",
          "Un Œuf costumé du mois tous les \(rate) tokens, d'abord les costumes qui te manquent.",
          "Um ovo fantasiado do mês a cada \(rate) tokens, primeiro as fantasias que faltam.",
          "Alle \(rate) Tokens ein Kostüm-Ei des Monats, zuerst die Kostüme, die dir fehlen.",
          "Каждые \(rate) токенов: костюмное яйцо месяца, сначала те костюмы, которых нет.")
    }
    func costumeEggNext(_ left: String) -> String {
        t("다음 알까지 \(left)", "\(left) to the next egg", "つぎのタマゴまで\(left)", "\(left) para el próximo huevo",
          "\(left) avant le prochain œuf", "\(left) para o próximo ovo", "\(left) bis zum nächsten Ei", "\(left) до следующего яйца")
    }
    /// The month's name in the app's language, capitalized.
    func monthName(_ month: Int) -> String {
        let formatter = DateFormatter()
        formatter.locale = lang.displayLocale
        let names = formatter.standaloneMonthSymbols ?? []
        guard names.indices.contains(month - 1) else { return String(month) }
        return names[month - 1].capitalized(with: lang.displayLocale)
    }

    var activeNewCostumeBadge: String {
        t("새 코스튬", "New costume", "新しいコスチューム", "Disfraz nuevo", "Nouveau costume", "Fantasia nova", "Neues Kostüm",
          "Новый костюм")
    }
    var activeNewCostumeHint: String {
        t("이 코스튬은 아직 코스튬 컬렉션에 없어요.", "This costume is not in your costume collection yet.",
          "このコスチュームはまだコスチュームのコレクションにありません。", "Este disfraz aún no está en tu colección de disfraces.",
          "Ce costume n'est pas encore dans ta collection costumée.", "Esta fantasia ainda não está na sua coleção de fantasias.",
          "Dieses Kostüm ist noch nicht in deiner Kostümsammlung.", "Этого костюма ещё нет в твоей коллекции костюмов.")
    }

    /// A Costume Medal's step: how many costumed Pokémon it asks for, or all of them.
    func costumeMedalStep(_ step: Int) -> String {
        let n = CostumeMedals.steps[max(0, min(step, CostumeMedals.steps.count) - 1)]
        if step >= CostumeMedals.steps.count {
            return t("전부 (\(n))", "All of them (\(n))", "すべて（\(n)）", "Todos (\(n))", "Tous (\(n))", "Todos (\(n))",
                     "Alle (\(n))", "Все (\(n))")
        }
        return t("코스튬 \(n)마리", "\(n) costumed", "コスチューム\(n)", "\(n) disfrazados", "\(n) costumés", "\(n) fantasiados",
                 "\(n) kostümiert", "В костюмах: \(n)")
    }
    /// A Seasons Medal's step: how many monthly lots it asks complete.
    func costumeLotsMedalStep(_ step: Int) -> String {
        t("묶음 \(step)개 완성", step == 1 ? "1 lot complete" : "\(step) lots complete", "\(step)か月ぶん完成",
          step == 1 ? "1 lote completo" : "\(step) lotes completos", step == 1 ? "1 lot complet" : "\(step) lots complets",
          step == 1 ? "1 lote completo" : "\(step) lotes completos", "\(step) vollständig", "Полных наборов: \(step)")
    }
    /// The costumed Pokémon collected, of all, and the lots complete, on the medals' cards.
    func costumesCollected(_ owned: Int, of total: Int) -> String {
        t("코스튬 \(owned)/\(total)", "\(owned)/\(total) costumed", "コスチューム \(owned)/\(total)", "\(owned)/\(total) disfrazados",
          "\(owned)/\(total) costumés", "\(owned)/\(total) fantasiados", "\(owned)/\(total) kostümiert", "В костюмах: \(owned)/\(total)")
    }
    func costumeLotsComplete(_ done: Int) -> String {
        t("완성한 묶음 \(done)/12", "\(done)/12 lots complete", "完成した月 \(done)/12", "\(done)/12 lotes completos",
          "\(done)/12 lots complets", "\(done)/12 lotes completos", "\(done)/12 vollständig", "Полных наборов: \(done)/12")
    }
}
