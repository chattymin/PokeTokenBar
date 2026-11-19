import Foundation

/// The villains' words (issue #180), in the app's eight languages. A team's name is said with no article to agree with:
/// "Cible : Œuf rare", never "ton Œuf rare".
extension L {
    func villainTeamName(_ team: VillainTeam) -> String {
        switch team {
        case .skull: t("스컬단", "Team Skull", "スカル団", "Team Skull", "Team Skull", "Equipe Skull", "Team Skull", "Команда Скалл")
        case .magma: t("마그마단", "Team Magma", "マグマ団", "Equipo Magma", "Team Magma", "Equipe Magma", "Team Magma", "Команда Магма")
        case .aqua: t("아쿠아단", "Team Aqua", "アクア団", "Equipo Aqua", "Team Aqua", "Equipe Aqua", "Team Aqua", "Команда Аква")
        case .galactic: t("갤럭시단", "Team Galactic", "ギンガ団", "Equipo Galaxia", "Team Galaxie", "Equipe Galáctica",
                          "Team Galaktik", "Команда Галактика")
        case .rocket: t("로켓단", "Team Rocket", "ロケット団", "Team Rocket", "Team Rocket", "Equipe Rocket", "Team Rocket", "Команда R")
        }
    }

    func villainLeaderName(_ team: VillainTeam) -> String {
        switch team {
        case .skull: t("구즈마", "Guzma", "グズマ", "Guzmán", "Guzma", "Guzma", "Bromley", "Гузма")
        case .magma: t("마적", "Maxie", "マツブサ", "Magno", "Max", "Maxie", "Marc", "Макси")
        case .aqua: t("아강", "Archie", "アオギリ", "Aquiles", "Arthur", "Archie", "Adrian", "Арчи")
        case .galactic: t("태홍", "Cyrus", "アカギ", "Helio", "Hélio", "Cyrus", "Zyrus", "Сайрус")
        case .rocket: t("비주기", "Giovanni", "サカキ", "Giovanni", "Giovanni", "Giovanni", "Giovanni", "Джованни")
        }
    }

    func villainAmbushTitle(_ team: VillainTeam) -> String {
        let n = villainTeamName(team)
        return t("\(n)의 도둑질!", "Stolen by \(n)!", "\(n)に盗まれた！", "¡Robo: \(n)!", "Vol : \(n) !", "Roubo: \(n)!",
                 "Diebstahl: \(n)!", "Кража: \(n)!")
    }

    /// The notification: they took it as they came (the owner, 2026-11-10).
    func villainStoleLine(_ team: VillainTeam, item: String) -> String {
        t("가방에서 훔쳐 갔어요: \(item).", "They stole from your Bag: \(item).", "バッグから盗まれました：\(item)。",
          "Te han robado de la bolsa: \(item).", "Ils t'ont volé dans ton sac : \(item).", "Roubaram da sua bolsa: \(item).",
          "Aus deinem Beutel gestohlen: \(item).", "Из вашей сумки украли: \(item).")
    }

    /// The bubble's words before the chase: the item is shown under them, its name said once.
    var villainAmbushBubble: String {
        t("가방에서 이걸 훔쳐 갔어요! 아지트에 숨기기 전에 붙잡으세요.", "They stole this from your Bag! Catch them before they hide it.",
          "バッグからこれを盗まれました！アジトに隠される前に追いかけましょう。",
          "¡Te han robado esto de la bolsa! Atrápalos antes de que lo escondan.",
          "Ils t'ont volé ça dans ton sac ! Rattrape-les avant qu'ils le cachent dans leur repaire.",
          "Roubaram isto da sua bolsa! Pegue-os antes que escondam.",
          "Sie haben das aus deinem Beutel gestohlen! Fang sie, bevor sie es verstecken.",
          "У вас украли это из сумки! Догоните их, пока не спрятали.")
    }

    var villainTheirPokemon: String {
        t("그들의 포켓몬", "Their Pokémon", "相手のポケモン", "Sus Pokémon", "Leurs Pokémon", "Os Pokémon deles", "Ihre Pokémon",
          "Их покемоны")
    }
    var villainDefend: String {
        t("뒤쫓기", "Catch them", "追いかける", "Atraparlos", "Les rattraper", "Pegá-los", "Hinterher", "Догнать")
    }
    var villainDefendWith: String {
        t("내 팀이 뒤쫓아요. 지면 아이템은 아지트에 남아요.", "Your team gives chase; lose and the item stays at their hideout.",
          "マイチームが追いかけます。負けると、どうぐはアジトに残ります。",
          "Tu equipo los persigue; si pierde, el objeto se queda en su guarida.",
          "Ton équipe les poursuit ; si elle perd, l'objet reste dans leur repaire.",
          "Sua equipe os persegue; se perder, o item fica no esconderijo.",
          "Dein Team verfolgt sie; verliert es, bleibt das Item in ihrem Versteck.",
          "Ваша команда в погоне; проиграете, и предмет останется в логове.")
    }
    var villainLater: String {
        t("나중에", "Later", "あとで", "Más tarde", "Plus tard", "Mais tarde", "Später", "Позже")
    }

    func villainBeaten(_ team: VillainTeam, item: String) -> String {
        let n = villainTeamName(team)
        return t("\(KoreanParticle.subject.attach(to: n)) 날아가 버렸다! 되찾았어요: \(item).",
                 "\(n) is blasting off again! You got back: \(item).",
                 "\(n)は 飛んでいった！取り返しました：\(item)。", "¡\(n) sale volando otra vez! Has recuperado: \(item).",
                 "\(n) s'envole vers d'autres cieux ! Tu as récupéré : \(item).", "\(n) decolando outra vez! Você recuperou: \(item).",
                 "\(n) fliegt davon! Zurückgeholt: \(item).", "\(n) улетает прочь! Вы вернули: \(item).")
    }

    /// Giovanni, when the player gives chase to Team Rocket, which is never caught (the owner, 2026-11-19).
    var villainRocketTaunt: String {
        t("하하하하... 정말 나를 이길 수 있다고 생각하나? 내 아지트로 찾아와라.",
          "Hahahaha... You really think you can beat me? Come and see me at my place.",
          "ハハハハ…本気でわたしに勝てると思っているのか？わたしのアジトまで来るがいい。",
          "Jajajaja... ¿De verdad crees que puedes vencerme? Ven a verme a mi guarida.",
          "Hahahaha... Tu crois vraiment pouvoir me battre ? Viens donc me voir chez moi.",
          "Hahahaha... Você acha mesmo que pode me vencer? Venha me ver no meu esconderijo.",
          "Hahahaha... Glaubst du wirklich, du kannst mich schlagen? Komm mich in meinem Versteck besuchen.",
          "Ха-ха-ха-ха... Ты правда думаешь, что можешь меня победить? Приходи ко мне в убежище.")
    }

    func villainGotAway(_ team: VillainTeam, item: String) -> String {
        let n = villainTeamName(team)
        return t("\(KoreanParticle.subject.attach(to: n)) 도망쳤어요: \(item). 던전 탭의 아지트에서 되찾으세요.",
                 "\(n) got away with: \(item). Take it back at their hideout, in Dungeons.",
                 "\(n)に逃げられました：\(item)。ダンジョンのアジトで取り返しましょう。",
                 "\(n) ha escapado con: \(item). Recupéralo en su guarida, en Mazmorras.",
                 "\(n) s'est enfuie avec : \(item). Reprends-le dans son repaire, onglet Donjons.",
                 "\(n) fugiu com: \(item). Recupere no esconderijo, em Masmorras.",
                 "\(n) ist damit entkommen: \(item). Hol es dir in ihrem Versteck zurück, unter Dungeons.",
                 "\(n) скрылась с добычей: \(item). Верните её в логове, во вкладке подземелий.")
    }

    var villainSeeFight: String {
        t("전투 다시 보기", "Watch the fight", "バトルを見る", "Ver el combate", "Revoir le combat", "Ver a batalha", "Kampf ansehen",
          "Смотреть бой")
    }
    var villainToHideout: String {
        t("아지트로", "To the hideout", "アジトへ", "A la guarida", "Aller au repaire", "Ir ao esconderijo", "Zum Versteck", "В логово")
    }

    func villainHideoutName(_ team: VillainTeam) -> String {
        let n = villainTeamName(team)
        return t("\(n) 아지트", "\(n) Hideout", "\(n)のアジト", "Guarida: \(n)", "Repaire de la \(n)", "Esconderijo: \(n)",
                 "Versteck: \(n)", "Логово: \(n)")
    }

    var villainKeeps: String {
        t("빼앗긴 것", "They keep", "奪われたもの", "Se quedan con", "Ils gardent", "Eles guardam", "Sie behalten", "У них")
    }

    func villainWaitsAtTheEnd(_ team: VillainTeam) -> String {
        let n = villainLeaderName(team)
        return t("끝에서 \(KoreanParticle.subject.attach(to: n)) 포켓몬 3마리와 기다려요.", "\(n) waits at the end with three Pokémon.",
                 "最後に\(n)がポケモン3匹と待っています。", "\(n) espera al final con tres Pokémon.",
                 "\(n) t'attend au bout avec trois Pokémon.", "\(n) espera no fim com três Pokémon.",
                 "\(n) wartet am Ende mit drei Pokémon.", "В конце ждёт \(n) с тремя покемонами.")
    }

    var villainTakenBack: String {
        t("되찾은 것", "Taken back", "取り返したもの", "Recuperado", "Récupéré", "Recuperado", "Zurückgeholt", "Возвращено")
    }

    var villainAbandon: String {
        t("포기하기", "Give up", "あきらめる", "Renunciar", "Abandonner", "Desistir", "Aufgeben", "Отказаться")
    }
    var villainAbandonConfirm: String {
        t("영영 잃어요. 아티팩트는 남아요.", "Lost for good; the artifacts stay to win back.", "ずっとうしないます。アーティファクトは残ります。",
          "Se pierde para siempre; los artefactos se quedan por recuperar.", "Perdu pour de bon ; les artefacts restent à récupérer.",
          "Perdido para sempre; os artefatos continuam a recuperar.", "Für immer verloren; die Artefakte bleiben zurückzuholen.",
          "Потеряно навсегда; артефакты остаются, их можно вернуть.")
    }
    var villainAbandonHint: String {
        t("빼앗긴 것을 포기해요(아티팩트 제외). 비면 아지트가 닫혀요.", "Give up what they took, the artifacts aside; the hideout closes once empty.",
          "うばわれたものをあきらめます（アーティファクトはのぞく）。空になるとアジトは閉じます。",
          "Renuncia a lo que se llevaron, salvo los artefactos; la guarida se cierra al quedar vacía.",
          "Abandonne ce qu'ils ont pris, sauf les artefacts ; le repaire ferme une fois vide.",
          "Desista do que levaram, exceto os artefatos; o esconderijo fecha quando vazio.",
          "Gib auf, was sie genommen haben, außer Artefakten; das Versteck schließt, sobald es leer ist.",
          "Откажитесь от украденного, кроме артефактов; логово закроется, когда опустеет.")
    }
}
