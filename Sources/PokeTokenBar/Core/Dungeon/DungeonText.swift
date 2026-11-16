import Foundation

/// The words of the dungeons, in the app's eight languages.
extension L {
    var dungeonItemHint: String {
        t("던전용", "For dungeons", "ダンジョン用", "Para mazmorras", "Pour les donjons", "Para masmorras", "Für Dungeons",
          "Для подземелий")
    }

    /// Prof. Oak's note while a team explores: the Pokémon raised waits. No word on candies (a player, 2026-11-10).
    func oakDungeonPause(_ name: String, _ dungeon: String) -> String {
        t("팀이 \(KoreanParticle.object.attach(to: dungeon)) 탐험하는 동안 \(KoreanParticle.subject.attach(to: name)) 자라지 않아요.",
          "While your team explores \(dungeon), \(name) doesn't grow.",
          "チームが\(dungeon)を探検しているあいだ、\(name)は育ちません。",
          "Mientras tu equipo explora \(dungeon), \(name) no crece.",
          "Tant que ton équipe explore \(dungeon), \(name) ne grandit pas.",
          "Enquanto sua equipe explora \(dungeon), \(name) não cresce.",
          "Solange dein Team \(dungeon) erkundet, wächst \(name) nicht.",
          "Пока команда исследует \"\(dungeon)\", \(name) не растёт.")
    }

    func oakDungeonWait(_ name: String, cost: String) -> String {
        t("탐험하는 동안 \(KoreanParticle.subject.attach(to: name)) 자라지 않아요. 던전은 최대 \(cost)까지 써요.",
          "While the team explores, \(name) doesn't grow: the dungeon takes up to \(cost).",
          "探検のあいだ\(name)は育ちません。ダンジョンは最大\(cost)を使います。",
          "Mientras el equipo explora, \(name) no crece: la mazmorra usa hasta \(cost).",
          "Pendant l'exploration, \(name) ne grandit pas : le donjon prend jusqu'à \(cost).",
          "Enquanto a equipe explora, \(name) não cresce: a masmorra usa até \(cost).",
          "Während das Team erkundet, wächst \(name) nicht: Der Dungeon braucht bis zu \(cost).",
          "Пока команда исследует, \(name) не растёт: подземелье забирает до \(cost).")
    }

    func oakDungeonWaitEgg(cost: String) -> String {
        t("탐험하는 동안 알은 부화하지 않아요. 던전은 최대 \(cost)까지 써요.",
          "While the team explores, your egg doesn't hatch: the dungeon takes up to \(cost).",
          "探検のあいだタマゴはかえりません。ダンジョンは最大\(cost)を使います。",
          "Mientras el equipo explora, tu huevo no eclosiona: la mazmorra usa hasta \(cost).",
          "Pendant l'exploration, ton œuf n'éclot pas : le donjon prend jusqu'à \(cost).",
          "Enquanto a equipe explora, seu ovo não choca: a masmorra usa até \(cost).",
          "Während das Team erkundet, schlüpft dein Ei nicht: Der Dungeon braucht bis zu \(cost).",
          "Пока команда исследует, яйцо не вылупляется: подземелье забирает до \(cost).")
    }

    var oakUseOnReturn: String {
        t("팀이 돌아온 뒤에 쓰세요.", "Use it once your team is back.", "チームが戻ってから使おう。",
          "Se usa cuando vuelva tu equipo.", "À utiliser au retour de ton équipe.", "Use quando sua equipe voltar.",
          "Erst benutzen, wenn dein Team zurück ist.", "Используйте, когда команда вернётся.")
    }

    var oakGiveOnReturn: String {
        t("팀이 돌아온 뒤에 주세요.", "Give them once your team is back.", "チームが戻ってからあげよう。",
          "Dáselos cuando vuelva tu equipo.", "À donner au retour de ton équipe.", "Dê quando sua equipe voltar.",
          "Gib sie, sobald dein Team zurück ist.", "Дайте их, когда команда вернётся.")
    }

    func oakExplore(_ dungeon: String) -> String {
        t("팀을 탐험 보내세요: \(dungeon)", "Send a team to explore: \(dungeon)", "チームを探検に出そう：\(dungeon)",
          "Envía un equipo a explorar: \(dungeon)", "Envoie une équipe explorer : \(dungeon)",
          "Envie uma equipe para explorar: \(dungeon)", "Schick ein Team auf Erkundung: \(dungeon)",
          "Отправьте команду исследовать: \(dungeon)")
    }

    func oakExploreForKey(_ dungeon: String, key: String) -> String {
        t("\(KoreanParticle.object.attach(to: key)) 얻으러 팀을 보내세요: \(dungeon)", "Send a team for a \(key): \(dungeon)",
          "\(key)を取りにチームを出そう：\(dungeon)", "Envía un equipo por una \(key): \(dungeon)",
          "Envoie une équipe chercher une \(key) : \(dungeon)", "Envie uma equipe atrás de uma \(key): \(dungeon)",
          "Schick ein Team los, um einen \(key) zu holen: \(dungeon)",
          "Отправьте команду за предметом \"\(key)\": \(dungeon)")
    }

    var oakDungeonFirstWin: String {
        t("여기서 처음 이기면 전리품이 두 배가 되고, 다른 던전이 열릴 수도 있어요.",
          "A first victory here doubles the loot and may open other dungeons.",
          "ここで初めて勝つと戦利品が2倍になり、ほかのダンジョンが開くこともあります。",
          "Una primera victoria aquí duplica el botín y puede abrir otras mazmorras.",
          "Une première victoire ici double le butin et peut ouvrir d'autres donjons.",
          "Uma primeira vitória aqui dobra o espólio e pode abrir outras masmorras.",
          "Ein erster Sieg hier verdoppelt die Beute und kann weitere Dungeons öffnen.",
          "Первая победа здесь удваивает добычу и может открыть другие подземелья.")
    }

    var oakDungeonChallenge: String {
        t("보스를 쓰러뜨리면 아직 없는 전투 형태를 얻어요.", "Beating its boss wins a battle form you lack.",
          "ボスを倒すと、まだ持っていないバトルのすがたが手に入ります。",
          "Vencer a su jefe te da una forma de combate que te falta.",
          "Battre son boss te donne une forme de combat qui te manque.",
          "Vencer o chefe dá uma forma de batalha que falta para você.",
          "Besiegst du seinen Boss, gewinnst du eine Kampfform, die dir fehlt.",
          "Победа над боссом даст недостающую боевую форму.")
    }

    var oakDungeonBoss: String {
        t("아직 잡지 못한 보스가 있어요. 잡으면 새로운 걸 가져와요.",
          "One of its bosses isn't yours yet: catching it brings you something new.",
          "まだ捕まえていないボスがいます。捕まえると新しいものを連れてきます。",
          "Uno de sus jefes aún no es tuyo: capturarlo te trae algo nuevo.",
          "Un de ses boss n'est pas encore à toi : le capturer t'apporte du nouveau.",
          "Um dos chefes ainda não é seu: capturá-lo traz algo novo.",
          "Einer seiner Bosse gehört dir noch nicht: Ihn zu fangen bringt dir etwas Neues.",
          "Одного из боссов у вас ещё нет: поймав его, вы получите что-то новое.")
    }

    func oakDungeonCoronetDoor(_ coronet: String) -> String {
        t("아직 이 던전에서 잡지 않은 보스가 있어요. 앞선 보스를 모두 각자의 던전에서 잡아야 \(KoreanParticle.subject.attach(to: coronet)) 열려요.",
          "One of its bosses was never caught here: \(coronet) opens once every boss before it is caught in its dungeon.",
          "まだこのダンジョンでつかまえていないボスがいます。それまでのボスをすべてそれぞれのダンジョンでつかまえると\(coronet)が開きます。",
          "Uno de sus jefes nunca fue capturado aquí: el \(coronet) se abre cuando todos los jefes anteriores están capturados en su mazmorra.",
          "Un de ses boss n'a jamais été capturé ici : le \(coronet) s'ouvre quand tous les boss d'avant sont capturés dans leur donjon.",
          "Um dos chefes nunca foi capturado aqui: o \(coronet) abre quando todos os chefes anteriores forem capturados na sua masmorra.",
          "Einen seiner Bosse hast du hier nie gefangen: Der \(coronet) öffnet sich, wenn alle Bosse davor in ihrem Dungeon gefangen sind.",
          "Одного из боссов вы здесь ещё не поймали: \"\(coronet)\" откроется, когда все боссы до неё будут пойманы в своих подземельях.")
    }

    func oakDungeonCoronet(_ hall: String) -> String {
        t("세 보스를 모두 쓰러뜨리면 \(KoreanParticle.subject.attach(to: hall)) 열려요.",
          "Beating its three bosses opens the \(hall).", "3体のボスをすべて倒すと\(hall)が開きます。",
          "Vencer a sus tres jefes abre la \(hall).", "Battre ses trois boss ouvre la \(hall).",
          "Vencer os três chefes abre o \(hall).", "Besiegst du seine drei Bosse, öffnet sich der \(hall).",
          "Победа над тремя боссами откроет \"\(hall)\".")
    }

    func oakDungeonHall(least: String) -> String {
        t("보스가 아직 컬렉션에 없어요. 승률 \(least)부터는 도전할 만해요.",
          "Its boss is missing from your collection: from \(least) of wins, it's worth a try.",
          "ボスがまだコレクションにいません。勝率\(least)からなら挑む価値があります。",
          "Su jefe falta en tu colección: desde un \(least) de victorias, vale la pena intentarlo.",
          "Son boss manque à ta collection : dès \(least) de victoires, l'essai vaut le coup.",
          "O chefe falta na sua coleção: a partir de \(least) de vitórias, vale a tentativa.",
          "Sein Boss fehlt in deiner Sammlung: Ab \(least) Siegchance lohnt sich der Versuch.",
          "Босса ещё нет в коллекции: с шансом победы от \(least) стоит попробовать.")
    }

    func oakDungeonKey(_ dungeon: String, key: String) -> String {
        t("\(dungeon)에 들어가려면 \(KoreanParticle.subject.attach(to: key)) 필요해요. 이 던전에서 얻을 수 있어요.",
          "You need a \(key) for \(dungeon), and this dungeon drops them.",
          "\(dungeon)には\(key)が必要です。このダンジョンで手に入ります。",
          "Necesitas una \(key) para \(dungeon), y esta mazmorra las da.",
          "Il faut une \(key) pour \(dungeon), et ce donjon en rapporte.",
          "Você precisa de uma \(key) para \(dungeon), e esta masmorra as dá.",
          "Für \(dungeon) brauchst du einen \(key), und dieser Dungeon lässt welche fallen.",
          "Для \"\(dungeon)\" нужен предмет \"\(key)\", а здесь его можно добыть.")
    }

    func oakDungeonOdds(_ odds: String) -> String {
        t("자동 편성 팀의 승률은 \(odds)예요.", "The team composed for you wins \(odds) of the time.",
          "おまかせ編成のチームの勝率は\(odds)です。", "El equipo compuesto para ti gana el \(odds) de las veces.",
          "L'équipe composée pour toi gagne dans \(odds) des cas.", "A equipe montada para você vence \(odds) das vezes.",
          "Das für dich zusammengestellte Team gewinnt in \(odds) der Fälle.",
          "Собранная для вас команда побеждает в \(odds) случаев.")
    }

    func oakSetBattleForm(_ form: String, on name: String) -> String {
        t("\(name)에게 \(form)", "\(form) on \(name)", "\(name)に\(form)", "\(form) en \(name)", "\(form) sur \(name)",
          "\(form) em \(name)", "\(form) für \(name)", "\(form): \(name)")
    }

    func oakGiveCapsule(_ item: String, to name: String) -> String {
        t("\(name)에게 \(item)", "\(item) for \(name)", "\(name)に\(item)", "\(item) para \(name)", "\(item) pour \(name)",
          "\(item) para \(name)", "\(item) für \(name)", "\(item): \(name)")
    }

    func oakWhyDungeons(win: String, hall: String, hallName: String, share: String) -> String {
        t("던전은? 자동 편성 팀의 승률이 \(win) 이상일 때 추천해요(\(hallName)에서는 \(hall)). 알이 아직 새로운 형태를 가져올 수 있는 동안에는 던전에 쓰는 토큰을 전체의 \(share) 미만으로 지켜요. 탐험하는 동안에는 아무것도 자라지 않으니까요.",
          "Dungeons? Oak suggests one when the team composed for you wins at least \(win) of the time, \(hall) for the \(hallName). While an egg can still bring a new form, dungeons stay under \(share) of your tokens: nothing grows while a team explores.",
          "ダンジョンは？おまかせ編成のチームの勝率が\(win)以上なら勧めます（\(hallName)は\(hall)）。タマゴがまだ新しいすがたを連れてこられるあいだは、ダンジョンに使うトークンを全体の\(share)未満におさえます。探検中は何も育たないからです。",
          "¿Mazmorras? Oak te propone una cuando el equipo compuesto para ti gana al menos el \(win) de las veces, el \(hall) en la \(hallName). Mientras un huevo aún pueda traer una forma nueva, las mazmorras se quedan por debajo del \(share) de tus tokens: nada crece mientras un equipo explora.",
          "Les donjons ? Chen en propose un quand l'équipe composée pour toi gagne dans au moins \(win) des cas, \(hall) pour la \(hallName). Tant qu'un œuf peut encore t'apporter une forme, les donjons restent sous \(share) de tes tokens : rien ne grandit pendant une exploration.",
          "Masmorras? Carvalho sugere uma quando a equipe montada para você vence pelo menos \(win) das vezes, \(hall) no \(hallName). Enquanto um ovo ainda puder trazer uma forma nova, as masmorras ficam abaixo de \(share) dos seus tokens: nada cresce enquanto uma equipe explora.",
          "Dungeons? Eich schlägt einen vor, wenn das für dich zusammengestellte Team in mindestens \(win) der Fälle gewinnt, \(hall) im \(hallName). Solange ein Ei noch eine neue Form bringen kann, bleiben Dungeons unter \(share) deiner Tokens: Während ein Team erkundet, wächst nichts.",
          "Подземелья? Оук советует подземелье, если собранная для вас команда побеждает хотя бы в \(win) случаев, в \"\(hallName)\" хватит \(hall). Пока яйцо может принести новую форму, на подземелья уходит меньше \(share) токенов: пока команда исследует, ничего не растёт.")
    }

    func oakDungeonPauseEgg(_ dungeon: String) -> String {
        t("팀이 \(KoreanParticle.object.attach(to: dungeon)) 탐험하는 동안 알은 부화하지 않아요.",
          "While your team explores \(dungeon), your egg doesn't hatch.",
          "チームが\(dungeon)を探検しているあいだ、タマゴはかえりません。",
          "Mientras tu equipo explora \(dungeon), tu huevo no eclosiona.",
          "Tant que ton équipe explore \(dungeon), ton œuf n'éclot pas.",
          "Enquanto sua equipe explora \(dungeon), seu ovo não choca.",
          "Solange dein Team \(dungeon) erkundet, schlüpft dein Ei nicht.",
          "Пока команда исследует \"\(dungeon)\", яйцо не вылупляется.")
    }

    var dungeonsTab: String {
        t("던전", "Dungeons", "ダンジョン", "Mazmorras", "Donjons", "Masmorras", "Dungeons", "Подземелья")
    }

    /// The tiers' names (Découverte to Origine).
    func dungeonTierName(_ tier: DungeonTier) -> String {
        switch tier {
        case .t1: t("발견", "Discovery", "はっけん", "Descubrimiento", "Découverte", "Descoberta", "Entdeckung", "Открытие")
        case .t2: t("모험", "Adventure", "ぼうけん", "Aventura", "Aventure", "Aventura", "Abenteuer", "Приключение")
        case .t3: t("숙련", "Expert", "エキスパート", "Experto", "Expert", "Especialista", "Experte", "Эксперт")
        case .t4: t("전설", "Legends", "でんせつ", "Leyendas", "Légendes", "Lendas", "Legenden", "Легенды")
        case .t5: t("기원", "Origin", "はじまり", "Origen", "Origine", "Origem", "Ursprung", "Исток")
        }
    }

    func dungeonRule(_ rule: DungeonRule) -> String {
        switch rule {
        case .noLegendary: t("전설 없음", "No legendary", "でんせつなし", "Ningún legendario", "Aucun légendaire",
                             "Nenhum lendário", "Kein Legendäres", "Без легендарных")
        case .atMostOneLegendary: t("전설 1마리까지", "One legendary at most", "でんせつは1ひきまで", "Un legendario como mucho",
                                    "1 légendaire au plus", "No máximo 1 lendário", "Höchstens ein Legendäres",
                                    "Не больше одного легендарного")
        case .onlyLegendaries: t("전설만", "Legendaries only", "でんせつのみ", "Solo legendarios", "Que des légendaires",
                                 "Só lendários", "Nur Legendäre", "Только легендарные")
        case .onlyStarters: t("스타팅만", "Starters only", "さいしょのポケモンのみ", "Solo iniciales", "Que des starters",
                              "Só iniciais", "Nur Starter", "Только стартовые")
        case .sharedType: t("같은 타입 하나", "One shared type", "共通のタイプ", "Un tipo en común", "Un type en commun",
                            "Um tipo em comum", "Ein gemeinsamer Typ", "Общий тип")
        case .oneRegion: t("한 지방", "One region", "ひとつの地方", "Una sola región", "Une seule région", "Uma só região",
                           "Eine Region", "Один регион")
        case .maxRarity(.common): t("일반만", "Commons only", "コモンのみ", "Solo comunes", "Que des communs", "Só comuns",
                                    "Nur Gewöhnliche", "Только обычные")
        case .maxRarity(let rarity): t("최대 \(rarityLabel(rarity))", "\(rarityLabel(rarity)) at most",
                                       "\(rarityLabel(rarity))まで", "Como mucho \(rarityLabel(rarity))",
                                       "Au plus \(rarityLabel(rarity))", "No máximo \(rarityLabel(rarity))",
                                       "Höchstens \(rarityLabel(rarity))", "Не выше: \(rarityLabel(rarity))")
        case .bannedType(let type): t("\(typeName(type)) 타입 금지", "No \(typeName(type)) type", "\(typeName(type))タイプ禁止",
                                      "Tipo \(typeName(type)) prohibido", "Type \(typeName(type)) interdit",
                                      "Tipo \(typeName(type)) proibido", "Kein Typ \(typeName(type))",
                                      "Тип \(typeName(type)) запрещён")
        case .onlyShinies: t("이로치만", "Shinies only", "色違いのみ", "Solo variocolor", "Que des chromatiques", "Só shiny",
                             "Nur Schillernde", "Только шайни")
        case .shinyOrBattleForm:
            t("이로치 또는 배틀 폼", "Shinies or battle forms", "色違いかバトルフォルム", "Variocolor o formas de combate",
              "Chromatiques ou formes de combat", "Shiny ou formas de batalha", "Schillernde oder Kampfformen",
              "Шайни или боевые формы")
        case .atLeastShinies(let n):
            t("이로치 \(n)마리 이상", "At least \(n) shinies", "色違い\(n)匹以上", "Al menos \(n) variocolor",
              "Au moins \(n) chromatiques", "Pelo menos \(n) shiny", "Mindestens \(n) Schillernde", "Не меньше \(n) шайни")
        case .needsBattleForm(let kinds) where kinds.contains(.gigantamax):
            t("거다이맥스 1마리", "A Gigantamax", "キョダイマックス1匹", "Una Gigamax", "Une Gigamax", "Uma Gigamax",
              "Eine Gigadynamax-Form", "Одна гигантамакс-форма")
        case .needsBattleForm:
            t("메가 또는 원시 1마리", "A Mega or a Primal", "メガかゲンシ1匹", "Una Mega o Primigenia", "Une Méga ou Primo",
              "Uma Mega ou Primitiva", "Eine Mega- oder Protoform", "Одна мега или первичная форма")
        }
    }

    // MARK: My team, a dungeon's page, the type chart (2026-11-05)

    var myTeamTitle: String {
        t("내 팀", "My team", "マイチーム", "Mi equipo", "Mon équipe", "Minha equipe", "Mein Team", "Моя команда")
    }
    var myTeamHint: String {
        t("최대 6마리의 기본 팀이에요. 던전 팀은 여기서 시작해, 그 던전 규칙이 받아들이는 멤버만 데려가요.",
          "Your general team, six at most: a dungeon's team starts from it, with the members its rules admit.",
          "最大6匹の基本チームです。ダンジョンのチームはここから始まり、そのルールが認めるメンバーだけを連れていきます。",
          "Tu equipo general, seis como máximo: el equipo de una mazmorra parte de él, con los miembros que sus reglas admiten.",
          "Ton équipe générale, six au plus : l'équipe d'un donjon part d'elle, avec les membres que ses règles acceptent.",
          "Sua equipe geral, seis no máximo: a equipe de uma masmorra parte dela, com os membros que as regras aceitam.",
          "Dein allgemeines Team, höchstens sechs: Das Team eines Dungeons beginnt damit, mit den Mitgliedern, die seine Regeln zulassen.",
          "Ваша общая команда, не больше шести: команда подземелья начинается с неё, с участниками, которых допускают его правила.")
    }
    var typeChartTitle: String {
        t("타입 상성표", "Type chart", "タイプ相性表", "Tabla de tipos", "Table des types", "Tabela de tipos", "Typentabelle", "Таблица типов")
    }
    var typeChartLegend: String {
        t("행은 공격 타입, 열은 받는 타입이에요. 2: 효과가 굉장함, ½: 효과가 별로, 0: 효과 없음. 타입을 누르면 자세히 보여요.",
          "Rows attack, columns take the hit. 2: super effective, ½: not very effective, 0: no effect. Click a type for its details.",
          "行がこうげきのタイプ、列が受けるタイプです。2：こうかはばつぐん、½：いまひとつ、0：こうかなし。タイプを押すと詳しく出ます。",
          "Las filas atacan, las columnas reciben. 2: superefectivo, ½: poco efectivo, 0: sin efecto. Pulsa un tipo para verlo en detalle.",
          "Les lignes attaquent, les colonnes reçoivent. 2 : super efficace, ½ : peu efficace, 0 : sans effet. Clique un type pour le détail.",
          "As linhas atacam, as colunas recebem. 2: supereficaz, ½: pouco eficaz, 0: sem efeito. Clique num tipo para ver o detalhe.",
          "Zeilen greifen an, Spalten nehmen den Treffer. 2: sehr effektiv, ½: nicht sehr effektiv, 0: keine Wirkung. Klicke einen Typ für Details.",
          "Строки атакуют, столбцы получают удар. 2: суперэффективно, ½: малоэффективно, 0: без эффекта. Нажмите на тип, чтобы увидеть подробности.")
    }
    var typeAttacking: String { t("공격할 때", "Attacking", "こうげきするとき", "Al atacar", "En attaque", "Ao atacar", "Im Angriff", "В атаке") }
    var typeDefending: String { t("받을 때", "Defending", "うけるとき", "Al defender", "En défense", "Ao defender", "In der Abwehr", "В защите") }
    var typeStrongAgainst: String {
        t("효과가 굉장함", "Super effective on", "こうかばつぐん", "Superefectivo contra", "Super efficace contre", "Supereficaz contra",
          "Sehr effektiv gegen", "Суперэффективно против")
    }
    var typeWeakAgainst: String {
        t("효과가 별로", "Not very effective on", "いまひとつ", "Poco efectivo contra", "Peu efficace contre", "Pouco eficaz contra",
          "Nicht sehr effektiv gegen", "Малоэффективно против")
    }
    var typeNoEffectOn: String {
        t("효과 없음", "No effect on", "こうかなし", "Sin efecto en", "Sans effet sur", "Sem efeito em", "Keine Wirkung auf", "Без эффекта на")
    }
    var typeWeakTo: String { t("약점", "Weak to", "よわい", "Débil ante", "Craint", "Fraco contra", "Schwach gegen", "Уязвим к") }
    var typeResists: String { t("반감", "Resists", "いまひとつで受ける", "Resiste", "Résiste à", "Resiste a", "Widersteht", "Устойчив к") }
    var typeImmuneTo: String { t("무효", "Immune to", "こうかがない", "Inmune a", "Immunisé contre", "Imune a", "Immun gegen", "Иммунитет к") }
    var dungeonDetailsButton: String { t("상세", "Details", "詳細", "Detalles", "Détails", "Detalhes", "Details", "Подробнее") }
    var dungeonDetailWild: String {
        t("야생 포켓몬", "Wild Pokémon", "やせいのポケモン", "Pokémon salvajes", "Pokémon sauvages", "Pokémon selvagens", "Wilde Pokémon", "Дикие покемоны")
    }
    func dungeonDetailBosses(met: Int, of total: Int) -> String {
        t("보스: \(total)마리 중 \(met)마리 만남", "Bosses: \(met) met of \(total)", "ボス：\(total)体中\(met)体と出会った",
          "Jefes: \(met) vistos de \(total)", "Boss : \(met) rencontrés sur \(total)", "Chefes: \(met) vistos de \(total)",
          "Bosse: \(met) von \(total) getroffen", "Боссы: встречено \(met) из \(total)")
    }
    var dungeonDetailLoot: String {
        t("전리품과 확률", "Loot and odds", "戦利品と確率", "Botín y probabilidades", "Butin et taux", "Espólio e chances", "Beute und Chancen",
          "Добыча и шансы")
    }
    func dungeonDetailCandies(_ low: Int, _ high: Int) -> String {
        let candy = itemName(.rareCandy)
        return t("\(candy): 탐험마다 \(low)~\(high)개", "\(candy): \(low) to \(high) an expedition", "\(candy)：1回の探検で\(low)〜\(high)個",
                 "\(candy): de \(low) a \(high) por expedición", "\(candy) : \(low) à \(high) par expédition",
                 "\(candy): de \(low) a \(high) por expedição", "\(candy): \(low) bis \(high) pro Expedition",
                 "\"\(candy)\": от \(low) до \(high) за экспедицию")
    }
    var dungeonDetailChestItems: String {
        t("상자 아이템", "Chest items", "宝箱の道具", "Objetos de los cofres", "Objets des coffres", "Itens dos baús", "Truhen-Items", "Предметы в сундуках")
    }
    var dungeonDetailChestEggs: String {
        t("상자 하나의 알", "An egg in a chest", "宝箱のタマゴ", "Huevo por cofre", "Œuf par coffre", "Ovo por baú", "Ei pro Truhe", "Яйцо в сундуке")
    }
    var dungeonDetailVictory: String {
        t("보스를 쓰러뜨리면 추가로", "If the boss falls, also", "ボスを倒すとさらに", "Si cae el jefe, además", "En plus si le boss tombe",
          "Se o chefe cair, também", "Fällt der Boss, zusätzlich", "Если босс падёт, ещё")
    }
    var dungeonDetailFirstVictory: String {
        t("첫 승리: 전리품 두 배와 등급 아이템 하나 추가.", "First victory: the loot doubled and one more item of the tier.",
          "初勝利：戦利品が2倍になり、ランクの道具がもう1つ。", "Primera victoria: botín doble y un objeto más del nivel.",
          "Première victoire : butin doublé et un objet du palier en plus.", "Primeira vitória: espólio em dobro e mais um item do nível.",
          "Erster Sieg: doppelte Beute und ein weiteres Item der Stufe.", "Первая победа: добыча удваивается и ещё один предмет уровня.")
    }
    var dungeonDetailNone: String { t("없음", "None", "なし", "Ninguno", "Aucun", "Nenhum", "Keins", "Нет") }
    var dungeonDetailHistory: String { t("기록", "History", "記録", "Historial", "Historique", "Histórico", "Verlauf", "История") }
    var dungeonDetailNoRun: String {
        t("아직 이곳에서 끝난 탐험이 없어요.", "No expedition has ended here yet.", "ここで終わった探検はまだありません。",
          "Aún no ha terminado ninguna expedición aquí.", "Aucune expédition terminée ici pour l'instant.",
          "Nenhuma expedição terminou aqui ainda.", "Hier ist noch keine Expedition zu Ende gegangen.", "Здесь ещё не закончилась ни одна экспедиция.")
    }
    func dungeonDetailRuns(_ runs: Int, wins: Int) -> String {
        t("탐험 \(runs)회 · 승리 \(wins)회", runs == 1 ? "1 expedition · \(wins) won" : "\(runs) expeditions · \(wins) won",
          "探検\(runs)回・勝利\(wins)回", "\(runs) expediciones · \(wins) ganadas", "\(runs) expéditions · \(wins) gagnées",
          "\(runs) expedições · \(wins) vencidas", "\(runs) Expeditionen · \(wins) gewonnen", "Экспедиций: \(runs) · побед: \(wins)")
    }
    func oddsPercent(_ value: Double) -> String {
        let p = percentNumber(value)
        return t("\(p)%", "\(p)%", "\(p)%", "\(p) %", "\(p) %", "\(p)%", "\(p) %", "\(p)%")
    }

    /// A tier's dungeons by name, as its unlock lists them.
    func tierDungeonNames(_ tier: DungeonTier) -> String {
        DungeonMedals.dungeons(tier).map(dungeonName).joined(separator: ", ")
    }

    func dungeonUnlock(_ unlock: DungeonUnlock) -> String {
        switch unlock {
        case .graduated(let n): t("졸업한 포켓몬 \(n)마리", "\(n) graduated Pokémon", "卒業したポケモン\(n)ひき",
                                  "\(n) Pokémon graduados", "\(n) Pokémon diplômés", "\(n) Pokémon formados",
                                  "\(n) verabschiedete Pokémon", "Выпускников: \(n)")
        case .wonTier(let tier):
            t("T\(tier.rawValue) 던전 하나 클리어", "Finish a T\(tier.rawValue) dungeon", "T\(tier.rawValue)のダンジョンをひとつクリア",
              "Superar una mazmorra T\(tier.rawValue)", "Finir un donjon T\(tier.rawValue)", "Concluir uma masmorra T\(tier.rawValue)",
              "Einen T\(tier.rawValue)-Dungeon abschließen", "Пройти подземелье T\(tier.rawValue)")
        case .wonEvery(let tier):
            t("T\(tier.rawValue) 던전 모두 클리어: \(tierDungeonNames(tier))", "Finish every T\(tier.rawValue) dungeon: \(tierDungeonNames(tier))",
              "T\(tier.rawValue)のダンジョンをすべてクリア：\(tierDungeonNames(tier))",
              "Superar todas las mazmorras T\(tier.rawValue): \(tierDungeonNames(tier))",
              "Finir tous les donjons T\(tier.rawValue) : \(tierDungeonNames(tier))",
              "Concluir todas as masmorras T\(tier.rawValue): \(tierDungeonNames(tier))",
              "Alle T\(tier.rawValue)-Dungeons abschließen: \(tierDungeonNames(tier))",
              "Пройти все подземелья T\(tier.rawValue): \(tierDungeonNames(tier))")
        case .won(let id): t("\(dungeonName(id)) 클리어", "Finish \(dungeonName(id))", "\(dungeonName(id))をクリア",
                             "Superar \(dungeonName(id))", "Finir \(dungeonName(id))", "Concluir \(dungeonName(id))",
                             "\(dungeonName(id)) abschließen", "Пройти: \(dungeonName(id))")
        case .linesGraduated(let n): t("졸업한 계열 \(n)개", "\(n) lines graduated", "卒業した系統\(n)",
                                       "\(n) líneas graduadas", "\(n) lignées diplômées", "\(n) linhas formadas",
                                       "\(n) verabschiedete Linien", "Линий выпущено: \(n)")
        case .legendariesGraduated(let n): t("졸업한 전설 \(n)마리", "\(n) legendaries graduated", "卒業したでんせつ\(n)ひき",
                                             "\(n) legendarios graduados", "\(n) légendaires diplômés",
                                             "\(n) lendários formados", "\(n) verabschiedete Legendäre",
                                             "Легендарных выпущено: \(n)")
        case .beatBosses: t("천관산의 세 보스 쓰러뜨리기", "Beat Mt. Coronet's three bosses", "テンガンざんの3体のボスを倒す",
                            "Vencer a los tres jefes del Monte Corona", "Battre les trois boss du Mont Couronné",
                            "Vencer os três chefes do Monte Coronet", "Die drei Bosse des Kraterbergs besiegen",
                            "Победить трёх боссов горы Коронет")
        case .treasureMap: t("보물지도 1장", "A Treasure Map", "たからのちず1まい", "Un Mapa del Tesoro", "Une Carte au trésor",
                             "Um Mapa do Tesouro", "Eine Schatzkarte", "Карта сокровищ")
        case .caughtBosses(let ids): dungeonCaughtBosses(DungeonCatalog.bosses(of: ids).count)
        }
    }

    func dungeonCaughtBosses(_ n: Int) -> String {
        t("앞선 던전의 보스 \(n)마리를 모두 쓰러뜨리고 잡기", "Beat and catch all \(n) bosses of the dungeons before",
          "これまでのダンジョンのボス\(n)体をすべて倒してつかまえる", "Vencer y capturar a los \(n) jefes de las mazmorras anteriores",
          "Battre et capturer les \(n) boss des donjons précédents", "Vencer e capturar os \(n) chefes das masmorras anteriores",
          "Alle \(n) Bosse der vorigen Dungeons besiegen und fangen", "Победить и поймать всех боссов прежних подземелий: \(n)")
    }

    var dungeonPrepare: String { t("준비", "Prepare", "じゅんび", "Preparar", "Préparer", "Preparar", "Vorbereiten", "Подготовить") }
    var dungeonGoAgain: String { t("다시 출발", "Go again", "もう一度", "Volver", "Repartir", "Ir de novo", "Erneut los", "Снова") }
    var dungeonLocked: String { t("잠김", "Locked", "ロック中", "Bloqueada", "Verrouillé", "Bloqueada", "Gesperrt", "Закрыто") }
    var dungeonNew: String { t("새로움", "New", "NEW", "Nueva", "Nouveau", "Nova", "Neu", "Новое") }
    func dungeonWins(_ n: Int) -> String {
        t("클리어 ×\(n)", "Finished ×\(n)", "クリア ×\(n)", "Superada ×\(n)", "Fini ×\(n)", "Concluída ×\(n)",
          "Geschafft ×\(n)", "Пройдено ×\(n)")
    }
    var dungeonBossUnknown: String {
        t("보스: 아직 못 봄", "Boss: never seen", "ボス：まだ見ていない", "Jefe: nunca visto", "Boss : jamais vu",
          "Chefe: nunca visto", "Boss: nie gesehen", "Босс: не встречен")
    }
    /// The count and the item stay together on a line, never "1 ×" at the end of one and the item on the next.
    func dungeonEntryKeys(_ n: Int, key: String) -> String {
        let key = key.replacingOccurrences(of: " ", with: "\u{00A0}")
        return t("입장: \(key)\u{00A0}\(n)개", "Entry: \(n)\u{00A0}×\u{00A0}\(key)", "入場：\(key)×\(n)",
                 "Entrada: \(n)\u{00A0}×\u{00A0}\(key)", "Entrée : \(n)\u{00A0}×\u{00A0}\(key)",
                 "Entrada: \(n)\u{00A0}×\u{00A0}\(key)", "Eintritt: \(n)\u{00A0}×\u{00A0}\(key)", "Вход: \(key)\u{00A0}×\(n)")
    }
    func dungeonEntryMap(_ map: String) -> String {
        let map = map.replacingOccurrences(of: " ", with: "\u{00A0}")
        return t("입장: \(map) 1장", "Entry: a\u{00A0}\(map)", "入場：\(map)1まい", "Entrada: un\u{00A0}\(map)",
                 "Entrée : une\u{00A0}\(map)", "Entrada: um\u{00A0}\(map)", "Eintritt: eine\u{00A0}\(map)", "Вход: \(map)")
    }
    func dungeonUnderway(_ dungeon: String, floor: Int, floors: Int) -> String {
        t("탐험 중: \(dungeon) · \(floor)/\(floors)층", "Exploring \(dungeon) · floor \(floor) of \(floors)",
          "探検中：\(dungeon)・\(floor)/\(floors)階", "Explorando \(dungeon) · piso \(floor) de \(floors)",
          "En expédition : \(dungeon) · étage \(floor) sur \(floors)", "Explorando \(dungeon) · andar \(floor) de \(floors)",
          "Erkundung: \(dungeon) · Ebene \(floor) von \(floors)", "Экспедиция: \(dungeon) · этаж \(floor) из \(floors)")
    }
    var dungeonSee: String { t("보기", "See", "見る", "Ver", "Voir", "Ver", "Ansehen", "Открыть") }
    var dungeonOneAtATime: String {
        t("탐험은 한 번에 하나", "One expedition at a time", "探検は一度にひとつ", "Una expedición a la vez",
          "Une expédition à la fois", "Uma expedição por vez", "Eine Erkundung auf einmal", "Одна экспедиция за раз")
    }
    func dungeonTeamSize(_ n: Int) -> String {
        t("포켓몬 \(n)마리", "\(n) Pokémon", "ポケモン\(n)ひき", "\(n) Pokémon", "\(n) Pokémon", "\(n) Pokémon",
          "\(n) Pokémon", "\(n) покемонов")
    }

    // MARK: The team screen

    var dungeonComposeForMe: String {
        t("자동 편성", "Compose for me", "おまかせ編成", "Componer por mí", "Composer pour moi", "Montar para mim",
          "Für mich zusammenstellen", "Собрать за меня")
    }
    var dungeonSetOff: String { t("출발", "Set off", "出発", "Partir", "Partir", "Partir", "Aufbrechen", "В путь") }
    /// The team screen (redone 2026-11-06): the winning odds beside the reaching ones, the team's matchup, each
    /// candidate's fit.
    var dungeonWinOdds: String {
        t("던전을 이길 확률", "Odds of winning the dungeon", "ダンジョンをクリアする確率", "Probabilidad de ganar la mazmorra",
          "Chances de réussir le donjon", "Chance de vencer a masmorra", "Chance, den Dungeon zu schaffen",
          "Шанс пройти подземелье")
    }
    var dungeonWinOddsHint: String {
        t("보스는 들어갈 때 정해져요: 나올 수 있는 모든 보스를 합친 확률이에요.",
          "The boss is drawn at the entry: these odds count every boss it may be.",
          "ボスは入るときに決まります：出てくるかもしれないすべてのボスを合わせた確率です。",
          "El jefe se sortea al entrar: esta probabilidad cuenta todos los jefes posibles.",
          "Le boss est tiré à l'entrée : ces chances comptent tous les boss possibles.",
          "O chefe é sorteado na entrada: esta chance conta todos os chefes possíveis.",
          "Der Boss wird beim Betreten gezogen: Diese Chance zählt jeden möglichen Boss.",
          "Босс выбирается при входе: этот шанс учитывает всех возможных боссов.")
    }
    func dungeonTeamHeader(_ count: Int, _ size: Int) -> String {
        t("팀 \(count)/\(size)", "Team \(count)/\(size)", "チーム \(count)/\(size)", "Equipo \(count)/\(size)",
          "Équipe \(count)/\(size)", "Equipe \(count)/\(size)", "Team \(count)/\(size)", "Команда \(count)/\(size)")
    }
    func dungeonVersus(boss: Bool) -> String {
        boss ? t("보스 상대로", "Against the boss", "ボスに対して", "Contra el jefe", "Face au boss", "Contra o chefe",
                 "Gegen den Boss", "Против босса")
            : t("이 던전 상대로", "Against this dungeon", "このダンジョンに対して", "Contra esta mazmorra", "Face au donjon",
                "Contra esta masmorra", "Gegen diesen Dungeon", "Против этого подземелья")
    }
    var dungeonYourHits: String {
        t("팀의 공격", "Your moves", "チームのわざ", "Tus movimientos", "Tes attaques", "Seus golpes", "Deine Attacken",
          "Ваши приёмы")
    }
    var dungeonWeakSpots: String {
        t("약점", "Weak spots", "弱点", "Puntos débiles", "Points faibles", "Pontos fracos", "Schwachstellen", "Слабые места")
    }
    /// Members a type hits twice: "2 weak".
    func dungeonWeakMembers(_ n: Int) -> String {
        t("\(n)마리 약함", n == 1 ? "1 weak" : "\(n) weak", "\(n)匹が弱い", n == 1 ? "1 débil" : "\(n) débiles",
          n == 1 ? "1 faible" : "\(n) faibles", n == 1 ? "1 fraco" : "\(n) fracos", "\(n) schwach",
          "слабых: \(n)")
    }
    var dungeonFitStrong: String {
        t("여기서 강함", "Strong here", "ここで強い", "Fuerte aquí", "Fort ici", "Forte aqui", "Stark hier", "Силён здесь")
    }
    var dungeonFitWeak: String {
        t("여기서 약함", "Weak here", "ここで弱い", "Débil aquí", "Faible ici", "Fraco aqui", "Schwach hier", "Слаб здесь")
    }
    var dungeonFitHint: String {
        t("\"여기서 강함\": 기술이 던전의 타입을 2배로 치고 그 타입에 약하지 않아요. \"여기서 약함\": 그 반대예요.",
          "\"Strong here\": a move hits a dungeon type twice and no dungeon type hits it twice. \"Weak here\": the other way round.",
          "「ここで強い」：わざがダンジョンのタイプに2倍で、そのタイプに弱くありません。「ここで弱い」：その逆です。",
          "\"Fuerte aquí\": un movimiento golpea el doble a un tipo de la mazmorra y ningún tipo de la mazmorra le golpea el doble. \"Débil aquí\": al revés.",
          "\"Fort ici\" : une attaque touche ×2 un type du donjon et aucun type du donjon ne le touche ×2. \"Faible ici\" : l'inverse.",
          "\"Forte aqui\": um golpe acerta em dobro um tipo da masmorra e nenhum tipo da masmorra o acerta em dobro. \"Fraco aqui\": o contrário.",
          "\"Stark hier\": Eine Attacke trifft einen Dungeon-Typ doppelt, und kein Dungeon-Typ trifft es doppelt. \"Schwach hier\": umgekehrt.",
          "\"Силён здесь\": приём бьёт тип подземелья вдвойне, и ни один тип подземелья не бьёт его вдвойне. \"Слаб здесь\": наоборот.")
    }
    var dungeonMemberDone: String {
        t("완료", "Done", "完了", "Listo", "Terminé", "Pronto", "Fertig", "Готово")
    }
    var dungeonComposing: String {
        t("최적의 팀을 시험하는 중…", "Trying the best teams…", "いちばんのチームを試しています…", "Probando los mejores equipos…",
          "Essai des meilleures équipes…", "Testando as melhores equipes…", "Die besten Teams werden getestet…",
          "Проверяю лучшие команды…")
    }
    var dungeonComposeHint: String {
        t("규칙이 허락하는 가장 좋은 팀들을 보스까지 시뮬레이션해 가장 많이 이기는 팀을 골라요.",
          "Runs the best teams the rules allow to the end, the boss included, and keeps the one that wins most.",
          "ルールで組めるいちばんのチームをボスまでシミュレーションし、いちばん勝つチームを選びます。",
          "Simula hasta el final, jefe incluido, los mejores equipos que permiten las reglas y se queda con el que más gana.",
          "Simule jusqu'au bout, boss compris, les meilleures équipes que les règles permettent et garde celle qui gagne le plus.",
          "Simula até o fim, chefe incluído, as melhores equipes que as regras permitem e fica com a que mais vence.",
          "Spielt die besten Teams, die die Regeln erlauben, bis zum Ende samt Boss durch und behält das, das am häufigsten gewinnt.",
          "Прогоняет до конца, с боссом, лучшие команды по правилам и оставляет ту, что побеждает чаще.")
    }

    var dungeonReachOdds: String {
        t("보스까지 갈 확률", "Odds of reaching the boss", "ボスまでたどり着く確率", "Probabilidad de llegar al jefe",
          "Chances d'atteindre le boss", "Chance de chegar ao chefe", "Chance, den Boss zu erreichen",
          "Шанс дойти до босса")
    }
    var dungeonRules: String { t("규칙", "Rules", "ルール", "Reglas", "Règles", "Regras", "Regeln", "Правила") }
    var dungeonCandidates: String {
        t("졸업한 포켓몬", "Graduated Pokémon", "卒業したポケモン", "Pokémon graduados", "Pokémon diplômés", "Pokémon formados",
          "Verabschiedete Pokémon", "Выпускники")
    }
    var dungeonNoCandidate: String {
        t("이 규칙에 맞는 포켓몬이 없어요.", "No Pokémon fits these rules.", "このルールに合うポケモンがいません。",
          "Ningún Pokémon cumple estas reglas.", "Aucun Pokémon ne respecte ces règles.", "Nenhum Pokémon segue essas regras.",
          "Kein Pokémon passt zu diesen Regeln.", "Ни один покемон не подходит под правила.")
    }
    func dungeonLoopOf(_ name: String) -> String {
        t("\(name)의 공격 순서", "\(name)'s loop", "\(name)のわざの順番", "Bucle de \(name)", "Boucle de \(name)",
          "Ciclo de \(name)", "Schleife von \(name)", "Цикл: \(name)")
    }
    var dungeonLoopHint: String {
        t("공격 4개를 차례로 반복해요. 바꾸려면 하나를 누르세요.", "It casts its four moves in turn, then again. Click one to change it.",
          "4つのわざを順に使い、くりかえします。押すと変えられます。", "Lanza sus cuatro movimientos en orden y vuelve a empezar. Pulsa uno para cambiarlo.",
          "Il lance ses 4 attaques dans l'ordre, puis recommence. Clique sur une attaque pour la changer.",
          "Ele usa os quatro golpes em ordem e recomeça. Clique em um para trocar.",
          "Es setzt seine vier Attacken der Reihe nach ein, dann von vorn. Klicke eine an, um sie zu ändern.",
          "Он применяет четыре атаки по очереди и снова. Нажмите на атаку, чтобы сменить её.")
    }
    var dungeonLockedMove: String {
        t("잠김: 기술 캡슐로 열어요", "Locked: a Technical Capsule unlocks it", "ロック：わざカプセルで解放",
          "Bloqueado: una Cápsula Técnica lo desbloquea", "Verrouillée : une Capsule Technique la débloque",
          "Bloqueado: uma Cápsula Técnica o desbloqueia", "Gesperrt: eine Technik-Kapsel schaltet sie frei",
          "Закрыто: открывается Технической капсулой")
    }
    var dungeonNoEffectMove: String {
        t("던전에서는 효과 없음", "No effect in dungeons", "ダンジョンでは効果なし", "Sin efecto en mazmorras",
          "Sans effet en donjon", "Sem efeito em masmorras", "Im Dungeon wirkungslos", "В подземельях не действует")
    }
    var dungeonSuggestLoop: String {
        t("추천으로 되돌리기", "Back to the suggestion", "おすすめにもどす", "Volver a la sugerencia", "Revenir à la suggestion",
          "Voltar à sugestão", "Zurück zum Vorschlag", "Вернуть рекомендацию")
    }
    func dungeonCast(_ seconds: Double) -> String { String(format: "%.1f s", seconds) }
    var dungeonRemove: String { t("빼기", "Remove", "はずす", "Quitar", "Retirer", "Remover", "Entfernen", "Убрать") }
    var dungeonLoopFrozen: String {
        t("탐험 중에는 공격 순서를 바꿀 수 없어요.", "Its loop can't change while it explores.",
          "たんけん中はわざの順番を変えられません。", "Su bucle no cambia mientras explora.",
          "Sa boucle ne change pas pendant qu'il explore.", "O ciclo não muda enquanto explora.",
          "Seine Schleife ändert sich nicht, solange es erkundet.", "Цикл не меняется, пока он в экспедиции.")
    }
    var dungeonLoopTitle: String {
        t("공격 순서", "Move loop", "わざの順番", "Bucle de movimientos", "Boucle d'attaques", "Ciclo de golpes",
          "Attackenschleife", "Цикл атак")
    }

    /// A move's card on hover: what the engine plays of it (R4: descriptions and stats on hover). `type`: its type for
    /// the Pokémon it is shown for (`BattleMove.type(for:)`).
    func moveDetails(_ move: BattleMove, unlocked: Set<String>, type: PokemonType? = nil) -> String {
        var parts: [String] = [typeName(type ?? move.type)]
        switch move.moveClass {
        case .physical: parts.append(t("물리", "Physical", "ぶつり", "Físico", "Physique", "Físico", "Physisch", "Физическая"))
        case .special: parts.append(t("특수", "Special", "とくしゅ", "Especial", "Spéciale", "Especial", "Speziell", "Специальная"))
        case .status: parts.append(t("변화", "Status", "へんか", "Estado", "Statut", "Status", "Status", "Статусная"))
        }
        if move.power > 0 {
            parts.append(t("위력 \(move.power)", "Power \(move.power)", "いりょく \(move.power)", "Potencia \(move.power)",
                           "Puissance \(move.power)", "Poder \(move.power)", "Stärke \(move.power)", "Сила \(move.power)"))
        }
        if move.accuracy > 0 {
            parts.append(t("명중 \(move.accuracy)%", "Accuracy \(move.accuracy)%", "命中 \(move.accuracy)%",
                           "Precisión \(move.accuracy) %", "Précision \(move.accuracy) %", "Precisão \(move.accuracy)%",
                           "Genauigkeit \(move.accuracy) %", "Точность \(move.accuracy)%"))
        }
        if move.priority > 0 {
            parts.append(t("빠른 시전", "Quick to cast", "すばやく出る", "Rápido", "Lancement rapide", "Rápido",
                           "Schnell", "Быстрая"))
        }
        if let ailment = move.ailment {
            let chance = move.ailmentChance > 0 ? move.ailmentChance : move.effectChance
            parts.append(ailmentName(ailment) + (chance > 0 && chance < 100 ? " \(chance)%" : ""))
        }
        for change in move.statChanges {
            parts.append("\(statName(change.stat)) \(change.change > 0 ? "+" : "")\(change.change)")
        }
        if move.healing > 0 {
            parts.append(t("회복 \(move.healing)%", "Heals \(move.healing)%", "回復 \(move.healing)%", "Cura \(move.healing) %",
                           "Soin \(move.healing) %", "Cura \(move.healing)%", "Heilt \(move.healing) %", "Лечит \(move.healing)%"))
        }
        if move.drain > 0 {
            parts.append(t("흡수 \(move.drain)%", "Drains \(move.drain)%", "吸収 \(move.drain)%", "Absorbe \(move.drain) %",
                           "Draine \(move.drain) %", "Drena \(move.drain)%", "Saugt \(move.drain) %", "Поглощает \(move.drain)%"))
        } else if move.drain < 0 {
            parts.append(t("반동 \(-move.drain)%", "Recoil \(-move.drain)%", "反動 \(-move.drain)%", "Retroceso \(-move.drain) %",
                           "Recul \(-move.drain) %", "Recuo \(-move.drain)%", "Rückstoß \(-move.drain) %", "Отдача \(-move.drain)%"))
        }
        if move.flinchChance > 0 {
            parts.append(t("풀죽음 \(move.flinchChance)%", "Flinch \(move.flinchChance)%", "ひるみ \(move.flinchChance)%",
                           "Retroceso \(move.flinchChance) %", "Peur \(move.flinchChance) %", "Hesitar \(move.flinchChance)%",
                           "Zurückschrecken \(move.flinchChance) %", "Испуг \(move.flinchChance)%"))
        }
        if move.maxHits > 1 {
            parts.append(t("\(move.minHits)-\(move.maxHits)회", "\(move.minHits) to \(move.maxHits) hits",
                           "\(move.minHits)〜\(move.maxHits)回", "\(move.minHits) a \(move.maxHits) golpes",
                           "\(move.minHits) à \(move.maxHits) coups", "\(move.minHits) a \(move.maxHits) golpes",
                           "\(move.minHits) bis \(move.maxHits) Treffer", "\(move.minHits)-\(move.maxHits) ударов"))
        }
        if move.hitsAllOpponents {
            parts.append(t("상대 전원 75%", "Every foe, 75%", "相手全員に75%", "Todos los rivales, 75 %",
                           "Tous les adversaires, 75 %", "Todos os oponentes, 75%", "Alle Gegner, 75 %", "Все противники, 75%"))
        }
        if move.charges || move.recharges {
            parts.append(t("시전 +2초", "Cast +2 s", "発動 +2秒", "Carga +2 s", "Lancement +2 s", "Carga +2 s",
                           "Aufladen +2 s", "Подготовка +2 с"))
        }
        if move.isLocked && !unlocked.contains(move.slug) { parts.append(dungeonLockedMove) }
        if !move.hasEffect { parts.append(dungeonNoEffectMove) }
        return parts.joined(separator: " · ")
    }

    func ailmentName(_ ailment: BattleAilment) -> String {
        switch ailment {
        case .burn: t("화상", "Burn", "やけど", "Quemadura", "Brûlure", "Queimadura", "Verbrennung", "Ожог")
        case .paralysis: t("마비", "Paralysis", "まひ", "Parálisis", "Paralysie", "Paralisia", "Paralyse", "Паралич")
        case .sleep: t("잠듦", "Sleep", "ねむり", "Sueño", "Sommeil", "Sono", "Schlaf", "Сон")
        case .freeze: t("얼음", "Freeze", "こおり", "Congelación", "Gel", "Congelamento", "Einfrieren", "Заморозка")
        case .poison, .badPoison: t("독", "Poison", "どく", "Veneno", "Poison", "Veneno", "Gift", "Отравление")
        case .confusion: t("혼란", "Confusion", "こんらん", "Confusión", "Confusion", "Confusão", "Verwirrung", "Смятение")
        case .trap: t("묶기", "Trap", "しめつけ", "Atrapa", "Piège", "Prende", "Fessel", "Захват")
        case .leechSeed: t("씨뿌리기", "Leech Seed", "やどりぎ", "Drenadoras", "Vampigraine", "Semente Sanguessuga", "Egelsamen", "Пиявка")
        case .yawn: t("하품", "Yawn", "あくび", "Bostezo", "Bâillement", "Bocejo", "Gähner", "Зевок")
        }
    }

    func statName(_ stat: BattleStat) -> String {
        switch stat {
        case .attack: t("공격", "Atk", "こうげき", "Atq", "Atq", "Atq", "Angr", "Атк")
        case .defense: t("방어", "Def", "ぼうぎょ", "Def", "Déf", "Def", "Vert", "Защ")
        case .specialAttack: t("특공", "Sp. Atk", "とくこう", "At. Esp", "Atq Spé", "At. Esp", "SpAng", "Сп. атк")
        case .specialDefense: t("특방", "Sp. Def", "とくぼう", "Def. Esp", "Déf Spé", "Def. Esp", "SpVert", "Сп. защ")
        case .speed: t("스피드", "Speed", "すばやさ", "Velocidad", "Vitesse", "Velocidade", "Init", "Скор")
        case .accuracy: t("명중", "Accuracy", "めいちゅう", "Precisión", "Précision", "Precisão", "Genauigkeit", "Точн")
        case .evasion: t("회피", "Evasion", "かいひ", "Evasión", "Esquive", "Evasão", "Ausweichen", "Укл")
        }
    }

    // MARK: Battles

    func battleKind(_ kind: ExpeditionEventKind) -> String {
        switch kind {
        case .horde: t("무리", "Horde", "むれ", "Horda", "Horde", "Horda", "Horde", "Орда")
        case .trainer: t("트레이너", "Trainer", "トレーナー", "Entrenador", "Dresseur", "Treinador", "Trainer", "Тренер")
        case .boss: t("보스", "Boss", "ボス", "Jefe", "Boss", "Chefe", "Boss", "Босс")
        default: t("야생", "Wild", "やせい", "Salvaje", "Sauvage", "Selvagem", "Wild", "Дикие")
        }
    }
    /// The plate's HP label, as the games write it.
    var battleHP: String { t("HP", "HP", "HP", "PS", "PV", "PS", "KP", "ОЗ") }
    var battleSuperEffective: String {
        t("효과가 굉장했다!", "Super effective!", "こうかは ばつぐんだ！", "¡Es muy eficaz!", "C'est super efficace !",
          "É super efetivo!", "Sehr effektiv!", "Очень эффективно!")
    }
    var battleNotVeryEffective: String {
        t("효과가 별로인 듯하다", "Not very effective", "こうかは いまひとつ", "No es muy eficaz", "Ce n'est pas très efficace",
          "Não é muito efetivo", "Nicht sehr effektiv", "Не очень эффективно")
    }
    var battleCritical: String {
        t("급소에 맞았다!", "Critical hit!", "きゅうしょに あたった！", "¡Golpe crítico!", "Coup critique !", "Acerto crítico!",
          "Volltreffer!", "Критический удар!")
    }
    var battlePause: String { t("일시정지", "Pause", "一時停止", "Pausa", "Pause", "Pausar", "Pause", "Пауза") }
    var battlePlay: String { t("재생", "Play", "再生", "Reproducir", "Lecture", "Reproduzir", "Abspielen", "Играть") }
    var battleSkip: String { t("건너뛰기", "Skip", "スキップ", "Saltar", "Passer", "Pular", "Überspringen", "Пропустить") }
    var battleWon: String { t("승리", "Won", "勝利", "Victoria", "Victoire", "Vitória", "Gewonnen", "Победа") }
    var battleLost: String { t("패배", "Lost", "敗北", "Derrota", "Défaite", "Derrota", "Verloren", "Поражение") }
    var battleKO: String { t("기절", "K.O.", "ひんし", "Debilitado", "K.O.", "Desmaiado", "K.O.", "Без сил") }

    // MARK: The expedition on Home (maquettes 3, 4, 6, 7)

    func dungeonFloorOf(_ floor: Int, _ floors: Int) -> String {
        t("\(floor)/\(floors)층", "Floor \(floor) of \(floors)", "\(floor)/\(floors)階", "Piso \(floor) de \(floors)",
          "Étage \(floor) sur \(floors)", "Andar \(floor) de \(floors)", "Ebene \(floor) von \(floors)",
          "Этаж \(floor) из \(floors)")
    }
    func dungeonFloor(_ floor: Int) -> String {
        t("\(floor)층", "Floor \(floor)", "\(floor)階", "Piso \(floor)", "Étage \(floor)", "Andar \(floor)", "Ebene \(floor)",
          "Этаж \(floor)")
    }
    /// The menu bar's short tag: "É6/12".
    /// The menu bar's floor, "3/8": no letter before it (#136), the "↑" and "¤" of the other numbers tell them apart.
    func dungeonFloorTag(_ floor: Int, _ floors: Int) -> String { "\(floor)/\(floors)" }
    func dungeonToNextFloor(_ have: String, _ need: String, next: Int) -> String {
        t("\(next)층까지 \(have) / \(need)", "\(have) / \(need) to floor \(next)", "\(next)階まで \(have) / \(need)",
          "\(have) / \(need) hasta el piso \(next)", "\(have) / \(need) avant l'étage \(next)",
          "\(have) / \(need) até o andar \(next)", "\(have) / \(need) bis Ebene \(next)", "\(have) / \(need) до этажа \(next)")
    }
    func dungeonToBoss(_ have: String, _ need: String) -> String {
        t("보스까지 \(have) / \(need)", "\(have) / \(need) to the boss", "ボスまで \(have) / \(need)",
          "\(have) / \(need) hasta el jefe", "\(have) / \(need) avant le boss", "\(have) / \(need) até o chefe",
          "\(have) / \(need) bis zum Boss", "\(have) / \(need) до босса")
    }
    var dungeonBossHidden: String { t("보스: ?", "Boss: ?", "ボス：？", "Jefe: ?", "Boss : ?", "Chefe: ?", "Boss: ?", "Босс: ?") }
    var dungeonRare: String { t("희귀", "Rare", "レア", "Raro", "Rare", "Raro", "Selten", "Редкое") }
    var dungeonReplay: String { t("다시 보기", "Replay", "見直す", "Repetir", "Revoir", "Rever", "Ansehen", "Повтор") }
    var dungeonLive: String { t("실시간", "Live", "ライブ", "En directo", "En direct", "Ao vivo", "Live", "В эфире") }
    var dungeonLogTitle: String { t("탐험 기록", "Journal", "たんけんの記録", "Diario", "Journal", "Diário", "Tagebuch", "Журнал") }
    var dungeonWholeLog: String {
        t("전체 기록", "Whole journal", "すべての記録", "Diario completo", "Tout le journal", "Diário completo", "Ganzes Tagebuch",
          "Весь журнал")
    }
    var dungeonSeeLog: String {
        t("기록 보기", "See the journal", "記録を見る", "Ver el diario", "Voir le journal", "Ver o diário", "Tagebuch ansehen",
          "Открыть журнал")
    }
    var dungeonAbandon: String { t("포기", "Give up", "あきらめる", "Abandonar", "Abandonner", "Desistir", "Aufgeben", "Сдаться") }
    var dungeonLeave: String {
        t("던전 나가기", "Leave the dungeon", "ダンジョンを出る", "Salir de la mazmorra", "Quitter le donjon", "Sair da masmorra",
          "Dungeon verlassen", "Покинуть подземелье")
    }
    /// Under the Rare Candies, the eggs and the stones in the Bag while a team explores: the Pokémon raised is paused.
    var candiesPausedForDungeon: String {
        t("팀이 돌아올 때까지 일시정지: 키우는 포켓몬이 쉬는 동안에는 쓸 수 없어요.",
          "Paused until the team is back: the Pokémon raised rests meanwhile.",
          "チームが戻るまで一時停止：育てているポケモンはそのあいだ休んでいます。",
          "En pausa hasta que vuelva el equipo: el Pokémon que crías descansa mientras tanto.",
          "En pause jusqu'au retour de l'équipe : le Pokémon en élevage se repose en attendant.",
          "Em pausa até a equipe voltar: o Pokémon que você cria descansa enquanto isso.",
          "Pausiert, bis das Team zurück ist: Das aufgezogene Pokémon ruht so lange.",
          "Пауза до возвращения команды: выращиваемый покемон пока отдыхает.")
    }
    /// What leaving keeps (the owner, 2026-11-04): the floors crossed, not the one under way.
    var dungeonLeaveKeeps: String {
        t("지나온 층의 물건을 갖고 나와요. 지금 층은 아무것도 주지 않아요.",
          "The team comes out with the loot of the floors crossed; the floor under way gives nothing.",
          "通った階で集めたものを持って出ます。いまの階では何も手に入りません。",
          "El equipo sale con el botín de los pisos superados; el piso en curso no da nada.",
          "L'équipe sort avec le butin des étages franchis ; l'étage en cours ne donne rien.",
          "A equipe sai com o saque dos andares vencidos; o andar em curso não dá nada.",
          "Das Team kommt mit der Beute der geschafften Ebenen heraus; die laufende Ebene gibt nichts.",
          "Команда уходит с добычей пройденных этажей; текущий этаж ничего не даёт.")
    }

    // The journal's lines: the species stand beside them as sprites, named on hover.

    var dungeonLogChest: String { t("상자", "Chest", "たからばこ", "Cofre", "Coffre", "Baú", "Truhe", "Сундук") }
    var dungeonLogEmptyChest: String {
        t("빈 상자", "Empty chest", "からっぽのたからばこ", "Cofre vacío", "Coffre vide", "Baú vazio", "Leere Truhe", "Пустой сундук")
    }
    func dungeonLogTrap(percent: Int) -> String {
        t("함정: 팀이 HP를 \(percent)% 잃었어요", "Trap: the team loses \(percent)% of its HP", "わな：チームのHPが\(percent)%減った",
          "Trampa: el equipo pierde el \(percent) % de sus PS", "Piège : l'équipe perd \(percent) % de ses PV",
          "Armadilha: a equipe perde \(percent)% dos PS", "Falle: Das Team verliert \(percent) % seiner KP",
          "Ловушка: команда теряет \(percent)% ОЗ")
    }
    func dungeonLogTrapItem(_ item: String) -> String {
        t("함정: 모은 물건 중 \(item) 1개를 잃었어요", "Trap: the loot loses 1 × \(item)", "わな：\(item)を1こ失った",
          "Trampa: el botín pierde 1 × \(item)", "Piège : le butin perd 1 × \(item)", "Armadilha: o saque perde 1 × \(item)",
          "Falle: Die Beute verliert 1 × \(item)", "Ловушка: добыча теряет \(item) ×1")
    }
    func dungeonLogSpring(percent: Int) -> String {
        t("샘: 팀이 HP를 \(percent)% 회복했어요", "Spring: the team gets \(percent)% of its HP back",
          "いずみ：チームのHPが\(percent)%回復した", "Manantial: el equipo recupera el \(percent) % de sus PS",
          "Source : l'équipe récupère \(percent) % de ses PV", "Fonte: a equipe recupera \(percent)% dos PS",
          "Quelle: Das Team erhält \(percent) % seiner KP zurück", "Источник: команда восстанавливает \(percent)% ОЗ")
    }
    var dungeonLogCenter: String {
        t("포켓몬센터: 팀 전원이 회복했어요", "Pokémon Center: the whole team is healed", "ポケモンセンター：チーム全員が回復した",
          "Centro Pokémon: todo el equipo se cura", "Centre Pokémon : toute l'équipe est soignée",
          "Centro Pokémon: toda a equipe é curada", "Pokémon-Center: Das ganze Team ist geheilt",
          "Покемон-центр: вся команда вылечена")
    }
    func dungeonLogLost(percent: Int) -> String {
        t("길 잃은 포켓몬: 팀이 데려다주고(HP -\(percent)%) 선물을 받았어요",
          "Lost Pokémon: the team walks it home (-\(percent)% HP) and gets a gift",
          "まいごのポケモン：送りとどけて(HP -\(percent)%)、おれいをもらった",
          "Pokémon perdido: el equipo lo acompaña (-\(percent) % PS) y recibe un regalo",
          "Pokémon égaré : l'équipe le raccompagne (-\(percent) % PV) et reçoit un cadeau",
          "Pokémon perdido: a equipe o acompanha (-\(percent)% PS) e ganha um presente",
          "Verirrtes Pokémon: Das Team bringt es heim (-\(percent) % KP) und erhält ein Geschenk",
          "Потерявшийся покемон: команда провожает его (-\(percent)% ОЗ) и получает подарок")
    }
    func dungeonLogShiny(caught: Bool) -> String {
        caught
            ? t("이로치 조우: 잡았어요! 알을 얻었어요", "Shiny encounter: caught! Its egg joins the loot",
                "色違いに出会った：つかまえた！タマゴを手に入れた", "Encuentro variocolor: ¡capturado! Su huevo va al botín",
                "Rencontre chromatique : capturé ! Son œuf rejoint le butin", "Encontro brilhante: capturado! O ovo vai para o saque",
                "Schillerndes Pokémon: gefangen! Sein Ei kommt zur Beute", "Встреча с шайни: пойман! Его яйцо в добыче")
            : t("이로치 조우: 도망쳤어요", "Shiny encounter: it fled", "色違いに出会った：にげられた", "Encuentro variocolor: huyó",
                "Rencontre chromatique : il s'est enfui", "Encontro brilhante: fugiu", "Schillerndes Pokémon: geflohen",
                "Встреча с шайни: сбежал")
    }
    /// The journal's fork: the die, the path it gives, until which floor, and what it changes (the owner, 2026-11-06:
    /// "on comprend pas ce que ça change").
    func dungeonLogBranch(roll: Int, risky: Bool, until floor: Int) -> String {
        risky
            ? t("갈림길: 주사위 \(roll)/6, 위험한 길로 \(floor)층까지. 전투와 함정이 늘어요.",
                "Fork: dice \(roll) of 6, the risky path until floor \(floor). More battles and traps.",
                "わかれ道：サイコロ \(roll)/6、\(floor)階まできけんな道。バトルとわなが増えます。",
                "Bifurcación: dado \(roll) de 6, camino arriesgado hasta el piso \(floor). Más combates y trampas.",
                "Embranchement : dé \(roll) sur 6, chemin risqué jusqu'à l'étage \(floor). Plus de combats et de pièges.",
                "Bifurcação: dado \(roll) de 6, caminho arriscado até o andar \(floor). Mais batalhas e armadilhas.",
                "Abzweigung: Würfel \(roll) von 6, riskanter Weg bis Ebene \(floor). Mehr Kämpfe und Fallen.",
                "Развилка: кубик \(roll) из 6, опасный путь до этажа \(floor). Больше боёв и ловушек.")
            : t("갈림길: 주사위 \(roll)/6, 안전한 길로 \(floor)층까지. 전투와 함정이 줄어요.",
                "Fork: dice \(roll) of 6, the safe path until floor \(floor). Fewer battles and traps.",
                "わかれ道：サイコロ \(roll)/6、\(floor)階まであんぜんな道。バトルとわなが減ります。",
                "Bifurcación: dado \(roll) de 6, camino seguro hasta el piso \(floor). Menos combates y trampas.",
                "Embranchement : dé \(roll) sur 6, chemin sûr jusqu'à l'étage \(floor). Moins de combats et de pièges.",
                "Bifurcação: dado \(roll) de 6, caminho seguro até o andar \(floor). Menos batalhas e armadilhas.",
                "Abzweigung: Würfel \(roll) von 6, sicherer Weg bis Ebene \(floor). Weniger Kämpfe und Fallen.",
                "Развилка: кубик \(roll) из 6, безопасный путь до этажа \(floor). Меньше боёв и ловушек.")
    }
    /// The artifacts that speed a dungeon's floors up, their sum first (the owner, 2026-11-06).
    func dungeonArtifactsSpeed(_ percent: Int, _ list: String) -> String {
        t("유물로 층이 \(percent)% 빨라져요: \(list)", "Artifacts make its floors \(percent)% faster: \(list)",
          "アーティファクトで各階が\(percent)%速くなります：\(list)", "Los artefactos hacen sus pisos un \(percent) % más rápidos: \(list)",
          "Les artefacts rendent ses étages \(percent) % plus rapides : \(list)", "Os artefatos deixam os andares \(percent)% mais rápidos: \(list)",
          "Artefakte machen seine Ebenen \(percent) % schneller: \(list)", "Артефакты ускоряют этажи на \(percent)%: \(list)")
    }

    /// The daily and weekly boss's form, won already (a form not won says nothing, the owner, 2026-11-09).
    var challengeFormOwned: String {
        t("이미 얻은 모습", "Won already", "もう手に入れた", "Ya la tienes", "Déjà obtenue", "Já é sua", "Schon gewonnen", "Уже получена")
    }

    /// #133: every expedition that ended.
    var runHistoryTitle: String {
        t("탐험 기록", "Expedition history", "たんけんの記録", "Historial de expediciones", "Historique des expéditions",
          "Histórico de expedições", "Expeditionsverlauf", "История экспедиций")
    }
    func runHistoryHint(_ n: Int) -> String {
        t("끝난 탐험이 최신순으로 보여요. 최근 \(n)개는 일지와 전투 다시보기를 열 수 있어요.",
          "Every expedition that ended, the latest first. The last \(n) open on their journal, every battle replayable.",
          "終わったたんけんを新しい順に表示します。最近の\(n)件は記録とバトルの見返しを開けます。",
          "Cada expedición terminada, la más reciente primero. Las \(n) últimas abren su diario, con cada combate para volver a ver.",
          "Chaque expédition terminée, la plus récente en premier. Les \(n) dernières s'ouvrent sur leur journal, chaque combat à revoir.",
          "Cada expedição terminada, a mais recente primeiro. As \(n) últimas abrem o diário, com cada batalha para rever.",
          "Jede beendete Expedition, die neueste zuerst. Die letzten \(n) öffnen ihr Protokoll, jeder Kampf zum Ansehen.",
          "Все завершённые экспедиции, сначала последние. Последние \(n) открывают журнал, каждый бой можно пересмотреть.")
    }
    var runOpenJournal: String {
        t("일지와 전투 보기", "See its journal and battles", "記録とバトルを見る", "Ver su diario y combates", "Voir son journal et ses combats",
          "Ver o diário e as batalhas", "Protokoll und Kämpfe ansehen", "Журнал и бои")
    }

    /// #141: a secret passage, in gold in the journal.
    func dungeonLogSecretSkip(_ floor: Int) -> String {
        t("비밀 통로: 팀이 \(floor)층을 토큰 없이 건너뛰었어요!", "Secret passage: the team skips floor \(floor), its tokens unpaid!",
          "ひみつの通路：チームは\(floor)階をトークンなしでとばした！", "¡Pasadizo secreto: el equipo se salta el piso \(floor) sin pagar sus tokens!",
          "Passage secret : l'équipe saute l'étage \(floor) sans payer ses tokens !", "Passagem secreta: a equipe pula o andar \(floor) sem pagar os tokens!",
          "Geheimgang: Das Team überspringt Ebene \(floor), ohne ihre Tokens zu zahlen!", "Тайный ход: команда пропускает этаж \(floor), не платя за него токены!")
    }
    var dungeonLogSecretRoom: String {
        t("비밀 통로: 숨겨진 방과 상자를 찾았어요!", "Secret passage: a hidden room and its chest!", "ひみつの通路：かくし部屋とたからばこ！",
          "¡Pasadizo secreto: una sala oculta y su cofre!", "Passage secret : une salle cachée et son coffre !",
          "Passagem secreta: uma sala escondida e seu baú!", "Geheimgang: ein versteckter Raum mit Truhe!",
          "Тайный ход: скрытая комната и её сундук!")
    }
    var dungeonSecretRule: String {
        t("T2부터 층마다 4% 확률로 비밀 통로가 나와요: 반은 다음 층을 토큰 없이 건너뛰고(보스 층과 포켓몬센터 층은 제외), 반은 숨겨진 방에 상자가 있어요.",
          "From T2, each floor has a 4% chance of a secret passage: half the time the team skips the next floor without paying its tokens (never the boss's nor the Pokémon Center's), else a hidden room holds a chest.",
          "T2から、各階に4%の確率でひみつの通路があります：半分は次の階をトークンなしでとばし（ボスとポケモンセンターの階はのぞく）、半分はかくし部屋にたからばこがあります。",
          "Desde T2, cada piso tiene un 4 % de probabilidad de un pasadizo secreto: la mitad de las veces el equipo se salta el piso siguiente sin pagar sus tokens (nunca el del jefe ni el del Centro Pokémon); si no, una sala oculta guarda un cofre.",
          "Dès le T2, chaque étage a 4 % de chances de cacher un passage secret : une fois sur deux, l'équipe saute l'étage suivant sans payer ses tokens (jamais celui du boss ni celui du Centre Pokémon) ; sinon, une salle cachée garde un coffre.",
          "A partir do T2, cada andar tem 4% de chance de uma passagem secreta: metade das vezes a equipe pula o andar seguinte sem pagar os tokens (nunca o do chefe nem o do Centro Pokémon); senão, uma sala escondida guarda um baú.",
          "Ab T2 hat jede Ebene eine Chance von 4 % auf einen Geheimgang: In der Hälfte der Fälle überspringt das Team die nächste Ebene, ohne ihre Tokens zu zahlen (nie die des Bosses oder des Pokémon-Centers), sonst wartet ein versteckter Raum mit einer Truhe.",
          "Начиная с T2, на каждом этаже 4% шанс тайного хода: в половине случаев команда пропускает следующий этаж, не платя за него токены (никогда этаж босса или Покецентра), иначе скрытая комната хранит сундук.")
    }
    var dungeonSecretPassage: String {
        t("비밀 통로", "Secret passage", "ひみつの通路", "Pasadizo secreto", "Passage secret", "Passagem secreta", "Geheimgang", "Тайный ход")
    }

    /// The path the team walks now, on Home.
    func dungeonPath(risky: Bool) -> String {
        risky ? t("위험한 길", "Risky path", "きけんな道", "Camino arriesgado", "Chemin risqué", "Caminho arriscado", "Riskanter Weg",
                  "Опасный путь")
            : t("안전한 길", "Safe path", "あんぜんな道", "Camino seguro", "Chemin sûr", "Caminho seguro", "Sicherer Weg",
                "Безопасный путь")
    }
    /// The rule of the dice, on Home and on each dungeon's page.
    var dungeonPathRule: String {
        t("3층마다 주사위를 굴려요: 4~6이면 다음 주사위까지 위험한 길(전투 1.4배, 함정 증가), 1~3이면 안전한 길이에요. 보스와 보상 표는 바뀌지 않아요.",
          "Every three floors a die is rolled: 4 to 6, the risky path until the next one (1.4 times the battles, more traps); 1 to 3, the safe path. The boss and the loot tables stay the same.",
          "3階ごとにサイコロをふります：4〜6なら次のサイコロまできけんな道（バトル1.4倍、わなが増える）、1〜3ならあんぜんな道です。ボスと戦利品の表は変わりません。",
          "Cada tres pisos se tira un dado: de 4 a 6, camino arriesgado hasta el siguiente (1,4 veces los combates, más trampas); de 1 a 3, camino seguro. El jefe y las tablas de botín no cambian.",
          "Tous les 3 étages, un dé est lancé : de 4 à 6, chemin risqué jusqu'au dé suivant (1,4 fois plus de combats, plus de pièges) ; de 1 à 3, chemin sûr. Le boss et les tables de butin ne changent pas.",
          "A cada três andares um dado é lançado: de 4 a 6, caminho arriscado até o próximo (1,4 vez as batalhas, mais armadilhas); de 1 a 3, caminho seguro. O chefe e as tabelas de saque não mudam.",
          "Alle drei Ebenen wird gewürfelt: 4 bis 6, der riskante Weg bis zum nächsten Wurf (1,4-mal so viele Kämpfe, mehr Fallen); 1 bis 3, der sichere Weg. Boss und Beutetabellen bleiben gleich.",
          "Каждые три этажа бросается кубик: от 4 до 6 опасный путь до следующего броска (боёв в 1,4 раза больше, больше ловушек); от 1 до 3 безопасный путь. Босс и таблицы добычи не меняются.")
    }
    var dungeonDetailEvents: String {
        t("층마다 일어나는 일", "What a floor holds", "各階のできごと", "Lo que trae cada piso", "Ce que réserve un étage",
          "O que cada andar traz", "Was eine Ebene bringt", "Что ждёт на этаже")
    }
    func dungeonEventName(_ kind: ExpeditionEventKind) -> String {
        switch kind {
        case .wild: t("야생 전투", "Wild battle", "やせいのバトル", "Combate salvaje", "Combat sauvage", "Batalha selvagem", "Wilder Kampf", "Дикий бой")
        case .horde: t("무리", "Horde", "むれ", "Horda", "Horde", "Horda", "Horde", "Орда")
        case .trainer: t("트레이너", "Trainer", "トレーナー", "Entrenador", "Dresseur", "Treinador", "Trainer", "Тренер")
        case .chest: dungeonLogChest
        case .trap: t("함정", "Trap", "わな", "Trampa", "Piège", "Armadilha", "Falle", "Ловушка")
        case .spring: t("샘", "Spring", "いずみ", "Manantial", "Source", "Fonte", "Quelle", "Источник")
        case .lost: t("길 잃은 포켓몬", "Lost Pokémon", "まいごのポケモン", "Pokémon perdido", "Pokémon perdu", "Pokémon perdido",
                      "Verirrtes Pokémon", "Потерянный покемон")
        case .shiny: t("이로치 조우", "Shiny encounter", "色違いに出会う", "Encuentro variocolor", "Rencontre chromatique",
                       "Encontro brilhante", "Schillernde Begegnung", "Встреча с блестящим")
        case .center: t("포켓몬센터", "Pokémon Center", "ポケモンセンター", "Centro Pokémon", "Centre Pokémon", "Centro Pokémon",
                        "Pokémon-Center", "Покецентр")
        case .boss: battleKind(.boss)
        }
    }

    func dungeonLogItemUsed(_ item: String) -> String {
        t("\(item) 사용", "\(item) used", "\(item)をつかった", "\(item) usado", "\(item) utilisé", "\(item) usado",
          "\(item) eingesetzt", "Использован предмет \"\(item)\"")
    }
    func dungeonLogHeal(_ price: String) -> String {
        t("긴급 회복: 팀 전원 HP 100% (\(price))", "Emergency heal: the whole team at 100% (\(price))",
          "きんきゅう回復：チーム全員HP100% (\(price))", "Curación de urgencia: todo el equipo al 100 % (\(price))",
          "Soin d'urgence : toute l'équipe à 100 % (\(price))", "Cura de emergência: toda a equipe a 100% (\(price))",
          "Notheilung: Das ganze Team auf 100 % (\(price))", "Срочное лечение: вся команда на 100% (\(price))")
    }
    var dungeonLogBoss: String {
        t("보스 등장", "The boss appears", "ボスがあらわれた", "Aparece el jefe", "Le boss apparaît", "O chefe aparece",
          "Der Boss erscheint", "Появляется босс")
    }
    /// The boss fell, every throw missed: on the return, over its greyed sprite.
    var dungeonBossGotAway: String {
        t("도망쳤어요", "Got away", "にげられた", "Se escapó", "S'est échappé", "Fugiu", "Entkommen", "Сбежал")
    }
    /// A secret boss in the boss's place, or after it (`SecretBosses`).
    var dungeonLogSecretBoss: String {
        t("비밀 보스 등장!", "A secret boss appears!", "ひみつのボスがあらわれた！", "¡Aparece un jefe secreto!",
          "Un boss secret apparaît !", "Um chefe secreto aparece!", "Ein geheimer Boss erscheint!", "Появляется тайный босс!")
    }
    func dungeonLogThrow(_ attempt: Int, ball: String, caught: Bool) -> String {
        caught
            ? t("\(attempt)번째 던지기 (\(ball)): 잡았다!", "Throw \(attempt) (\(ball)): caught!", "\(attempt)回目 (\(ball))：つかまえた！",
                "Lanzamiento \(attempt) (\(ball)): ¡capturado!", "Lancer \(attempt) (\(ball)) : capturé !",
                "Lance \(attempt) (\(ball)): capturado!", "Wurf \(attempt) (\(ball)): gefangen!", "Бросок \(attempt) (\(ball)): пойман!")
            : t("\(attempt)번째 던지기 (\(ball)): 놓쳤다", "Throw \(attempt) (\(ball)): missed", "\(attempt)回目 (\(ball))：だめだった",
                "Lanzamiento \(attempt) (\(ball)): fallido", "Lancer \(attempt) (\(ball)) : raté", "Lance \(attempt) (\(ball)): errou",
                "Wurf \(attempt) (\(ball)): daneben", "Бросок \(attempt) (\(ball)): мимо")
    }
    var dungeonLogVictory: String {
        t("보스 격파: 모은 물건을 얻었어요", "Boss beaten: the loot is won", "ボスをたおした：集めたものを手に入れた",
          "Jefe vencido: el botín es tuyo", "Boss vaincu : le butin est gagné", "Chefe vencido: o saque é seu",
          "Boss besiegt: Die Beute gehört dir", "Босс повержен: добыча твоя")
    }
    var dungeonLogDefeat: String {
        t("팀 전멸: 지나온 층의 물건은 지켰어요", "Team down: the loot of the floors crossed is kept",
          "チームぜんめつ：通った階で集めたものは残る", "Equipo derrotado: el botín de los pisos superados se conserva",
          "Équipe K.O. : le butin des étages franchis est gardé", "Equipe derrotada: o saque dos andares vencidos fica",
          "Team besiegt: Die Beute der geschafften Ebenen bleibt", "Команда побеждена: добыча пройденных этажей сохранена")
    }
    var dungeonLogLeft: String {
        t("던전을 나왔어요: 모은 물건은 지켰어요", "Left the dungeon: loot kept", "ダンジョンを出た：集めたものは無事",
          "Salida de la mazmorra: botín conservado", "Sortie du donjon : butin gardé", "Saída da masmorra: saque mantido",
          "Dungeon verlassen: Beute behalten", "Выход из подземелья: добыча сохранена")
    }

    // The emergency heal (R5, maquette 4).

    var dungeonPaused: String { t("일시정지", "paused", "一時停止中", "en pausa", "en pause", "em pausa", "pausiert", "на паузе") }
    func dungeonTeamInDanger(_ percent: Int) -> String {
        t("팀 위험: HP \(percent)%", "Team in danger: \(percent)% of its HP", "チームがあぶない：HP \(percent)%",
          "Equipo en peligro: \(percent) % de sus PS", "Équipe en danger : \(percent) % de ses PV",
          "Equipe em perigo: \(percent)% dos PS", "Team in Gefahr: \(percent) % seiner KP", "Команда в опасности: \(percent)% ОЗ")
    }
    var dungeonHealExplain: String {
        t("긴급 회복: 팀 전원 HP 100%, 기절한 포켓몬도 일어나요. 탐험마다 한 번뿐이에요. 회복하지 않고 지면 탐험이 끝나지만, 지나온 층의 물건은 지켜요.",
          "Emergency heal: the whole team back to 100%, fainted ones revived. Once per expedition. Without it, a defeat ends the expedition, the loot of the floors crossed kept.",
          "きんきゅう回復：チーム全員HP100%、ひんしも回復。たんけん1回につき1度だけ。回復せずに負けるとたんけんは終わりますが、通った階で集めたものは残ります。",
          "Curación de urgencia: todo el equipo al 100 %, los debilitados se levantan. Una sola vez por expedición. Sin ella, una derrota termina la expedición, con el botín de los pisos superados.",
          "Soin d'urgence : toute l'équipe à 100 %, les K.O. relevés. Une seule fois par expédition. Sans lui, une défaite termine l'expédition, avec le butin des étages franchis.",
          "Cura de emergência: toda a equipe a 100%, os desmaiados de pé. Uma vez por expedição. Sem ela, uma derrota encerra a expedição, com o saque dos andares vencidos.",
          "Notheilung: Das ganze Team auf 100 %, besiegte Pokémon stehen wieder auf. Einmal pro Expedition. Ohne sie beendet eine Niederlage die Expedition, die Beute der geschafften Ebenen bleibt.",
          "Срочное лечение: вся команда на 100%, павшие встают. Один раз за экспедицию. Без него поражение завершает экспедицию, добыча пройденных этажей остаётся.")
    }
    func dungeonHealPrice(_ price: String, have: String) -> String {
        t("가격: \(price) · 보유 \(have)", "Price: \(price) · you have \(have)", "ねだん：\(price)・所持 \(have)",
          "Precio: \(price) · tienes \(have)", "Prix : \(price) · tu as \(have)", "Preço: \(price) · você tem \(have)",
          "Preis: \(price) · du hast \(have)", "Цена: \(price) · у тебя \(have)")
    }
    var dungeonHealSkip: String {
        t("그냥 계속", "Go on without", "そのまま進む", "Seguir sin ella", "Continuer sans", "Seguir sem", "Ohne weiter", "Продолжить без")
    }
    func dungeonHealPay(_ price: String) -> String {
        t("회복 · \(price)", "Heal · \(price)", "回復・\(price)", "Curar · \(price)", "Soigner · \(price)", "Curar · \(price)",
          "Heilen · \(price)", "Лечить · \(price)")
    }
    /// Above a Legendary Egg or a Master Ball in a recap (2026-11-09).
    var dungeonExceptionalFind: String {
        t("대박 발견!", "Exceptional find!", "すごい掘り出し物！", "¡Hallazgo excepcional!", "Trouvaille exceptionnelle !",
          "Achado excepcional!", "Außergewöhnlicher Fund!", "Исключительная находка!")
    }
    /// The heal waiting: the tokens grow the Pokémon raised meanwhile (2026-11-09).
    var dungeonHealGrowthGoesOn: String {
        t("팀이 답을 기다리는 동안 토큰은 평소처럼 키우는 포켓몬과 알을 키워요. 답하면 팀이 다시 출발해요.",
          "While the team waits for your answer, your tokens grow your Pokémon or egg as usual; it sets off again once you answer.",
          "チームが答えを待つあいだ、トークンはいつもどおり育てているポケモンやタマゴを育てます。答えるとチームはまた進みます。",
          "Mientras el equipo espera tu respuesta, tus tokens hacen crecer tu Pokémon o tu huevo como siempre; sigue en cuanto respondas.",
          "Pendant que l'équipe attend ta réponse, tes tokens font grandir ton Pokémon ou ton œuf comme d'habitude ; elle repart dès ta réponse.",
          "Enquanto a equipe espera sua resposta, seus tokens fazem seu Pokémon ou ovo crescer como sempre; ela segue assim que você responder.",
          "Während das Team auf deine Antwort wartet, lassen deine Tokens dein Pokémon oder Ei wie gewohnt wachsen; es zieht weiter, sobald du antwortest.",
          "Пока команда ждёт ответа, токены как обычно растят вашего покемона или яйцо; после ответа команда пойдёт дальше.")
    }
    func dungeonReserve(_ tokens: String) -> String {
        t("토큰 \(tokens) 대기 중, 답하면 바로 반영돼요.", "\(tokens) tokens on hold, put in as soon as you answer.",
          "トークン\(tokens)が待機中。答えるとすぐに反映されます。", "\(tokens) tokens en reserva, aplicados en cuanto respondas.",
          "\(tokens) de tokens en réserve, appliqués dès ta réponse.", "\(tokens) tokens em reserva, aplicados assim que você responder.",
          "\(tokens) Tokens in Reserve, angerechnet, sobald du antwortest.", "\(tokens) токенов в резерве, учтутся сразу после ответа.")
    }

    // The capture (Q18, maquette 6).

    var dungeonPokeBall: String {
        t("몬스터볼", "Poké Ball", "モンスターボール", "Poké Ball", "Poké Ball", "Poké Bola", "Pokéball", "Покебол")
    }

    // The return (maquette 7).

    func dungeonResultTitle(won: Bool, roped: Bool) -> String {
        if won {
            return t("탐험 성공", "Expedition won", "たんけん成功", "Expedición superada", "Expédition réussie", "Expedição concluída",
                     "Expedition geschafft", "Экспедиция удалась")
        }
        if roped {
            return t("조기 귀환", "Back early", "早めの帰還", "Regreso anticipado", "Retour anticipé", "Retorno antecipado",
                     "Früh zurück", "Досрочное возвращение")
        }
        return t("탐험 실패", "Expedition failed", "たんけん失敗", "Expedición fallida", "Expédition échouée", "Expedição fracassada",
                 "Expedition gescheitert", "Экспедиция провалена")
    }
    var dungeonFirstVictory: String {
        t("첫 승리", "1st win", "初勝利", "1.ª victoria", "1re victoire", "1ª vitória", "1. Sieg", "1-я победа")
    }
    func dungeonBattles(_ n: Int) -> String {
        t("전투 \(n)회", n == 1 ? "1 battle" : "\(n) battles", "\(n)戦", n == 1 ? "1 combate" : "\(n) combates",
          n <= 1 ? "\(n) combat" : "\(n) combats", n == 1 ? "1 batalha" : "\(n) batalhas", n == 1 ? "1 Kampf" : "\(n) Kämpfe",
          "Боёв: \(n)")
    }
    var dungeonBossCaught: String {
        t("잡았어요: 알은 가방에 있어요", "Caught: its egg is in the Bag", "つかまえた：タマゴはバッグに",
          "Capturado: su huevo está en la Bolsa", "Capturé : son œuf est dans le Sac", "Capturado: o ovo está na Mochila",
          "Gefangen: Sein Ei ist im Beutel", "Пойман: его яйцо в сумке")
    }
    /// A boss already caught gives an egg of the dungeon's tier instead of its own.
    func dungeonBossCaughtAgain(_ egg: String) -> String {
        t("이미 잡은 포켓몬: 대신 가방에 \(egg) 1개", "Already caught: \(egg) in the Bag instead",
          "つかまえ済み：かわりに\(egg)をバッグに", "Ya capturado: en su lugar, \(egg) en la Bolsa",
          "Déjà capturé : à la place, \(egg) dans le Sac", "Já capturado: em vez disso, \(egg) na Mochila",
          "Schon gefangen: stattdessen \(egg) im Beutel", "Уже пойман: вместо него \(egg) в сумке")
    }
    /// A legendary whose egg was won once: no throws, the loot only.
    var dungeonBossEggWonBefore: String {
        t("알은 이미 받았어요: 전리품만", "Its egg is already yours: the loot only", "タマゴはもう手に入れた：戦利品だけ",
          "Su huevo ya es tuyo: solo el botín", "Son œuf est déjà à toi : le butin seulement", "O ovo dele já é seu: só o saque",
          "Sein Ei hast du schon: nur die Beute", "Его яйцо уже твоё: только добыча")
    }
    /// The Pokémon raised hatched from a legendary boss's egg: nothing sends it off before it graduates.
    var legendaryBossPokemonLocked: String {
        t("전설 보스의 알에서 태어났어요: 졸업할 때까지 다른 무엇으로도 바꿀 수 없어요.",
          "Hatched from a legendary boss's egg: nothing can replace it before it graduates.",
          "伝説のボスのタマゴから生まれました：卒業するまで何とも入れ替えられません。",
          "Nació del huevo de un jefe legendario: nada puede sustituirlo antes de graduarse.",
          "Éclos d'un œuf de boss légendaire : rien ne peut le remplacer avant son diplôme.",
          "Nasceu do ovo de um chefe lendário: nada pode substituí-lo antes de se formar.",
          "Aus dem Ei eines legendären Bosses geschlüpft: Nichts ersetzt es vor seinem Abschluss.",
          "Вылупился из яйца легендарного босса: до выпуска его ничем не заменить.")
    }
    var dungeonBossNotCaught: String {
        t("잡지 못했어요", "Not caught", "つかまえられなかった", "No capturado", "Pas capturé", "Não capturado", "Nicht gefangen", "Не пойман")
    }
    func dungeonUnlocked(_ names: String) -> String {
        t("열림: \(names)", "Unlocked: \(names)", "解放：\(names)", "Desbloqueado: \(names)", "Débloqué : \(names)",
          "Desbloqueado: \(names)", "Freigeschaltet: \(names)", "Открыто: \(names)")
    }
    var dungeonTechnicalCapsule: String {
        t("기술 캡슐", "Technical Capsule", "わざカプセル", "Cápsula Técnica", "Capsule Technique", "Cápsula Técnica", "Technikkapsel",
          "Техническая капсула")
    }
    /// A defeat before any loot: nothing found, what was taken along is back.
    /// No loot before the fall, or before leaving.
    func dungeonNothingFound(left: Bool) -> String {
        left
            ? t("나오기 전에 얻은 물건이 없어요. 쓰지 않은 가져간 물건은 가방으로 돌아왔어요.",
                "Nothing found before leaving. What the team took along and didn't use is back in the Bag.",
                "出る前に見つけたものはありません。使わなかった持ち物はバッグにもどりました。",
                "No encontró nada antes de salir. Lo que el equipo llevó y no usó vuelve a la Bolsa.",
                "Rien trouvé avant de sortir. Ce que l'équipe avait emporté sans l'utiliser est revenu au Sac.",
                "Nada encontrado antes de sair. O que a equipe levou e não usou voltou para a Mochila.",
                "Vor dem Verlassen nichts gefunden. Was das Team mitnahm und nicht nutzte, ist wieder im Beutel.",
                "До выхода ничего не найдено. Что команда взяла и не использовала, вернулось в сумку.")
            : t("쓰러지기 전에 얻은 물건이 없어요. 쓰지 않은 가져간 물건은 가방으로 돌아왔어요.",
                "Nothing found before the fall. What the team took along and didn't use is back in the Bag.",
                "たおれる前に見つけたものはありません。使わなかった持ち物はバッグにもどりました。",
                "No encontró nada antes de caer. Lo que el equipo llevó y no usó vuelve a la Bolsa.",
                "Rien trouvé avant la chute. Ce que l'équipe avait emporté sans l'utiliser est revenu au Sac.",
                "Nada encontrado antes da queda. O que a equipe levou e não usou voltou para a Mochila.",
                "Vor dem Sturz nichts gefunden. Was das Team mitnahm und nicht nutzte, ist wieder im Beutel.",
                "До поражения ничего не найдено. Что команда взяла и не использовала, вернулось в сумку.")
    }
    /// A defeat's loot, kept: above its rows.
    var dungeonLootKept: String {
        t("지나온 층의 물건은 지켰어요.", "The loot of the floors crossed is yours.", "通った階で集めたものは手に入りました。",
          "El botín de los pisos superados es tuyo.", "Le butin des étages franchis est à toi.", "O saque dos andares vencidos é seu.",
          "Die Beute der geschafften Ebenen gehört dir.", "Добыча пройденных этажей твоя.")
    }
    /// The balls the automatic throws took, in order.
    func dungeonThrowsUsed(_ balls: String) -> String {
        t("던진 볼: \(balls)", "Thrown: \(balls)", "投げたボール：\(balls)", "Lanzadas: \(balls)", "Lancers : \(balls)",
          "Lançadas: \(balls)", "Geworfen: \(balls)", "Брошено: \(balls)")
    }
    /// The team screen's box: the automatic throws may take the Master Ball at a legendary boss.
    func dungeonUseMasterBall(_ ball: String) -> String {
        t("전설의 보스에게 \(ball) 던지기", "Throw the \(ball) at a legendary boss", "伝説のボスに\(ball)を投げる",
          "Lanzar la \(ball) a un jefe legendario", "Lancer la \(ball) sur un boss légendaire", "Lançar a \(ball) num chefe lendário",
          "Den \(ball) auf einen legendären Boss werfen", "Бросить \(ball) в легендарного босса")
    }
    var dungeonGrowthResumes: String {
        t("키우는 포켓몬이 다시 자라요.", "Your Pokémon being raised grows again.", "育てているポケモンがまた育ちます。",
          "Tu Pokémon en crianza vuelve a crecer.", "Ton Pokémon en cours reprend sa croissance.",
          "Seu Pokémon em criação volta a crescer.", "Dein Pokémon in Aufzucht wächst wieder.", "Растущий покемон снова растёт.")
    }

    // The Bag's dungeon items.

    var dungeonOpen: String { t("열기", "Open", "開ける", "Abrir", "Ouvrir", "Abrir", "Öffnen", "Открыть") }
    func dungeonChestFound(_ what: String) -> String {
        t("발견: \(what)", "Found: \(what)", "見つけた：\(what)", "Encontrado: \(what)", "Trouvé : \(what)",
          "Encontrado: \(what)", "Gefunden: \(what)", "Найдено: \(what)")
    }
    var dungeonNoCapsuleTarget: String {
        t("개체값이 31 미만인 졸업 포켓몬이 없어요", "No graduated Pokémon with an IV under 31",
          "個体値が31未満の卒業ポケモンがいません", "Ningún Pokémon graduado con un IV bajo 31",
          "Aucun diplômé avec un IV sous 31", "Nenhum Pokémon formado com IV abaixo de 31",
          "Kein verabschiedetes Pokémon mit einem DV unter 31", "Нет выпускников с IV ниже 31")
    }
    var dungeonCapsulePick: String {
        t("졸업 포켓몬을 고르세요", "Pick a graduated Pokémon", "卒業ポケモンをえらんでね", "Elige un Pokémon graduado",
          "Choisis un diplômé", "Escolha um Pokémon formado", "Wähle ein verabschiedetes Pokémon", "Выбери выпускника")
    }
    func label(for option: CompanionStore.CapsuleSortOption) -> String {
        switch option {
        case .strongest:
            t("강한 순", "Strongest", "強い順", "Los más fuertes", "Les plus forts", "Mais fortes", "Stärkste zuerst",
              "Сначала сильные")
        case .mostToGain:
            t("올릴 게 많은 순", "Most to gain", "上げ幅が大きい順", "Más por ganar", "Le plus à gagner", "Mais a ganhar",
              "Meiste zu gewinnen", "Больше всего прироста")
        case .recentFirst: label(for: CompanionStore.CatchLogSortOption.recentFirst)
        case .numberAsc: sortDexNumberAsc
        case .nameAsc: sortNameAsc
        }
    }
    var dungeonCapsulePickStat: String {
        t("31로 올릴 개체값을 고르세요", "Pick the IV to raise to 31", "31にする個体値をえらんでね",
          "Elige el IV que subir a 31", "Choisis l'IV à monter à 31", "Escolha o IV a subir para 31",
          "Wähle den DV, der auf 31 steigt", "Выбери IV, который поднять до 31")
    }
    var dungeonCapsuleRaiseAll: String {
        t("모두 31로", "All to 31", "すべて31に", "Todo a 31", "Tout à 31", "Tudo para 31", "Alle auf 31", "Все до 31")
    }
    /// A Silver Capsule just used: this IV at 31, the others still to raise.
    func dungeonCapsuleStatRaised(_ stat: String) -> String {
        t("\(stat) 개체값을 31로 올렸어요", "\(stat) IV raised to 31", "\(stat)の個体値を31にしました", "\(stat): IV subido a 31",
          "\(stat) : IV monté à 31", "\(stat): IV elevado a 31", "\(stat)-DV auf 31 erhöht", "\(stat): IV поднят до 31")
    }
    /// A Pokémon whose six IVs are at 31: nothing for a Capsule to raise.
    var dungeonCapsuleAllMaxed: String {
        t("개체값이 이미 모두 31이에요", "Its IVs are all at 31 already", "個体値はもうぜんぶ31です", "Sus IV ya están todos a 31",
          "Ses IV sont déjà tous à 31", "Seus IVs já estão todos em 31", "Seine DV sind schon alle auf 31",
          "Все IV уже на 31")
    }
    func dungeonCapsuleNoneLeft(_ item: String) -> String {
        t("남은 \(item)이 없어요", "No \(item) left", "\(item)がもうありません", "No te queda ninguna \(item)",
          "Plus de \(item)", "Nenhuma \(item) restante", "Keine \(item) mehr", "Больше нет: \(item)")
    }
    var dungeonCapsuleDone: String {
        t("개체값을 31로 올렸어요", "IVs raised to 31", "個体値を31にしました", "IV subidos a 31", "IV montés à 31",
          "IVs elevados a 31", "DV auf 31 erhöht", "IV подняты до 31")
    }
    var dungeonEggShiny: String {
        t("이로치 확정", "Shiny guaranteed", "色違い確定", "Variocolor asegurado", "Chromatique garanti", "Brilhante garantido",
          "Schillernd garantiert", "Гарантированно шайни")
    }

    /// A Dungeons medal's step: its dungeon, or the whole tier.
    func medalStepName(_ tier: DungeonTier, step: Int) -> String {
        let dungeons = DungeonMedals.dungeons(tier)
        if step <= dungeons.count { return dungeonName(dungeons[step - 1]) }
        return t("T\(tier.rawValue) 전부", "All of T\(tier.rawValue)", "T\(tier.rawValue)すべて", "Todo T\(tier.rawValue)",
                 "Tout T\(tier.rawValue)", "Todo T\(tier.rawValue)", "Ganz T\(tier.rawValue)", "Весь T\(tier.rawValue)")
    }

    /// The places' official names (Q26).
    func dungeonName(_ id: DungeonID) -> String {
        switch id {
        case .daily: t("오늘의 던전", "Daily dungeon", "今日のダンジョン", "Mazmorra del día", "Donjon du jour", "Masmorra do dia",
                       "Tages-Dungeon", "Подземелье дня")
        case .weekly: t("이번 주 던전", "Weekly dungeon", "今週のダンジョン", "Mazmorra de la semana", "Donjon de la semaine",
                        "Masmorra da semana", "Wochen-Dungeon", "Подземелье недели")
        case .viridianForest: t("상록숲", "Viridian Forest", "トキワのもり", "Bosque Verde", "Forêt de Jade",
                                "Floresta de Viridian", "Vertania-Wald", "Виридиан-лес")
        case .diglettsCave: t("디그다굴", "Diglett's Cave", "ディグダのあな", "Cueva Diglett", "Grotte Taupiqueur",
                              "Caverna do Diglett", "Digda-Höhle", "Пещера Диглетта")
        case .mtMoon: t("달맞이산", "Mt. Moon", "おつきみやま", "Mt. Moon", "Mont Sélénite", "Monte Lua", "Mondberg",
                        "Гора Луны")
        case .mtEmber: t("불꽃산", "Mt. Ember", "ともしびやま", "Monte Ascuas", "Mont Braise", "Monte Brasa", "Glutberg",
                         "Гора Эмбер")
        case .victoryRoad: t("챔피언로드", "Victory Road", "チャンピオンロード", "Calle Victoria", "Route Victoire",
                             "Estrada Vitória", "Siegesstraße", "Дорога победы")
        case .pokemonTower: t("포켓몬타워", "Pokémon Tower", "ポケモンタワー", "Torre Pokémon", "Tour Pokémon",
                              "Torre Pokémon", "Pokémon-Turm", "Покемон-башня")
        case .dragonsDen: t("용의굴", "Dragon's Den", "りゅうのあな", "Guarida Dragón", "Antre du Dragon",
                            "Covil do Dragão", "Drachenhöhle", "Логово дракона")
        case .powerPlant: t("무인발전소", "Power Plant", "むじんはつでんしょ", "Central Energía", "Centrale",
                            "Usina de Energia", "Kraftwerk", "Электростанция")
        case .seafoamIslands: t("쌍둥이섬", "Seafoam Islands", "ふたごじま", "Islas Espuma", "Îles Écume",
                                "Ilhas Seafoam", "Seeschauminseln", "Острова Сифоум")
        case .ceruleanCave: t("블루시티동굴", "Cerulean Cave", "ハナダのどうくつ", "Cueva Celeste", "Caverne Azurée",
                              "Caverna Celeste", "Azuria-Höhle", "Церулинская пещера")
        case .mtCoronet: t("천관산", "Mt. Coronet", "テンガンざん", "Monte Corona", "Mont Couronné", "Monte Coronet",
                           "Kraterberg", "Гора Коронет")
        case .ruinsOfAlph: t("알프의 유적", "Ruins of Alph", "アルフのいせき", "Ruinas Alfa", "Ruines d'Alpha",
                             "Ruínas de Alfa", "Alph-Ruinen", "Руины Альфа")
        case .hallOfOrigin: t("시작의 방", "Hall of Origin", "はじまりのま", "Sala del Origen", "Salle Originelle",
                              "Salão da Origem", "Saal des Ursprungs", "Зал Истоков")
        case .skullHideout, .magmaHideout, .aquaHideout, .galacticHideout, .rocketHideout:
            villainHideoutName(id.villain ?? .rocket)
        }
    }
}

// MARK: Home during an expedition, the dungeon eggs' names (02/11 review)

extension L {
    /// A dungeon egg by the Pokémon it hatches ("Mewtwo Egg"), never "dungeon egg": where it came from goes without saying.
    func eggOf(_ name: String) -> String {
        let vowel = name.first.map { "AEIOUYÉÈÊÂÎÔaeiouyéèêâîô".contains($0) } ?? false
        return t("\(name)의 알", "\(name) Egg", "\(name)のタマゴ", "Huevo de \(name)", vowel ? "Œuf d'\(name)" : "Œuf de \(name)",
                 "Ovo de \(name)", "\(name)-Ei", "Яйцо: \(name)")
    }

    /// A secret boss's egg: the Secret Egg, its Pokémon written (the owner: "même si on sait ce qu'il y a dedans").
    func secretEggOf(_ name: String) -> String {
        t("비밀의 알 · \(name)", "Secret Egg · \(name)", "ひみつのタマゴ・\(name)", "Huevo secreto · \(name)",
          "Œuf secret · \(name)", "Ovo secreto · \(name)", "Geheimes Ei · \(name)", "Тайное яйцо · \(name)")
    }

    /// What is going on while the team explores, said once at the top of its card.
    var dungeonExploringNow: String {
        t("팀이 탐험 중이에요. 쓰는 토큰만큼 앞으로 나아가요.", "Your team is exploring: every token you spend moves it on.",
          "チームが探検中。使ったトークンのぶんだけ先へ進みます。", "Tu equipo explora: cada token que gastas lo hace avanzar.",
          "Ton équipe explore : chaque token dépensé la fait avancer.", "Sua equipe explora: cada token gasto a faz avançar.",
          "Dein Team erkundet: Jeder verbrauchte Token bringt es weiter.",
          "Ваша команда исследует: каждый потраченный токен продвигает её вперёд.")
    }

    func dungeonBossAt(_ floor: Int) -> String {
        t("보스: \(floor)층", "Boss on floor \(floor)", "ボス：\(floor)階", "Jefe en el piso \(floor)", "Boss à l'étage \(floor)",
          "Chefe no andar \(floor)", "Boss auf Ebene \(floor)", "Босс на этаже \(floor)")
    }

    func dungeonLeftToBoss(_ tokens: String) -> String {
        t("보스까지 \(tokens) 남음", "\(tokens) left to the boss", "ボスまであと\(tokens)", "Faltan \(tokens) hasta el jefe",
          "Encore \(tokens) avant le boss", "Faltam \(tokens) até o chefe", "Noch \(tokens) bis zum Boss", "До босса ещё \(tokens)")
    }

    var dungeonTeamTitle: String { t("팀", "Team", "チーム", "Equipo", "Équipe", "Equipe", "Team", "Команда") }

    var dungeonRecentTitle: String {
        t("최근 일지", "Latest events", "最近のできごと", "Últimos sucesos", "Derniers événements", "Últimos eventos",
          "Letzte Ereignisse", "Последние события")
    }

    /// Under the Pokémon raised, shrunk to a strip while its growth waits for the team.
    var companionPausedForExpedition: String {
        t("팀이 돌아올 때까지 일시정지", "Paused until the team is back", "チームが戻るまで一時停止",
          "En pausa hasta que vuelva el equipo", "En pause jusqu'au retour de l'équipe", "Em pausa até a equipe voltar",
          "Pausiert, bis das Team zurück ist", "На паузе до возвращения команды")
    }

    /// The team screen's guidance: how to fill the team, then how to set a member's moves.
    func dungeonTeamPickHint(compose: String) -> String {
        t("규칙에 맞는 졸업 포켓몬을 눌러 팀을 꾸리거나 \"\(compose)\"를 눌러요. 다시 누르면 빠져요.",
          "Click graduated Pokémon that fit the rules to build the team, or use \"\(compose)\". Click again to remove one.",
          "ルールに合う卒業ポケモンを押してチームを組むか、\"\(compose)\"を押そう。もう一度押すと外れます。",
          "Pulsa Pokémon graduados que cumplan las reglas para formar el equipo, o usa \"\(compose)\". Púlsalo otra vez para quitarlo.",
          "Clique sur des Pokémon diplômés qui respectent les règles pour former l'équipe, ou sur \"\(compose)\". Reclique pour en retirer un.",
          "Clique em Pokémon formados que sigam as regras para montar a equipe, ou use \"\(compose)\". Clique de novo para tirar.",
          "Klicke verabschiedete Pokémon an, die den Regeln entsprechen, oder nutze \"\(compose)\". Erneut klicken entfernt eines.",
          "Нажимайте на выпущенных покемонов по правилам, чтобы собрать команду, или на \"\(compose)\". Повторное нажатие убирает.")
    }

    var dungeonTeamEditHint: String {
        t("팀원을 누르면 그 포켓몬의 기술 4개를 정할 수 있어요.", "Click a team member to set its four moves.",
          "チームのポケモンを押すと、4つのわざを決められます。", "Pulsa un miembro del equipo para elegir sus cuatro movimientos.",
          "Clique sur un membre de l'équipe pour régler ses quatre attaques.", "Clique em um membro da equipe para escolher seus quatro golpes.",
          "Klicke ein Teammitglied an, um seine vier Attacken festzulegen.", "Нажмите на члена команды, чтобы выбрать его четыре приёма.")
    }

    var dungeonTeamIncomplete: String {
        t("팀 미완성", "Team incomplete", "チーム未完成", "Equipo incompleto", "Équipe incomplète", "Equipe incompleta",
          "Team unvollständig", "Команда не собрана")
    }

    /// The Dungeons tab's first line: the whole idea, for a player who never sent a team.
    var dungeonsIntro: String {
        t("졸업한 포켓몬 팀을 보내면, 쓰는 토큰이 팀을 한 층씩 보스까지 데려가요. 그동안 키우는 포켓몬은 쉬어요.",
          "Send a team of graduated Pokémon: the tokens you spend take it floor by floor to the boss, while your Pokémon raised rests.",
          "卒業ポケモンのチームを送り出すと、使ったトークンでボスまで1階ずつ進みます。その間、育てているポケモンはお休み。",
          "Envía un equipo de Pokémon graduados: los tokens que gastas lo llevan piso a piso hasta el jefe, mientras tu Pokémon descansa.",
          "Envoie une équipe de Pokémon diplômés : tes tokens la font avancer étage par étage jusqu'au boss, pendant que ton Pokémon en cours se repose.",
          "Envie uma equipe de Pokémon formados: os tokens gastos a levam andar por andar até o chefe, enquanto seu Pokémon descansa.",
          "Schicke ein Team verabschiedeter Pokémon los: Deine Tokens bringen es Ebene für Ebene zum Boss, während dein Pokémon ruht.",
          "Отправьте команду выпущенных покемонов: потраченные токены ведут её этаж за этажом к боссу, пока ваш покемон отдыхает.")
    }

    /// A dungeon's length in tokens, on its card.
    func dungeonCost(_ tokens: String) -> String {
        t("토큰 \(tokens)", "\(tokens) tokens", "\(tokens)トークン", "\(tokens) de tokens", "\(tokens) de tokens", "\(tokens) de tokens",
          "\(tokens) Tokens", "\(tokens) токенов")
    }

    // MARK: Battle forms

    /// " X", " Y", " Z" for the Megas that come in two or three.
    private func megaSuffix(_ form: BattleForm) -> String {
        for letter in ["x", "y", "z"] where form.form.rawValue.hasSuffix("mega-\(letter)") { return " " + letter.uppercased() }
        return ""
    }

    /// A battle form alone, in a picker beside the species' other forms ("Mega X", "Gigantamax").
    func battleFormLabel(_ form: BattleForm) -> String {
        let x = megaSuffix(form)
        switch form.kind {
        case .mega: return t("메가\(x)", "Mega\(x)", "メガ\(x)", "Mega\(x)", "Méga\(x)", "Mega\(x)", "Mega\(x)", "Мега\(x)")
        case .gigantamax:
            return t("거다이맥스", "Gigantamax", "キョダイマックス", "Gigamax", "Gigamax", "Gigantamax", "Gigadynamax", "Гигантамакс")
        case .primal: return t("원시회귀", "Primal", "ゲンシカイキ", "Primigenio", "Primo", "Primitivo", "Proto", "Первобытный")
        }
    }

    /// A battle form's own name, the species' in it ("Mega Charizard X", "Gigantamax Pikachu", "Primal Kyogre").
    func battleFormName(_ form: BattleForm, species: String) -> String {
        let x = megaSuffix(form), tight = x.replacingOccurrences(of: " ", with: "")
        switch form.kind {
        case .mega:
            return t("메가\(species)\(tight)", "Mega \(species)\(x)", "メガ\(species)\(tight)", "Mega-\(species)\(x)",
                     "Méga-\(species)\(x)", "Mega \(species)\(x)", "Mega-\(species)\(x)", "Мега-\(species)\(x)")
        case .gigantamax:
            return t("거다이맥스 \(species)", "Gigantamax \(species)", "キョダイマックス\(species)", "\(species) Gigamax",
                     "\(species) Gigamax", "\(species) Gigantamax", "Gigadynamax-\(species)", "Гигантамакс \(species)")
        case .primal:
            return t("원시\(species)", "Primal \(species)", "ゲンシ\(species)", "\(species) Primigenio", "Primo-\(species)",
                     "\(species) Primitivo", "Proto-\(species)", "Первобытный \(species)")
        }
    }

    // MARK: The daily and weekly dungeons

    func dungeonFloors(_ n: Int) -> String {
        t("\(n)층", "\(n) floors", "\(n)階", "\(n) pisos", "\(n) étages", "\(n) andares", "\(n) Ebenen", "Этажей: \(n)")
    }
    /// A challenge card's title on two lines, broken before "du jour" and "la semaine" (the owner, 2026-11-10): the two
    /// cards stand side by side at one height.
    func challengeCardTitle(_ id: DungeonID) -> String {
        id == .weekly
            ? t("이번 주\n던전", "Weekly\ndungeon", "今週の\nダンジョン", "Mazmorra de\nla semana", "Donjon de\nla semaine",
                "Masmorra da\nsemana", "Wochen-\nDungeon", "Подземелье\nнедели")
            : t("오늘의\n던전", "Daily\ndungeon", "今日の\nダンジョン", "Mazmorra\ndel día", "Donjon\ndu jour",
                "Masmorra\ndo dia", "Tages-\nDungeon", "Подземелье\nдня")
    }
    var challengeOneTryADay: String {
        t("하루 한 번", "one try a day", "1日1回", "un intento al día", "une tentative par jour", "uma tentativa por dia",
          "ein Versuch pro Tag", "одна попытка в день")
    }
    var challengeAllWon: String {
        t("졸업한 포켓몬의 형태를 모두 얻었어요. 새로 졸업하면 더 생겨요.",
          "Every form your graduated Pokémon can take is won. New graduations bring more.",
          "卒業したポケモンのすがたはすべて手に入れました。新しく卒業させると増えます。",
          "Ya tienes todas las formas de tus Pokémon graduados. Graduar más trae otras.",
          "Toutes les formes de tes Pokémon diplômés sont gagnées. De nouveaux diplômés en apportent d'autres.",
          "Você já tem todas as formas dos seus Pokémon formados. Novos formados trazem outras.",
          "Alle Formen deiner verabschiedeten Pokémon sind gewonnen. Neue Abschlüsse bringen weitere.",
          "Все формы ваших выпускников получены. Новые выпускники принесут ещё.")
    }
    var challengeTriedToday: String {
        t("오늘은 이미 도전했어요. 내일 새 보스가 나와요.", "Tried today: a new boss tomorrow.", "今日は挑戦済み。明日は新しいボス。",
          "Ya lo intentaste hoy: mañana, un jefe nuevo.", "Déjà tenté aujourd'hui : nouveau boss demain.",
          "Já tentou hoje: amanhã, um chefe novo.", "Heute schon versucht: morgen ein neuer Boss.",
          "Сегодня уже была попытка: завтра новый босс.")
    }
    var challengeHard: String {
        t("어려워요: 한 번뿐이니 최강의 팀으로.", "Hard: one try only, send your best team.", "手ごわい：1回だけなので最強のチームで。",
          "Difícil: un solo intento, envía tu mejor equipo.", "Difficile : une seule tentative, envoie ta meilleure équipe.",
          "Difícil: uma só tentativa, envie sua melhor equipe.", "Schwer: nur ein Versuch, schick dein bestes Team.",
          "Сложно: одна попытка, отправьте лучшую команду.")
    }
    func challengeFormWon(_ form: String) -> String {
        t("새 형태: \(form)", "New form: \(form)", "新しいすがた：\(form)", "Nueva forma: \(form)", "Nouvelle forme : \(form)",
          "Nova forma: \(form)", "Neue Form: \(form)", "Новая форма: \(form)")
    }
    /// The badge of a battle form's line in the catch log.
    var battleFormBadge: String {
        t("전투 형태", "Battle form", "バトルのすがた", "Forma de combate", "Forme de combat", "Forma de batalha", "Kampfform",
          "Боевая форма")
    }
    var battleFormsTitle: String {
        t("전투 형태", "Battle forms", "バトルのすがた", "Formas de combate", "Formes de combat", "Formas de batalha",
          "Kampfformen", "Боевые формы")
    }
    func battleFormsWon(_ won: Int, of total: Int) -> String {
        t("\(battleFormsTitle) \(won)/\(total)", "\(battleFormsTitle) \(won)/\(total)", "\(battleFormsTitle) \(won)/\(total)",
          "\(battleFormsTitle) \(won)/\(total)", "\(battleFormsTitle) \(won)/\(total)", "\(battleFormsTitle) \(won)/\(total)",
          "\(battleFormsTitle) \(won)/\(total)", "\(battleFormsTitle) \(won)/\(total)")
    }
    /// Where a missing battle form is won.
    func battleFormSource(_ form: BattleForm) -> String {
        dungeonName(BattleForms.daily.contains(form) ? .daily : .weekly)
    }
    var battleFormUsual: String {
        t("기본", "Usual", "ふだん", "Habitual", "Habituelle", "Habitual", "Normal", "Обычная")
    }
    var battleFormPickTitle: String {
        t("이 던전에서의 형태", "Form in the dungeons", "ダンジョンでのすがた", "Forma en las mazmorras", "Forme en donjon",
          "Forma nas masmorras", "Form in Dungeons", "Форма в подземельях")
    }

    /// A Battle Forms Medal's step: how many forms it asks for, or all of them.
    func battleFormsMedalStep(_ step: Int) -> String {
        let n = BattleFormsMedal.steps[max(0, min(step, BattleFormsMedal.steps.count) - 1)]
        if step >= BattleFormsMedal.steps.count {
            return t("전부 (\(n))", "All of them (\(n))", "すべて（\(n)）", "Todas (\(n))", "Toutes (\(n))", "Todas (\(n))",
                     "Alle (\(n))", "Все (\(n))")
        }
        return t("형태 \(n)개", "\(n) forms", "すがた\(n)", "\(n) formas", "\(n) formes", "\(n) formas", "\(n) Formen", "Форм: \(n)")
    }

    // Short, for the challenges' half-row cards.
    var challengeTriedShortDay: String {
        t("오늘 도전함", "Tried today", "今日は挑戦済み", "Intentado hoy", "Tenté aujourd'hui", "Tentado hoje", "Heute versucht",
          "Сегодня было")
    }
    var challengeAllWonShort: String {
        t("모두 획득", "All won", "すべて入手", "Todo ganado", "Tout gagné", "Tudo ganho", "Alle gewonnen", "Всё получено")
    }

    var challengeUnderway: String {
        t("진행 중", "Under way", "探検中", "En curso", "En cours", "Em andamento", "Läuft", "Идёт")
    }

    // The challenges' one try, lost or won (the owner, 2026-11-09: a lost daily dungeon shows as such).
    var challengeLostDay: String {
        t("오늘 실패", "Lost today", "今日は失敗", "Fallado hoy", "Raté aujourd'hui", "Falhou hoje", "Heute verloren", "Сегодня провал")
    }
    var challengeWonDay: String {
        t("오늘 성공", "Won today", "今日は成功", "Superado hoy", "Réussi aujourd'hui", "Vencido hoje", "Heute geschafft",
          "Сегодня успех")
    }
    var challengeWonWeek: String {
        t("이번 주 성공", "Won this week", "今週は成功", "Superado esta semana", "Réussi cette semaine", "Vencido esta semana",
          "Diese Woche geschafft", "На этой неделе успех")
    }
    var challengeNextWeek: String {
        t("월요일에 새 보스", "New boss on Monday", "月曜日に新しいボス", "Nuevo jefe el lunes", "Nouveau boss lundi",
          "Novo chefe na segunda", "Am Montag ein neuer Boss", "В понедельник новый босс")
    }
    var challengeWeekWonTip: String {
        t("이번 주 보스를 이겼어요. 월요일에 새 보스가 나와요.", "This week's boss is beaten: a new boss on Monday.",
          "今週のボスは倒しました。月曜日に新しいボスが出ます。", "Jefe de la semana vencido: nuevo jefe el lunes.",
          "Boss de la semaine battu : nouveau boss lundi.", "Chefe da semana vencido: novo chefe na segunda.",
          "Wochenboss besiegt: am Montag ein neuer Boss.", "Босс недели побеждён: в понедельник новый босс.")
    }
    var challengeNextDay: String {
        t("내일 새 보스", "New boss tomorrow", "明日は新しいボス", "Nuevo jefe mañana", "Nouveau boss demain", "Novo chefe amanhã",
          "Morgen ein neuer Boss", "Завтра новый босс")
    }
    // The team screen's filters for the battle forms (2026-11-10).
    var teamFilterMega: String {
        t("메가·원시", "Mega/Primal", "メガ・ゲンシ", "Mega/Primigenia", "Méga/Primo", "Mega/Primitiva", "Mega/Proto", "Мега/первичная")
    }
    var teamFilterGigantamax: String {
        t("거다이맥스", "Gigantamax", "キョダイマックス", "Gigamax", "Gigamax", "Gigamax", "Gigadynamax", "Гигантамакс")
    }
    var challengeTryTomorrow: String {
        t("내일 다시 도전", "Try again tomorrow", "明日また挑戦", "Otro intento mañana", "Nouvel essai demain", "Nova tentativa amanhã",
          "Morgen ein neuer Versuch", "Новая попытка завтра")
    }

    // The expedition under way, at the top of the Dungeons tab (the owner, 2026-11-09: the line did not show).
    var expeditionLive: String {
        t("탐험 진행 중", "Expedition under way", "探検中", "Expedición en curso", "Expédition en cours", "Expedição em andamento",
          "Expedition läuft", "Экспедиция идёт")
    }
    var expeditionWaitsForYou: String {
        t("답을 기다려요", "Waiting for you", "返事を待っています", "Te espera", "Attend ta réponse", "Esperando você",
          "Wartet auf dich", "Ждёт тебя")
    }

    // The battle's journal under its arena.
    var battleLogEnters: String {
        t("등장", "comes in", "登場", "entra", "entre en jeu", "entra", "kommt", "выходит")
    }
    var battleLogMiss: String { t("빗나감", "missed", "はずれ", "falla", "raté", "errou", "verfehlt", "мимо") }
    var battleLogNoEffect: String {
        t("효과 없음", "no effect", "効果なし", "sin efecto", "aucun effet", "sem efeito", "keine Wirkung", "нет эффекта")
    }
    var battleLogFailed: String { t("실패", "failed", "失敗", "falló", "échoue", "falhou", "scheitert", "не вышло") }
}
