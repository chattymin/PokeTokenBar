import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `companion.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    func t(_ ko: String, _ en: String, _ ja: String, _ es: String, _ fr: String, _ pt: String, _ de: String) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        case .es: return es
        case .fr: return fr
        case .pt: return pt
        case .de: return de
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム", "Inicio", "Accueil", "Início", "Startseite") }
    var quests: String { t("퀘스트", "Quests", "クエスト", "Misiones", "Quêtes", "Missões", "Quests") }
    /// 상위 탭 이름 — 안에서 도감/포획 로그를 세그먼트로 전환하므로 둘을 아우르는 말이어야 한다.
    /// (ko 가 "도감"이면 탭과 세그먼트가 같은 이름이 돼 en/ja 의 Collection/コレクション 과도 어긋난다.)
    var collection: String { t("컬렉션", "Collection", "コレクション", "Colección", "Collection", "Coleção", "Sammlung") }

    var costUnavailable: String { t("계산 불가", "Unavailable", "計算不可", "No disponible", "Indisponible", "Indisponível", "Nicht verfügbar") }
    var costEstimateHint: String { t("모델 단가로 환산한 추정 비용입니다. 구독료나 실제 청구액이 아닙니다.", "Estimated from model token rates; not a subscription fee or invoice. Service-tier and other unlogged charges are excluded.", "モデル単価による推定です。購読料や実際の請求額ではありません。", "Estimación por tarifas del modelo; no es la cuota ni la factura real.", "Estimation selon les tarifs du modèle, pas un abonnement ni une facture.", "Estimativa pelas tarifas do modelo; não é assinatura nem fatura.", "Schätzung anhand der Modellpreise, keine Abogebühr oder Rechnung.") }
    var costReportedHint: String { t("도구가 기록한 비용입니다. 실제 청구액과 다를 수 있습니다.", "Cost recorded by the tool; it may differ from the actual bill.", "ツールが記録したコストです。実際の請求額とは異なる場合があります。", "Coste registrado por la herramienta; puede diferir de la factura.", "Coût enregistré par l’outil, pouvant différer de la facture.", "Custo registrado pela ferramenta; pode diferir da fatura.", "Vom Tool gemeldete Kosten; die Rechnung kann abweichen.") }
    var costUnavailableHint: String { t("비용 기록이나 확인된 단가·토큰 구분이 없어 계산할 수 없습니다.", "No usable cost record or verified model rate and token breakdown is available.", "コスト記録、確認済み単価、またはトークン内訳がないため計算できません。", "Faltan el coste, la tarifa verificada o el desglose de tokens.", "Coût, tarif vérifié ou détail des tokens indisponible.", "Faltam custo, tarifa verificada ou detalhamento de tokens.", "Kostenangabe, bestätigter Preis oder Token-Aufteilung fehlen.") }
    var costPartialHint: String { t("일부 사용량은 계산할 수 없어 제외했습니다. 표시 금액은 계산 가능한 부분의 합계이며 청구액이 아닙니다.", "Some usage could not be priced and is excluded. This is the known portion of usage cost, not an invoice.", "計算できない使用量を除いた部分合計です。請求額ではありません。", "Total parcial: excluye uso sin precio; no es una factura.", "Total partiel hors usage non chiffrable, pas une facture.", "Total parcial sem o uso não calculável; não é uma fatura.", "Teilsumme ohne nicht berechenbare Nutzung, keine Rechnung.") }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour", "Tokens de hoje", "Heute verbrauchte Tokens") }
    var thisWeek: String { t("이번 주", "This week", "今週", "Esta semana", "Cette semaine", "Esta semana", "Diese Woche") }
    var thisMonth: String { t("이번 달", "This month", "今月", "Este mes", "Ce mois-ci", "Este mês", "Dieser Monat") }
    /// 일별 추이 막대 행의 제목. 범위가 "이번 달"임을 문구에 담는다 — 롤링 30일로 읽히면 안 된다.
    /// de 는 "Täglich diesen Monat" 이 캡션 폭을 넘겨 줄바꿈된다(실측 79.5pt vs 66.5pt) →
    /// `weekly` 의 fr "Hebdo" 와 같은 이유로 줄인다. 바로 위 줄이 "Dieser Monat" 이라 문맥은 남는다.
    var dailyTrend: String { t("이번 달 일별", "Daily this month", "今月の日別",
                               "Diario de este mes", "Par jour ce mois-ci", "Diário deste mês",
                               "Täglich") }
    /// 추이의 최댓값 라벨 — 막대 높이가 상대값이라 절대 스케일을 한 군데는 적어줘야 한다.
    var peakDay: String { t("최다", "Peak", "最多", "Máx.", "Max.", "Máx.", "Max.") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）", "Límites (oficial)", "Limites (officiel)", "Limites (oficiais)", "Limits (offiziell)") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション", "Sesión de 5 horas", "Session de 5 h", "Sessão de 5 horas", "5-Stunden-Sitzung") }
    var weekly: String { t("주간", "Weekly", "週間", "Semanal", "Hebdo", "Semanal", "Wöchentlich") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus", "Opus semanal", "Opus hebdo", "Opus semanal", "Opus – wöchentlich") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet", "Sonnet semanal", "Sonnet hebdo", "Sonnet semanal", "Sonnet – wöchentlich") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック", "Bloque actual de 5h de Claude", "Bloc 5 h actuel de Claude", "Bloco atual de 5h do Claude", "Aktueller 5-Stunden-Block von Claude") }
    var reset: String { t("리셋", "Reset", "リセット", "Reinicio", "Réinit.", "Renovação", "Zurücksetzen") }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達", "Límite alcanzado", "Limite atteinte", "Limite atingido", "Limit erreicht") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限", "Límite de gasto personal", "Limite de dépense personnelle", "Limite de gasto pessoal", "Persönliches Ausgabenlimit") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延", "Desactualizado", "Périmé", "Desatualizado", "Nicht aktuell") }
    var refresh: String { t("갱신", "Refresh", "更新", "Actualizar", "Actualiser", "Atualizar", "Aktualisieren") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む", "Cargar límites oficiales", "Charger les limites officielles", "Carregar limites oficiais", "Offizielle Limits laden") }

    /// 프로바이더 상태 페이지 인시던트 지표 → 현지화 라벨(표시 전용).
    func providerStatusLabel(_ indicator: ProviderStatusIndicator) -> String {
        switch indicator {
        case .operational: return t("정상", "Operational", "正常", "Operativo", "Opérationnel", "Operacional", "Betriebsbereit")
        case .minor:       return t("일부 장애", "Minor issues", "一部障害", "Problemas menores", "Problèmes mineurs", "Problemas menores", "Kleinere Störungen")
        case .major:       return t("장애", "Major outage", "障害", "Interrupción grave", "Panne majeure", "Interrupção grave", "Großer Ausfall")
        case .critical:    return t("심각한 장애", "Critical outage", "重大障害", "Interrupción crítica", "Panne critique", "Interrupção crítica", "Kritischer Ausfall")
        case .maintenance: return t("점검 중", "Maintenance", "メンテナンス", "Mantenimiento", "Maintenance", "Manutenção", "Wartung")
        case .unknown:     return t("상태 불명", "Status unknown", "状態不明", "Estado desconocido", "État inconnu", "Status desconhecido", "Status unbekannt")
        }
    }
    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)", "Plan \(p)", "Forfait \(p)", "Plano \(p)", "Tarif \(p)") }
    func limitsAccount(_ a: String) -> String { t("계정 \(a)", "Account \(a)", "アカウント \(a)", "Cuenta \(a)", "Compte \(a)", "Conta \(a)", "Konto \(a)") }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達", "Al ritmo actual, límite alcanzado a las \(time)", "À ce rythme, limite atteinte à \(time)", "No ritmo atual, limite atingido às \(time)", "Bei diesem Tempo erreichst du das Limit um \(time)")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし", "Al ritmo actual, no alcanzarás el límite antes del reinicio", "À ce rythme, tu n'atteindras pas la limite avant la réinit.", "No ritmo atual, você não vai bater o limite antes da renovação", "Bei diesem Tempo erreichst du das Limit nicht vor dem Zurücksetzen")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）", "Semanal (por modelo)", "Hebdo (par modèle)", "Semanal (por modelo)", "Wöchentlich (pro Modell)") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)", "Semanal \(model)", "Hebdo \(model)", "Semanal \(model)", "\(model) – wöchentlich")
        default:
            let base = kind ?? "limit"
            let name = model.map { " \($0)" } ?? ""
            return base.replacingOccurrences(of: "_", with: " ") + name
        }
    }

    /// Codex 한도 윈도우 이름 (windowDurationMins 기반). 알림·팝오버 공통.
    func codexWindow(_ mins: Int?) -> String {
        switch mins {
        case 300: return fiveHourSession
        case 10_080: return weekly
        case let m? where m >= 60 && m % 60 == 0:
            let h = m / 60
            return t("\(h)시간", "\(h)h", "\(h)時間", "\(h)h", "\(h) h", "\(h)h", "\(h) Std.")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分", "\(m)m", "\(m) min", "\(m) min", "\(m) Min.")
        case nil: return t("한도", "Limit", "上限", "Límite", "Limite", "Limite", "Limit")
        }
    }

    /// Antigravity 한도 그룹 및 윈도우 이름
    var antigravityGeminiGroup: String { t("Gemini 모델군", "Gemini Models", "Gemini モデル群", "Modelos Gemini", "Modèles Gemini", "Modelos Gemini", "Gemini-Modelle") }
    var antigravityThirdPartyGroup: String { t("Claude & GPT 모델군", "Claude & GPT Models", "Claude & GPT モデル群", "Modelos Claude y GPT", "Modèles Claude et GPT", "Modelos Claude e GPT", "Claude- & GPT-Modelle") }
    func antigravityWindow(window: String?, bucketId: String) -> String {
        if window == "5h" || bucketId.contains("5h") {
            return fiveHourSession
        }
        if window == "weekly" || bucketId.contains("weekly") {
            return weekly
        }
        return t("한도", "Limit", "上限", "Límite", "Limite", "Limite", "Limit")
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新", "Actualizar ahora", "Actualiser maintenant", "Atualizar agora", "Jetzt aktualisieren") }
    var updated: String { t("갱신", "Updated", "更新", "Actualizado", "Mis à jour", "Atualizado", "Aktualisiert") }
    var settings: String { t("설정", "Settings", "設定", "Ajustes", "Réglages", "Ajustes", "Einstellungen") }
    var tokenInput: String { t("입력", "Input", "入力", "Entrada", "Entrée", "Entrada", "Eingabe") }
    var tokenOutput: String { t("출력", "Output", "出力", "Salida", "Sortie", "Saída", "Ausgabe") }
    var tokenCacheWrite: String { t("캐시 쓰기", "Cache write", "キャッシュ書込", "Escritura caché", "Écriture cache", "Gravação cache", "Cache schreiben") }
    var tokenCacheRead: String { t("캐시 읽기", "Cache read", "キャッシュ読込", "Lectura caché", "Lecture cache", "Leitura cache", "Cache lesen") }
    var website: String { t("웹사이트", "Website", "ウェブサイト", "Sitio web", "Site web", "Site", "Website") }
    var sponsor: String { t("후원", "Sponsor", "支援", "Apoyar", "Soutenir", "Apoiar", "Unterstützen") }
    var evolutionScrollPrevious: String { t("이전 진화 보기", "Show previous evolutions", "前の進化を見る", "Ver evoluciones anteriores", "Voir les évolutions précédentes", "Ver evoluções anteriores", "Vorherige Entwicklungen anzeigen") }
    var evolutionScrollNext: String { t("다음 진화 보기", "Show next evolutions", "次の進化を見る", "Ver evoluciones siguientes", "Voir les évolutions suivantes", "Ver próximas evoluções", "Nächste Entwicklungen anzeigen") }

    var back: String { t("뒤로", "Back", "戻る", "Atrás", "Retour", "Voltar", "Zurück") }
    var generalSectionTitle: String { t("일반", "General", "一般", "General", "Général", "Geral", "Allgemein") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示", "Mostrar en la barra de menús", "Afficher dans la barre des menus", "Mostrar na barra de menus", "In der Menüleiste anzeigen") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細", "Avanzado", "Avancé", "Avançado", "Erweitert") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断", "Avanzado · diagnóstico", "Avancé · diagnostics", "Avançado · diagnóstico", "Erweitert · Diagnose") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート", "Acerca de y soporte", "À propos et assistance", "Sobre e suporte", "Info & Support") }
    var quit: String { t("종료", "Quit", "終了", "Salir", "Quitter", "Encerrar", "Beenden") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔", "Intervalo de actualización", "Intervalle d'actualisation", "Intervalo de atualização", "Aktualisierungsintervall") }
    var language: String { t("언어", "Language", "言語", "Idioma", "Langue", "Idioma", "Sprache") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）", "Elementos de la barra de menús (selección múltiple)", "Éléments de la barre des menus (sélection multiple)", "Itens da barra de menus (seleção múltipla)", "Elemente der Menüleiste (Mehrfachauswahl)") }
    var todayTokensShort: String { t("오늘 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour", "Tokens de hoje", "Heutige Tokens") }
    var todayCost: String { t("오늘 비용 ($)", "Today's cost ($)", "本日のコスト ($)", "Coste de hoy ($)", "Coût du jour ($)", "Custo de hoje ($)", "Heutige Kosten ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %", "Límite %", "Limite %", "Limite %", "Limit %") }
    var animationQualityLabel: String { t("애니메이션", "Animation", "アニメーション", "Animación", "Animation", "Animação", "Animation") }
    var animationQualityHint: String {
        t("부드러울수록 배터리를 더 씁니다", "Smoother uses more battery",
          "滑らかにするとバッテリー消費が増えます", "Más fluido consume más batería",
          "Plus fluide consomme plus de batterie", "Mais fluido consome mais bateria",
          "Flüssigere Animationen verbrauchen mehr Batterie")
    }
    var animationPowerSaver: String { t("배터리 절약", "Power saver", "バッテリー優先", "Ahorro de batería", "Économie d'énergie", "Economia de bateria", "Energiesparmodus") }
    var animationBalanced: String { t("기본", "Balanced", "標準", "Equilibrado", "Équilibré", "Equilibrado", "Ausgewogen") }
    var animationSmooth: String { t("부드럽게", "Smooth", "滑らか", "Fluido", "Fluide", "Fluido", "Flüssig") }
    var limitDisplayModeLabel: String { t("한도 표시 방식", "Limit display", "上限の表示", "Visualización del límite", "Affichage de la limite", "Exibição do limite", "Limit-Anzeige") }
    var limitDisplayUsed: String { t("사용량", "Used", "使用量", "Usado", "Utilisé", "Usado", "Verbraucht") }
    var limitDisplayRemaining: String { t("남은 양", "Remaining", "残量", "Restante", "Restant", "Restante", "Verbleibend") }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        t("\(percent) 남음", "\(percent) left", "残り\(percent)", "\(percent) restante", "\(percent) restant", "\(percent) restante", "\(percent) übrig")
    }
    var allOffHint: String { t("전부 끄면 캐릭터만 표시됩니다", "All off shows only the character", "すべてオフにするとキャラクターのみ表示", "Si desactivas todo, solo se mostrará el personaje", "Tout désactiver n'affiche que le personnage", "Se desativar tudo, só o personagem aparece", "Wenn du alles ausschaltest, wird nur das Pokémon angezeigt") }
    // MARK: 대표 포켓몬
    var representativePokemonLabel: String {
        t("대표 포켓몬", "Representative Pokémon", "代表ポケモン", "Pokémon representativo", "Pokémon représentatif", "Pokémon representativo", "Repräsentatives Pokémon")
    }
    var representativeFollowCurrent: String {
        t("현재 포켓몬 따라가기", "Follow current companion", "現在のポケモンに合わせる", "Seguir al compañero actual", "Suivre le compagnon actuel", "Seguir o companheiro atual", "Aktuellem Begleiter folgen")
    }
    var representativeChooseFromDex: String {
        t("도감에서 선택…", "Choose in Pokédex…", "図鑑で選ぶ…", "Elegir en la Pokédex…", "Choisir dans le Pokédex…", "Escolher na Pokédex…", "Im Pokédex auswählen…")
    }
    var representativeSet: String {
        t("대표로 설정", "Set as representative", "代表ポケモンに設定", "Establecer como representante", "Définir comme représentatif", "Definir como representante", "Als repräsentativ festlegen")
    }
    var representativeBadge: String { t("대표", "Representative", "代表", "Representante", "Représentatif", "Representante", "Repräsentativ") }
    // MARK: 난이도
    var difficultySectionTitle: String { t("난이도", "Difficulty", "難易度", "Dificultad", "Difficulté", "Dificuldade", "Schwierigkeit") }
    var difficultyGrowthLabel: String { t("성장", "Growth", "成長", "Crecimiento", "Croissance", "Crescimento", "Wachstum") }
    var difficultyShopLabel: String { t("상점 가격", "Shop prices", "ショップ価格", "Precios de la tienda", "Prix de la boutique", "Preços da loja", "Shop-Preise") }
    var difficultyHint: String {
        t("기본값 100% 기준이에요 — 낮추면 빨리 자라고 싸지고, 높이면 그 반대예요",
          "Percentages of the default balance — lower grows faster and costs less, higher does the opposite",
          "標準バランスに対する割合です — 下げると早く育ち安くなり、上げるとその逆になります",
          "Porcentajes del balance predeterminado: si los bajas, crece más rápido y cuesta menos; si los subes, al revés",
          "Pourcentages de l'équilibrage par défaut — plus bas, la croissance est plus rapide et les prix baissent ; plus haut, l'inverse",
          "Porcentagens do balanceamento padrão — reduzir faz crescer mais rápido e custar menos; aumentar faz o contrário",
          "Prozentwerte der Standardbalance — niedriger wächst schneller und kostet weniger, höher bewirkt das Gegenteil")
    }
    /// 슬라이더 옆 현재 배율 — 10%~200%, 1.0 = 100%.
    func difficultyValue(_ value: Double) -> String {
        let percent = value * 100
        if percent >= 10 { return String(format: "%.0f%%", percent) }
        if percent >= 1 { return String(format: "%.1f%%", percent) }
        return String(format: "%.2f%%", percent)
    }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット", "Mascota flotante", "Compagnon flottant", "Mascote flutuante", "Schwebendes Pokémon") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示", "Mostrar mascota flotante", "Afficher le compagnon flottant", "Mostrar mascote flutuante", "Schwebendes Pokémon anzeigen") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요 — 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen — drag to reposition",
          "ポケモンが画面の上に浮かびます — ドラッグで移動できます",
          "Tu Pokémon flota sobre la pantalla — arrástralo para moverlo",
          "Ton Pokémon flotte au-dessus de l'écran — fais-le glisser pour le déplacer",
          "Seu Pokémon flutua sobre a tela — arraste para reposicionar",
          "Dein Pokémon schwebt über dem Bildschirm – zieh es an die gewünschte Stelle")
    }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ", "Tamaño", "Taille", "Tamanho", "Größe") }
    /// 푸터 눈 아이콘의 툴팁(켜져 있을 때) — 켜는 쪽 문구는 floatingPetEnableLabel 을 그대로 쓴다.
    var floatingPetHideLabel: String {
        t("플로팅 펫 숨기기", "Hide floating pet", "フローティングペットを隠す", "Ocultar mascota flotante",
          "Masquer le compagnon flottant", "Ocultar mascote flutuante", "Schwebendes Pokémon ausblenden")
    }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示", "Mostrar notificaciones como globos", "Afficher les notifications en bulles", "Mostrar notificações em balões", "Benachrichtigungen als Sprechblasen anzeigen")
    }
    var floatingPetMenuOpen: String { t("토큰 바 열기", "Open Token Bar", "トークンバーを開く", "Abrir Token Bar", "Ouvrir Token Bar", "Abrir o Token Bar", "Token Bar öffnen") }
    var floatingPetMenuHide: String {
        t("플로팅 펫 끄기", "Turn off floating pet", "フローティングペットをオフ", "Desactivar mascota flotante", "Désactiver le compagnon flottant", "Desativar mascote flutuante", "Schwebendes Pokémon ausschalten")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens) 토큰", "Today: \(tokens) tokens", "今日: \(tokens) トークン", "Hoy: \(tokens) tokens", "Aujourd'hui : \(tokens) tokens", "Hoje: \(tokens) tokens", "Heute: \(tokens) Tokens")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) 토큰 (한도 \(percent))",
          "Today: \(tokens) tokens (limit \(percent))",
          "今日: \(tokens) トークン（上限 \(percent)）",
          "Hoy: \(tokens) tokens (límite \(percent))",
          "Aujourd'hui : \(tokens) tokens (limite \(percent))",
          "Hoje: \(tokens) tokens (limite \(percent))",
          "Heute: \(tokens) Tokens (Limit \(percent))")
    }

    var disableKeychain: String { t("Keychain 접근 끄기", "Disable Keychain access", "Keychainアクセスを無効化", "Desactivar acceso a Keychain", "Désactiver l'accès au Keychain", "Desativar acesso ao Keychain", "Keychain-Zugriff deaktivieren") }
    var disableKeychainHint: String { t("켜면 Keychain 접근 허용 팝업이 더 안 뜹니다 — 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, no more Keychain permission pop-ups — only official limits (%) are hidden; tokens/cost stay", "オンにするとKeychain許可のポップアップが出なくなります — 公式上限(%)のみ非表示、トークン・費用はそのまま", "Al activarlo, ya no aparecerán los avisos de permiso de Keychain — solo se ocultan los límites oficiales (%), los tokens y el coste se mantienen", "Une fois activé, plus de pop-ups d'autorisation Keychain — seules les limites officielles (%) sont masquées ; les tokens et le coût restent visibles", "Ao ativar, os avisos de permissão do Keychain não aparecem mais — só os limites oficiais (%) ficam ocultos; tokens e custo continuam", "Wenn aktiviert, erscheinen keine Keychain-Berechtigungsfenster mehr – nur offizielle Limits (%) werden ausgeblendet; Tokens und Kosten bleiben sichtbar") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新", "Actualizar caché del token de límite", "Actualiser le cache du token de limite", "Atualizar cache do token de limite", "Limit-Token-Cache aktualisieren") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요 — 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed — auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます — 自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新", "Solo lee Keychain al pulsar — el sondeo automático nunca lo hace, así que no aparecen avisos. Usa este botón para actualizar los límites tras la expiración del token", "Lit le Keychain uniquement sur appui — le polling automatique ne le fait jamais, donc pas de pop-up. Actualise les limites ici après l'expiration du token", "Só lê o Keychain quando você clica no botão — a atualização automática nunca lê, então não aparecem avisos. Use este botão para atualizar os limites depois que o token expirar", "Keychain wird nur auf Knopfdruck gelesen – die automatische Abfrage greift nicht darauf zu, daher gibt es keine Pop-ups. Aktualisiere die Limits hier, wenn das Token abgelaufen ist") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動", "Iniciar al arrancar sesión", "Lancer à l'ouverture de session", "Abrir ao iniciar sessão", "Bei der Anmeldung starten") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)", "Disponible solo si se instaló como paquete .app (scripts/build-app.sh)", "Disponible uniquement si installé comme paquet .app (scripts/build-app.sh)", "Disponível apenas quando instalado como pacote .app (scripts/build-app.sh)", "Nur verfügbar, wenn die App als .app-Bundle installiert ist (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知", "Notificaciones", "Notifications", "Notificações", "Benachrichtigungen") }
    // MARK: claude.ai 세션 키 (Keychain 프롬프트 없는 한도 경로)
    var sessionKeyLabel: String { t("claude.ai 세션 키", "claude.ai session key", "claude.ai セッションキー", "Clave de sesión de claude.ai", "Clé de session claude.ai", "Chave de sessão do claude.ai", "claude.ai-Sitzungsschlüssel") }
    var sessionKeyHint: String {
        t("Keychain 팝업 없이 공식 한도를 조회합니다. 브라우저 개발자도구 → Application → Cookies → claude.ai → sessionKey 값을 붙여넣으세요.",
          "Fetches official limits with no Keychain pop-up. Paste the value from DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Keychain のポップアップなしで公式上限を取得します。開発者ツール → Application → Cookies → claude.ai → sessionKey の値を貼り付けてください。",
          "Obtiene los límites oficiales sin avisos de Keychain. Pega el valor de DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Récupère les limites officielles sans pop-up Keychain. Colle la valeur depuis DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Busca os limites oficiais sem avisos do Keychain. Cole o valor de DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Ruft offizielle Limits ohne Keychain-Pop-up ab. Füge den Wert aus DevTools → Application → Cookies → claude.ai → sessionKey ein.")
    }
    /// 평문 보관을 숨기지 않는다 — 사용자가 무엇을 맡기는지, 어떻게 취소하는지 알아야 한다.
    var sessionKeyStorageNote: String {
        t("키는 이 Mac 의 앱 폴더에 본인만 읽을 수 있는 파일로 저장됩니다(암호화 아님). 브라우저에서 로그아웃하면 즉시 무효화됩니다.",
          "The key is stored in this Mac's app folder as an owner-only file (not encrypted). Logging out in your browser invalidates it immediately.",
          "キーはこの Mac のアプリフォルダに本人のみ読み取り可能なファイルとして保存されます(暗号化なし)。ブラウザでログアウトすると即時無効になります。",
          "La clave se guarda en la carpeta de la app de este Mac como archivo solo para el propietario (sin cifrar). Al cerrar sesión en el navegador se invalida de inmediato.",
          "La clé est enregistrée dans le dossier de l'app sur ce Mac, en fichier lisible par toi seul (non chiffré). Te déconnecter dans le navigateur l'invalide immédiatement.",
          "A chave fica na pasta do app neste Mac, em um arquivo que só você pode ler (sem criptografia). Sair da conta no navegador a invalida na hora.",
          "Der Schlüssel liegt im App-Ordner dieses Macs in einer Datei, die nur du lesen kannst (unverschlüsselt). Meldest du dich im Browser ab, wird er sofort ungültig.")
    }
    var sessionKeySaved: String { t("설정됨", "Saved", "設定済み", "Guardada", "Enregistrée", "Salva", "Gespeichert") }
    var save: String { t("저장", "Save", "保存", "Guardar", "Enregistrer", "Salvar", "Speichern") }
    var delete: String { t("삭제", "Delete", "削除", "Eliminar", "Supprimer", "Excluir", "Löschen") }
    var sessionKeyOrganizationLabel: String { t("조직", "Organization", "組織", "Organización", "Organisation", "Organização", "Organisation") }
    var sessionKeyMalformedError: String {
        t("세션 키 형식이 아닙니다. sessionKey 쿠키 값 전체를 붙여넣었는지 확인하세요(sk-ant- 로 시작).",
          "That isn't a session key. Check you pasted the whole sessionKey cookie value (starts with sk-ant-).",
          "セッションキーの形式ではありません。sessionKey クッキーの値全体を貼り付けたか確認してください(sk-ant- で始まります)。",
          "Eso no es una clave de sesión. Comprueba que pegaste todo el valor de la cookie sessionKey (empieza por sk-ant-).",
          "Ce n'est pas une clé de session. Vérifie que tu as collé toute la valeur du cookie sessionKey (elle commence par sk-ant-).",
          "Isso não é uma chave de sessão. Confira se você colou todo o valor do cookie sessionKey (começa com sk-ant-).",
          "Das ist kein Sitzungsschlüssel. Prüfe, ob du den vollständigen Wert des sessionKey-Cookies eingefügt hast (beginnt mit sk-ant-).")
    }
    var sessionKeyExpiredError: String {
        t("세션 키가 만료됐습니다. 브라우저에서 다시 복사해 붙여넣으세요.",
          "The session key expired. Copy a fresh one from your browser and paste it again.",
          "セッションキーの有効期限が切れました。ブラウザから再度コピーして貼り付けてください。",
          "La clave de sesión caducó. Copia una nueva desde el navegador y pégala otra vez.",
          "La clé de session a expiré. Copie-en une nouvelle depuis le navigateur et colle-la à nouveau.",
          "A chave de sessão expirou. Copie uma nova do navegador e cole de novo.",
          "Der Sitzungsschlüssel ist abgelaufen. Kopiere einen neuen aus deinem Browser und füge ihn erneut ein.")
    }
    var sessionKeyNoOrgError: String {
        t("이 키로 한도를 볼 수 있는 조직이 없습니다.",
          "No organization on this key can show limits.",
          "このキーで上限を確認できる組織がありません。",
          "Ninguna organización de esta clave puede mostrar límites.",
          "Aucune organisation liée à cette clé ne peut afficher de limites.",
          "Nenhuma organização desta chave pode mostrar limites.",
          "Keine Organisation dieses Schlüssels kann Limits anzeigen.")
    }

    // MARK: 세션 키 만료 안내 — OAuth 만료와 처방이 다르므로 문구·행동을 따로 둔다
    var sessionKeyExpiredTitle: String {
        t("claude.ai 세션 키 만료 — 한도가 갱신 안 돼요",
          "claude.ai session key expired — limits aren't refreshing",
          "claude.ai セッションキーの期限切れ — 上限が更新されません",
          "La clave de sesión de claude.ai caducó: los límites no se actualizan",
          "Clé de session claude.ai expirée — les limites ne s'actualisent plus",
          "A chave de sessão do claude.ai expirou — os limites não estão atualizando",
          "claude.ai-Sitzungsschlüssel abgelaufen – Limits werden nicht aktualisiert")
    }
    /// Keychain 재조회를 권하지 않는다 — 세션 키가 죽은 상태에서 그건 아무것도 고치지 못하고,
    /// 하필 세션 키로 피하려던 그 팝업을 띄운다.
    var sessionKeyExpiredNoticeHint: String {
        t("표시된 값은 만료 전 기준이에요. 브라우저에서 sessionKey 를 다시 복사해 설정 → 고급에 붙여넣으세요.",
          "The numbers shown are from before it expired. Copy a fresh sessionKey from your browser and paste it under Settings → Advanced.",
          "表示中の値は期限切れ前のものです。ブラウザから sessionKey を再度コピーし、設定 → 詳細に貼り付けてください。",
          "Los valores mostrados son anteriores a la caducidad. Copia una nueva sessionKey del navegador y pégala en Ajustes → Avanzado.",
          "Les valeurs affichées datent d'avant l'expiration. Copie une nouvelle sessionKey depuis ton navigateur et colle-la dans Réglages → Avancé.",
          "Os valores exibidos são de antes de expirar. Copie uma nova sessionKey do navegador e cole em Ajustes → Avançado.",
          "Die angezeigten Werte stammen von vor dem Ablauf. Kopiere einen neuen sessionKey aus deinem Browser und füge ihn unter Einstellungen → Erweitert ein.")
    }
    var sessionKeyExpiredBadge: String {
        t("만료됨", "Expired", "期限切れ", "Caducada", "Expirée", "Expirada", "Abgelaufen")
    }

    // MARK: Claude Keychain 항상 허용 초기화 도움말 (상시 안내)
    var claudeKeychainHelpTitle: String {
        t("왜 주기적으로 암호를 묻나요?",
          "Why does it ask for password periodically?",
          "なぜ定期的にパスワードを求められるのですか？",
          "¿Por qué pide la contraseña periódicamente?",
          "Pourquoi le mot de passe est-il demandé périodiquement ?",
          "Por que pede a senha periodicamente?",
          "Warum wird regelmäßig nach dem Passwort gefragt?")
    }
    var claudeKeychainHelpBody: String {
        t("Claude CLI가 백그라운드에서 토큰을 교체할 때 macOS 키체인의 '항상 허용' 권한이 초기화됩니다. 세션 키를 등록하면 암호 입력 없이 백그라운드 자동 갱신이 유지됩니다.",
          "When Claude CLI rotates tokens in the background, macOS resets the Keychain 'Always Allow' permission. Registering a session key keeps background limits refreshed without any password prompt.",
          "Claude CLI がバックグラウンドでトークンをローテーションすると、macOS Keychain の「常に許可」権限がリセットされます。セッションキーを登録すると、パスワード入力なしで自動更新が維持されます。",
          "Cuando Claude CLI rota tokens en segundo plano, macOS restablece el permiso 'Permitir siempre' del Llavero. Registrar una clave de sesión mantiene los límites actualizados sin pedir contraseña.",
          "Lorsque Claude CLI renouvelle les jetons en arrière-plan, macOS réinitialise l'autorisation 'Toujours autoriser'. L'enregistrement d'une clé de session permet de maintenir les limites à jour sans mot de passe.",
          "Quando o Claude CLI renova tokens em segundo plano, o macOS redefine a permissão 'Permitir Sempre'. Cadastrar uma chave de sessão mantém a atualização automática sem solicitar senha.",
          "Wenn Claude CLI Tokens im Hintergrund erneuert, setzt macOS die Berechtigung 'Immer erlauben' zurück. Ein registrierter Sitzungsschlüssel hält Limits ohne Passwortabfrage aktuell.")
    }
    var registerSessionKey: String {
        t("세션 키 등록",
          "Register Session Key",
          "セッションキーを登録",
          "Registrar clave de sesión",
          "Enregistrer la clé de session",
          "Cadastrar chave de sessão",
          "Sitzungsschlüssel registrieren")
    }
    var claudeKeychainHelpTooltip: String {
        t("Claude 키체인 인증 안내",
          "Claude Keychain authentication info",
          "Claude Keychain 認証について",
          "Información de autenticación de Keychain de Claude",
          "Info sur l'authentification Keychain Claude",
          "Informações de autenticação do Keychain do Claude",
          "Claude Keychain-Authentifizierungsinformation")
    }

    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知", "Alertas de límite", "Alertes de limite", "Alertas de limite", "Limit-Warnungen") }
    var companionNotificationsLabel: String { t("Companion 이벤트 (부화·진화·졸업)", "Companion events (hatch / evolve / graduate)", "コンパニオンイベント（孵化・進化・卒業）", "Eventos del compañero (eclosión / evolución / graduación)", "Événements du compagnon (éclosion / évolution / diplôme)", "Eventos do companheiro (nascimento / evolução / formatura)", "Begleiter-Ereignisse (Schlüpfen / Entwicklung / Abschied)") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック", "Comprobación de estado de proveedores", "Vérification de l'état des fournisseurs", "Verificação de status dos provedores", "Anbieterstatus prüfen") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）", "Muestra incidentes de Claude/OpenAI en el popover (no es una notificación)", "Affiche les incidents Claude / OpenAI dans le popover (pas une notification)", "Mostra incidentes do Claude/OpenAI no painel (não é uma notificação)", "Störungen bei Claude / OpenAI im Popover anzeigen (keine Benachrichtigung)") }
    var warning: String { t("경고", "Warning", "警告", "Aviso", "Avertissement", "Aviso", "Warnung") }
    var critical: String { t("임박", "Critical", "切迫", "Crítico", "Critique", "Crítico", "Kritisch") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)", "Base de cálculo: totalTokens (input + output + cache, fecha local)", "Base de calcul : totalTokens (input + output + cache, date locale)", "Base de cálculo: totalTokens (input + output + cache, data local)", "Token-Grundlage: totalTokens (input + output + cache, lokales Datum)") }
    var customScanProviderLabel: String { t("프로바이더", "Provider", "プロバイダー", "Proveedor", "Fournisseur", "Provedor", "Anbieter") }
    var customScanRootsLabel: String { t("추가 스캔 폴더", "Additional scan folders", "追加スキャンフォルダ", "Carpetas de escaneo adicionales", "Dossiers d'analyse supplémentaires", "Pastas extras para escanear", "Zusätzliche Scan-Ordner") }
    var customScanRootsHint: String {
        t("선택한 프로바이더의 로그가 기본 위치 밖에 있을 때만. 콤마·줄바꿈 구분, * 와일드카드. 다른 프로바이더 폴더를 넣지 마세요.",
          "Only for this provider's logs outside the built-in locations. Comma/newline separated, * wildcards. Do not point at another provider's folder.",
          "選択したプロバイダーのログが既定の場所にないときだけ。カンマ・改行区切り、*ワイルドカード。別プロバイダーのフォルダは指定しないでください。",
          "Solo para los registros de este proveedor fuera de las ubicaciones integradas. Separados por coma o salto de línea; comodines *. No indiques la carpeta de otro proveedor.",
          "Uniquement pour les journaux de ce fournisseur en dehors des emplacements intégrés. Séparés par des virgules ou des retours à la ligne ; caractères génériques *. N'indique pas le dossier d'un autre fournisseur.",
          "Só para os logs deste provedor fora dos locais padrão. Separados por vírgula ou quebra de linha; curingas *. Não aponte para a pasta de outro provedor.",
          "Nur für Protokolle dieses Anbieters außerhalb der Standardpfade. Durch Kommas oder Zeilenumbrüche getrennt, * als Platzhalter. Wähle keinen Ordner eines anderen Anbieters.")
    }
    var customScanRootsPlaceholder: String { t("~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions") }
    func customScanRootsMatches(_ n: Int) -> String {
        t("지금 \(n)개 추가 폴더를 스캔함", "Scans \(n) extra folder(s) now", "現在\(n)個の追加フォルダをスキャン", "Escanea \(n) carpeta(s) extra ahora", "Analyse \(n) dossier(s) supplémentaire(s) maintenant", "Escaneando \(n) pasta(s) extra agora", "Zusätzlich gescannte Ordner: \(n)")
    }
    var close: String { t("닫기", "Close", "閉じる", "Cerrar", "Fermer", "Fechar", "Schließen") }

    // MARK: 세이브 이전 (설정 → 백업 & 이전)
    var transferSectionTitle: String { t("백업 & 이전", "Backup & Transfer", "バックアップと移行", "Copia de seguridad y transferencia", "Sauvegarde et transfert", "Backup e transferência", "Sicherung & Übertragung") }
    var exportSaveLabel: String { t("세이브 내보내기", "Export save", "セーブを書き出す", "Exportar partida", "Exporter la sauvegarde", "Exportar save", "Spielstand exportieren") }
    var exportSaveHint: String {
        t("도감·누적 토큰·가방·현재 포켓몬을 파일 하나로 저장해요",
          "Saves your Pokédex, lifetime tokens, Bag, and current Pokémon as one file",
          "図鑑・累計トークン・バッグ・現在のポケモンを1つのファイルに保存します",
          "Guarda tu Pokédex, tokens acumulados, Bolsa y Pokémon actual en un solo archivo",
          "Enregistre ton Pokédex, tes tokens cumulés, ton Sac et ton Pokémon actuel dans un seul fichier",
          "Salva sua Pokédex, tokens acumulados, Bolsa e Pokémon atual em um único arquivo",
          "Speichert deinen Pokédex, alle bisherigen Tokens, deinen Beutel und dein aktuelles Pokémon in einer Datei")
    }
    var exportSaveButton: String { t("내보내기…", "Export…", "書き出す…", "Exportar…", "Exporter…", "Exportar…", "Exportieren…") }
    var importSaveLabel: String { t("세이브 불러오기", "Import save", "セーブを読み込む", "Importar partida", "Importer une sauvegarde", "Importar save", "Spielstand importieren") }
    var importSaveHint: String {
        t("다른 Mac에서 내보낸 파일을 골라 이 Mac으로 이어서 키워요",
          "Pick a file exported from another Mac and continue here",
          "他のMacから書き出したファイルを選んでこのMacで続けます",
          "Elige un archivo exportado desde otro Mac y continúa aquí",
          "Choisis un fichier exporté depuis un autre Mac et continue ici",
          "Escolha um arquivo exportado de outro Mac e continue por aqui",
          "Wähle eine auf einem anderen Mac exportierte Datei aus und mach hier weiter")
    }
    var importSaveButton: String { t("불러오기…", "Import…", "読み込む…", "Importar…", "Importer…", "Importar…", "Importieren…") }
    var importConfirmTitle: String {
        t("이 Mac의 진행을 대체할까요?", "Replace this Mac's progress?", "このMacの進行を置き換えますか？", "¿Reemplazar el progreso de este Mac?", "Remplacer la progression de ce Mac ?", "Substituir o progresso deste Mac?", "Fortschritt auf diesem Mac ersetzen?")
    }
    /// 무엇이 사라지는지 수치로 적는다 — 일반적인 "정말 진행할까요?" 보다 판단에 실제로 쓸모 있다.
    /// 내보낸 시각·출처 기기를 함께 보여주는 이유: 도감 수가 같으면 3주 전 세이브도 문구가 똑같아,
    /// 오래된 파일을 되돌리는 상황을 사용자가 알아챌 단서가 없다.
    func importConfirmBody(incomingDex: Int, incomingTokens: String,
                           exportedAt: String, sourceDevice: String,
                           currentDex: Int, currentTokens: String) -> String {
        t("""
          불러올 세이브: 도감 \(incomingDex)마리 · 누적 \(incomingTokens)
          내보낸 시각: \(exportedAt) · \(sourceDevice)
          현재 이 Mac: 도감 \(currentDex)마리 · 누적 \(currentTokens)

          이 Mac의 현재 진행은 대체됩니다. 직전 상태는 상태 폴더에 백업으로 남습니다(최근 5개).
          """,
          """
          Incoming save: \(incomingDex) in Pokédex · \(incomingTokens) lifetime
          Exported: \(exportedAt) · \(sourceDevice)
          This Mac now: \(currentDex) in Pokédex · \(currentTokens) lifetime

          This Mac's current progress is replaced. The previous state is kept as a backup in the state folder (last 5).
          """,
          """
          読み込むセーブ: 図鑑 \(incomingDex)匹 · 累計 \(incomingTokens)
          書き出し日時: \(exportedAt) · \(sourceDevice)
          現在のこのMac: 図鑑 \(currentDex)匹 · 累計 \(currentTokens)

          このMacの現在の進行は置き換えられます。直前の状態は状態フォルダにバックアップとして残ります（最新5件）。
          """,
          """
          Partida a importar: Pokédex \(incomingDex) · \(incomingTokens) acumulados
          Exportada: \(exportedAt) · \(sourceDevice)
          Este Mac ahora: Pokédex \(currentDex) · \(currentTokens) acumulados

          El progreso actual de este Mac será reemplazado. El estado anterior se guarda como copia de seguridad en la carpeta de estado (últimas 5).
          """,
          """
          Sauvegarde à importer : Pokédex \(incomingDex) · \(incomingTokens) cumulés
          Exportée : \(exportedAt) · \(sourceDevice)
          Ce Mac actuellement : Pokédex \(currentDex) · \(currentTokens) cumulés

          La progression actuelle de ce Mac sera remplacée. L'état précédent est conservé en sauvegarde dans le dossier d'état (5 derniers).
          """,
          """
          Save a ser importado: Pokédex \(incomingDex) · \(incomingTokens) acumulados
          Exportado: \(exportedAt) · \(sourceDevice)
          Este Mac agora: Pokédex \(currentDex) · \(currentTokens) acumulados

          O progresso atual deste Mac será substituído. O estado anterior fica guardado como backup na pasta de estado (últimos 5).
          """,
          """
          Zu importierender Spielstand: \(incomingDex) im Pokédex · \(incomingTokens) insgesamt
          Exportiert: \(exportedAt) · \(sourceDevice)
          Dieser Mac jetzt: \(currentDex) im Pokédex · \(currentTokens) insgesamt

          Der aktuelle Fortschritt auf diesem Mac wird ersetzt. Der vorherige Stand bleibt als Sicherung im Statusordner erhalten (die letzten 5).
          """)
    }
    var importConfirmReplace: String { t("대체", "Replace", "置き換える", "Reemplazar", "Remplacer", "Substituir", "Ersetzen") }
    func importSaveDone(dex: Int, tokens: String) -> String {
        t("불러왔어요 — 도감 \(dex)마리 · 누적 \(tokens)",
          "Imported — \(dex) in Pokédex · \(tokens) lifetime",
          "読み込みました — 図鑑 \(dex)匹 · 累計 \(tokens)",
          "Importado — Pokédex \(dex) · \(tokens) acumulados",
          "Importé — Pokédex \(dex) · \(tokens) cumulés",
          "Importado — Pokédex \(dex) · \(tokens) acumulados",
          "Importiert – \(dex) im Pokédex · \(tokens) insgesamt")
    }
    var importErrorNotSaveFile: String {
        t("PokeTokenBar 세이브 파일이 아니에요.",
          "That isn't a PokeTokenBar save file.",
          "PokeTokenBar のセーブファイルではありません。",
          "Ese no es un archivo de partida de PokeTokenBar.",
          "Ce n'est pas un fichier de sauvegarde PokeTokenBar.",
          "Esse não é um arquivo de save do PokeTokenBar.",
          "Das ist keine PokeTokenBar-Spielstandsdatei.")
    }
    var importErrorNewerSchema: String {
        t("더 새로운 버전에서 만든 세이브예요 — 앱을 업데이트한 뒤 다시 시도해 주세요.",
          "This save was made by a newer version — update the app and try again.",
          "より新しいバージョンで作成されたセーブです — アプリを更新してから再試行してください。",
          "Esta partida se creó con una versión más reciente — actualiza la app e inténtalo de nuevo.",
          "Cette sauvegarde a été créée par une version plus récente — mets l'app à jour et réessaie.",
          "Esse save foi criado por uma versão mais recente — atualize o app e tente de novo.",
          "Dieser Spielstand wurde mit einer neueren Version erstellt – aktualisiere die App und versuche es erneut.")
    }
    /// 불러오기 실패 사유 → 사용자 문구. 뷰가 아니라 여기 두는 이유는 이 매핑이 테스트 가능해야 하기
    /// 때문이다 — 매핑이 어긋나면 `SaveTransferError` 는 LocalizedError 가 아니라서 "The operation
    /// couldn't be completed…" 같은 원문이 그대로 노출된다(조용한 품질 저하).
    func importErrorMessage(_ error: Error) -> String {
        switch error {
        case SaveTransferError.notASaveFile:  return importErrorNotSaveFile
        case SaveTransferError.newerSchema:   return importErrorNewerSchema
        case SaveTransferError.fileTooLarge:  return importErrorTooLarge
        case SaveTransferError.backupFailed:  return importErrorBackupFailed
        default: return userFacingError(error)
        }
    }
    var importErrorTooLarge: String {
        t("세이브 파일이라기엔 너무 커요 — 다른 파일을 고른 것 같아요.",
          "That file is too large to be a save — it looks like the wrong file.",
          "セーブファイルにしては大きすぎます — 別のファイルを選んだようです。",
          "Ese archivo es demasiado grande para ser una partida — parece que elegiste el archivo equivocado.",
          "Ce fichier est trop volumineux pour être une sauvegarde — ce n'est sans doute pas le bon fichier.",
          "Esse arquivo é grande demais para ser um save — parece que você escolheu o arquivo errado.",
          "Diese Datei ist zu groß für einen Spielstand – wahrscheinlich hast du die falsche Datei ausgewählt.")
    }
    /// 백업을 못 남기면 불러오기를 중단한다 — 되돌릴 수단 없이 진행을 대체하지 않기 위해서다.
    var importErrorBackupFailed: String {
        t("현재 상태를 백업하지 못해 불러오기를 중단했어요 — 진행은 그대로예요. 디스크 여유 공간을 확인해 주세요.",
          "Import stopped because the current state couldn't be backed up — your progress is untouched. Check free disk space.",
          "現在の状態をバックアップできなかったため読み込みを中止しました — 進行はそのままです。ディスクの空き容量を確認してください。",
          "Se detuvo la importación porque no se pudo hacer una copia de seguridad del estado actual — tu progreso no se ha tocado. Comprueba el espacio libre en disco.",
          "Import interrompu car l'état actuel n'a pas pu être sauvegardé — ta progression est intacte. Vérifie l'espace disque disponible.",
          "A importação foi interrompida porque não deu para fazer backup do estado atual — seu progresso está intacto. Verifique o espaço livre em disco.",
          "Der Import wurde abgebrochen, weil der aktuelle Stand nicht gesichert werden konnte – dein Fortschritt ist unverändert. Prüfe den freien Speicherplatz.")
    }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { t("문제점 알리기", "Report a problem", "問題を報告", "Reportar un problema", "Signaler un problème", "Relatar um problema", "Problem melden") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示", "Mostrar archivo de registro", "Afficher le fichier journal", "Mostrar arquivo de log", "Protokolldatei anzeigen") }
    var reportAttachHint: String {
        t("메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요.",
          "Attaching the log file to the email helps a lot with diagnosis.",
          "メールにログファイルを添付していただくと原因の特定に役立ちます。",
          "Adjuntar el archivo de registro al correo ayuda mucho a diagnosticar el problema.",
          "Joindre le fichier journal au mail aide beaucoup au diagnostic.",
          "Anexar o arquivo de log ao e-mail ajuda muito no diagnóstico.",
          "Wenn du die Protokolldatei an die E-Mail anhängst, hilft das sehr bei der Fehlersuche.")
    }
    func reportMailFallback(_ address: String) -> String {
        t("메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요.",
          "Couldn't open a mail app. Please email \(address) directly.",
          "メールアプリを開けません。\(address) 宛に直接お送りください。",
          "No se pudo abrir una app de correo. Escribe directamente a \(address).",
          "Impossible d'ouvrir une app de messagerie. Écris directement à \(address).",
          "Não foi possível abrir um app de e-mail. Escreva diretamente para \(address).",
          "Es konnte keine Mail-App geöffnet werden. Schreib bitte direkt an \(address).")
    }
    func reportMailSubject(_ version: String) -> String {
        t("[PokeTokenBar] 문제 리포트 (v\(version))",
          "[PokeTokenBar] Problem report (v\(version))",
          "[PokeTokenBar] 問題レポート (v\(version))",
          "[PokeTokenBar] Reporte de problema (v\(version))",
          "[PokeTokenBar] Rapport de problème (v\(version))",
          "[PokeTokenBar] Relato de problema (v\(version))",
          "[PokeTokenBar] Problembericht (v\(version))")
    }
    func reportMailBody(version: String, os: String) -> String {
        t("""
        문제 내용:
        (겪으신 문제를 적어주세요 — 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        What happened:
        (Describe the problem — when, on which screen, and what you saw)


        ---
        App version: v\(version)
        macOS: \(os)
        Log file (please attach): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        問題の内容:
        （いつ・どの画面で・どうなったかをご記入ください）


        ---
        アプリのバージョン: v\(version)
        macOS: \(os)
        ログファイル（添付推奨）: ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Descripción del problema:
        (Describe lo que ocurrió — cuándo, en qué pantalla y qué viste)


        ---
        Versión de la app: v\(version)
        macOS: \(os)
        Archivo de registro (se recomienda adjuntar): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Ce qui s'est passé :
        (Décris le problème — quand, sur quel écran, et ce que tu as vu)


        ---
        Version de l'app : v\(version)
        macOS: \(os)
        Fichier journal (à joindre de préférence) : ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Descrição do problema:
        (Descreva o que aconteceu — quando, em qual tela e o que você viu)


        ---
        Versão do app: v\(version)
        macOS: \(os)
        Arquivo de log (anexe, por favor): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Was ist passiert:
        (Beschreibe das Problem – wann, auf welchem Bildschirm und was du gesehen hast)


        ---
        App-Version: v\(version)
        macOS: \(os)
        Protokolldatei (bitte anhängen): ~/Library/Logs/PokeTokenBar.log
        """)
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動", "Manual", "Manuel", "Manual", "Manuell") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分", "\(m) min", "\(m) min", "\(m) min", "\(m) Min.")
    }

    // MARK: 컴패니언
    var finalForm: String { t("최종 진화체", "Final form", "最終進化", "Forma final", "Forme finale", "Forma final", "Letzte Entwicklungsstufe") }
    func stage(_ i: Int, _ k: Int) -> String { t("진화 단계 \(i) / \(k)", "Stage \(i) / \(k)", "進化段階 \(i) / \(k)", "Etapa \(i) / \(k)", "Stade \(i) / \(k)", "Estágio \(i) / \(k)", "Entwicklungsstufe \(i) / \(k)") }
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明", "Próxima evolución desconocida", "Prochaine évolution inconnue", "Próxima evolução desconhecida", "Nächste Entwicklung unbekannt") }
    var eggIncubating: String { t("🥚 부화 준비 중", "🥚 Incubating", "🥚 孵化の準備中", "🥚 Incubando", "🥚 En incubation", "🥚 Incubando", "🥚 Wird ausgebrütet") }
    func eggToHatch(_ amount: String) -> String { t("부화까지 \(amount)", "\(amount) to hatch", "孵化まで \(amount)", "\(amount) para eclosionar", "\(amount) avant l'éclosion", "\(amount) para chocar", "\(amount) bis zum Schlüpfen") }
    func toNextEvolution(_ amount: String) -> String { t("다음 진화까지 \(amount)", "\(amount) to next evolution", "次の進化まで \(amount)", "\(amount) para la siguiente evolución", "\(amount) avant la prochaine évolution", "\(amount) para a próxima evolução", "\(amount) bis zur nächsten Entwicklung") }
    func toGraduation(_ amount: String) -> String { t("졸업까지 \(amount)", "\(amount) to graduation", "卒業まで \(amount)", "\(amount) para graduarse", "\(amount) avant le diplôme", "\(amount) para se formar", "\(amount) bis zum Abschied") }
    func growthBoost(_ multiplier: Int) -> String { t("\(multiplier)× 성장", "\(multiplier)× growth", "成長 \(multiplier)倍", "Crecimiento ×\(multiplier)", "Croissance ×\(multiplier)", "Crescimento ×\(multiplier)", "\(multiplier)× Wachstum") }
    func graduated(_ name: String) -> String {
        t("\(name) 졸업 → 도감에 보존. 새 Token Egg가 도착했어요!",
          "\(name) graduated → saved to the dex. A new Token Egg has arrived!",
          "\(name) 卒業 → 図鑑に保存。新しいToken Eggが届きました！",
          "\(name) se graduó → guardado en la Pokédex. ¡Ha llegado un nuevo Token Egg!",
          "\(name) a été diplômé → conservé dans le Pokédex. Un nouveau Token Egg est arrivé !",
          "\(name) se formou → guardado na Pokédex. Chegou um novo Token Egg!",
          "\(name) verabschiedet sich → im Pokédex gespeichert. Ein neues Token Egg ist da!")
    }
    var dexEmptyTitle: String { t("아직 잡은 포켓몬이 없어요!", "No Pokémon caught yet!", "まだ捕まえたポケモンがいません！", "¡Todavía no has capturado ningún Pokémon!", "Aucun Pokémon capturé pour l'instant !", "Você ainda não capturou nenhum Pokémon!", "Du hast noch kein Pokémon gefangen!") }
    var dexEmptyHint: String { t("토큰을 써서 첫 포켓몬을 부화시켜 보세요.", "Spend tokens to hatch your first Pokémon.", "トークンを使って最初のポケモンを孵化させましょう。", "Usa tokens para eclosionar tu primer Pokémon.", "Dépense des tokens pour faire éclore ton premier Pokémon.", "Use tokens para chocar seu primeiro Pokémon.", "Verwende Tokens, damit dein erstes Pokémon schlüpft.") }

    // MARK: 도감 요약 헤더
    var dexTitle: String { t("도감", "Pokédex", "図鑑", "Pokédex", "Pokédex", "Pokédex", "Pokédex") }
    func dexTotal(_ n: Int) -> String { t("총 \(n)마리", "\(n) total", "全\(n)匹", "\(n) en total", "\(n) au total", "\(n) no total", "\(n) insgesamt") }
    /// 포획 로그 = 개체 단위 기록(같은 라인 중복이 정상). 도감 = 종 단위 집계.
    var catchLogTitle: String { t("포획 로그", "Catch log", "捕獲ログ", "Registro de capturas", "Journal de captures", "Registro de capturas", "Fangprotokoll") }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    func dexSpeciesTotal(_ n: Int) -> String { t("\(n)종", "\(n) species", "\(n)種", "\(n) especies", "\(n) espèces", "\(n) espécies", "\(n) Spezies") }
    func dexPageLabel(_ page: Int, _ total: Int) -> String {
        t("\(total)페이지 중 \(page)페이지", "Page \(page) of \(total)", "\(total)ページ中 \(page)ページ", "Página \(page) de \(total)", "Page \(page) sur \(total)", "Página \(page) de \(total)", "Seite \(page) von \(total)")
    }
    var dexPagePrev: String { t("이전 페이지", "Previous page", "前のページ", "Página anterior", "Page précédente", "Página anterior", "Vorherige Seite") }
    var dexPageNext: String { t("다음 페이지", "Next page", "次のページ", "Página siguiente", "Page suivante", "Próxima página", "Nächste Seite") }
    var dexRaising: String { t("키우는 중", "Raising", "育成中", "Criando", "En élevage", "Treinando", "In Aufzucht") }
    /// 포획 로그에서 졸업분과 놓아준 개체를 가르는 표식. 종은 도감에 남고 개체 기록만 이 뱃지를 단다.
    var dexReleased: String { t("놓아줌", "Released", "逃がした", "Liberado", "Relâché", "Solto", "Freigelassen") }
    var rarityCommon: String { t("일반", "Common", "ノーマル", "Común", "Commun", "Comum", "Gewöhnlich") }
    var rarityUncommon: String { t("고급", "Uncommon", "アンコモン", "Poco común", "Peu commun", "Incomum", "Ungewöhnlich") }
    var rarityRare: String { t("희귀", "Rare", "レア", "Raro", "Rare", "Raro", "Selten") }
    var rarityStarter: String { t("스타팅", "Starter", "御三家", "Inicial", "Starter", "Inicial", "Starter") }
    var rarityLegendary: String { t("전설", "Legendary", "伝説", "Legendario", "Légendaire", "Lendário", "Legendär") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体", "Toca para ver solo esta rareza · toca de nuevo para ver todo", "Touche pour n'afficher que cette rareté · touche à nouveau pour tout afficher", "Toque para ver só esta raridade · toque de novo para ver tudo", "Tippe, um nur diese Seltenheit zu sehen · tippe erneut für alle") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い", "Variocolor", "Chromatique", "Shiny", "Schillernd") }
    // MARK: Pokémon 상세
    var loadingPokemonDetails: String { t("포켓몬 정보를 불러오는 중…", "Loading Pokémon details…", "ポケモン情報を読み込み中…", "Cargando detalles del Pokémon…", "Chargement des détails du Pokémon…", "Carregando detalhes do Pokémon…", "Pokémon-Details werden geladen…") }
    var pokemonDetailsUnavailable: String { t("포켓몬 정보를 불러오지 못했어요.", "Pokémon details could not be loaded.", "ポケモン情報を読み込めませんでした。", "No se pudieron cargar los detalles.", "Impossible de charger les détails.", "Não foi possível carregar os detalhes.", "Pokémon-Details konnten nicht geladen werden.") }
    var pokemonIndividual: String { t("개체", "Individual", "個体", "Ejemplar", "Individu", "Indivíduo", "Individuum") }
    var level: String { t("레벨", "Level", "レベル", "Nivel", "Niveau", "Nível", "Level") }
    var gender: String { t("성별", "Gender", "性別", "Sexo", "Sexe", "Gênero", "Geschlecht") }
    var nature: String { t("성격", "Nature", "性格", "Naturaleza", "Nature", "Natureza", "Wesen") }
    var ability: String { t("특성", "Ability", "特性", "Habilidad", "Talent", "Habilidade", "Fähigkeit") }
    var hiddenAbility: String { t("숨겨진 특성", "Hidden Ability", "隠れ特性", "Habilidad oculta", "Talent caché", "Habilidade oculta", "Versteckte Fähigkeit") }
    var hidden: String { t("숨김", "Hidden", "隠れ", "Oculta", "Caché", "Oculta", "Versteckt") }
    var activeMoves: String { t("배운 기술", "Known moves", "覚えている技", "Movimientos conocidos", "Capacités connues", "Golpes conhecidos", "Erlernte Attacken") }
    var noLevelMoves: String { t("현재 레벨에서 배운 기술이 없어요.", "No level-up moves learned at this level.", "現在のレベルで覚えた技はありません。", "No hay movimientos aprendidos a este nivel.", "Aucune capacité apprise à ce niveau.", "Nenhum golpe aprendido neste nível.", "Auf diesem Level wurden keine Attacken erlernt.") }
    var actualStats: String { t("실제 능력치", "Actual stats", "実能力値", "Estadísticas reales", "Stats réelles", "Atributos reais", "Tatsächliche Werte") }
    var baseStats: String { t("기본 능력치", "Base stats", "種族値", "Estadísticas base", "Stats de base", "Atributos base", "Basiswerte") }
    var speciesData: String { t("종 정보", "Species data", "種情報", "Datos de especie", "Données de l’espèce", "Dados da espécie", "Speziesdaten") }
    var height: String { t("키", "Height", "高さ", "Altura", "Taille", "Altura", "Größe") }
    var weight: String { t("몸무게", "Weight", "重さ", "Peso", "Poids", "Peso", "Gewicht") }
    var baseStatTotal: String { t("합계", "Base total", "合計", "Total base", "Total de base", "Total base", "Basiswertsumme") }
    var possibleAbilities: String { t("가능한 특성", "Possible abilities", "可能な特性", "Habilidades posibles", "Talents possibles", "Habilidades possíveis", "Mögliche Fähigkeiten") }
    func completeMoveList(_ count: Int) -> String { t("전체 기술 목록 \(count)개", "Complete move list · \(count)", "全技リスト・\(count)", "Lista completa · \(count)", "Liste complète · \(count)", "Lista completa · \(count)", "Vollständige Attackenliste · \(count)") }
    func genderLabel(_ gender: PokemonGender?) -> String {
        switch gender {
        case .male: return t("수컷", "Male", "オス", "Macho", "Mâle", "Macho", "Männlich")
        case .female: return t("암컷", "Female", "メス", "Hembra", "Femelle", "Fêmea", "Weiblich")
        case .genderless: return t("무성", "Genderless", "性別不明", "Sin género", "Asexué", "Sem gênero", "Geschlechtslos")
        case nil: return "—"
        }
    }
    func statLabel(_ stat: String) -> String {
        switch stat {
        case "hp": return "HP"
        case "attack": return t("공격", "Attack", "こうげき", "Ataque", "Attaque", "Ataque", "Angriff")
        case "defense": return t("방어", "Defense", "ぼうぎょ", "Defensa", "Défense", "Defesa", "Vert.")
        case "special-attack": return t("특공", "Sp. Atk", "とくこう", "At. Esp.", "Atq. Spé.", "Atq. Esp.", "Sp.-Ang.")
        case "special-defense": return t("특방", "Sp. Def", "とくぼう", "Def. Esp.", "Déf. Spé.", "Def. Esp.", "Sp.-Vert.")
        case "speed": return t("스피드", "Speed", "すばやさ", "Velocidad", "Vitesse", "Velocidade", "Initiative")
        default: return stat
        }
    }
    func moveMethod(_ detail: PokemonMoveLearnMethod) -> String {
        switch detail.method {
        case "level-up": return detail.level > 0 ? "Lv. \(detail.level)" : t("시작", "Start", "基本", "Inicio", "Départ", "Inicial", "Start")
        case "machine": return "TM"
        case "egg": return t("교배", "Egg", "タマゴ", "Huevo", "Œuf", "Ovo", "Ei")
        case "light-ball-egg": return t("전기구 교배", "Light Ball breeding", "でんきだま遺伝", "Crianza con Bola Luminosa", "Reproduction avec Balle Lumière", "Cruzamento com Bola de Luz", "Zucht mit Kugelblitz")
        case "form-change": return t("폼 체인지", "Form change", "フォルムチェンジ", "Cambio de forma", "Changement de forme", "Mudança de forma", "Formwechsel")
        case "tutor": return t("가르침", "Tutor", "教え", "Tutor", "Maître", "Tutor", "Tutor")
        default: return detail.method.replacingOccurrences(of: "-", with: " ")
        }
    }
    func rarityLabel(_ r: Rarity) -> String {
        switch r {
        case .common:    return rarityCommon
        case .uncommon:  return rarityUncommon
        case .rare:      return rarityRare
        case .starter:   return rarityStarter
        case .legendary: return rarityLegendary
        }
    }

    // 상태 한 줄
    var statusEgg: String { t("곧 깨어나요.", "Hatching soon.", "もうすぐ孵化します。", "Está a punto de eclosionar.", "Bientôt l'éclosion.", "Vai chocar logo.", "Schlüpft bald.") }
    var statusIdle: String { t("오늘은 조용히 자리를 지켜요.", "Keeping quiet today.", "今日は静かにしています。", "Hoy se mantiene tranquilo.", "Tranquille aujourd'hui.", "Hoje está quietinho.", "Ist heute ganz ruhig.") }
    var statusWorking: String { t("오늘의 작업 흔적이 쌓이고 있어요.", "Today's work is piling up.", "本日の作業が積み重なっています。", "El trabajo de hoy se va acumulando.", "Le travail du jour s'accumule.", "O trabalho de hoje está se acumulando.", "Heute kommt einiges an Arbeit zusammen.") }
    var statusFocus: String { t("지금은 집중 모드예요.", "In focus mode now.", "今は集中モードです。", "Ahora está en modo concentración.", "En mode concentration.", "Agora está em modo foco.", "Gerade voll konzentriert.") }
    var statusTired: String { t("한도에 가까워요. 잠깐 쉬어도 괜찮아요.", "Close to the limit. A short break is fine.", "上限が近いです。少し休んでも大丈夫。", "Está cerca del límite. Un pequeño descanso no vendría mal.", "Proche de la limite. Une petite pause ne fait pas de mal.", "Está perto do limite. Uma pausa cai bem.", "Fast am Limit. Eine kurze Pause tut gut.") }
    var statusSleep: String { t("지금은 자고 있어요.", "Sleeping now.", "今は眠っています。", "Ahora está durmiendo.", "En train de dormir.", "Agora está dormindo.", "Schläft gerade.") }
    func statusEvolved(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!") }
    var statusGrew: String { t("성장했어요!", "It grew!", "成長しました！", "¡Ha crecido!", "Il a grandi !", "Cresceu!", "Ist gewachsen!") }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { t("🥚 부화!", "🥚 Hatched!", "🥚 孵化！", "🥚 ¡Eclosionó!", "🥚 Éclosion !", "🥚 Chocou!", "🥚 Geschlüpft!") }
    func notifHatchBody(_ name: String) -> String { t("알에서 \(name)이(가) 나왔어요!", "\(name) hatched from the egg!", "タマゴから \(name) が生まれました！", "¡\(name) salió del huevo!", "\(name) est sorti de l'œuf !", "\(name) saiu do ovo!", "\(name) ist aus dem Ei geschlüpft!") }
    var notifShinyHatchTitle: String { t("✨ 이로치 포켓몬!", "✨ Shiny Pokémon!", "✨ 色違いポケモン！", "✨ ¡Pokémon variocolor!", "✨ Pokémon chromatique !", "✨ Pokémon shiny!", "✨ Schillerndes Pokémon!") }
    func notifShinyHatchBody(_ name: String) -> String { t("이로치 \(name)이(가) 태어났어요! (1/64)", "A shiny \(name) hatched! (1 in 64)", "色違いの \(name) が生まれました！(1/64)", "¡Nació un \(name) variocolor! (1 entre 64)", "Un \(name) chromatique est né ! (1 sur 64)", "Nasceu um \(name) shiny! (1 em 64)", "Ein schillerndes \(name) ist geschlüpft! (1/64)") }
    var eggImminent: String { t("곧 부화해요!", "About to hatch!", "もうすぐ孵化！", "¡Está a punto de eclosionar!", "Sur le point d'éclore !", "Está quase chocando!", "Schlüpft gleich!") }
    /// 첫 실행(아직 토큰 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    var eggFirstRunHint: String {
        t("로컬 AI 코딩 도구의 사용량으로 자라요. 약 5M 토큰을 쓰면 알이 부화해요.",
          "Grows from your local AI coding usage. Your egg hatches after ~5M tokens.",
          "ローカルの AI コーディング使用量で育ちます。約5Mトークンでタマゴが孵化します。",
          "Crece con el uso de tus herramientas locales de programación con IA. Tu huevo eclosiona tras unos 5M de tokens.",
          "Il grandit avec l'usage de tes outils de code IA locaux. Ton œuf éclôt après environ 5M de tokens.",
          "Cresce com o uso das suas ferramentas locais de programação com IA. O ovo choca depois de uns 5M de tokens.",
          "Wächst mit der Nutzung deiner lokalen KI-Coding-Tools. Nach etwa 5M Tokens schlüpft dein Ei.") }
    var notifEvolveTitle: String { t("✨ 진화!", "✨ Evolved!", "✨ 進化！", "✨ ¡Evolucionó!", "✨ Évolution !", "✨ Evoluiu!", "✨ Entwicklung!") }
    func notifEvolveBody(_ name: String) -> String { t("\(name)(으)로 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!") }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { t("🎭 어라? 메타몽!", "🎭 Huh? It's Ditto!", "🎭 あれ？メタモン！", "🎭 ¿Eh? ¡Es Ditto!", "🎭 Hein ? C'est Métamorph !", "🎭 Ué? É um Ditto!", "🎭 Huch? Ditto!") }
    func notifDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 사실은 메타몽이었어요!", "You thought it was \(disguise) — it was Ditto all along!", "\(disguise) だと思ってた… 実はメタモンでした！", "Pensabas que era \(disguise) — ¡en realidad era Ditto!", "Tu croyais que c'était \(disguise) — c'était Métamorph depuis le début !", "Você achava que era \(disguise) — era um Ditto o tempo todo!", "Du dachtest, es wäre \(disguise) – dabei war es die ganze Zeit Ditto!") }
    var notifShinyDittoRevealTitle: String { t("🎭✨ 어라? 이로치 메타몽!", "🎭✨ Huh? A shiny Ditto!", "🎭✨ あれ？色違いメタモン！", "🎭✨ ¿Eh? ¡Un Ditto variocolor!", "🎭✨ Hein ? Un Métamorph chromatique !", "🎭✨ Ué? Um Ditto shiny!", "🎭✨ Huch? Ein schillerndes Ditto!") }
    func notifShinyDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 이로치 메타몽이었어요! (1/64)", "You thought it was \(disguise) — it was a shiny Ditto! (1 in 64)", "\(disguise) だと思ってた… 色違いのメタモンでした！(1/64)", "Pensabas que era \(disguise) — ¡era un Ditto variocolor! (1 entre 64)", "Tu croyais que c'était \(disguise) — c'était un Métamorph chromatique ! (1 sur 64)", "Você achava que era \(disguise) — era um Ditto shiny! (1 em 64)", "Du dachtest, es wäre \(disguise) – dabei war es ein schillerndes Ditto! (1/64)") }
    var notifGraduateTitle: String { t("🎓 졸업!", "🎓 Graduated!", "🎓 卒業！", "🎓 ¡Graduado!", "🎓 Diplômé !", "🎓 Formatura!", "🎓 Abschied!") }
    func notifGraduateBody(_ name: String) -> String { t("\(name) — 도감에 보존! 새 알이 도착했어요.", "\(name) — saved to your Pokédex! A new egg has arrived.", "\(name) — 図鑑に保存！新しいタマゴが届きました。", "\(name) — ¡guardado en tu Pokédex! Ha llegado un nuevo huevo.", "\(name) — conservé dans ton Pokédex ! Un nouvel œuf est arrivé.", "\(name) — guardado na sua Pokédex! Chegou um novo ovo.", "\(name) – in deinem Pokédex gespeichert! Ein neues Ei ist da.") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다 — Codex 한도는 따로 표시돼요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this — Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます — Codex の上限は別に表示されます。",
                "La credencial de Claude expiró o no tiene permisos (\(status)). Comprueba que has iniciado sesión en Claude Code. Si solo usas Codex, puedes ignorar esto — los límites de Codex se muestran aparte.",
                "L'identifiant Claude a expiré ou n'est pas autorisé (\(status)). Vérifie que tu es connecté à Claude Code. Si tu n'utilises que Codex, ignore ceci — les limites Codex s'affichent séparément.",
                "A credencial do Claude expirou ou não tem permissão (\(status)). Verifique se você fez login no Claude Code. Se você só usa o Codex, pode ignorar — os limites do Codex aparecem à parte.",
                "Deine Claude-Anmeldedaten sind abgelaufen oder nicht berechtigt (\(status)). Prüfe, ob du bei Claude Code angemeldet bist. Wenn du nur Codex verwendest, kannst du das ignorieren – Codex-Limits werden separat angezeigt.")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。", "No se pudieron obtener los límites de Claude (\(status)).", "Échec de récupération des limites Claude (\(status)).", "Não foi possível obter os limites do Claude (\(status)).", "Claude-Limits konnten nicht abgerufen werden (\(status)).")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。",
          "No se encontró ninguna credencial de Claude. Inicia sesión en Claude Code para ver los límites. Si solo usas Codex, puedes ignorar esto.",
          "Aucun identifiant Claude trouvé. Connecte-toi à Claude Code pour voir les limites. Si tu n'utilises que Codex, ignore ceci.",
          "Nenhuma credencial do Claude encontrada. Faça login no Claude Code para ver os limites. Se você só usa o Codex, pode ignorar.",
          "Keine Claude-Anmeldedaten gefunden. Melde dich bei Claude Code an, um Limits zu sehen. Wenn du nur Codex verwendest, kannst du das ignorieren.")
    }
    var limitRefreshReauthNeeded: String {
        t("Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다.",
          "Your Claude credential has no account sign-in. Run `/login` in Claude Code to sign in again and limits will appear.",
          "Claude の認証情報にアカウントのサインインが含まれていません。Claude Code で `/login` を実行して再度サインインすると上限が表示されます。",
          "Tu credencial de Claude no tiene una sesión de cuenta asociada. Ejecuta `/login` en Claude Code para volver a iniciar sesión y ver los límites.",
          "Ton identifiant Claude n'a pas de connexion de compte. Lance `/login` dans Claude Code pour te reconnecter et les limites apparaîtront.",
          "A credencial do Claude não está associada a nenhuma conta. Rode `/login` no Claude Code para fazer login de novo — aí os limites aparecem.",
          "Deine Claude-Anmeldedaten enthalten keine Kontoanmeldung. Führe `/login` in Claude Code aus, um dich erneut anzumelden und die Limits anzuzeigen.")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。",
          "No se pudieron obtener los límites de Claude. Inténtalo de nuevo en unos momentos.",
          "Impossible de récupérer les limites Claude. Réessaie dans un instant.",
          "Não foi possível obter os limites do Claude. Tente de novo daqui a pouco.",
          "Claude-Limits konnten nicht abgerufen werden. Versuch es gleich noch einmal.")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。",
          "Las comprobaciones de límites de Claude están temporalmente limitadas (429). Se reintentará automáticamente en breve.",
          "Les vérifications de limites Claude sont temporairement restreintes (429). Pause puis nouvelle tentative automatique.",
          "As consultas de limite do Claude estão com as requisições restringidas (429). Vamos aguardar e tentar de novo automaticamente.",
          "Claude-Limitabfragen sind vorübergehend eingeschränkt (429). Nach einer kurzen Pause wird es automatisch erneut versucht.")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료 — 한도가 갱신 안 돼요",
          "Claude session expired — limits can't refresh",
          "Claude セッション期限切れ — 上限を更新できません",
          "Sesión de Claude expirada — los límites no se pueden actualizar",
          "Session Claude expirée — les limites ne s'actualisent pas",
          "Sessão do Claude expirada — não dá para atualizar os limites",
          "Claude-Sitzung abgelaufen – Limits können nicht aktualisiert werden")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。",
          "Los valores mostrados son de antes de la expiración. Reinténtalo, o ejecuta Claude Code una vez para actualizarlos automáticamente.",
          "Les valeurs affichées datent d'avant l'expiration. Réessaie, ou lance Claude Code une fois pour actualiser automatiquement.",
          "Os valores exibidos são de antes da expiração. Tente de novo ou rode o Claude Code uma vez para atualizá-los automaticamente.",
          "Die angezeigten Werte stammen von vor dem Ablauf. Versuch es erneut oder starte Claude Code einmal, um sie automatisch zu aktualisieren.")
    }
    var retry: String { t("다시 시도", "Retry", "再試行", "Reintentar", "Réessayer", "Tentar de novo", "Erneut versuchen") }

    // MARK: Antigravity 세션 만료(401) 안내 — Claude 쪽과 동일 문안 구조로 통일
    var antigravityAuthExpiredTitle: String {
        t("Antigravity 세션 만료 — 한도가 갱신 안 돼요",
          "Antigravity session expired — limits can't refresh",
          "Antigravity セッション期限切れ — 上限を更新できません",
          "Sesión de Antigravity expirada — los límites no se pueden actualizar",
          "Session Antigravity expirée — les limites ne s'actualisent pas",
          "Sessão do Antigravity expirada — não dá para atualizar os limites",
          "Antigravity-Sitzung abgelaufen – Limits können nicht aktualisiert werden")
    }
    var antigravityAuthExpiredHint: String {
        t("인증 토큰이 만료됐어요. 다시 시도하거나, Antigravity IDE 를 한 번 실행하면 자동 갱신됩니다.",
          "The auth token expired. Retry, or run Antigravity IDE once to refresh automatically.",
          "認証トークンの期限が切れました。再試行するか、Antigravity IDE を一度実行すると自動更新されます。",
          "El token de autenticación expiró. Reinténtalo, o ejecuta Antigravity IDE una vez para actualizarlo automáticamente.",
          "Le jeton d'authentification a expiré. Réessaie, ou lance Antigravity IDE une fois pour actualiser automatiquement.",
          "O token de autenticação expirou. Tente de novo, ou abra o Antigravity IDE uma vez para atualizar automaticamente.",
          "Das Authentifizierungs-Token ist abgelaufen. Versuch es erneut oder starte Antigravity IDE einmal, um es automatisch zu aktualisieren.")
    }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）",
          "🆕 v\(version) disponible (tienes \(current))",
          "🆕 v\(version) disponible (tu as \(current))",
          "🆕 v\(version) disponível (você tem \(current))",
          "🆕 v\(version) verfügbar (installiert: \(current))")
    }
    var updateButton: String { t("업데이트", "Update", "更新", "Actualizar", "Mettre à jour", "Instalar", "Aktualisieren") }
    var updateLater: String { t("나중에", "Later", "後で", "Más tarde", "Plus tard", "Depois", "Später") }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…", "Actualizando…", "Mise à jour…", "Atualizando…", "Wird aktualisiert…") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート", "Actualizaciones", "Mises à jour", "Atualizações", "Aktualisierungen") }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知", "Notificaciones de actualización", "Notifications de mise à jour", "Notificações de atualização", "Hinweise auf Aktualisierungen") }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認", "Buscar actualizaciones", "Rechercher des mises à jour", "Buscar atualizações", "Nach Aktualisierungen suchen") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認", "Comprobar ahora", "Vérifier maintenant", "Buscar agora", "Jetzt prüfen") }
    func updateFound(_ version: String) -> String { t("새 버전 v\(version) 있어요", "Version \(version) is available", "バージョン \(version) が利用可能です", "La versión \(version) está disponible", "La version \(version) est disponible", "A versão \(version) está disponível", "Version \(version) ist verfügbar") }
    func upToDate(_ version: String) -> String { t("최신 버전이에요 (v\(version))", "You're on the latest (v\(version))", "最新です (v\(version))", "Tienes la última versión (v\(version))", "Tu as la dernière version (v\(version))", "Você está na última versão (v\(version))", "Du hast die neueste Version (v\(version))") }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫", "Límite inminente", "Limite imminente", "Limite iminente", "Limit fast erreicht") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告", "Aviso de límite", "Alerte de limite", "Aviso de limite", "Limit-Warnung") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用", "\(name) al \(percent)", "\(name) à \(percent)", "\(name) em \(percent)", "\(name): \(percent) verbraucht")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション", "Sesión de 5 horas de Claude", "Session de 5 h de Claude", "Sessão de 5 horas do Claude", "Claude-5-Stunden-Sitzung") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間", "Semanal de Claude", "Claude hebdo", "Semanal do Claude", "Claude – wöchentlich") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限", "Límite personal de Codex", "Limite personnelle Codex", "Limite pessoal do Codex", "Persönliches Codex-Limit") }

    // MARK: 가방 / 아이템
    var bag: String { t("가방", "Bag", "バッグ", "Bolsa", "Sac", "Bolsa", "Beutel") }
    var bagEmptyTitle: String { t("아직 가방이 비어있어요!", "Your bag is empty!", "バッグはまだ空っぽです！", "¡Tu bolsa todavía está vacía!", "Ton sac est encore vide !", "Sua bolsa ainda está vazia!", "Dein Beutel ist noch leer!") }
    var useItem: String { t("사용하기", "Use", "つかう", "Usar", "Utiliser", "Usar", "Verwenden") }
    var use: String { t("사용", "Use", "つかう", "Usar", "Utiliser", "Usar", "Verwenden") }
    var cancel: String { t("취소", "Cancel", "キャンセル", "Cancelar", "Annuler", "Cancelar", "Abbrechen") }
    func useOnCurrent(_ name: String) -> String {
        t("\(name)에게 사용할까요?", "Use on \(name)?", "\(name) に使いますか？", "¿Usar en \(name)?", "Utiliser sur \(name) ?", "Usar em \(name)?", "Bei \(name) verwenden?")
    }
    var useAfterHatch: String { t("부화 후 사용할 수 있어요", "Usable after hatching", "孵化後に使えます", "Se puede usar después de eclosionar", "Utilisable après l'éclosion", "Dá para usar depois que chocar", "Nach dem Schlüpfen verwendbar") }
    var useNeedsPokemon: String { t("사용할 포켓몬이 없어요", "No Pokémon to use it on", "使えるポケモンがいません", "No hay ningún Pokémon en quien usarlo", "Aucun Pokémon sur qui l'utiliser", "Nenhum Pokémon para usar o item", "Kein Pokémon, bei dem du es verwenden kannst") }

    /// 포켓몬 타입 표시명.
    func typeName(_ type: PokemonType) -> String {
        switch type {
        case .normal:   return t("노말", "Normal", "ノーマル", "Normal", "Normal", "Normal", "Normal")
        case .fire:     return t("불꽃", "Fire", "ほのお", "Fuego", "Feu", "Fogo", "Feuer")
        case .water:    return t("물", "Water", "みず", "Agua", "Eau", "Água", "Wasser")
        case .grass:    return t("풀", "Grass", "くさ", "Planta", "Plante", "Planta", "Pflanze")
        case .electric: return t("전기", "Electric", "でんき", "Eléctrico", "Électrik", "Elétrico", "Elektro")
        case .ice:      return t("얼음", "Ice", "こおり", "Hielo", "Glace", "Gelo", "Eis")
        case .fighting: return t("격투", "Fighting", "かくとう", "Lucha", "Combat", "Lutador", "Kampf")
        case .poison:   return t("독", "Poison", "どく", "Veneno", "Poison", "Veneno", "Gift")
        case .ground:   return t("땅", "Ground", "じめん", "Tierra", "Sol", "Terra", "Boden")
        case .flying:   return t("비행", "Flying", "ひこう", "Volador", "Vol", "Voador", "Flug")
        case .psychic:  return t("에스퍼", "Psychic", "エスパー", "Psíquico", "Psy", "Psíquico", "Psycho")
        case .bug:      return t("벌레", "Bug", "むし", "Bicho", "Insecte", "Inseto", "Käfer")
        case .rock:     return t("바위", "Rock", "いわ", "Roca", "Roche", "Rocha", "Gestein")
        case .ghost:    return t("고스트", "Ghost", "ゴースト", "Fantasma", "Spectre", "Fantasma", "Geist")
        case .dragon:   return t("드래곤", "Dragon", "ドラゴン", "Dragón", "Dragon", "Dragão", "Drache")
        case .steel:    return t("강철", "Steel", "はがね", "Acero", "Acier", "Aço", "Stahl")
        case .dark:     return t("악", "Dark", "あく", "Siniestro", "Ténèbres", "Sombrio", "Unlicht")
        case .fairy:    return t("페어리", "Fairy", "フェアリー", "Hada", "Fée", "Fada", "Fee")
        }
    }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ", "Caramelo Raro", "Super Bonbon", "Doce Raro", "Sonderbonbon")
        case .mint:      return t("민트", "Mint", "ミント", "Menta", "Menthe", "Menta", "Minze")
        case .shinyCharm: return t("이로치 부적", "Shiny Charm", "ひかるおまもり", "Amuleto Iris", "Charme Chroma", "Amuleto Shiny", "Schillerpin")
        case .legendCharm: return t("천공의피리", "Azure Flute", "てんかいのふえ", "Flauta Azur", "Flûte Azur", "Flauta Celestial", "Azurflöte")
        case .silverWing: return t("은빛날개", "Silver Wing", "ぎんいろのはね", "Ala Plateada", "Aile d'Argent", "Asa Prateada", "Silberflügel")
        case .oldSeaMap: return t("오래된해도", "Old Sea Map", "ふるびたかいず", "Mapa Viejo", "Vieille Carte", "Mapa Velho", "Alte Karte")
        case .clearBell: return t("투명한방울", "Clear Bell", "とうめいなスズ", "Campana Clara", "Clochette Claire", "Sino Transparente", "Klarglocke")
        case .rainbowWing: return t("무지갯빛날개", "Rainbow Wing", "にじいろのはね", "Ala Arcoíris", "Aile Arc-en-Ciel", "Asa Arco-íris", "Buntflügel")
        case .magmaStone: return t("화산의돌", "Magma Stone", "かざんのおきいし", "Piedra Magma", "Pierre Magma", "Pedra de Magma", "Magmastein")
        case .soulDew: return t("마음의물방울", "Soul Dew", "こころのしずく", "Rocío Bondad", "Rosée Âme", "Orvalho da Alma", "Seelentau")
        case .jadeOrb: return t("초록구슬", "Jade Orb", "もえぎいろのたま", "Esfera Verde", "Orbe Vert", "Esfera de Jade", "Grüne Kugel")
        case .gracidea: return t("그라시데아꽃", "Gracidea", "グラシデアのはな", "Gracídea", "Gracidée", "Gracidea", "Gracidea")
        case .griseousOrb: return t("백금옥", "Griseous Orb", "はっきんだま", "Griseosfera", "Orbe Platiné", "Esfera de Platina", "Platinum-Orb")
        case .libertyPass: return t("리버티티켓", "Liberty Pass", "リバティチケット", "Pase Libertad", "Passe Liberté", "Passe da Liberdade", "Gartenpass")
        case .revealGlass: return t("비추는거울", "Reveal Glass", "うつしかがみ", "Espejo Veraz", "Miroir Sacré", "Espelho Revelador", "Wahrspiegel")
        case .dnaSplicers: return t("유전자쐐기", "DNA Splicers", "いでんしのくさび", "Punta ADN", "Pointeau ADN", "Fundidor de DNA", "DNS-Keil")
        case .boulderBadge: return t("회색배지", "Boulder Badge", "グレーバッジ", "Medalla Roca", "Badge Roche", "Insígnia da Rocha", "Felsorden")
        case .cascadeBadge: return t("블루배지", "Cascade Badge", "ブルーバッジ", "Medalla Cascada", "Badge Cascade", "Insígnia da Cascata", "Quellorden")
        case .thunderBadge: return t("오렌지배지", "Thunder Badge", "オレンジバッジ", "Medalla Trueno", "Badge Foudre", "Insígnia do Trovão", "Donnerorden")
        case .rainbowBadge: return t("무지개배지", "Rainbow Badge", "レインボーバッジ", "Medalla Arcoíris", "Badge Prisme", "Insígnia do Arco-Íris", "Farborden")
        case .soulBadge:    return t("핑크배지", "Soul Badge", "ピンクバッジ", "Medalla Alma", "Badge Âme", "Insígnia da Alma", "Seelenorden")
        case .marshBadge:   return t("골드배지", "Marsh Badge", "ゴールドバッジ", "Medalla Pantano", "Badge Marais", "Insígnia do Pântano", "Sumpforden")
        case .volcanoBadge: return t("진홍배지", "Volcano Badge", "クリムゾンバッジ", "Medalla Volcán", "Badge Volcan", "Insígnia do Vulcão", "Vulkanorden")
        case .earthBadge:   return t("그린배지", "Earth Badge", "グリーンバッジ", "Medalla Tierra", "Badge Terre", "Insígnia da Terra", "Erdorden")
        case .zephyrBadge:  return t("윙배지", "Zephyr Badge", "ウイングバッジ", "Medalla Céfiro", "Badge Zéphyr", "Insígnia do Zéfiro", "Flügelorden")
        case .hiveBadge:    return t("인섹트배지", "Hive Badge", "インセクトバッジ", "Medalla Colmena", "Badge Essaim", "Insígnia da Colmeia", "Insektorden")
        case .plainBadge:   return t("레귤러배지", "Plain Badge", "レギュラーバッジ", "Medalla Planicie", "Badge Plaine", "Insígnia da Planície", "Basisorden")
        case .fogBadge:     return t("팬텀배지", "Fog Badge", "ファントムバッジ", "Medalla Niebla", "Badge Brume", "Insígnia da Névoa", "Phantomorden")
        case .stormBadge:   return t("쇼크배지", "Storm Badge", "ショックバッジ", "Medalla Tormenta", "Badge Choc", "Insígnia da Tempestade", "Faustorden")
        case .mineralBadge: return t("스틸배지", "Mineral Badge", "스チールバッジ", "Medalla Mineral", "Badge Minéral", "Insígnia do Mineral", "Stahlorden")
        case .glacierBadge: return t("아이스배지", "Glacier Badge", "アイスバッジ", "Medalla Glaciar", "Badge Glacier", "Insígnia da Geada", "Eisorden")
        case .risingBadge:  return t("라이징배지", "Rising Badge", "ライジングバッジ", "Medalla Dragón", "Badge Lever", "Insígnia do Dragão", "Drachenorden")
        case .darkBadge:    return t("악배지", "Dark Badge", "あくバッジ", "Medalla Siniestro", "Badge Ténèbres", "Insígnia Sombria", "Unlicht-Orden")
        case .fairyBadge:   return t("페어리배지", "Fairy Badge", "フェアリーバッジ", "Medalla Hada", "Badge Fée", "Insígnia da Fada", "Feenorden")
        case .leafStone:    return t("리프의돌", "Leaf Stone", "リーフのいし", "Piedra Hoja", "Pierre Plante", "Pedra da Folha", "Blattstein")
        case .fireStone:    return t("불꽃의돌", "Fire Stone", "ほのおのいし", "Piedra Fuego", "Pierre Feu", "Pedra do Fogo", "Feuerstein")
        case .waterStone:   return t("물의돌", "Water Stone", "みずのいし", "Piedra Agua", "Pierre Eau", "Pedra da Água", "Wasserstein")
        case .thunderStone: return t("천둥의돌", "Thunder Stone", "かみなりのいし", "Piedra Trueno", "Pierre Foudre", "Pedra do Trovão", "Donnerstein")
        case .sunStone:     return t("태양의돌", "Sun Stone", "たいようのいし", "Piedra Solar", "Pierre Soleil", "Pedra Solar", "Sonnenstein")
        case .moonStone:    return t("달의돌", "Moon Stone", "つきのいし", "Piedra Lunar", "Pierre Lune", "Pedra da Lua", "Mondstein")
        case .iceStone:     return t("얼음의돌", "Ice Stone", "こおりのいし", "Piedra Hielo", "Pierre Glace", "Pedra de Gelo", "Eisstein")
        case .duskStone:    return t("어둠의돌", "Dusk Stone", "やみのいし", "Piedra Noche", "Pierre Nuit", "Pedra do Anoitecer", "Finsterstein")
        case .dawnStone:    return t("각성의돌", "Dawn Stone", "めざめのいし", "Piedra Alba", "Pierre Aube", "Pedra da Alvorada", "Funkelstein")
        case .shinyStone:   return t("빛의돌", "Shiny Stone", "ひかりのいし", "Piedra Día", "Pierre Éclat", "Pedra do Brilho", "Leuchtstein")
        }
    }
    func itemDescription(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy:
            let xp = TokenFormatter.compact(RareCandy.xp)   // 상수에서 파생(하드코딩 드리프트 방지)
            return t("현재 포켓몬의 경험치를 \(xp) 올려줘요.",
                     "Raises your Pokémon's EXP by \(xp).",
                     "ポケモンの経験値を\(xp)上げます。",
                     "Aumenta la experiencia de tu Pokémon en \(xp).",
                     "Augmente l'EXP de ton Pokémon de \(xp).",
                     "Aumenta a experiência do seu Pokémon em \(xp).",
                     "Gibt deinem aktuellen Pokémon \(xp) EP.")
        case .mint:
            return t("현재 포켓몬의 성격을 랜덤으로 바꿔줘요.",
                     "Randomly changes your Pokémon's nature.",
                     "ポケモンのせいかくをランダムに変えます。",
                     "Cambia aleatoriamente la naturaleza de tu Pokémon.",
                     "Change aléatoirement la nature de ton Pokémon.",
                     "Muda a natureza do seu Pokémon aleatoriamente.",
                     "Ändert das Wesen deines aktuellen Pokémon zufällig.")
        case .shinyCharm:
            return t("보유하면 이로치 포켓몬이 태어날 확률이 올라가요.",
                     "While owned, raises the chance of hatching a shiny.",
                     "持っていると色違いが生まれる確率が上がります。",
                     "Mientras lo tengas, aumenta la probabilidad de que nazca un Pokémon variocolor.",
                     "Tant que tu le possèdes, augmente les chances qu'un Pokémon chromatique éclose.",
                     "Enquanto estiver na sua bolsa, aumenta a chance de nascer um Pokémon shiny.",
                     "Erhöht im Beutel die Chance, dass ein schillerndes Pokémon schlüpft.")
        case .legendCharm:
            return t("보유하면 전설의 포켓몬이 태어날 확률이 크게 올라가요.",
                     "While owned, greatly increases the chance of hatching a legendary Pokémon.",
                     "持っていると伝説のポケモンが生まれる確率が大きく上がります。",
                     "Mientras lo tengas, aumenta considerablemente la probabilidad de eclosionar un Pokémon legendario.",
                     "Tant que tu la possèdes, augmente grandement les chances de faire éclore un Pokémon légendaire.",
                     "Enquanto estiver na bolsa, aumenta muito a chance de chocar um Pokémon lendário.",
                     "Erhöht im Beutel die Chance auf ein legendäres Pokémon erheblich.")
        case .silverWing:
            return t("보유하면 알 부화에 필요한 토큰 소모량이 대폭 줄어듭니다.",
                     "While owned, significantly reduces the token threshold needed to hatch eggs.",
                     "持っているとタマゴの孵化に必要なトークン消費量が大幅に減少します。",
                     "Mientras lo tengas, reduce significativamente los tokens necesarios para eclosionar huevos.",
                     "Tant que tu la possèdes, réduit considérablement les tokens requis pour faire éclore un œuf.",
                     "Enquanto estiver na bolsa, reduz significativamente os tokens necessários para chocar ovos.",
                     "Verringert im Beutel die benötigten Tokens zum Ausbrüten von Eiern spürbar.")
        case .oldSeaMap:
            return t("보유하면 토큰 소모를 통한 포켓몬 성장 경험치가 추가로 증가합니다.",
                     "While owned, grants bonus growth EXP from token usage.",
                     "持っているとトークン消費によるポケモンの成長経験値が増加します。",
                     "Mientras lo tengas, otorga EXP de crecimiento adicional por gasto de tokens.",
                     "Tant que tu la possèdes, augmente l'EXP de croissance reçue via vos tokens.",
                     "Enquanto estiver na bolsa, concede bônus de EXP de crescimento ao gastar tokens.",
                     "Verleiht im Beutel zusätzliche Wachstums-EP durch Token-Verbrauch.")
        case .clearBell:
            return t("보유하면 알에서 희귀(Rare) 등급 이상의 포켓몬이 등장할 확률이 올라갑니다.",
                     "While owned, increases the appearance rate of Rare Pokémon in eggs.",
                     "持っているとタマゴからレアなポケモンが出現する確率が上がります。",
                     "Mientras lo tengas, aumenta la probabilidad de obtener Pokémon raros en huevos.",
                     "Tant que tu la possèdes, augmente le taux d'apparition des Pokémon Rares dans les œufs.",
                     "Enquanto estiver na bolsa, aumenta a taxa de aparição de Pokémon Raros em ovos.",
                     "Erhöht im Beutel die Chance auf seltene Pokémon aus Eiern.")
        case .rainbowWing:
            return t("보유하면 토큰 상점의 모든 아이템을 할인된 가격으로 구매할 수 있습니다.",
                     "While owned, grants a discount on all shop purchases.",
                     "持っているとショップの全商品を割引価格で購入できます。",
                     "Mientras lo tengas, otorga un descuento en todos los artículos de la tienda.",
                     "Tant que tu l'as, offre une réduction sur tous les articles de la boutique de tokens.",
                     "Enquanto estiver na bolsa, concede desconto em todos os itens da loja.",
                     "Gewährt im Beutel einen Rabatt auf alle Einkäufe im Token-Laden.")
        case .magmaStone:
            return t("보유하면 이미 졸업시킨 종을 다시 키울 때 성장 요구량이 감소합니다.",
                     "While owned, reduces the growth required when raising duplicate species.",
                     "持っていると図鑑登録済みの種を再育成する際の成長必要量が減少します。",
                     "Mientras lo tengas, reduce el esfuerzo requerido al criar especies ya registradas.",
                     "Tant que tu la possèdes, accélère la croissance des Pokémon d'une espèce déjà enregistrée.",
                     "Enquanto estiver na bolsa, reduz a exigência de crescimento ao criar espécies já registradas.",
                     "Verringert im Beutel den Wachstumsbedarf beim wiederholten Züchten registrierter Arten.")
        case .soulDew:
            return t("보유하면 이상한 사탕 사용 시 획득하는 경험치가 크게 증가합니다.",
                     "While owned, Rare Candies grant significantly more EXP.",
                     "持っているとふしぎなアメ使用時の獲得経験値が大きく増加します。",
                     "Mientras lo tengas, los Caramelos Raros otorgan mucha más experiencia.",
                     "Tant que tu la possèdes, augmente grandement l'EXP conférée par les Super Bonbons.",
                     "Enquanto estiver na bolsa, os Doces Raros concedem muito mais experiência.",
                     "Erhöht im Beutel die durch Sonderbonbons erhaltenen EP deutlich.")
        case .jadeOrb:
            return t("보유하면 상점에서 판매하는 포켓몬 알을 추가 할인된 가격에 구매합니다.",
                     "While owned, gives an extra discount on eggs in the shop.",
                     "持っているとショップのタマゴを特別割引価格で購入できます。",
                     "Mientras lo tengas, otorga un descuento adicional en los huevos de la tienda.",
                     "Tant que tu l'as, offre une réduction supplémentaire sur les œufs de la boutique.",
                     "Enquanto estiver na bolsa, concede desconto adicional nos ovos da loja.",
                     "Gibt im Beutel einen zusätzlichen Rabatt auf Eier im Laden.")
        case .gracidea:
            return t("보유하면 스트릭 유지를 위한 유예 기간이 늘어나 연속 기록이 더 안전하게 보호됩니다.",
                     "While owned, extends streak protection grace periods to keep your streak safe.",
                     "持っているとストリークの猶予期間が延び、連続記録が保護されます。",
                     "Mientras la tengas, amplía el período de gracia para proteger tu racha.",
                     "Tant que tu la possèdes, étend la période de grâce pour protéger votre série.",
                     "Enquanto estiver na bolsa, estende a tolerância para manter sua sequência segura.",
                     "Verlängert im Beutel den Schutzzeitraum, um deinen Streak abzusichern.")
        case .griseousOrb:
            return t("보유하면 퀘스트 및 업적 보상으로 받는 토큰이 증가합니다.",
                     "While owned, boosts token rewards claimed from quests and achievements.",
                     "持っているとクエストや実績で獲得できるトークン報酬が増加します。",
                     "Mientras lo tengas, aumenta las recompensas de tokens de misiones y logros.",
                     "Tant que tu l'as, augmente les tokens reçus en récompense de quêtes et succès.",
                     "Enquanto estiver na bolsa, aumenta as recompensas de tokens em missões e conquistas.",
                     "Erhöht im Beutel die Token-Belohnungen aus Quests und Erfolgen.")
        case .libertyPass:
            return t("보유하면 알 인큐베이션 일일 퀘스트의 진행 속도가 빨라집니다.",
                     "While owned, accelerates progress on daily incubation quests.",
                     "持っているとタマゴ孵化デイリークエストの進行が加速します。",
                     "Mientras lo tengas, acelera el progreso en las misiones diarias de incubación.",
                     "Tant que tu le possèdes, accélère la progression de la quête quotidienne d'incubation.",
                     "Enquanto estiver na bolsa, acelera o progresso na missão diária de incubação.",
                     "Beschleunigt im Beutel den Fortschritt bei täglichen Ausbrüt-Quests.")
        case .revealGlass:
            return t("보유하면 이로치 포켓몬이 태어날 확률이 더욱 증가합니다 (이로치 부적과 중첩).",
                     "While owned, further boosts shiny hatch odds (stacks with Shiny Charm).",
                     "持っていると色違いの出現率がさらに上昇します（ひかるおまもりと重複可）。",
                     "Mientras lo tengas, mejora aún más las probabilidades de obtener variocolor (acumulable con Amuleto Iris).",
                     "Tant que tu le possèdes, augmente encore davantage les chances d'obtenir un chromatique (cumulable avec Charme Chroma).",
                     "Enquanto estiver na bolsa, aumenta ainda mais a chance de shiny (acumula com Amuleto Shiny).",
                     "Erhöht im Beutel die Schiller-Chance noch weiter (stapelbar mit dem Schillerpin).")
        case .dnaSplicers:
            return t("보유하면 토큰 소모를 통한 포켓몬 성장 속도가 극적으로 빨라집니다.",
                     "While owned, dramatically accelerates Pokémon growth from token usage.",
                     "持っているとトークン消費によるポケモンの成長スピードが劇的に速くなります。",
                     "Mientras lo tengas, acelera drásticamente el crecimiento del Pokémon por tokens.",
                     "Tant que tu le possèdes, accélère considérablement la croissance de votre Pokémon via les tokens.",
                     "Enquanto estiver na bolsa, acelera drasticamente o crescimento do Pokémon com tokens.",
                     "Beschleunigt im Beutel das Wachstum deines Pokémon durch Token-Verbrauch drastisch.")
        case .plainBadge:
            return t("보유하면 노말타입 포켓몬의 출현률과 성장 속도가 20% 빨라져요 (누적 가능).",
                     "While owned, Normal-type Pokémon appear and grow 20% faster (stacks cumulatively).",
                     "持っていると、ノーマルタイプのポケモンの出現率と成長速度が20%早くなります（重複可能）。",
                     "Mientras lo tengas, los Pokémon de tipo Normal aparecen y crecen un 20% más rápido (acumulable).",
                     "Tant que tu le possèdes, les Pokémon de type Normal apparaissent et grandissent 20% plus vite (cumulable).",
                     "Enquanto estiver na bolsa, Pokémon do tipo Normal aparecem e crescem 20% mais rápido (cumulativo).",
                     "Erhöht im Beutel die Erscheinungs- und Wachstumsrate für Normal-Pokémon um 20% (stapelbar).")
        case .boulderBadge, .cascadeBadge, .thunderBadge, .rainbowBadge,
             .soulBadge, .marshBadge, .volcanoBadge, .earthBadge,
             .zephyrBadge, .hiveBadge, .fogBadge, .stormBadge,
             .mineralBadge, .glacierBadge, .risingBadge, .darkBadge, .fairyBadge:
            return t("보유하면 이 배지에 약한 포켓몬의 출현률과 성장 속도가 20% 빨라져요 (누적 가능).",
                     "While owned, Pokémon weak to this badge appear and grow 20% faster (stacks cumulatively).",
                     "持っていると、このバッジに弱いポケモンの出現率と成長速度が20%早くなります（重複可能）。",
                     "Mientras lo tengas, los Pokémon débiles a esta medalla aparecen y crecen un 20% más rápido (acumulable).",
                     "Tant que tu le possèdes, les Pokémon faibles face à ce badge apparaissent et grandissent 20% plus vite (cumulable).",
                     "Enquanto estiver na bolsa, Pokémon fracos a esta insígnia aparecem e crescem 20% mais rápido (cumulativo).",
                     "Erhöht im Beutel die Erscheinungs- und Wachstumsrate für Pokémon mit Schwäche gegen diesen Orden um 20% (stapelbar).")
        case .leafStone, .fireStone, .waterStone, .thunderStone, .sunStone,
             .moonStone, .iceStone, .duskStone, .dawnStone, .shinyStone:
            let tn = kind.stoneType.map { typeName($0) } ?? ""
            return t("사용하면 현재 동료를 보내고 \(tn)타입 확정 알을 새로 품어요.",
                     "Using this replaces your companion with an egg guaranteed to be \(tn)-type.",
                     "使うと現在の相棒とお別れし、\(tn)タイプ確定のタマゴを新しく温めます。",
                     "Usar esta piedra reemplaza a tu compañero por un huevo garantizado de tipo \(tn).",
                     "Utiliser cette pierre remplace ton compagnon par un œuf garanti de type \(tn).",
                     "Usar esta pedra substitui seu companheiro por um ovo garantido do tipo \(tn).",
                     "Beim Benutzen wird dein Begleiter durch ein Ei vom Typ \(tn) ersetzt.")
        }
    }
    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更", "Naturaleza aleatoria", "Nature aléatoire", "Natureza aleatória", "Zufälliges Wesen") }
    /// 가방 사용 컨트롤의 효과 힌트 — 진화의 돌.
    func stoneEffectHint(_ typeName: String) -> String {
        t("\(typeName)타입 알 교체", "Guaranteed \(typeName) Egg", "\(typeName)タイプ確定タマゴ", "Huevo de \(typeName)", "Œuf \(typeName) garanti", "Ovo \(typeName) garantido", "Garantiertes \(typeName)-Ei")
    }
    /// 진화의 돌 사용 시 현재 포켓몬 교체 확인 문구.
    func stoneConfirm(_ monName: String, _ stoneName: String) -> String {
        t("\(monName)을(를) 보내고 \(stoneName)을(를) 사용할까요?",
          "Send off \(monName) and use \(stoneName)?",
          "\(monName) を手放して \(stoneName) を使いますか？",
          "¿Soltar a \(monName) y usar \(stoneName)?",
          "Laisser partir \(monName) et utiliser \(stoneName) ?",
          "Soltar \(monName) e usar \(stoneName)?",
          "\(monName) verabschieden und \(stoneName) einsetzen?")
    }
    /// 인큐베이션 중 표시하는 타입 보증 배지 — 진화의 돌로 품은 알의 확정 타입.
    func eggTypeGuaranteeHint(_ type: PokemonType) -> String {
        let name = typeName(type)
        return t("\(name)타입 확정", "Guaranteed \(name)", "\(name)タイプ確定", "\(name) garantizado", "\(name) garanti", "\(name) garantido", "Garantiert \(name)")
    }

    // MARK: 상점 (재화 = 사용한 토큰)
    var shop: String { t("상점", "Shop", "ショップ", "Tienda", "Boutique", "Loja", "Laden") }
    var spendableTokens: String { t("쓸 수 있는 토큰", "Spendable tokens", "使えるトークン", "Tokens disponibles", "Tokens disponibles", "Tokens disponíveis", "Verfügbare Tokens") }
    var shopHint: String { t("사용한 토큰으로 아이템을 살 수 있어요.", "Spend the tokens you've used on items.", "使ったトークンでアイテムを購入できます。", "Usa los tokens que has consumido para comprar objetos.", "Dépense les tokens que tu as consommés pour acheter des objets.", "Compre itens com os tokens que você já usou.", "Mit deinen verbrauchten Tokens kannst du Gegenstände kaufen.") }
    var buy: String { t("구매", "Buy", "購入", "Comprar", "Acheter", "Comprar", "Kaufen") }
    func buyConfirm(_ name: String) -> String { t("\(name) 구매할까요?", "Buy \(name)?", "\(name) を購入しますか？", "¿Comprar \(name)?", "Acheter \(name) ?", "Comprar \(name)?", "\(name) kaufen?") }
    var notEnoughTokens: String { t("토큰이 부족해요", "Not enough tokens", "トークンが足りません", "No tienes suficientes tokens", "Pas assez de tokens", "Tokens insuficientes", "Nicht genug Tokens") }
    func ownedCount(_ n: Int) -> String { t("보유 ×\(n)", "Owned ×\(n)", "所持 ×\(n)", "En posesión ×\(n)", "Possédés ×\(n)", "Você tem ×\(n)", "Im Beutel ×\(n)") }
    var shopPriceLabel: String { t("가격", "Price", "価格", "Precio", "Prix", "Preço", "Preis") }
    var ownedAlready: String { t("보유 중", "Owned", "所持済み", "En posesión", "Possédé", "Já tem", "Im Beutel") }
    var shinyCharmEffectHint: String { t("이로치 확률 ↑ · 적용 중", "Shiny rate ↑ · active", "色違い率↑ · 適用中", "Prob. variocolor ↑ · activo", "Taux chromatique ↑ · actif", "Chance shiny ↑ · ativo", "Schillerchance ↑ · aktiv") }
    var legendCharmEffectHint: String { t("전설 출현 4× · 적용 중", "Legendary rate 4× · active", "伝説出現 4× · 適用中", "Prob. legendario 4× · activo", "Taux légendaire 4× · actif", "Chance lendária 4× · ativo", "Legendäre Chance 4× · aktiv") }
    var silverWingEffectHint: String { t("부화 임계치 ½ · 적용 중", "Egg threshold ½ · active", "タマゴ必要量½ · 適用中", "Umbral eclosión ½ · activo", "Seuil d'éclosion ½ · actif", "Meta de choque ½ · ativo", "Ei-Schwelle ½ · aktiv") }
    var oldSeaMapEffectHint: String { t("성장 경험치 +20% · 적용 중", "Growth EXP +20% · active", "育成EXP +20% · 適用中", "EXP crecimiento +20% · activo", "EXP croissance +20% · actif", "EXP crescimento +20% · ativo", "Wachstums-EP +20% · aktiv") }
    var clearBellEffectHint: String { t("희귀 출현 2× · 적용 중", "Rare rate 2× · active", "レア出現 2× · 適用中", "Prob. raro 2× · activo", "Taux Rare 2× · actif", "Chance raro 2× · ativo", "Seltene Chance 2× · aktiv") }
    var rainbowWingEffectHint: String { t("상점 할인 25% · 적용 중", "Shop discount 25% · active", "ショップ25%引 · 適用中", "Descuento tienda 25% · activo", "Réduction boutique 25% · actif", "Desconto loja 25% · ativo", "Ladenrabatt 25% · aktiv") }
    var magmaStoneEffectHint: String { t("중복 육성 25% 할인 · 적용 중", "Duplicate raising -25% · active", "重複育成25%減 · 適用中", "Crianza repetida -25% · activo", "Élevage doublon -25% · actif", "Criação repetida -25% · ativo", "Doppelte Zucht -25% · aktiv") }
    var soulDewEffectHint: String { t("사탕 경험치 +50% · 적용 중", "Candy EXP +50% · active", "アメEXP +50% · 適用中", "EXP caramelo +50% · activo", "EXP bonbon +50% · actif", "EXP doce +50% · ativo", "Bonbon-EP +50% · aktiv") }
    var jadeOrbEffectHint: String { t("알 추가할인 20% · 적용 중", "Egg discount 20% · active", "タマゴ20%引 · 適用中", "Descuento huevos 20% · activo", "Réduction œufs 20% · actif", "Desconto ovos 20% · ativo", "Ei-Rabatt 20% · aktiv") }
    var gracideaEffectHint: String { t("스트릭 2일 유예 · 적용 중", "Streak 2-day grace · active", "連続日数2日猶予 · 適用中", "Margen racha 2 días · activo", "Tolérance série 2j · actif", "Tolerância sequência 2d · ativo", "Streak-Kulanz 2 Tage · aktiv") }
    var griseousOrbEffectHint: String { t("퀘스트 토큰 2× · 적용 중", "Quest tokens 2× · active", "報酬トークン 2× · 適用中", "Tokens misión 2× · activo", "Tokens quêtes 2× · actif", "Tokens missão 2× · ativo", "Quest-Tokens 2× · aktiv") }
    var libertyPassEffectHint: String { t("부화 퀘스트 2× · 적용 중", "Hatch quest 2× · active", "孵化デイリー 2× · 適用中", "Misión eclosión 2× · activo", "Quête éclosion 2× · actif", "Missão choque 2× · ativo", "Brut-Quest 2× · aktiv") }
    var revealGlassEffectHint: String { t("이로치 분모 ½ · 적용 중", "Shiny denom ½ · active", "色違い分母½ · 適用中", "Denominador shiny ½ · activo", "Dénominateur shiny ½ · actif", "Denominador shiny ½ · ativo", "Schiller-Nenner ½ · aktiv") }
    var dnaSplicersEffectHint: String { t("성장 경험치 +50% · 적용 중", "Growth EXP +50% · active", "育成EXP +50% · 適用中", "EXP crecimiento +50% · activo", "EXP croissance +50% · actif", "EXP crescimento +50% · ativo", "Wachstums-EP +50% · aktiv") }
    var badgeEffectHint: String { t("약점 포획 속도 +20% · 적용 중", "Weakness speed +20% · active", "弱点捕獲速度 +20% · 適用中", "Vel. debilidad +20% · activo", "Vitesse faiblesse +20% · actif", "Vel. fraqueza +20% · ativo", "Schwäche-Tempo +20% · aktiv") }
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다: 한국어·영어는 맞아떨어져도 일본어에서
    // 조사가 어긋난다(レアのタマゴ vs 자연스러운 レアなタマゴ). 세 언어를 명시 트리플로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return t("포켓몬 알", "Pokémon Egg", "ポケモンのタマゴ", "Huevo Pokémon", "Œuf Pokémon", "Ovo Pokémon", "Pokémon-Ei")
        case .uncommon?:  return t("고급 알", "Uncommon Egg", "アンコモンのタマゴ", "Huevo poco común", "Œuf peu commun", "Ovo incomum", "Ungewöhnliches Ei")
        case .rare?:      return t("희귀 알", "Rare Egg", "レアのタマゴ", "Huevo raro", "Œuf rare", "Ovo raro", "Seltenes Ei")
        case .starter?:   return t("스타팅 알", "Starter Egg", "御三家のタマゴ", "Huevo inicial", "Œuf de starter", "Ovo inicial", "Starter-Ei")
        case .legendary?: return t("전설 알", "Legendary Egg", "でんせつのタマゴ", "Huevo legendario", "Œuf légendaire", "Ovo lendário", "Legendäres Ei")   // 미판매(FreshEgg.shopTiers)
        }
    }
    func eggDescription(_ tier: Rarity?) -> String {
        guard let tier, tier != .common else {
            return t("지금 포켓몬을 놓아주고 새 알로 다시 시작해요.",
                     "Send off your current Pokémon and start fresh with a new egg.",
                     "いまのポケモンを手放して新しいタマゴからやり直します。",
                     "Suelta a tu Pokémon actual y empieza de nuevo con un huevo nuevo.",
                     "Laisse partir ton Pokémon actuel et repars de zéro avec un nouvel œuf.",
                     "Solte seu Pokémon atual e recomece com um ovo novo.",
                     "Verabschiede dein aktuelles Pokémon und starte mit einem neuen Ei.")
        }
        let r = rarityLabel(tier)
        return t("지금 포켓몬을 놓아주고 \(r) 이상이 확정으로 나오는 알을 받아요.",
                 "Send off your current Pokémon for an egg guaranteed to hatch \(r) or better.",
                 "いまのポケモンを手放して \(r) 以上が確定で孵るタマゴをもらいます。",
                 "Suelta a tu Pokémon actual y consigue un huevo garantizado de \(r) o superior.",
                 "Laisse partir ton Pokémon actuel pour un œuf garanti \(r) ou mieux.",
                 "Solte seu Pokémon atual e ganhe um ovo que garante \(r) ou melhor.",
                 "Verabschiede dein aktuelles Pokémon und erhalte ein Ei, aus dem garantiert ein Pokémon der Seltenheitsstufe \(r) oder höher schlüpft.")
    }
    /// 알 상태의 상점 알 카드 비활성 사유 — 항목은 보이되 구매 버튼 아래에 한 줄로 붙는다(EggCard).
    var eggShopLockedHint: String {
        t("지금 품고 있는 알이 부화하면 살 수 있어요.",
          "Available once your current egg hatches.",
          "いま抱えているタマゴが孵ると購入できます。",
          "Disponible cuando eclosione tu huevo actual.",
          "Disponible une fois ton œuf actuel éclos.",
          "Disponível quando seu ovo atual chocar.",
          "Verfügbar, sobald dein aktuelles Ei geschlüpft ist.")
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        let r = rarityLabel(tier)
        return t("\(r) 이상 확정", "\(r) or better", "\(r) 以上確定", "\(r) o superior garantizado", "\(r) ou mieux garanti", "\(r) ou melhor garantido", "Garantiert \(r) oder besser")
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        t("\(monName)을(를) 놓아주고 \(eggName)(으)로 바꿀까요?",
          "Send off \(monName) for the \(eggName)?",
          "\(monName) を手放して \(eggName) にしますか？",
          "¿Soltar a \(monName) y cambiarlo por \(eggName)?",
          "Laisser partir \(monName) pour le \(eggName) ?",
          "Soltar \(monName) e trocar pelo \(eggName)?",
          "\(monName) verabschieden und gegen \(eggName) tauschen?")
    }
    var freshEggShinyWarning: String { t("⚠️ 이로치 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This one is shiny! Really send it off?", "⚠️ 色違いです！本当に手放しますか？", "⚠️ ¡Este es variocolor! ¿Seguro que quieres soltarlo?", "⚠️ Celui-ci est chromatique ! Vraiment le laisser partir ?", "⚠️ Esse é shiny! Quer mesmo soltar?", "⚠️ Dieses Pokémon ist schillernd! Wirklich verabschieden?") }
    var freshEggDiscardShiny: String { t("이로치 놓아주기", "Send shiny off", "手放す", "Soltar variocolor", "Laisser partir le chromatique", "Soltar o shiny", "Schillerndes Pokémon verabschieden") }

    // MARK: 사탕 획득 알림 ("왜 받는지" = 토큰 한도를 다 채운 수고에 대한 보상)
    func notifCandyTitle(item: String, count: Int) -> String {
        t("🍬 \(item) \(count)개를 받았어요!",
          "🍬 You got \(count)× \(item)!",
          "🍬 \(item)を\(count)個もらいました！",
          "🍬 ¡Has recibido \(count)× \(item)!",
          "🍬 Tu as reçu \(count)× \(item) !",
          "🍬 Você ganhou \(count)× \(item)!",
          "🍬 Du hast \(count)× \(item) erhalten!")
    }
    func notifCandyBody(window: String) -> String {
        t("\(window) 토큰 한도를 다 채웠어요. 열심히 쓴 만큼 사탕을 드려요 — 포켓몬에게 써서 진화시켜 보세요!",
          "You maxed out your \(window) token limit. A treat for the effort — use it to evolve your Pokémon!",
          "\(window)のトークン上限を使い切りました。がんばったごほうびです — ポケモンに使って進化させよう！",
          "Has agotado tu límite de tokens \(window). Un premio por el esfuerzo — ¡úsalo para evolucionar a tu Pokémon!",
          "Tu as atteint ta limite de tokens \(window). Une récompense pour l'effort — utilise-la pour faire évoluer ton Pokémon !",
          "Você esgotou seu limite de tokens — \(window). Você merece um agrado: use no seu Pokémon para evoluir!",
          "Du hast das Token-Limit für \(window) ausgeschöpft. Eine Belohnung für deinen Einsatz – verwende sie, um dein Pokémon zu entwickeln!")
    }

    // MARK: Quests & Streaks
    var dailyQuests: String { t("일일 퀘스트", "Daily Quests", "デイリークエスト", "Misiones diarias", "Quêtes du jour", "Missões diárias", "Tägliche Quests") }
    var weeklyQuests: String { t("주간 퀘스트", "Weekly Quests", "週間クエスト", "Misiones semanales", "Quêtes hebdomadaires", "Missões semanais", "Wöchentliche Quests") }
    var achievements: String { t("업적", "Achievements", "実績", "Logros", "Succès", "Conquistas", "Erfolge") }
    func streakTitle(days: Int) -> String {
        t("\(days)일 연속 코딩!", "\(days)-Day Coding Streak!", "\(days)日連続コーディング！", "¡Racha de \(days) días!", "Série de \(days) jours !", "Sequência de \(days) dias!", "\(days) Tage Coding-Streak!")
    }
    func bestStreakTitle(days: Int) -> String {
        t("최고 기록: \(days)일", "Best: \(days) days", "最高記録: \(days)日", "Récord: \(days) días", "Record : \(days) jours", "Recorde: \(days) dias", "Rekord: \(days) Tage")
    }
    var streakActiveToday: String {
        t("오늘 코딩 완료", "Streak extended today", "今日コーディング完了", "¡Racha activa hoy!", "Série validée aujourd'hui", "Sequência ativa hoje", "Streak heute aktiv")
    }
    var streakInactiveToday: String {
        t("오늘 토큰을 쓰면 연속 기록이 이어져요", "Burn tokens today to keep your streak alive", "今日トークンを使うと継続します", "Usa tokens hoy para mantener tu racha", "Consommez des tokens pour continuer la série", "Use tokens hoje para manter a sequência", "Verbrauche heute Tokens, um den Streak zu halten")
    }
    var claimReward: String { t("보상 받기", "Claim", "受け取る", "Reclamar", "Récupérer", "Resgatar", "Einlösen") }
    var claimAll: String { t("모두 받기", "Claim All", "すべて受け取る", "Reclamar todo", "Tout réclamer", "Reivindicar tudo", "Alle abholen") }
    var rewardClaimed: String { t("완료됨", "Claimed", "受取済み", "Reclamado", "Récupéré", "Resgatado", "Eingelöst") }
    var questsCompletedToday: String { t("오늘의 퀘스트를 모두 완료했어요!", "All daily quests completed today!", "今日のクエストをすべて完了しました！", "¡Misiones de hoy completadas!", "Toutes les quêtes du jour sont terminées !", "Todas as missões de hoje concluídas!", "Alle täglichen Quests abgeschlossen!") }
    var completedQuests: String { t("완료된 퀘스트", "Completed Quests", "完了したクエスト", "Misiones completadas", "Quêtes terminées", "Missões concluídas", "Abgeschlossene Quests") }
    var completedAchievements: String { t("완료된 업적", "Completed Achievements", "完了した実績", "Logros completados", "Succès terminés", "Conquistas concluídas", "Abgeschlossene Erfolge") }
    var allDailyQuestsCompleted: String { t("오늘의 모든 일일 퀘스트를 완료했습니다!", "All daily quests completed for today!", "今日のクエストをすべて完了しました！", "¡Misiones de hoy completadas!", "Toutes les quêtes quotidiennes sont terminées !", "Todas as missões de hoje concluídas!", "Alle täglichen Quests abgeschlossen!") }
    var allWeeklyQuestsCompleted: String { t("이번 주의 모든 주간 퀘스트를 완료했습니다!", "All weekly quests completed for this week!", "今週のウィークリークエストをすべて完了しました！", "¡Todas las misiones semanales completadas!", "Toutes les quêtes hebdomadaires sont terminées !", "Todas as missões semanais foram concluídas!", "Alle wöchentlichen Quests abgeschlossen!") }
    var allAchievementsCompleted: String { t("모든 업적을 달성했습니다!", "All achievements unlocked!", "すべての実績を達成しました！", "¡Todos los logros desbloqueados!", "Tous les succès sont débloqués !", "Todas as conquistas concluídas!", "Alle Erfolge abgeschlossen!") }
    var allCategories: String { t("전체", "All", "すべて", "Todos", "Tous", "Todos", "Alle") }

    func achievementCategoryTitle(_ category: AchievementCategory) -> String {
        switch category {
        case .adventure:
            return t("모험 & 훈련", "Adventure & Training", "冒険と育成", "Aventura y Entrenamiento", "Aventure & Entraînement", "Aventura e Treinamento", "Abenteuer & Training")
        case .starters:
            return t("스타터 파트너", "Starter Partners", "最初のパートナー", "Compañeros Iniciales", "Partenaires de départ", "Iniciais Regionais", "Starter-Partner")
        case .legendaries:
            return t("전설 & 환상", "Legendary & Mythical", "伝説・幻のポケモン", "Legendarios y Míticos", "Légendaires & Fabuleux", "Lendários e Míticos", "Legendär & Mystisch")
        case .gymBadges:
            return t("체육관 관장 배지", "Gym Badges", "ジムバッジ", "Medallas de Gimnasio", "Badges d'Arène", "Insígnias de Ginásio", "Arena-Orden")
        case .productivity:
            return t("연속 기록 & 토큰", "Streaks & Tokens", "継続記録とトークン", "Rachas y Tokens", "Séries & Productivité", "Sequências e Tokens", "Streaks & Tokens")
        }
    }

    func achievementCategorySubtitle(_ category: AchievementCategory) -> String {
        switch category {
        case .adventure:
            return t("첫 발걸음, 진화, 도감 완성 및 반짝이", "First steps, evolutions, Pokédex milestones, and shinies", "最初の一歩、進化、図鑑登録、色違い", "Primeros pasos, evoluciones, Pokédex y variocolores", "Premiers pas, évolutions, Pokédex et chromatiques", "Primeiros passos, evoluções, Pokédex e brilhantes", "Erste Schritte, Entwicklungen, Pokédex und Shinys")
        case .starters:
            return t("각 지방의 스타터 삼총사 및 스타터 마스터", "Regional starter trios and Starter Master", "各地方の御三家とスターターマスター", "Tríos iniciales regionales y Maestro Inicial", "Trios de starters régionaux et Maître des Starters", "Tríos de iniciais de cada região e Mestre Inicial", "Regionale Starter-Trios und Starter-Meister")
        case .legendaries:
            return t("전설의 새, 야수, 거인, 신화 속 포켓몬들", "Legendary birds, beasts, titans, and mythical deities", "伝説の鳥、三獣、巨人、神話のポケモンたち", "Aves legendarias, bestias, titanes y deidades míticas", "Oiseaux légendaires, fauves, titans et mythes anciens", "Aves lendárias, feras, titãs e divindades antigas", "Legendäre Vögel, Bestien, Titanen und Urzeit-Mythen")
        case .gymBadges:
            return t("18가지 포켓몬 타입을 정복하고 모든 배지를 획득하세요", "Master all 18 elemental types and collect gym badges", "全18タイプを極めてジムバッジを集めよう", "Domina los 18 tipos elementales y reúne las medallas", "Maîtrisez les 18 types élémentaires et décrochez les badges", "Domine os 18 tipos elementares e conquiste as insígnias", "Meistere alle 18 Elementartypen und sammle alle Orden")
        case .productivity:
            return t("매일 이어가는 스트릭과 대규모 토큰 사용 마일스톤", "Daily coding streaks and massive token burn milestones", "毎日の継続ストリークと大量トークン消費マイルストーン", "Rachas diarias de programación e hitos de tokens", "Séries quotidiennes de code et grands paliers de tokens", "Sequências diárias de código e marcos de uso de tokens", "Tägliche Coding-Streaks und große Token-Meilensteine")
        }
    }

    func weeklyQuestTitle(_ type: WeeklyQuestType) -> String {
        switch type {
        case .activeDays3: return t("주간 3일 출석", "Weekly Trio", "週間3日稼働", "Trío semanal", "Trio Hebdo", "Trio Semanal", "Wöchentliches Trio")
        case .activeDays5: return t("완벽한 평일", "Workweek Warrior", "平日の戦士", "Guerrero laboral", "Semaine Complète", "Guerreiro da Semana", "Arbeitswochen-Krieger")
        case .tokens100M: return t("주간 100M", "Weekly 100M", "週間100M", "100M semanal", "100M Hebdo", "100M Semanal", "Wöchentliche 100M")
        case .tokens300M: return t("주간 스프린트", "Weekly Sprint", "週間スプリント", "Sprint semanal", "Sprint Hebdomadaire", "Sprint Semanal", "Wöchentlicher Sprint")
        case .tokens1B: return t("주간 1B 마일스톤", "Weekly Billion", "週間1Bマイルストーン", "1B semanal", "1 Milliard Hebdo", "1B Semanal", "Wöchentliche Milliarde")
        case .tokens2B: return t("주간 더블 빌리언", "Weekly Double Billion", "週間2Bマイルストーン", "2B semanal", "2 Milliards Hebdo", "2B Semanal", "Wöchentlicher Doppel-Milliardär")
        case .tokens3_5B: return t("주간 레전드 타이탄", "Weekly Legend (3.5B)", "週間3.5Bレジェンド", "3.5B semanal", "Légende Hebdomadaire (3.5B)", "Lenda Semanal (3.5B)", "Wöchentliche Legende (3.5B)")
        }
    }

    func weeklyQuestDescription(_ type: WeeklyQuestType) -> String {
        switch type {
        case .activeDays3: return t("이번 주 3일 이상 코딩하세요.", "Code on at least 3 days this week.", "今週3日以上コーディングする。", "Programa al menos 3 días esta semana.", "Codez au moins 3 jours cette semaine.", "Programe em pelo menos 3 dias esta semana.", "Code an mindestens 3 Tagen diese Woche.")
        case .activeDays5: return t("이번 주 5일 이상 코딩하세요.", "Code on at least 5 days this week.", "今週5日以上コーディングする。", "Programa al menos 5 días esta semana.", "Codez au moins 5 jours cette semaine.", "Programe em pelo menos 5 dias esta semana.", "Code an mindestens 5 Tagen diese Woche.")
        case .tokens100M: return t("이번 주 총 100M 토큰을 사용하세요.", "Burn 100M tokens this week.", "今週合計100Mトークンを使用する。", "Consume 100M de tokens esta semana.", "Consommez 100M de tokens cette semaine.", "Use 100M de tokens esta semana.", "Verbrauche diese Woche 100M Tokens.")
        case .tokens300M: return t("이번 주 총 300M 토큰을 사용하세요.", "Burn 300M tokens this week.", "今週合計300Mトークンを使用する。", "Consume 300M de tokens esta semana.", "Consommez 300M de tokens cette semaine.", "Use 300M de tokens esta semana.", "Verbrauche diese Woche 300M Tokens.")
        case .tokens1B: return t("이번 주 총 1B 토큰을 사용하세요.", "Burn 1 billion tokens this week.", "今週合計1Bトークンを使用する。", "Consume 1B de tokens esta semana.", "Consommez 1 milliard de tokens cette semaine.", "Use 1B de tokens esta semana.", "Verbrauche diese Woche 1B Tokens.")
        case .tokens2B: return t("이번 주 총 2B 토큰을 사용하세요.", "Burn 2 billion tokens this week.", "今週合計2Bトークンを使用する。", "Consume 2B de tokens esta semana.", "Consommez 2 milliards de tokens cette semaine.", "Use 2B de tokens esta semana.", "Verbrauche diese Woche 2B Tokens.")
        case .tokens3_5B: return t("이번 주 총 3.5B 토큰을 사용하세요.", "Burn 3.5 billion tokens this week.", "今週合計3.5Bトークンを使用する。", "Consume 3.5B de tokens esta semana.", "Consommez 3.5 milliards de tokens cette semaine.", "Use 3.5B de tokens esta semana.", "Verbrauche diese Woche 3.5B Tokens.")
        }
    }

    func dailyQuestTitle(_ type: DailyQuestType) -> String {
        switch type {
        case .warmup: return t("워밍업", "Warm-Up", "ウォームアップ", "Calentamiento", "Échauffement", "Aquecimento", "Aufwärmen")
        case .focus: return t("집중 모드", "Steady Focus", "集中モード", "Enfoque constante", "Concentration", "Foco constante", "Voller Fokus")
        case .power: return t("파워 세션", "Power Session", "パワーセッション", "Sesión intensa", "Productivité Intense", "Sessão poderosa", "Power-Session")
        case .deepWork: return t("딥워크 마스터", "Deep Work Mastery", "ディープワークの達人", "Maestría en trabajo profundo", "Maîtrise du Deep Work", "Mestria em trabalho profundo", "Deep-Work-Meister")
        case .marathon: return t("일일 마라톤", "Daily Marathon", "デイリーマラソン", "Maratón diario", "Marathon Quotidien", "Maratona Diária", "Täglicher Marathon")
        case .titan: return t("일일 타이탄", "Daily Titan", "デイリータイタン", "Titán diario", "Titan Quotidien (500M)", "Titã Diário", "Täglicher Titan")
        case .streak: return t("매일의 불꽃", "Daily Flame", "毎日の炎", "Llama diaria", "Flamme Quotidienne", "Chama diária", "Tägliche Flamme")
        case .incubator: return t("동행 돌보기", "Companion Care", "相棒のお世話", "Cuidado del compañero", "Soin du Compagnon", "Cuidado do companheiro", "Begleiter-Pflege")
        }
    }

    func dailyQuestDescription(_ type: DailyQuestType) -> String {
        switch type {
        case .warmup: return t("오늘 10M 토큰을 사용하세요.", "Burn 10M tokens today.", "今日10Mトークンを使用する。", "Consume 10M de tokens hoy.", "Consommez 10M de tokens aujourd'hui.", "Use 10M de tokens hoje.", "Verbrauche heute 10M Tokens.")
        case .focus: return t("오늘 50M 토큰을 사용하세요.", "Burn 50M tokens today.", "今日50Mトークンを使用する。", "Consume 50M de tokens hoy.", "Consommez 50M de tokens aujourd'hui.", "Use 50M de tokens hoje.", "Verbrauche heute 50M Tokens.")
        case .power: return t("오늘 100M 토큰을 사용하세요.", "Burn 100M tokens today.", "今日100Mトークンを使用する。", "Consume 100M de tokens hoy.", "Consommez 100M de tokens aujourd'hui.", "Use 100M de tokens hoje.", "Verbrauche heute 100M Tokens.")
        case .deepWork: return t("오늘 150M 토큰을 사용하세요.", "Burn 150M tokens today.", "今日150Mトークンを使用する。", "Consume 150M de tokens hoy.", "Consommez 150M de tokens aujourd'hui.", "Use 150M de tokens hoje.", "Verbrauche heute 150M Tokens.")
        case .marathon: return t("오늘 300M 토큰을 사용하세요.", "Burn 300M tokens today.", "今日300Mトークンを使用する。", "Consume 300M de tokens hoy.", "Consommez 300M de tokens aujourd'hui.", "Use 300M de tokens hoje.", "Verbrauche heute 300M Tokens.")
        case .titan: return t("오늘 500M 토큰을 사용하세요.", "Burn 500M tokens today.", "今日500Mトークンを使用する。", "Consume 500M de tokens hoy.", "Consommez 500M de tokens aujourd'hui.", "Use 500M de tokens hoje.", "Verbrauche heute 500M Tokens.")
        case .streak: return t("오늘 코딩해서 연속 기록을 이어가세요.", "Code today to keep your streak active.", "今日コーディングして連続記録を維持する。", "Programa hoy para mantener tu racha activa.", "Codez aujourd'hui pour garder votre série active.", "Programe hoje para manter sua sequência ativa.", "Code heute, um deinen Streak aufrechtzuerhalten.")
        case .incubator: return t("알 또는 포켓몬 성장에 10M 토큰을 반영하세요.", "Advance your egg or Pokémon by 10M tokens.", "タマゴまたはポケモンの成長を10M進める。", "Avanza tu huevo o Pokémon con 10M de tokens.", "Faites progresser votre œuf ou Pokémon de 10M de tokens.", "Avance seu ovo ou Pokémon em 10M de tokens.", "Bringe dein Ei oder Pokémon um 10M Tokens voran.")
        }
    }

    func achievementTitle(_ type: AchievementType) -> String {
        if let badgeType = type.badgeType {
            return itemName(badgeType.badgeItem)
        }
        switch type {
        case .firstHatch: return t("첫 만남", "First Step", "はじまりの一歩", "Primer paso", "Premier Pas", "Primeiro passo", "Erster Schritt")
        case .firstEvolve: return t("눈부신 진화", "Evolution!", "かがやく進化", "¡Evolución!", "Évolution !", "Evolução!", "Entwicklung!")
        case .firstGraduate: return t("명예로운 졸업", "Honor Graduate", "名誉ある卒業", "Graduado con honores", "Diplômé d'Honneur", "Graduado com honras", "Ehrenvoller Abschluss")
        case .squad5: return t("포켓몬 스쿼드", "Star Squad", "スター分隊", "Equipo estrella", "Équipe Étoilée", "Esquadrão estrela", "Star-Team")
        case .dex15: return t("도감 애호가", "Dex Connoisseur", "図鑑愛好家", "Conocedor de la Pokédex", "Collectionneur Averti", "Conhecedor da Pokédex", "Pokédex-Kenner")
        case .dex30: return t("도감 마스터", "Pokédex Master", "図鑑マスター", "Maestro Pokédex", "Maître Pokédex", "Mestre da Pokédex", "Pokédex-Meister")
        case .shinyHunter: return t("별빛 기적", "Shooting Star", "星の奇跡", "Estrella fugaz", "Étoile Filante", "Estrela cadente", "Sternschnuppe")
        case .streak3: return t("습관의 시작", "Habit Builder", "習慣の始まり", "Constructor de hábitos", "Régularité", "Criador de hábitos", "Gewohnheitsbildner")
        case .streak7: return t("일주일의 헌신", "Weekly Dedication", "1週間の献身", "Dedicación semanal", "Persévérance", "Dedicação semanal", "Wöchentliche Hingabe")
        case .streak14: return t("철의 규율", "Fortnight Focus", "2週間の集中", "Disciplina de hierro", "Discipline de Fer", "Foco quinzenal", "Zwei Wochen Fokus")
        case .streak30: return t("월간 레전드", "Monthly Legend", "月間レジェンド", "Leyenda mensual", "Légende du Code", "Lenda mensal", "Monats-Legende")
        case .tokens100M: return t("토큰 센츄리온", "Token Centurion", "トークンセンチュリオン", "Centurión de tokens", "Premier Million", "Centurião de tokens", "Token-Zenturio")
        case .tokens1B: return t("토큰 억만장자", "Token Billionaire", "トークンビリオネア", "Billonario de tokens", "Milliardaire", "Bilionário de tokens", "Token-Milliardär")
        case .tokens5B: return t("토큰 타이탄", "Token Titan", "トークンタイタン", "Titán de tokens", "Titan du Token", "Titã de tokens", "Token-Titan")
        case .tokens10B: return t("코스믹 개발자", "Cosmic Dev", "コズミック開発者", "Desarrollador cósmico", "Entité Cosmique", "Dev Cósmico", "Kosmischer Entwickler")
        case .candyUser: return t("달콤한 맛", "Sweet Tooth", "甘いもの好き", "Goloso", "Gourmand", "Formiguinha", "Süßschnabel")
        case .shopSpender: return t("VIP 단골손님", "VIP Customer", "VIPお得意様", "Cliente VIP", "Client Privilège", "Cliente VIP", "VIP-Kunde")
        case .limitBreaker: return t("한계 돌파", "Limit Breaker", "限界突破", "Rompelímites", "Dépassement de Soi", "Quebrador de limites", "Grenzbrecher")
        case .duplicateLegendary: return t("전설의 계승", "Legendary Twin", "伝説の継承", "Doble Legendario", "Doublon Légendaire", "Gêmeo Lendário", "Legendärer Zwilling")
        case .legendaryBirds: return t("전설의 세 새", "Legendary Birds", "伝説の三鳥", "Aves Legendarias", "Trio des Oiseaux", "Pássaros Lendários", "Legendäre Vögel")
        case .kantoDuo: return t("관동의 시원", "Kanto Origin", "カントーの始原", "Dúo de Kanto", "Duo de Kanto", "Dupla de Kanto", "Kanto-Ursprung")
        case .legendaryBeasts: return t("전설의 세 야수", "Legendary Beasts", "伝説の三聖獣", "Bestias Legendarias", "Fauves Légendaires", "Feras Lendárias", "Legendäre Bestien")
        case .towerDuo: return t("탑의 수호자", "Tower Duo", "塔の守護者", "Dúo Torre", "Duo de la Tour", "Guardiões da Torre", "Turm-Duo")
        case .legendaryTitans: return t("전설의 거인들", "Legendary Titans", "伝説の巨人", "Titanes Legendarios", "Golems Légendaires", "Titãs Lendários", "Legendäre Titanen")
        case .eonDuo: return t("무한의 듀오", "Eon Duo", "無限のデュオ", "Dúo Eón", "Duo Éon", "Dupla Eon", "Äon-Duo")
        case .weatherTrio: return t("초고대 삼총사", "Weather Trio", "超古代トリオ", "Trío del Clima", "Trio Météo", "Trio do Clima", "Wetter-Legenden")
        case .lakeGuardians: return t("호수의 수호신", "Lake Guardians", "湖の守護神", "Trío del Lago", "Gardiens des Lacs", "Guardiões do Lago", "See-Trio")
        case .creationTrio: return t("신화의 삼총사", "Creation Trio", "神話の創世神", "Trío Dragón", "Trio de la Création", "Trio da Criação", "Dimensions-Trio")
        case .swordsOfJustice: return t("성검사", "Swords of Justice", "聖剣士", "Espadachines Místicos", "Lames de la Justice", "Espadachins da Justiça", "Ritter der Redlichkeit")
        case .forcesOfNature: return t("자연의 화신", "Forces of Nature", "コピペ三銃士", "Fuerzas de la Naturaleza", "Fauves du Vent", "Forças da Natureza", "Kräfte der Natur")
        case .taoDuo: return t("흑백의 드래곤", "Tao Duo", "理想と真実", "Dúo Tao", "Dragons Idéal & Réalité", "Dupla Tao", "Tao-Duo")
        case .kantoStarters: return t("관동의 삼총사", "Kanto Starters", "カントー御三家", "Iniciales de Kanto", "Starters de Kanto", "Iniciais de Kanto", "Kanto-Starter")
        case .johtoStarters: return t("성도의 삼총사", "Johto Starters", "ジョウト御三家", "Iniciales de Johto", "Starters de Johto", "Iniciais de Johto", "Johto-Starter")
        case .hoennStarters: return t("호연의 삼총사", "Hoenn Starters", "ホウエン御三家", "Iniciales de Hoenn", "Starters de Hoenn", "Iniciais de Hoenn", "Hoenn-Starter")
        case .sinnohStarters: return t("신오의 삼총사", "Sinnoh Starters", "シンオウ御三家", "Iniciales de Sinnoh", "Starters de Sinnoh", "Iniciais de Sinnoh", "Sinnoh-Starter")
        case .unovaStarters: return t("하나의 삼총사", "Unova Starters", "イッシュ御三家", "Iniciales de Teselia", "Starters d'Unys", "Iniciais de Unova", "Einall-Starter")
        case .starterMaster: return t("스타팅 마스터", "Starter Master", "スターターマスター", "Maestro Inicial", "Maître des Starters", "Mestre Inicial", "Starter-Meister")
        case .eeveeKantoTrio: return t("관동의 이브이 삼총사", "Kanto Eeveelutions", "カントーのブイズ", "Trío de Eevee de Kanto", "Trio Évoli de Kanto", "Trio Eevee de Kanto", "Kanto-Evolis")
        case .eeveeJohtoDuo: return t("일월의 이브이", "Sun & Moon Eeveelutions", "太陽と月のブイズ", "Dúo Sol y Luna de Eevee", "Duo Évoli Soleil & Lune", "Dupla Sol e Lua de Eevee", "Sonne- & Mond-Evolis")
        case .eeveeSinnohDuo: return t("신오의 이브이", "Sinnoh Eeveelutions", "シンオウのブイズ", "Dúo de Eevee de Sinnoh", "Duo Évoli de Sinnoh", "Dupla Eevee de Sinnoh", "Sinnoh-Evolis")
        case .eeveeMaster: return t("이브이 마스터", "Eeveelution Master", "ブイズマスター", "Maestro Eevee", "Maître des Évolitions", "Mestre Eevee", "Evoli-Meister")
        case .firstFossil: return t("첫 화석의 부활", "First Fossil", "化石の目覚め", "Primer fósil", "Premier Fossile", "Primeiro fóssil", "Erster Fossil-Fund")
        case .fossilCollector: return t("고대의 수집가", "Ancient Era", "古代の探求者", "Era antigua", "Ère Antique", "Era antiga", "Uralte Ära")
        case .fossilMaster: return t("화석 마스터", "Fossil Master", "化石マスター", "Maestro de Fósiles", "Maître des Fossiles", "Mestre dos Fósseis", "Fossil-Meister")
        case .elementalStones: return t("원초의 돌", "Elemental Trio Stones", "三色の進化石", "Piedras elementales", "Pierres Originelles", "Pedras elementares", "Elementarsteine")
        case .allStonesUsed: return t("연금술 마스터", "Master Alchemist", "錬金術マスター", "Maestro alquimista", "Alchimiste Suprême", "Mestre alquimista", "Meister-Alchemist")
        case .bagCollector: return t("가방 수집가", "Adventurer's Bag", "冒険者のバッグ", "Mochila llena", "Sacoche d'Aventurier", "Mochila cheia", "Abenteurertasche")
        case .shinyTrio: return t("샤이니 트리오", "Shiny Trio", "かがやくトリオ", "Trío variocolor", "Trio Chromatique", "Trio brilhante", "Schillerndes Trio")
        case .shinySquad: return t("황금 스쿼드", "Golden Squad", "黄金のパーティ", "Equipo dorado", "Équipe Dorée", "Equipe dourada", "Goldenes Team")
        case .shinyLegendOrStarter: return t("기적의 반짝임", "Legendary Sparkle", "奇跡のきらめき", "Brillo legendario", "Miracle Suprême", "Brilho lendário", "Legendärer Glanz")
        case .streak60: return t("강철의 연속", "Iron Streak", "鋼の継続", "Racha de hierro", "Série d'Acier", "Sequência de ferro", "Eisen-Streak")
        case .streak100: return t("백일의 기적", "Centurion Streak", "百日の奇跡", "El centurión", "Le Centenaire", "O centurião", "Hundert Tage")
        case .tokens25B: return t("토큰 특이점", "Token Singularity", "トークン特異点", "Singularidad de tokens", "Milliardaire Ultime", "Singularidade de tokens", "Token-Singularität")
        case .dailyMarathon: return t("토큰 마라톤", "Token Marathon", "トークンマラソン", "Maratón de tokens", "Marathonien du Code", "Maratona de tokens", "Token-Marathon")
        case .nightOwl: return t("밤의 올빼미", "Night Owl", "夜のフクロウ", "Búho nocturno", "Oiseau de Nuit", "Coruja da noite", "Nachteule")
        case .earlyBird: return t("새벽의 날개", "Early Bird", "早起きの鳥", "Madrugador", "Lève-Tôt", "Madrugador", "Frühaufsteher")
        default: return ""
        }
    }

    func achievementDescription(_ type: AchievementType) -> String {
        if let badgeType = type.badgeType {
            let count = PokemonTypeData.species(for: badgeType).count
            switch badgeType {
            case .normal:
                return t("도감에 노말타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Normal-type Pokémon in your Pokédex.",
                         "ノーマルタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Normal en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Normal dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Normal na sua Pokédex.",
                         "Registriere alle \(count) Normal-Pokémon im Pokédex.")
            case .fire:
                return t("도감에 불꽃타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Fire-type Pokémon in your Pokédex.",
                         "ほのおタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Fuego en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Feu dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Fogo na sua Pokédex.",
                         "Registriere alle \(count) Feuer-Pokémon im Pokédex.")
            case .water:
                return t("도감에 물타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Water-type Pokémon in your Pokédex.",
                         "みずタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Agua en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Eau dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Água na sua Pokédex.",
                         "Registriere alle \(count) Wasser-Pokémon im Pokédex.")
            case .grass:
                return t("도감에 풀타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Grass-type Pokémon in your Pokédex.",
                         "くさタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Planta en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Plante dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Planta na sua Pokédex.",
                         "Registriere alle \(count) Pflanze-Pokémon im Pokédex.")
            case .electric:
                return t("도감에 전기타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Electric-type Pokémon in your Pokédex.",
                         "でんきタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Eléctrico en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Électrik dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Elétrico na sua Pokédex.",
                         "Registriere alle \(count) Elektro-Pokémon im Pokédex.")
            case .ice:
                return t("도감에 얼음타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Ice-type Pokémon in your Pokédex.",
                         "こおりタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Hielo en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Glace dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Gelo na sua Pokédex.",
                         "Registriere alle \(count) Eis-Pokémon im Pokédex.")
            case .fighting:
                return t("도감에 격투타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Fighting-type Pokémon in your Pokédex.",
                         "かくとうタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Lucha en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Combat dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Lutador na sua Pokédex.",
                         "Registriere alle \(count) Kampf-Pokémon im Pokédex.")
            case .poison:
                return t("도감에 독타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Poison-type Pokémon in your Pokédex.",
                         "どくタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Veneno en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Poison dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Veneno na sua Pokédex.",
                         "Registriere alle \(count) Gift-Pokémon im Pokédex.")
            case .ground:
                return t("도감에 땅타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Ground-type Pokémon in your Pokédex.",
                         "じめんタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Tierra en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Sol dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Terra na sua Pokédex.",
                         "Registriere alle \(count) Boden-Pokémon im Pokédex.")
            case .flying:
                return t("도감에 비행타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Flying-type Pokémon in your Pokédex.",
                         "ひこうタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Volador en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Vol dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Voador na sua Pokédex.",
                         "Registriere alle \(count) Flug-Pokémon im Pokédex.")
            case .psychic:
                return t("도감에 에스퍼타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Psychic-type Pokémon in your Pokédex.",
                         "エスパータイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Psíquico en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Psy dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Psíquico na sua Pokédex.",
                         "Registriere alle \(count) Psycho-Pokémon im Pokédex.")
            case .bug:
                return t("도감에 벌레타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Bug-type Pokémon in your Pokédex.",
                         "むしタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Bicho en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Insecte dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Inseto na sua Pokédex.",
                         "Registriere alle \(count) Käfer-Pokémon im Pokédex.")
            case .rock:
                return t("도감에 바위타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Rock-type Pokémon in your Pokédex.",
                         "いわタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Roca en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Roche dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Rocha na sua Pokédex.",
                         "Registriere alle \(count) Gestein-Pokémon im Pokédex.")
            case .ghost:
                return t("도감에 고스트타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Ghost-type Pokémon in your Pokédex.",
                         "ゴーストタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Fantasma en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Spectre dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Fantasma na sua Pokédex.",
                         "Registriere alle \(count) Geist-Pokémon im Pokédex.")
            case .dragon:
                return t("도감에 드래곤타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Dragon-type Pokémon in your Pokédex.",
                         "ドラゴンタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Dragón en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Dragon dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Dragão na sua Pokédex.",
                         "Registriere alle \(count) Drachen-Pokémon im Pokédex.")
            case .steel:
                return t("도감에 강철타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Steel-type Pokémon in your Pokédex.",
                         "はがねタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Acero en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Acier dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Aço na sua Pokédex.",
                         "Registriere alle \(count) Stahl-Pokémon im Pokédex.")
            case .dark:
                return t("도감에 악타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Dark-type Pokémon in your Pokédex.",
                         "あくタイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Siniestro en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Ténèbres dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Sombrio na sua Pokédex.",
                         "Registriere alle \(count) Unlicht-Pokémon im Pokédex.")
            case .fairy:
                return t("도감에 페어리타입 포켓몬 \(count)종을 모두 등록하세요.",
                         "Register all \(count) Fairy-type Pokémon in your Pokédex.",
                         "フェアリータイプのポケモン\(count)種をすべて図鑑に登録する。",
                         "Registra a los \(count) Pokémon de tipo Hada en tu Pokédex.",
                         "Enregistrez les \(count) Pokémon de type Fée dans le Pokédex.",
                         "Registre todos os \(count) Pokémon do tipo Fada na sua Pokédex.",
                         "Registriere alle \(count) Feen-Pokémon im Pokédex.")
            }
        }
        switch type {
        case .firstHatch: return t("첫 포켓몬 알을 부화시키세요.", "Hatch your very first Pokémon egg.", "初めてのポケモンのタマゴを孵化させる。", "Eclosiona tu primer huevo Pokémon.", "Faites éclore votre premier œuf Pokémon.", "Choque seu primeiríssimo ovo Pokémon.", "Lasse dein allererstes Pokémon-Ei schlüpfen.")
        case .firstEvolve: return t("포켓몬을 처음으로 진화시키세요.", "Evolve a Pokémon for the first time.", "初めてポケモンを進化させる。", "Evoluciona un Pokémon por primera vez.", "Faites évoluer un Pokémon pour la première fois.", "Evolua um Pokémon pela primeira vez.", "Entwickle zum ersten Mal ein Pokémon.")
        case .firstGraduate: return t("포켓몬을 최종 진화시켜 도감으로 졸업시키세요.", "Complete an evolution line and graduate a Pokémon.", "進化ラインを完走して図鑑へ卒業させる。", "Completa una línea evolutiva y gradúa un Pokémon.", "Complétez une lignée évolutive et diplômez un Pokémon.", "Complete uma linha evolutiva e gradue um Pokémon.", "Schließe eine Entwicklungslinie ab und graduiere ein Pokémon.")
        case .squad5: return t("서로 다른 포켓몬 5종을 졸업시키세요.", "Graduate 5 different Pokémon species.", "異なる5種のポケモンを卒業させる。", "Gradúa 5 especies de Pokémon diferentes.", "Diplômez 5 espèces de Pokémon différentes.", "Gradue 5 espécies diferentes de Pokémon.", "Graduiere 5 verschiedene Pokémon-Spezies.")
        case .dex15: return t("도감에 15종 이상의 포켓몬을 등록하세요.", "Register 15 unique species in your Pokédex.", "図鑑に15種以上のポケモンを登録する。", "Registra 15 especies únicas en tu Pokédex.", "Enregistrez 15 espèces différentes dans le Pokédex.", "Registre 15 espécies únicas na sua Pokédex.", "Registriere 15 verschiedene Spezies im Pokédex.")
        case .dex30: return t("도감에 30종 이상의 포켓몬을 등록하세요.", "Register 30 unique species in your Pokédex.", "図鑑に30種以上のポケモンを登録する。", "Registra 30 especies únicas en tu Pokédex.", "Enregistrez 30 espèces différentes dans le Pokédex.", "Registre 30 espécies únicas na sua Pokédex.", "Registriere 30 verschiedene Spezies im Pokédex.")
        case .shinyHunter: return t("이로치(색이 다른) 포켓몬을 획득하세요.", "Obtain your first Shiny Pokémon.", "初めての色違いポケモンを獲得する。", "Consigue tu primer Pokémon variocolor.", "Obtenez votre premier Pokémon chromatique (Shiny).", "Obtenha seu primeiro Pokémon shiny.", "Erhalte dein erstes schillerndes Pokémon.")
        case .streak3: return t("3일 연속으로 코딩하세요.", "Reach a 3-day coding streak.", "3日連続でコーディングする。", "Alcanza una racha de 3 días programando.", "Atteignez une série de 3 jours de code consécutifs.", "Alcance uma sequência de 3 dias de código.", "Erreiche einen 3-Tage-Coding-Streak.")
        case .streak7: return t("7일 연속으로 코딩하세요.", "Reach a 7-day coding streak.", "7日連続でコーディングする。", "Alcanza una racha de 7 días programando.", "Atteignez une série de 7 jours de code consécutifs.", "Alcance uma sequência de 7 dias de código.", "Erreiche einen 7-Tage-Coding-Streak.")
        case .streak14: return t("14일 연속으로 코딩하세요.", "Reach a 14-day coding streak.", "14日連続でコーディングする。", "Alcanza una racha de 14 días programando.", "Atteignez une série de 14 jours de code consécutifs.", "Alcance uma sequência de 14 dias de código.", "Erreiche einen 14-Tage-Coding-Streak.")
        case .streak30: return t("30일 연속으로 코딩하세요.", "Reach a 30-day coding streak.", "30日連続でコーディングする。", "Alcanza una racha de 30 días programando.", "Atteignez une série de 30 jours de code consécutifs.", "Alcance uma sequência de 30 dias de código.", "Erreiche einen 30-Tage-Coding-Streak.")
        case .tokens100M: return t("누적 100M 토큰을 사용하세요.", "Burn 100M total lifetime tokens.", "累計100Mトークンを使用する。", "Consume 100M de tokens en total.", "Consommez 100M de tokens au total.", "Use 100M de tokens no total.", "Verbrauche insgesamt 100M Tokens.")
        case .tokens1B: return t("누적 1B 토큰을 사용하세요.", "Burn 1 billion total lifetime tokens.", "累計1Bトークンを使用する。", "Consume 1B de tokens en total.", "Consommez 1 milliard de tokens au total.", "Use 1B de tokens no total.", "Verbrauche insgesamt 1B Tokens.")
        case .tokens5B: return t("누적 5B 토큰을 사용하세요.", "Burn 5 billion total lifetime tokens.", "累計5Bトークンを使用する。", "Consume 5B de tokens en total.", "Consommez 5 milliards de tokens au total.", "Use 5B de tokens no total.", "Verbrauche insgesamt 5B Tokens.")
        case .tokens10B: return t("누적 10B 토큰을 사용하세요.", "Burn 10 billion total lifetime tokens.", "累計10Bトークンを使用する。", "Consume 10B de tokens en total.", "Consommez 10 milliards de tokens au total.", "Use 10B de tokens no total.", "Verbrauche insgesamt 10B Tokens.")
        case .candyUser: return t("이상한 사탕을 5개 사용하세요.", "Use 5 Rare Candies on your Pokémon.", "ふしぎなアメ를5個使用する。", "Usa 5 Caramelos Raros en tu Pokémon.", "Utilisez 5 Super Bonbons sur vos Pokémon.", "Use 5 Doces Raros nos seus Pokémon.", "Verwende 5 Sonderbonbons bei deinem Pokémon.")
        case .shopSpender: return t("상점에서 누적 1B 토큰을 지출하세요.", "Spend 1 billion tokens in the Shop.", "ショップで累計1Bトークンを使う。", "Gasta 1B de tokens en la Tienda.", "Dépensez 1 milliard de tokens dans la Boutique.", "Gaste 1B de tokens na Loja.", "Gib 1 Milliarde Tokens im Laden aus.")
        case .limitBreaker: return t("공식 사용량 한도 100%에 도달하세요.", "Reach 100% of an official usage limit.", "公式利用上限の100%に到達する。", "Alcanza el 100% de un límite oficial de uso.", "Atteignez 100% d'une limite d'utilisation officielle.", "Alcance 100% de um limite oficial de uso.", "Erreiche 100% eines offiziellen Nutzungslimits.")
        case .duplicateLegendary: return t("이미 졸업시킨 전설의 포켓몬과 같은 종을 한 번 더 졸업시키세요.", "Graduate a duplicate of a Legendary Pokémon you have already raised.", "すでに卒業させた伝説のポケモンと同じ種をもう一度卒業させる。", "Gradúa un duplicado de un Pokémon legendario que ya hayas criado.", "Complétez l'élevage d'un doublon d'un Pokémon légendaire que vous possédez déjà.", "Gradue uma duplicata de um Pokémon lendário que você já criou.", "Graduiere ein Duplikat eines bereits gezüchteten legendären Pokémon.")
        case .legendaryBirds: return t("프리져, 썬더, 파이어를 모두 도감에 등록하세요.", "Register Articuno, Zapdos, and Moltres in your Pokédex.", "フリーザー、サンダー、ファイヤーをすべて図鑑に登録する。", "Registra a Articuno, Zapdos y Moltres en tu Pokédex.", "Enregistrez Artikodin, Électhor et Sulfura dans le Pokédex.", "Registre Articuno, Zapdos e Moltres na sua Pokédex.", "Registriere Arktos, Zapdos und Lavados im Pokédex.")
        case .kantoDuo: return t("뮤츠와 뮤를 모두 도감에 등록하세요.", "Register Mewtwo and Mew in your Pokédex.", "ミュウツーとミュウを両方図鑑に登録する。", "Registra a Mewtwo y Mew en tu Pokédex.", "Enregistrez Mewtwo et Mew dans le Pokédex.", "Registre Mewtwo e Mew na sua Pokédex.", "Registriere Mewtu und Mew im Pokédex.")
        case .legendaryBeasts: return t("라이코, 앤테이, 스이쿤을 모두 도감에 등록하세요.", "Register Raikou, Entei, and Suicune in your Pokédex.", "ライコウ、エンテイ、スイクンをすべて図鑑に登録する。", "Registra a Raikou, Entei y Suicune en tu Pokédex.", "Enregistrez Raikou, Entei et Suicune dans le Pokédex.", "Registre Raikou, Entei e Suicune na sua Pokédex.", "Registriere Raikou, Entei und Suicune im Pokédex.")
        case .towerDuo: return t("루기아와 칠색조를 모두 도감에 등록하세요.", "Register Lugia and Ho-Oh in your Pokédex.", "ルギアとホウオウを両方図鑑に登録する。", "Registra a Lugia y Ho-Oh en tu Pokédex.", "Enregistrez Lugia et Ho-Oh dans le Pokédex.", "Registre Lugia e Ho-Oh na sua Pokédex.", "Registriere Lugia und Ho-Oh im Pokédex.")
        case .legendaryTitans: return t("레지락, 레지아이스, 레지스틸을 모두 도감에 등록하세요.", "Register Regirock, Regice, and Registeel in your Pokédex.", "レジロック、レジアイス、レジスチルをすべて図鑑に登録する。", "Registra a Regirock, Regice y Registeel en tu Pokédex.", "Enregistrez Regirock, Regice et Registeel dans le Pokédex.", "Registre Regirock, Regice e Registeel na sua Pokédex.", "Registriere Regirock, Regice und Registeel im Pokédex.")
        case .eonDuo: return t("라티아스와 라티오스를 모두 도감에 등록하세요.", "Register Latias and Latios in your Pokédex.", "ラティアスとラティオスを両方図鑑に登録する。", "Registra a Latias y Latios en tu Pokédex.", "Enregistrez Latias et Latios dans le Pokédex.", "Registre Latias e Latios na sua Pokédex.", "Registriere Latias und Latios im Pokédex.")
        case .weatherTrio: return t("가이오가, 그란돈, 레쿠쟈를 모두 도감에 등록하세요.", "Register Kyogre, Groudon, and Rayquaza in your Pokédex.", "カイオーガ、グラードン、レックウザをすべて図鑑に登録する。", "Registra a Kyogre, Groudon y Rayquaza en tu Pokédex.", "Enregistrez Kyogre, Groudon et Rayquaza dans le Pokédex.", "Registre Kyogre, Groudon e Rayquaza na sua Pokédex.", "Registriere Kyogre, Groudon und Rayquaza im Pokédex.")
        case .lakeGuardians: return t("유크시, 엠라이트, 아그놈을 모두 도감에 등록하세요.", "Register Uxie, Mesprit, and Azelf in your Pokédex.", "ユクシー、エムリット、アグノムをすべて図鑑に登録する。", "Registra a Uxie, Mesprit y Azelf en tu Pokédex.", "Enregistrez Créhelf, Créfollet et Créfadet dans le Pokédex.", "Registre Uxie, Mesprit e Azelf na sua Pokédex.", "Registriere Selfe, Vesprit und Tobutz im Pokédex.")
        case .creationTrio: return t("디아루가, 펄기아, 기라티나를 모두 도감에 등록하세요.", "Register Dialga, Palkia, and Giratina in your Pokédex.", "ディアルガ、パルキア、ギラティナをすべて図鑑に登録する。", "Registra a Dialga, Palkia y Giratina en tu Pokédex.", "Enregistrez Dialga, Palkia et Giratina dans le Pokédex.", "Registre Dialga, Palkia e Giratina na sua Pokédex.", "Registriere Dialga, Palkia und Giratina im Pokédex.")
        case .swordsOfJustice: return t("코바르온, 테라키온, 비리디온을 모두 도감에 등록하세요.", "Register Cobalion, Terrakion, and Virizion in your Pokédex.", "コバルオン、テラキオン、ビリジオンをすべて図鑑に登録する。", "Registra a Cobalion, Terrakion y Virizion en tu Pokédex.", "Enregistrez Cobaltium, Terrakium et Viridium dans le Pokédex.", "Registre Cobalion, Terrakion e Virizion na sua Pokédex.", "Registriere Kobalium, Terrakium und Viridium im Pokédex.")
        case .forcesOfNature: return t("토네로스, 볼트로스, 랜드로스를 모두 도감에 등록하세요.", "Register Tornadus, Thundurus, and Landorus in your Pokédex.", "トルネロス、ボルトロス、ランドロスをすべて図鑑に登録する。", "Registra a Tornadus, Thundurus y Landorus en tu Pokédex.", "Enregistrez Boréas, Fulguris et Démétéros dans le Pokédex.", "Registre Tornadus, Thundurus e Landorus na sua Pokédex.", "Registriere Boreos, Voltolos und Demeteros im Pokédex.")
        case .taoDuo: return t("레시라무와 제크로무를 모두 도감에 등록하세요.", "Register Reshiram and Zekrom in your Pokédex.", "レシラムとゼクロムを両方図鑑に登録する。", "Registra a Reshiram y Zekrom en tu Pokédex.", "Enregistrez Reshiram et Zekrom dans le Pokédex.", "Registre Reshiram e Zekrom na sua Pokédex.", "Registriere Reshiram und Zekrom im Pokédex.")
        case .kantoStarters: return t("이상해꽃, 리자몽, 거북왕을 모두 도감에 등록하세요.", "Register Venusaur, Charizard, and Blastoise in your Pokédex.", "フシギバナ、リザードン、カメックスをすべて図鑑に登録する。", "Registra a Venusaur, Charizard y Blastoise en tu Pokédex.", "Enregistrez Florizarre, Dracaufeu et Tortank dans le Pokédex.", "Registre Venusaur, Charizard e Blastoise na sua Pokédex.", "Registriere Bisaflor, Glurak und Turtok im Pokédex.")
        case .johtoStarters: return t("메가니움, 블레이범, 장크로다일을 모두 도감에 등록하세요.", "Register Meganium, Typhlosion, and Feraligatr in your Pokédex.", "メガニウム、バクフーン、オーダイルをすべて図鑑に登録する。", "Registra a Meganium, Typhlosion y Feraligatr en tu Pokédex.", "Enregistrez Méganium, Typhlosion et Aligatueur dans le Pokédex.", "Registre Meganium, Typhlosion e Feraligatr na sua Pokédex.", "Registriere Meganie, Tornupto und Impergator im Pokédex.")
        case .hoennStarters: return t("나무킹, 번치코, 대짱이를 모두 도감에 등록하세요.", "Register Sceptile, Blaziken, and Swampert in your Pokédex.", "ジュカイン、バシャーモ、ラグラージをすべて図鑑に登録する。", "Registra a Sceptile, Blaziken y Swampert en tu Pokédex.", "Enregistrez Jungko, Braségali et Laggron dans le Pokédex.", "Registre Sceptile, Blaziken e Swampert na sua Pokédex.", "Registriere Gewaldro, Lohgock und Sumpex im Pokédex.")
        case .sinnohStarters: return t("토대부기, 초염몽, 엠페르트를 모두 도감에 등록하세요.", "Register Torterra, Infernape, and Empoleon in your Pokédex.", "ドダイトス、ゴウカザル、エンペルトをすべて図鑑に登録する。", "Registra a Torterra, Infernape y Empoleon en tu Pokédex.", "Enregistrez Torterra, Simiabraz et Pingoléon dans le Pokédex.", "Registre Torterra, Infernape e Empoleon na sua Pokédex.", "Registriere Chelterrar, Panferno und Impoleon im Pokédex.")
        case .unovaStarters: return t("샤로다, 염무왕, 대검귀를 모두 도감에 등록하세요.", "Register Serperior, Emboar, and Samurott in your Pokédex.", "ジャローダ、エンブオー、ダイケンキをすべて図鑑に登録する。", "Registra a Serperior, Emboar y Samurott en tu Pokédex.", "Enregistrez Majaspic, Roitiflam et Clamiral dans le Pokédex.", "Registre Serperior, Emboar e Samurott na sua Pokédex.", "Registriere Serpiroyal, Flambirex und Admurai im Pokédex.")
        case .starterMaster: return t("도감에 1~5세대 최종 진화 스타팅 포켓몬 15종을 모두 등록하세요.", "Register all 15 fully evolved starter Pokémon in your Pokédex.", "第1〜5世代の最終進化スターターポケモン15種をすべて図鑑に登録する。", "Registra a los 15 Pokémon iniciales totalmente evolucionados en tu Pokédex.", "Enregistrez les 15 Pokémon de départ entièrement évolués dans le Pokédex.", "Registre todos os 15 Pokémon iniciais totalmente evoluídos na sua Pokédex.", "Registriere alle 15 voll entwickelten Starter-Pokémon im Pokédex.")
        case .eeveeKantoTrio: return t("샤미드, 쥬피썬더, 부스터를 모두 도감에 등록하세요.", "Register Vaporeon, Jolteon, and Flareon in your Pokédex.", "シャワーズ、サンダース、ブースターをすべて図鑑に登録する。", "Registra a Vaporeon, Jolteon y Flareon en tu Pokédex.", "Enregistrez Aquali, Voltali et Pyroli dans le Pokédex.", "Registre Vaporeon, Jolteon e Flareon na sua Pokédex.", "Registriere Aquana, Blitza und Flamara im Pokédex.")
        case .eeveeJohtoDuo: return t("에브이와 블래키를 모두 도감에 등록하세요.", "Register Espeon and Umbreon in your Pokédex.", "エーフィとブラッキーを両方図鑑に登録する。", "Registra a Espeon y Umbreon en tu Pokédex.", "Enregistrez Mentali et Noctali dans le Pokédex.", "Registre Espeon e Umbreon na sua Pokédex.", "Registriere Psiana und Nachtara im Pokédex.")
        case .eeveeSinnohDuo: return t("리피아와 글레이시아를 모두 도감에 등록하세요.", "Register Leafeon and Glaceon in your Pokédex.", "リーフィアとグレイシアを両方図鑑に登録する。", "Registra a Leafeon y Glaceon en tu Pokédex.", "Enregistrez Phyllali et Givrali dans le Pokédex.", "Registre Leafeon e Glaceon na sua Pokédex.", "Registriere Folipurba und Glaziola im Pokédex.")
        case .eeveeMaster: return t("1~4세대 이브이 진화형 7종을 모두 도감에 등록하세요.", "Register all 7 Eevee evolutions in your Pokédex.", "第1〜4世代のブイズ7種をすべて図鑑に登録する。", "Registra las 7 evoluciones de Eevee en tu Pokédex.", "Enregistrez les 7 évolutions d'Évoli dans le Pokédex.", "Registre todas as 7 evoluções de Eevee na sua Pokédex.", "Registriere alle 7 Evoli-Entwicklungen im Pokédex.")
        case .firstFossil: return t("최종 진화 화석 포켓몬 1종을 도감에 등록하세요.", "Register at least 1 fully evolved fossil Pokémon in your Pokédex.", "最終進化の化石ポケモン1種を図鑑に登録する。", "Registra al menos 1 Pokémon fósil completamente evolucionado en tu Pokédex.", "Enregistrez au moins 1 Pokémon fossile final dans le Pokédex.", "Registre pelo menos 1 Pokémon fóssil totalmente evoluído na sua Pokédex.", "Registriere mindestens 1 voll entwickeltes Fossil-Pokémon im Pokédex.")
        case .fossilCollector: return t("최종 진화 화석 포켓몬 4종을 도감에 등록하세요.", "Register 4 different fully evolved fossil Pokémon in your Pokédex.", "最終進化の化石ポケモン4種を図鑑に登録する。", "Registra 4 Pokémon fósiles totalmente evolucionados en tu Pokédex.", "Enregistrez 4 Pokémon fossiles finaux différents dans le Pokédex.", "Registre 4 Pokémon fósseis totalmente evoluídos na sua Pokédex.", "Registriere 4 voll entwickelte Fossil-Pokémon im Pokédex.")
        case .fossilMaster: return t("1~5세대 최종 진화 화석 포켓몬 9종을 모두 도감에 등록하세요.", "Register all 9 fully evolved fossil Pokémon in your Pokédex.", "第1〜5世代の最終進化化石ポケモン9種をすべて図鑑に登録する。", "Registra los 9 Pokémon fósiles totalmente evolucionados en tu Pokédex.", "Enregistrez les 9 Pokémon fossiles entièrement évolués dans le Pokédex.", "Registre todos os 9 Pokémon fósseis totalmente evoluídos na sua Pokédex.", "Registriere alle 9 voll entwickelten Fossil-Pokémon im Pokédex.")
        case .elementalStones: return t("불꽃의돌, 물의돌, 천둥의돌을 각각 1회 이상 사용하세요.", "Use a Fire Stone, Water Stone, and Thunder Stone at least once.", "ほのおのいし、みずのいし、かみなりのいしをそれぞれ1回以上使う。", "Usa una Piedra Fuego, Piedra Agua y Piedra Trueno al menos una vez.", "Utilisez au moins une fois les pierres Feu, Eau et Foudre.", "Use uma Pedra do Fogo, Pedra da Água e Pedra do Trovão pelo menos uma vez.", "Verwende mindestens einmal einen Feuer-, Wasser- und Donnerstein.")
        case .allStonesUsed: return t("10종의 모든 진화의 돌을 각각 1회 이상 사용하세요.", "Use all 10 different evolution stones at least once.", "全10種の進化の石をそれぞれ1回以上使う。", "Usa las 10 piedras de evolución diferentes al menos una vez.", "Utilisez les 10 pierres d'évolution différentes au moins une fois.", "Use todas as 10 pedras de evolução diferentes pelo menos uma vez.", "Verwende alle 10 verschiedenen Entwicklungssteine mindestens einmal.")
        case .bagCollector: return t("가방에 서로 다른 8종의 아이템을 동시에 보유하세요.", "Possess at least 8 different item kinds in your bag at once.", "バッグに異なる8種類のアイテムを同時に所持する。", "Ten al menos 8 tipos de objetos diferentes en tu mochila a la vez.", "Possédez au moins 8 types d'objets différents simultanément dans votre sac.", "Tenha pelo menos 8 tipos de itens diferentes na sua mochila ao mesmo tempo.", "Besitze mindestens 8 verschiedene Gegenstandsarten gleichzeitig in deiner Tasche.")
        case .shinyTrio: return t("도감에 이로치 포켓몬 3종을 등록하세요.", "Register at least 3 shiny Pokémon in your Pokédex.", "図鑑に色違いポケモン3匹を登録する。", "Registra al menos 3 Pokémon variocolor en tu Pokédex.", "Enregistrez au moins 3 Pokémon chromatiques dans le Pokédex.", "Registre pelo menos 3 Pokémon brilhantes na sua Pokédex.", "Registriere mindestens 3 schillernde Pokémon im Pokédex.")
        case .shinySquad: return t("도감에 이로치 포켓몬 6종을 등록하세요.", "Register at least 6 shiny Pokémon in your Pokédex.", "図鑑に色違いポケモン6匹を登録する。", "Registra al menos 6 Pokémon variocolor en tu Pokédex.", "Enregistrez au moins 6 Pokémon chromatiques dans le Pokédex.", "Registre pelo menos 6 Pokémon brilhantes na sua Pokédex.", "Registriere mindestens 6 schillernde Pokémon im Pokédex.")
        case .shinyLegendOrStarter: return t("이로치 스타팅 또는 이로치 전설의 포켓몬을 획득하세요.", "Obtain a shiny starter or shiny legendary Pokémon.", "色違いのスターターまたは伝説のポケモンを獲得する。", "Consigue un Pokémon inicial o legendario variocolor.", "Obtenez un Pokémon de départ ou légendaire chromatique.", "Obtenha um Pokémon inicial ou lendário brilhante.", "Erhalte ein schillerndes Starter- oder legendäres Pokémon.")
        case .streak60: return t("60일 연속으로 코딩하세요.", "Reach a 60-day coding streak.", "60日連続でコーディングする。", "Alcanza una racha de 60 días programando.", "Atteignez une série de 60 jours de code consécutifs.", "Alcance uma sequência de 60 dias de código.", "Erreiche einen 60-Tage-Coding-Streak.")
        case .streak100: return t("100일 연속으로 코딩하세요.", "Reach a 100-day coding streak.", "100日連続でコーディングする。", "Alcanza una racha de 100 días programando.", "Atteignez une série de 100 jours de code consécutifs.", "Alcance uma sequência de 100 dias de código.", "Erreiche einen 100-Tage-Coding-Streak.")
        case .tokens25B: return t("누적 25B 토큰을 사용하세요.", "Burn 25 billion total lifetime tokens.", "累計25Bトークンを使用する。", "Consume 25B de tokens en total.", "Consommez 25 milliards de tokens au total.", "Use 25B de tokens no total.", "Verbrauche insgesamt 25B Tokens.")
        case .dailyMarathon: return t("하루 동안 100M 토큰 이상을 사용하세요.", "Burn 100M tokens or more in a single day.", "1日で100Mトークン以上を使用する。", "Consume 100M de tokens o más en un solo día.", "Consommez plus de 100M de tokens en une seule journée.", "Use 100M de tokens ou mais em um único dia.", "Verbrauche 100M Tokens oder mehr an einem Tag.")
        case .nightOwl: return t("새벽 1시에서 5시 사이에 코딩하세요.", "Log token usage between 1 AM and 5 AM.", "午前1時から5時の間にコーディングする。", "Registra uso de tokens entre la 1:00 y las 5:00.", "Enregistrez une session de tokens entre 1h et 5h du matin.", "Registre uso de tokens entre 1h e 5h.", "Erfasse Token-Nutzung zwischen 1:00 und 5:00 Uhr morgens.")
        case .earlyBird: return t("아침 7시 이전에 코딩하세요.", "Log token usage before 7 AM.", "午前7時前にコーディングする。", "Registra uso de tokens antes de las 7:00.", "Enregistrez une session de tokens avant 7h du matin.", "Registre uso de tokens antes das 7h.", "Erfasse Token-Nutzung vor 7:00 Uhr morgens.")
        default: return ""
        }
    }
}
