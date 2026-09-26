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
    var today: String { t("오늘", "Today", "今日", "Hoy", "Aujourd'hui", "Hoje", "Heute") }
    func unattributedClaudeUsage(_ tokens: String) -> String {
        t("이번 달 계정 미확인: \(tokens)", "Not linked to an account this month: \(tokens)", "今月アカウント不明: \(tokens)",
          "Sin cuenta asociada este mes: \(tokens)", "Non rattaché à un compte ce mois-ci : \(tokens)",
          "Sem conta associada neste mês: \(tokens)", "Diesen Monat keinem Konto zugeordnet: \(tokens)")
    }
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
    var fiveHourNotStarted: String { t("다음 메시지부터 시작", "Starts with your next message", "次のメッセージから開始", "Empieza con tu próximo mensaje", "Démarre au prochain message", "Começa na próxima mensagem", "Beginnt mit der nächsten Nachricht") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション", "Sesión de 5 horas", "Session de 5 h", "Sessão de 5 horas", "5-Stunden-Sitzung") }
    var weekly: String { t("주간", "Weekly", "週間", "Semanal", "Hebdo", "Semanal", "Wöchentlich") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus", "Opus semanal", "Opus hebdo", "Opus semanal", "Opus – wöchentlich") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet", "Sonnet semanal", "Sonnet hebdo", "Sonnet semanal", "Sonnet – wöchentlich") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック", "Bloque actual de 5h de Claude", "Bloc 5 h actuel de Claude", "Bloco atual de 5h do Claude", "Aktueller 5-Stunden-Block von Claude") }
    var reset: String { t("리셋", "Reset", "リセット", "Reinicio", "Réinit.", "Renovação", "Zurücksetzen") }
    /// 페이스 눈금 툴팁. "적정 사용량"으로 부르지 않는다 — 덜 쓰라는 권고가 아니라 "이 속도면 리셋
    /// 전에 소진된다"는 기준선이고, 창을 다 채워 쓸 이유가 없는 날에 규범으로 읽히면 안 된다.
    func paceHint(_ percent: String) -> String {
        t("페이스 — 창 시간만큼 균등하게 썼다면 지금 \(percent)입니다.",
          "Pace — an even burn across this window would sit at \(percent) now.",
          "ペース — この枠を均等に使っていれば今は \(percent) です。",
          "Ritmo: un consumo uniforme en esta ventana estaría en \(percent) ahora.",
          "Rythme — une consommation régulière sur cette fenêtre serait à \(percent).",
          "Ritmo — um consumo uniforme nesta janela estaria em \(percent) agora.",
          "Tempo – bei gleichmäßigem Verbrauch in diesem Fenster wären es jetzt \(percent).")
    }
    /// 페이스 대비 단계 이름. paceHint 와 같은 이유로 "적정"처럼 규범적인 말은 피하고
    /// 소진 속도만 묘사한다.
    func paceTier(_ tier: PaceTier) -> String {
        switch tier {
        case .wayUnder: return t("여유 많음", "Well under pace", "かなり余裕", "Muy por debajo del ritmo", "Bien sous le rythme", "Bem abaixo do ritmo", "Deutlich unter Tempo")
        case .under: return t("여유", "Under pace", "余裕あり", "Por debajo del ritmo", "Sous le rythme", "Abaixo do ritmo", "Unter Tempo")
        case .onPace: return t("페이스대로", "On pace", "ペース通り", "Al ritmo", "Dans le rythme", "No ritmo", "Im Tempo")
        case .slightlyOver: return t("조금 빠름", "Slightly fast", "やや速い", "Algo rápido", "Un peu rapide", "Um pouco rápido", "Etwas schnell")
        case .over: return t("빠름", "Fast", "速い", "Rápido", "Rapide", "Rápido", "Schnell")
        case .wayOver: return t("매우 빠름", "Very fast", "とても速い", "Muy rápido", "Très rapide", "Muito rápido", "Sehr schnell")
        }
    }
    /// 페이스 대비 차이(%p). **쓴 양**으로 말한다 — "앞섬/위" 같은 위치 표현은 잔량 모드에서
    /// 채움이 마커보다 짧게 그려질 때 방향이 반대로 읽힌다(#286 부류). 0 이면 문구 없음.
    /// 유럽어는 단계 이름("Under pace")이 이미 "페이스"를 말하므로 여기선 반복하지 않는다.
    func paceDelta(_ points: Int) -> String? {
        if points > 0 {
            return t("페이스보다 \(points)%p 더 씀", "\(points) pts more used", "ペースより\(points)pt多く使用",
                     "\(points) pts más de uso", "\(points) pts de plus utilisés",
                     "\(points) p.p. a mais de uso", "\(points) Pkt. mehr verbraucht")
        }
        if points < 0 {
            let n = -points
            return t("페이스보다 \(n)%p 덜 씀", "\(n) pts less used", "ペースより\(n)pt少なく使用",
                     "\(n) pts menos de uso", "\(n) pts de moins utilisés",
                     "\(n) p.p. a menos de uso", "\(n) Pkt. weniger verbraucht")
        }
        return nil
    }
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
    /// API `displayName` ("Gemini Models", "Claude and GPT models", …) → 앱 언어 라벨.
    /// 팝오버·한도 알림·사탕 알림·펫 버블이 같은 매핑을 써야 한 화면 두 언어가 안 난다(#322).
    /// 판정은 `AntigravityRateLimitStatus.geminiGroup` / `thirdPartyGroup` 과 같은 축(gemini /
    /// claude|gpt|3p). 모르는 이름은 API 문자열을 그대로 둔다.
    func antigravityGroupTitle(_ displayName: String) -> String {
        if displayName.localizedCaseInsensitiveContains("gemini") { return antigravityGeminiGroup }
        if displayName.localizedCaseInsensitiveContains("claude")
            || displayName.localizedCaseInsensitiveContains("gpt")
            || displayName.localizedCaseInsensitiveContains("3p") {
            return antigravityThirdPartyGroup
        }
        return displayName
    }
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

    // MARK: Usage recap
    var recapOpen: String { t("사용량 돌아보기", "Usage recap", "使用量のふりかえり", "Resumen de uso", "Récap d'utilisation", "Resumo de uso", "Nutzungsrückblick") }
    var recapTokensUnit: String { t("토큰", "tokens", "トークン", "tokens", "tokens", "tokens", "Tokens") }
    func recapScopeName(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("주간", "Week", "週", "Semana", "Semaine", "Semana", "Woche")
        case .month: t("월간", "Month", "月", "Mes", "Mois", "Mês", "Monat")
        case .year: t("연간", "Year", "年", "Año", "Année", "Ano", "Jahr")
        }
    }
    /// Shown under a running period, whose chip compares the same number of days.
    func recapCompareSoFar(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("지난주 같은 기간과 비교", "Compared with the same days last week", "先週の同じ期間と比較",
                      "Comparado con los mismos días de la semana pasada", "Comparé aux mêmes jours de la semaine dernière",
                      "Comparado com os mesmos dias da semana passada", "Verglichen mit denselben Tagen der Vorwoche")
        case .month: t("지난달 같은 기간과 비교", "Compared with the same days last month", "先月の同じ期間と比較",
                       "Comparado con los mismos días del mes pasado", "Comparé aux mêmes jours du mois dernier",
                       "Comparado com os mesmos dias do mês passado", "Verglichen mit denselben Tagen des Vormonats")
        case .year: t("작년 같은 기간과 비교", "Compared with the same days last year", "昨年の同じ期間と比較",
                      "Comparado con los mismos días del año pasado", "Comparé aux mêmes jours de l'an dernier",
                      "Comparado com os mesmos dias do ano passado", "Verglichen mit denselben Tagen des Vorjahres")
        }
    }
    var recapPrevious: String { t("이전", "Previous", "前へ", "Anterior", "Précédent", "Anterior", "Vorherige") }
    var recapNext: String { t("다음", "Next", "次へ", "Siguiente", "Suivant", "Próximo", "Nächste") }
    var recapBestDay: String { t("최고의 날", "Best day", "最高の日", "Mejor día", "Meilleur jour", "Melhor dia", "Bester Tag") }
    var recapActiveDays: String { t("활동한 날", "Active days", "稼働日", "Días activos", "Jours actifs", "Dias ativos", "Aktive Tage") }
    var recapBestStreak: String { t("최장 연속", "Best streak", "最長連続", "Mejor racha", "Meilleure série", "Melhor sequência", "Beste Serie") }
    var recapGraduates: String { t("졸업", "Graduated", "卒業", "Graduados", "Diplômés", "Formados", "Abschlüsse") }
    var recapNoData: String { t("기록 없음", "no data", "記録なし", "sin datos", "pas de données", "sem dados", "keine Daten") }
    func recapDays(_ count: Int) -> String {
        t("\(count)일", "\(count)d", "\(count)日", "\(count) d", "\(count) j", "\(count) d", "\(count) T")
    }
    func recapBestDayLine(_ day: String, _ tokens: String) -> String {
        t("최고의 날은 \(day) — \(tokens) 토큰.",
          "Your best day was \(day) — \(tokens) tokens.",
          "最高の日は \(day)、\(tokens) トークン。",
          "Tu mejor día fue el \(day): \(tokens) tokens.",
          "Ton meilleur jour, c'était \(day) : \(tokens) tokens.",
          "Seu melhor dia foi \(day): \(tokens) tokens.",
          "Dein bester Tag war \(day) — \(tokens) Tokens.")
    }
    var recapNoGraduates: String {
        t("이 기간에 졸업한 포켓몬이 없어요.", "No graduation in this period.", "この期間の卒業はありません。",
          "Ninguna graduación en este periodo.", "Aucun diplômé sur cette période.",
          "Nenhuma formatura neste período.", "Kein Abschluss in diesem Zeitraum.")
    }

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
    var menuLimitColor: String {
        t("퍼센트 색상", "Percent color", "パーセントの色", "Color del porcentaje", "Couleur du pourcentage",
          "Cor da porcentagem", "Prozentfarbe")
    }
    var menuLimitColorHint: String {
        t("팝오버 한도 게이지와 같은 색", "Same colors as the popover limit gauges",
          "ポップオーバーの上限ゲージと同じ色", "Los mismos colores que los medidores de límite",
          "Les mêmes couleurs que les jauges de limite", "As mesmas cores dos medidores de limite",
          "Dieselben Farben wie die Limit-Balken")
    }
    func menuLimitColorMode(_ mode: UsageStore.MenuLimitColorMode) -> String {
        switch mode {
        case .gauge:
            return t("게이지와 같게", "Match gauges", "ゲージと同じ", "Como los medidores",
                     "Comme les jauges", "Como os medidores", "Wie die Balken")
        case .attention:
            return t("주의 단계만", "Only when fast", "速いときだけ", "Solo si va rápido",
                     "Seulement si rapide", "Só quando rápido", "Nur wenn schnell")
        case .off:
            return t("끔", "Off", "オフ", "Desactivado", "Désactivé", "Desligado", "Aus")
        }
    }
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
    var sessionKeyPerAccountNote: String {
        t("기본 Claude 계정(~/.claude)에 적용됩니다. 다른 계정은 아래에서 각자 키를 넣을 수 있어요.",
          "Applies to the default Claude account (~/.claude). Each other account can have its own key below.",
          "デフォルトの Claude アカウント（~/.claude）に適用されます。ほかのアカウントは下でそれぞれキーを設定できます。",
          "Se aplica a la cuenta de Claude predeterminada (~/.claude). Cada una de las otras cuentas puede tener su propia clave abajo.",
          "Concerne le compte Claude principal (~/.claude). Chaque autre compte peut avoir sa propre clé ci-dessous.",
          "Aplica-se à conta padrão do Claude (~/.claude). Cada uma das outras contas pode ter a própria chave abaixo.",
          "Gilt für das Standard-Claude-Konto (~/.claude). Jedes weitere Konto kann unten einen eigenen Schlüssel haben.")
    }
    /// An additional account's own key row: the account's tab title, or its folder before its limits load.
    func accountSessionKeyLabel(_ account: String) -> String {
        t("\(account) 세션 키", "Session key for \(account)", "\(account) のセッションキー",
          "Clave de sesión de \(account)", "Clé de session de \(account)", "Chave de sessão de \(account)",
          "Sitzungsschlüssel für \(account)")
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
    // MARK: Additional Claude accounts (Settings → Advanced)
    var additionalClaudeAccountsLabel: String { t("추가 Claude 계정", "Additional Claude accounts", "追加のClaudeアカウント", "Cuentas de Claude adicionales", "Comptes Claude supplémentaires", "Contas extras do Claude", "Weitere Claude-Konten") }
    var additionalClaudeAccountsHint: String {
        t("다른 Claude Code 로그인(CLAUDE_CONFIG_DIR)은 ~/.claude-* 폴더와 export 된 CLAUDE_CONFIG_DIR 에서 자동으로 찾습니다. 다른 위치의 설정 폴더만 여기 추가하세요(콤마·줄바꿈 구분). 공식 한도에 계정마다 탭이 생기며, 수동 갱신 때 폴더마다 Keychain 접근을 물을 수 있습니다.",
          "Other Claude Code logins (CLAUDE_CONFIG_DIR) are detected in ~/.claude-* folders and from an exported CLAUDE_CONFIG_DIR. Add config folders stored elsewhere here, comma/newline separated. Each account gets its own tab in the official limits; a manual refresh may ask for Keychain access for each folder.",
          "他のClaude Codeログイン(CLAUDE_CONFIG_DIR)は ~/.claude-* フォルダと、エクスポートされた CLAUDE_CONFIG_DIR から自動検出されます。別の場所にある設定フォルダだけをここに追加してください(カンマ・改行区切り)。公式上限にアカウントごとのタブが追加され、手動更新時にフォルダごとにKeychainへのアクセスを確認することがあります。",
          "Los otros inicios de sesión de Claude Code (CLAUDE_CONFIG_DIR) se detectan en las carpetas ~/.claude-* y en un CLAUDE_CONFIG_DIR exportado. Añade aquí las carpetas de configuración guardadas en otro lugar, separadas por coma o salto de línea. Cada cuenta tiene su pestaña en los límites oficiales; una actualización manual puede pedir acceso a Keychain para cada carpeta.",
          "Les autres connexions Claude Code (CLAUDE_CONFIG_DIR) sont détectées dans les dossiers ~/.claude-* et depuis un CLAUDE_CONFIG_DIR exporté. Ajoute ici les dossiers de config rangés ailleurs, séparés par des virgules ou des retours à la ligne. Chaque compte a son onglet dans les limites officielles ; une actualisation manuelle peut demander l'accès au Keychain pour chaque dossier.",
          "Os outros logins do Claude Code (CLAUDE_CONFIG_DIR) são detectados nas pastas ~/.claude-* e num CLAUDE_CONFIG_DIR exportado. Adicione aqui pastas de configuração guardadas em outro lugar, separadas por vírgula ou quebra de linha. Cada conta ganha sua aba nos limites oficiais; uma atualização manual pode pedir acesso ao Keychain para cada pasta.",
          "Weitere Claude-Code-Anmeldungen (CLAUDE_CONFIG_DIR) werden in ~/.claude-*-Ordnern und über ein exportiertes CLAUDE_CONFIG_DIR erkannt. Füge hier Konfigurationsordner an anderen Orten hinzu, durch Kommas oder Zeilenumbrüche getrennt. Jedes Konto bekommt bei den offiziellen Limits einen eigenen Tab; eine manuelle Aktualisierung kann für jeden Ordner nach Keychain-Zugriff fragen.")
    }
    func additionalClaudeAccountsDetected(_ folders: String) -> String {
        t("자동 감지: \(folders)", "Detected: \(folders)", "自動検出: \(folders)", "Detectadas: \(folders)", "Détectés : \(folders)", "Detectadas: \(folders)", "Erkannt: \(folders)")
    }
    var trackedAccountLabel: String { t("추적할 Claude 계정", "Tracked Claude account", "追跡する Claude アカウント", "Cuenta de Claude seguida", "Compte Claude suivi", "Conta do Claude acompanhada", "Verfolgtes Claude-Konto") }
    func trackedAccountToolTip(_ title: String) -> String {
        t("추적할 Claude 계정: \(title)", "Tracked Claude account: \(title)", "追跡する Claude アカウント: \(title)",
          "Cuenta de Claude seguida: \(title)", "Compte Claude suivi : \(title)",
          "Conta do Claude acompanhada: \(title)", "Verfolgtes Claude-Konto: \(title)")
    }
    var trackedAccountHint: String {
        t("메뉴바 한도·경고 상태·컴패니언 기분·5시간 예측의 기준이에요.",
          "Drives the menu bar limit, warning state, companion mood and 5h forecast.",
          "メニューバーの上限・警告状態・コンパニオンの様子・5時間予測に使われます。",
          "Define el límite de la barra de menús, el estado de alerta, el ánimo del compañero y la previsión de 5 h.",
          "Pilote la limite de la barre des menus, l'état d'alerte, l'humeur du compagnon et la prévision 5 h.",
          "Define o limite na barra de menus, o estado de alerta, o humor do companheiro e a previsão de 5 h.",
          "Bestimmt das Limit in der Menüleiste, den Warnstatus, die Stimmung des Begleiters und die 5-Stunden-Prognose.")
    }
    var trackedAccountAutomatic: String { t("자동 (마지막 사용)", "Automatic (last used)", "自動（最後に使用）", "Automático (último usado)", "Automatique (dernier utilisé)", "Automático (último usado)", "Automatisch (zuletzt verwendet)") }
    var trackedAccountHighest: String { t("사용률 최고", "Highest usage", "使用率が最大", "Mayor uso", "Le plus chargé", "Maior uso", "Höchste Auslastung") }
    var additionalClaudeAccountsPlaceholder: String { t("~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work") }
    func additionalClaudeAccountsFound(_ n: Int) -> String {
        t("계정 폴더 \(n)개 찾음", "\(n) account folder(s) found", "アカウントフォルダが\(n)個見つかりました", "\(n) carpeta(s) de cuenta encontrada(s)", "\(n) dossier(s) de compte trouvé(s)", "\(n) pasta(s) de conta encontrada(s)", "Gefundene Kontoordner: \(n)")
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

    // MARK: 스냅샷 백업 (설정 → 자동 백업)
    var snapshotsSectionTitle: String {
        t("자동 백업 (스냅샷)",
          "Automatic Backups (Snapshots)",
          "自動バックアップ（スナップショット）",
          "Copias automáticas (Instantáneas)",
          "Sauvegardes automatiques (Instantanés)",
          "Backups automáticos (Instantâneos)",
          "Automatische Sicherungen (Snapshots)")
    }
    var createSnapshotButton: String {
        t("스냅샷 만들기",
          "Create snapshot",
          "スナップショットを作成",
          "Crear instantánea",
          "Créer un instantané",
          "Criar instantâneo",
          "Snapshot erstellen")
    }
    var createSnapshotHint: String {
        t("진행 상태의 로컬 복원 지점을 즉시 저장해요 (최근 10개 보존)",
          "Saves an instant local restore point of your progress (keeps up to 10)",
          "現在の進行状況の復元ポイントを即座に保存します（最新10件を保持）",
          "Guarda un punto de restauración local de tu progreso (mantiene hasta 10)",
          "Enregistre un point de restauration local de ta progression (jusqu'à 10 conservés)",
          "Salva um ponto de restauração local do seu progresso (mantém até 10)",
          "Speichert einen lokalen Wiederherstellungspunkt deines Fortschritts (behält bis zu 10)")
    }
    var snapshotCreatedToast: String {
        t("스냅샷이 생성되었습니다",
          "Snapshot created",
          "スナップショットを作成しました",
          "Instantánea creada",
          "Instantané créé",
          "Instantâneo criado",
          "Snapshot erstellt")
    }
    var restoreSnapshotButton: String {
        t("복원",
          "Restore",
          "復元",
          "Restaurar",
          "Restaurer",
          "Restaurar",
          "Wiederherstellen")
    }
    var restoreConfirmTitle: String {
        t("이 스냅샷으로 복원할까요?",
          "Restore this snapshot?",
          "このスナップショットに復元しますか？",
          "¿Restaurar esta instantánea?",
          "Restaurer cet instantané ?",
          "Restaurar este instantâneo?",
          "Diesen Snapshot wiederherstellen?")
    }
    func restoreConfirmBody(snapshotDate: String, snapshotDex: Int, snapshotTokens: String,
                            currentDex: Int, currentTokens: String) -> String {
        t("""
          복원할 스냅샷: 도감 \(snapshotDex)마리 · 누적 \(snapshotTokens)
          저장 시각: \(snapshotDate)
          현재 상태: 도감 \(currentDex)마리 · 누적 \(currentTokens)

          현재 상태는 새 스냅샷으로 자동 백업된 뒤 복원됩니다.
          """,
          """
          Target snapshot: \(snapshotDex) in Pokédex · \(snapshotTokens) lifetime
          Created: \(snapshotDate)
          Current state: \(currentDex) in Pokédex · \(currentTokens) lifetime

          Your current state will be backed up as a new snapshot before restoring.
          """,
          """
          復元するスナップショット: 図鑑 \(snapshotDex)匹 · 累計 \(snapshotTokens)
          作成日時: \(snapshotDate)
          現在の状態: 図鑑 \(currentDex)匹 · 累計 \(currentTokens)

          現在の状態は復元前に新しいスナップショットとしてバックアップされます。
          """,
          """
          Instantánea a restaurar: Pokédex \(snapshotDex) · \(snapshotTokens) acumulados
          Creada: \(snapshotDate)
          Estado actual: Pokédex \(currentDex) · \(currentTokens) acumulados

          Tu estado actual se guardará como una nueva instantánea antes de restaurar.
          """,
          """
          Instantané à restaurer : Pokédex \(snapshotDex) · \(snapshotTokens) cumulés
          Créé le : \(snapshotDate)
          État actuel : Pokédex \(currentDex) · \(currentTokens) cumulés

          Ton état actuel sera sauvegardé dans un nouvel instantané avant la restauration.
          """,
          """
          Instantâneo a restaurar: Pokédex \(snapshotDex) · \(snapshotTokens) acumulados
          Criado: \(snapshotDate)
          Estado atual: Pokédex \(currentDex) · \(currentTokens) acumulados

          Seu estado atual será salvo como um novo instantâneo antes de restaurar.
          """,
          """
          Wiederherzustellender Snapshot: \(snapshotDex) im Pokédex · \(snapshotTokens) insgesamt
          Erstellt: \(snapshotDate)
          Aktueller Stand: \(currentDex) im Pokédex · \(currentTokens) insgesamt

          Dein aktueller Stand wird vor der Wiederherstellung als neuer Snapshot gesichert.
          """)
    }
    func restoreDoneMessage(dex: Int, tokens: String) -> String {
        t("복원되었습니다 — 도감 \(dex)마리 · 누적 \(tokens)",
          "Restored — \(dex) in Pokédex · \(tokens) lifetime",
          "復元しました — 図鑑 \(dex)匹 · 累計 \(tokens)",
          "Restaurado — Pokédex \(dex) · \(tokens) acumulados",
          "Restauré — Pokédex \(dex) · \(tokens) cumulés",
          "Restaurado — Pokédex \(dex) · \(tokens) acumulados",
          "Wiederhergestellt – \(dex) im Pokédex · \(tokens) insgesamt")
    }
    var noSnapshotsYet: String {
        t("아직 저장된 스냅샷이 없습니다",
          "No snapshots saved yet",
          "保存されたスナップショットはまだありません",
          "Aún no hay instantáneas guardadas",
          "Aucun instantané enregistré pour l'instant",
          "Nenhum instantâneo salvo ainda",
          "Noch keine Snapshots gespeichert")
    }
    func snapshotDexAndTokens(dex: Int, tokens: String) -> String {
        t("도감 \(dex)마리 · 누적 \(tokens)",
          "Pokédex \(dex) · \(tokens) lifetime",
          "図鑑 \(dex)匹 · 累計 \(tokens)",
          "Pokédex \(dex) · \(tokens) acumulados",
          "Pokédex \(dex) · \(tokens) cumulés",
          "Pokédex \(dex) · \(tokens) acumulados",
          "Pokédex \(dex) · \(tokens) insgesamt")
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
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明", "Próxima evolución desconocida", "Prochaine évolution inconnue", "Próxima evolución desconhecida", "Nächste Entwicklung unbekannt") }
    var eggIncubating: String { t("🥚 부화 준비 중", "🥚 Incubating", "🥚 孵化の準備中", "🥚 Incubando", "🥚 En incubation", "🥚 Incubando", "🥚 Wird ausgebrütet") }
    func eggToHatch(_ amount: String) -> String { t("부화까지 \(amount)", "\(amount) to hatch", "孵化まで \(amount)", "\(amount) para eclosionar", "\(amount) avant l'éclosion", "\(amount) para chocar", "\(amount) bis zum Schlüpfen") }
    /// 알 부화 임계 도달 후 외부 데이터 요청이 실패한 동안의 다음 새로고침 안내.
    var eggHatchDelayed: String {
        t("⏳ 부화가 지연되고 있어요. 다음 새로고침에서 다시 시도해요",
          "⏳ Hatching is delayed — retrying on the next refresh",
          "⏳ 孵化が遅れています。次回の更新時に再試行します",
          "⏳ La eclosión se retrasa; se reintentará en la próxima actualización",
          "⏳ L’éclosion est retardée — nouvel essai au prochain rafraîchissement",
          "⏳ A eclosão está atrasada — nova tentativa na próxima atualização",
          "⏳ Das Schlüpfen verzögert sich — neuer Versuch bei der nächsten Aktualisierung")
    }
    func toNextEvolution(_ amount: String) -> String { t("다음 진화까지 \(amount)", "\(amount) to next evolution", "次の進化まで \(amount)", "\(amount) para la siguiente evolución", "\(amount) avant la prochaine évolution", "\(amount) para a próxima evolución", "\(amount) bis zur nächsten Entwicklung") }
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
    func unownFormsCollected(_ count: Int) -> String {
        t("안농 글자 \(count)/28", "Unown forms \(count)/28", "アンノーン \(count)/28文字",
          "Formas Unown \(count)/28", "Formes Zarbi \(count)/28", "Formas Unown \(count)/28",
          "Icognito-Formen \(count)/28")
    }
    var unownChooseForm: String {
        t("글자 선택", "Choose form", "フォルムを選択", "Elegir forma", "Choisir une forme", "Escolher forma", "Form auswählen")
    }
    var unownNotCollected: String {
        t("미수집", "Not collected", "未収集", "Sin conseguir", "Non collectionnée", "Não coletada", "Noch nicht gesammelt")
    }
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
    var rarityLegendary: String { t("전설", "Legendary", "伝説", "Legendario", "Légendaire", "Lendário", "Legendär") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体", "Toca para ver solo esta rareza · toca de nuevo para ver todo", "Touche pour n'afficher que cette rareté · touche à nouveau pour tout afficher", "Toque para ver só esta raridade · toque de novo para ver tudo", "Tippe, um nur diese Seltenheit zu sehen · tippe erneut für alle") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い", "Variocolor", "Chromatique", "Shiny", "Schillernd") }
    var dexSearchPlaceholder: String { t("이름 또는 #번호 검색…", "Search name or #…", "名前または#番号で検索…", "Buscar por nombre o #…", "Rechercher par nom ou #…", "Buscar por nome ou #…", "Nach Name oder # suchen…") }
    var sortTitle: String { t("정렬", "Sort", "並び替え", "Ordenar", "Trier", "Ordenar", "Sortieren") }
    var sortDexNumberAsc: String { t("도감 번호 (낮은 순)", "Number (Low to High)", "図鑑番号（昇順）", "Nº de Pokédex (asc.)", "N° de Pokédex (croissant)", "Nº da Pokédex (crescente)", "Nummer (aufsteigend)") }
    var sortDexNumberDesc: String { t("도감 번호 (높은 순)", "Number (High to Low)", "図鑑番号（降順）", "Nº de Pokédex (desc.)", "N° de Pokédex (décroissant)", "Nº da Pokédex (decrescente)", "Nummer (absteigend)") }
    var sortNameAsc: String { t("이름 (가나다·A-Z)", "Name (A–Z)", "名前（五十音・A-Z）", "Nombre (A–Z)", "Nom (A–Z)", "Nome (A–Z)", "Name (A–Z)") }
    var sortNameDesc: String { t("이름 (역순)", "Name (Z–A)", "名前（逆順）", "Nombre (Z–A)", "Nom (Z–A)", "Nome (Z–A)", "Name (Z–A)") }
    var sortRarity: String { t("희귀도 순", "Rarity (High to Low)", "希少度順", "Rareza (mayor a menor)", "Rareté (décroissante)", "Raridade (maior a menor)", "Seltenheit (absteigend)") }
    var sortDateDesc: String { t("최근 잡은 순", "Most Recent", "最近捕獲", "Más recientes", "Plus récents", "Mais recentes", "Neueste zuerst") }
    var sortDateAsc: String { t("오래된 순", "Oldest First", "古い順", "Más antiguos", "Plus anciens", "Mais antigos", "Älteste zuerst") }
    var filterShinyOnly: String { t("이로치만", "Shiny only", "色違いのみ", "Solo variocolor", "Chromatique uniquement", "Apenas Shiny", "Nur schillernde") }
    var noSearchResults: String { t("검색 결과가 없어요", "No Pokémon found", "見つかりませんでした", "No se encontraron Pokémon", "Aucun Pokémon trouvé", "Nenhum Pokémon encontrado", "Keine Pokémon gefunden") }
    var clearFilters: String { t("필터 초기화", "Reset filters", "フィルターを解除", "Restablecer filtros", "Réinitialiser les filtres", "Redefinir filtros", "Filter zurücksetzen") }
    func label(for option: CompanionStore.DexSortOption) -> String {
        switch option {
        case .numberAsc: return sortDexNumberAsc
        case .numberDesc: return sortDexNumberDesc
        case .nameAsc: return sortNameAsc
        case .nameDesc: return sortNameDesc
        case .rarityDesc: return sortRarity
        }
    }
    func label(for option: CompanionStore.CatchLogSortOption) -> String {
        switch option {
        case .recentFirst: return sortDateDesc
        case .oldestFirst: return sortDateAsc
        case .numberAsc: return sortDexNumberAsc
        case .numberDesc: return sortDexNumberDesc
        case .nameAsc: return sortNameAsc
        case .nameDesc: return sortNameDesc
        case .rarityDesc: return sortRarity
        }
    }
    var dexNormalLabel: String { t("일반", "Normal", "通常", "Normal", "Normal", "Normal", "Normal") }
    var dexAppearance: String { t("모습", "Appearance", "姿", "Aspecto", "Apparence", "Aparência", "Aussehen") }
    var dexAppearancePreview: String { t("수집한 모습 · 종 정보", "Collected appearance · species reference", "収集した姿・種情報", "Aspecto coleccionado · datos de especie", "Apparence collectionnée · données de l’espèce", "Aparência coletada · dados da espécie", "Gesammeltes Aussehen · Speziesdaten") }
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
    func statusEvolved(_ name: String) -> String { t("\(KoreanParticle.direction.attach(to: name)) 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!") }
    var statusGrew: String { t("성장했어요!", "It grew!", "成長しました！", "¡Ha crecido!", "Il a grandi !", "Cresceu!", "Ist gewachsen!") }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { t("🥚 부화!", "🥚 Hatched!", "🥚 孵化！", "🥚 ¡Eclosionó!", "🥚 Éclosion !", "🥚 Chocou!", "🥚 Geschlüpft!") }
    func notifHatchBody(_ name: String) -> String { t("알에서 \(KoreanParticle.subject.attach(to: name)) 나왔어요!", "\(name) hatched from the egg!", "タマゴから \(name) が生まれました！", "¡\(name) salió del huevo!", "\(name) est sorti de l'œuf !", "\(name) saiu do ovo!", "\(name) ist aus dem Ei geschlüpft!") }
    var notifShinyHatchTitle: String { t("✨ 이로치 포켓몬!", "✨ Shiny Pokémon!", "✨ 色違いポケモン！", "✨ ¡Pokémon variocolor!", "✨ Pokémon chromatique !", "✨ Pokémon shiny!", "✨ Schillerndes Pokémon!") }
    /// 실제 판정에 쓴 분모를 받는다 — 부적이 있으면 64 가 아니다.
    func notifShinyHatchBody(_ name: String, odds: UInt64) -> String { t("이로치 \(KoreanParticle.subject.attach(to: name)) 태어났어요! (1/\(odds))", "A shiny \(name) hatched! (1 in \(odds))", "色違いの \(name) が生まれました！(1/\(odds))", "¡Nació un \(name) variocolor! (1 entre \(odds))", "Un \(name) chromatique est né ! (1 sur \(odds))", "Nasceu um \(name) shiny! (1 em \(odds))", "Ein schillerndes \(name) ist geschlüpft! (1/\(odds))") }
    var eggImminent: String { t("곧 부화해요!", "About to hatch!", "もうすぐ孵化！", "¡Está a punto de eclosionar!", "Sur le point d'éclore !", "Está quase chocando!", "Schlüpft gleich!") }
    /// 첫 실행(아직 토큰 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    /// `amount` 는 성장 난이도가 반영된 부화 임계(포맷된 값) — 고정 5M 이 아니다.
    func eggFirstRunHint(_ amount: String) -> String {
        t("로컬 AI 코딩 도구의 사용량으로 자라요. 약 \(amount) 토큰을 쓰면 알이 부화해요.",
          "Grows from your local AI coding usage. Your egg hatches after ~\(amount) tokens.",
          "ローカルの AI コーディング使用量で育ちます。約\(amount)トークンでタマゴが孵化します。",
          "Crece con el uso de tus herramientas locales de programación con IA. Tu huevo eclosiona tras unos \(amount) de tokens.",
          "Il grandit avec l'usage de tes outils de code IA locaux. Ton œuf éclôt après environ \(amount) de tokens.",
          "Cresce com o uso das suas ferramentas locais de programação com IA. O ovo choca depois de uns \(amount) de tokens.",
          "Wächst mit der Nutzung deiner lokalen KI-Coding-Tools. Nach etwa \(amount) Tokens schlüpft dein Ei.") }
    var notifEvolveTitle: String { t("✨ 진화!", "✨ Evolved!", "✨ 進化！", "✨ ¡Evolucionó!", "✨ Évolution !", "✨ Evoluiu!", "✨ Entwicklung!") }
    func notifEvolveBody(_ name: String) -> String { t("\(KoreanParticle.direction.attach(to: name)) 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!") }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { t("🎭 어라? 메타몽!", "🎭 Huh? It's Ditto!", "🎭 あれ？メタモン！", "🎭 ¿Eh? ¡Es Ditto!", "🎭 Hein ? C'est Métamorph !", "🎭 Ué? É um Ditto!", "🎭 Huch? Ditto!") }
    func notifDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 사실은 메타몽이었어요!", "You thought it was \(disguise) — it was Ditto all along!", "\(disguise) だと思ってた… 実はメタモンでした！", "Pensabas que era \(disguise) — ¡en realidad era Ditto!", "Tu croyais que c'était \(disguise) — c'était Métamorph depuis le début !", "Você achava que era \(disguise) — era um Ditto o tempo todo!", "Du dachtest, es wäre \(disguise) – dabei war es die ganze Zeit Ditto!") }
    var notifShinyDittoRevealTitle: String { t("🎭✨ 어라? 이로치 메타몽!", "🎭✨ Huh? A shiny Ditto!", "🎭✨ あれ？色違いメタモン！", "🎭✨ ¿Eh? ¡Un Ditto variocolor!", "🎭✨ Hein ? Un Métamorph chromatique !", "🎭✨ Ué? Um Ditto shiny!", "🎭✨ Huch? Ein schillerndes Ditto!") }
    /// 확률을 적지 않는다 — 이로치는 부화 때 굴렸고, 그때의 부적 보유 여부는 저장되지 않는다.
    func notifShinyDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데 — 이로치 메타몽이었어요!", "You thought it was \(disguise) — it was a shiny Ditto!", "\(disguise) だと思ってた… 色違いのメタモンでした！", "Pensabas que era \(disguise) — ¡era un Ditto variocolor!", "Tu croyais que c'était \(disguise) — c'était un Métamorph chromatique !", "Você achava que era \(disguise) — era um Ditto shiny!", "Du dachtest, es wäre \(disguise) – dabei war es ein schillerndes Ditto!") }
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
    func additionalAccountExpiredHint(_ folder: String) -> String {
        t("CLAUDE_CONFIG_DIR=\(folder) 로 Claude Code 를 한 번 실행한 뒤 다시 시도하세요.",
          "Run Claude Code once with CLAUDE_CONFIG_DIR=\(folder), then retry.",
          "CLAUDE_CONFIG_DIR=\(folder) で Claude Code を一度実行してから再試行してください。",
          "Ejecuta Claude Code una vez con CLAUDE_CONFIG_DIR=\(folder) y reinténtalo.",
          "Lance Claude Code une fois avec CLAUDE_CONFIG_DIR=\(folder), puis réessaie.",
          "Rode o Claude Code uma vez com CLAUDE_CONFIG_DIR=\(folder) e tente de novo.",
          "Starte Claude Code einmal mit CLAUDE_CONFIG_DIR=\(folder) und versuch es dann erneut.")
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

    // MARK: Cursor 공식 한도(월간 포함 allowance)
    var cursorMonthlyIncluded: String {
        t("월간 포함 allowance", "Monthly included", "月間 included", "Incluido mensual", "Inclus mensuel", "Incluso mensal", "Monatlich inklusive")
    }
    var cursorAutoUsage: String {
        t("Auto 사용", "Auto usage", "Auto 使用", "Uso Auto", "Usage Auto", "Uso Auto", "Auto-Nutzung")
    }
    var cursorApiUsage: String {
        t("API 사용", "API usage", "API 使用", "Uso API", "Usage API", "Uso API", "API-Nutzung")
    }
    func cursorRemainingSpend(_ amount: String) -> String {
        t("\(amount) 남음", "\(amount) left", "残り \(amount)", "Quedan \(amount)", "Reste \(amount)", "Restam \(amount)", "\(amount) übrig")
    }
    var cursorAuthExpiredTitle: String {
        t("Cursor 세션 만료 — 한도가 갱신 안 돼요",
          "Cursor session expired — limits can't refresh",
          "Cursor セッション期限切れ — 上限を更新できません",
          "Sesión de Cursor expirada — los límites no se pueden actualizar",
          "Session Cursor expirée — les limites ne s'actualisent pas",
          "Sessão do Cursor expirada — não dá para atualizar os limites",
          "Cursor-Sitzung abgelaufen – Limits können nicht aktualisiert werden")
    }
    var cursorAuthExpiredHint: String {
        t("Cursor IDE 에 다시 로그인하거나, 다시 시도해 주세요.",
          "Sign in to Cursor IDE again, or retry.",
          "Cursor IDE に再度サインインするか、再試行してください。",
          "Vuelve a iniciar sesión en Cursor IDE o reinténtalo.",
          "Reconnecte-toi à Cursor IDE ou réessaie.",
          "Entre de novo no Cursor IDE ou tente de novo.",
          "Melde dich erneut in Cursor IDE an oder versuch es noch einmal.")
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
    var skipThisVersion: String { t("이 버전 건너뛰기", "Skip this version", "このバージョンをスキップ", "Omitir esta versión", "Ignorer cette version", "Ignorar esta versão", "Diese Version überspringen") }
    func skippedVersion(_ version: String) -> String {
        t("v\(version)을 건너뛰었어요",
          "You skipped v\(version)",
          "v\(version) をスキップしました",
          "Omitiste la v\(version)",
          "Tu as ignoré la v\(version)",
          "Você ignorou a v\(version)",
          "Du hast v\(version) übersprungen")
    }
    var showSkippedAgain: String { t("다시 알리기", "Show again", "もう一度表示", "Mostrar de nuevo", "Afficher à nouveau", "Mostrar de novo", "Wieder anzeigen") }
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

    /// Rare Candy batch preview, including carryover and graduation waste.
    var candyGraduates: String {
        t("이 포켓몬은 졸업할 것으로 예상돼요.", "Expected to graduate.", "卒業する見込みです。",
          "Se espera que se gradúe.", "Devrait terminer sa croissance.",
          "Deve se formar.", "Schließt voraussichtlich sein Training ab.")
    }
    func candyCarryoverXP(_ xp: String) -> String {
        t("예상 진화 후 이월 경험치: \(xp) XP.",
          "Expected after evolution: \(xp) XP carried over.",
          "進化後の予想繰越経験値：\(xp) XP。",
          "Tras evolucionar: \(xp) XP de remanente previsto.",
          "Après évolution : \(xp) XP de report prévu.",
          "Após evoluir: previsão de \(xp) XP restantes.",
          "Nach der Entwicklung: voraussichtlich \(xp) EP übertragen.")
    }
    func candyDiscardedXP(_ xp: String) -> String {
        t("졸업 시 남는 \(xp) XP는 사라져요.", "On graduation, \(xp) leftover XP will be discarded.",
          "卒業時、余った\(xp) XPは失われます。", "Al graduarse, se perderán \(xp) XP sobrantes.",
          "À la fin de la croissance, les \(xp) XP restants seront perdus.",
          "Ao se formar, \(xp) XP restantes serão descartados.",
          "Beim Trainingsabschluss verfallen \(xp) überschüssige EP.")
    }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ", "Caramelo Raro", "Super Bonbon", "Doce Raro", "Sonderbonbon")
        case .mint:      return t("민트", "Mint", "ミント", "Menta", "Menthe", "Menta", "Minze")
        case .shinyCharm: return t("이로치 부적", "Shiny Charm", "ひかるおまもり", "Amuleto Iris", "Charme Chroma", "Amuleto Shiny", "Schillerpin")
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
        }
    }
    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更", "Naturaleza aleatoria", "Nature aléatoire", "Natureza aleatória", "Zufälliges Wesen") }

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
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다: 한국어·영어는 맞아떨어져도 일본어에서
    // 조사가 어긋난다(レアのタマゴ vs 자연스러운 レアなタマゴ). 세 언어를 명시 트리플로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return t("포켓몬 알", "Pokémon Egg", "ポケモンのタマゴ", "Huevo Pokémon", "Œuf Pokémon", "Ovo Pokémon", "Pokémon-Ei")
        case .uncommon?:  return t("고급 알", "Uncommon Egg", "アンコモンのタマゴ", "Huevo poco común", "Œuf peu commun", "Ovo incomum", "Ungewöhnliches Ei")
        case .rare?:      return t("희귀 알", "Rare Egg", "レアのタマゴ", "Huevo raro", "Œuf rare", "Ovo raro", "Seltenes Ei")
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
    /// 놓아주면 무엇이 남는지 — `eggDescription` 바로 아래 줄(EggCard).
    ///
    /// 경고가 아니라 **안심**이 목적이다. `eggDescription` 이 "놓아준다"까지만 말해서 도감까지 잃는다고
    /// 읽히지만, `buyEgg` 는 `releasedDexEntry` 로 도감에 남긴다.
    ///
    /// "같은 확률"은 비유가 아니라 실제 수치다. `chooseBase` 의 가중치는 이미 수집한 base 를 ½ 로
    /// 깎는데(미수집 부스트), 그 판정인 `collectedFinals` 는 졸업에서만 채워지고 놓아줌에선 그대로다
    /// → 놓아준 종의 부화 가중치는 100% 를 유지한다. 재인큐베이션은 말하지 않는다(`eggDescription`
    /// 의 "새 알로 다시 시작해요" 와 중복).
    var eggReleaseNote: String {
        t("놓아준 포켓몬도 도감에 남고, 같은 확률로 다시 만날 수 있어요. 키운 진행도만 사라져요.",
          "A released Pokémon stays in your Pokédex and can hatch again at the same odds — only the growth progress is lost.",
          "手放したポケモンも図鑑に残り、同じ確率でまた出会えます。失われるのは育てた進み具合だけです。",
          "El Pokémon liberado permanece en la Pokédex y puede volver a salir con la misma probabilidad; solo se pierde el progreso de crianza.",
          "Un Pokémon relâché reste dans le Pokédex et peut réapparaître avec la même probabilité ; seule la progression est perdue.",
          "O Pokémon solto continua na Pokédex e pode voltar a aparecer com a mesma chance; só o progresso de criação se perde.",
          "Ein freigelassenes Pokémon bleibt im Pokédex und kann mit gleicher Wahrscheinlichkeit wieder schlüpfen; nur der Aufzuchtfortschritt geht verloren.")
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        let r = rarityLabel(tier)
        return t("\(r) 이상 확정", "\(r) or better", "\(r) 以上確定", "\(r) o superior garantizado", "\(r) ou mieux garanti", "\(r) ou melhor garantido", "Garantiert \(r) oder besser")
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        t("\(KoreanParticle.object.attach(to: monName)) 놓아주고 \(KoreanParticle.direction.attach(to: eggName)) 바꿀까요?",
          "Send off \(monName) for the \(eggName)?",
          "\(monName) を手放して \(eggName) にしますか？",
          "¿Soltar a \(monName) y cambiarlo por \(eggName)?",
          "Laisser partir \(monName) pour le \(eggName) ?",
          "Soltar \(monName) e trocar pelo \(eggName)?",
          "\(monName) verabschieden und gegen \(eggName) tauschen?")
    }
    var freshEggShinyWarning: String { t("⚠️ 이로치 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This one is shiny! Really send it off?", "⚠️ 色違いです！本当に手放しますか？", "⚠️ ¡Este es variocolor! ¿Seguro que quieres soltarlo?", "⚠️ Celui-ci est chromatique ! Vraiment le laisser partir ?", "⚠️ Esse é shiny! Quer mesmo soltar?", "⚠️ Dieses Pokémon ist schillernd! Wirklich verabschieden?") }
    var freshEggLegendaryWarning: String { t("⚠️ 전설 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This is a Legendary Pokémon! Really send it off?", "⚠️ 伝説のポケモンです！本当に手放しますか？", "⚠️ ¡Es un Pokémon legendario! ¿Seguro que quieres soltarlo?", "⚠️ C'est un Pokémon légendaire ! Vraiment le laisser partir ?", "⚠️ Esse é um Pokémon lendário! Quer mesmo soltar?", "⚠️ Dieses Pokémon ist legendär! Wirklich verabschieden?") }
    var freshEggDiscardShiny: String { t("이로치 놓아주기", "Send shiny off", "手放す", "Soltar variocolor", "Laisser partir le chromatique", "Soltar o shiny", "Schillerndes Pokémon verabschieden") }
    var freshEggDiscardValuable: String { t("놓아주기", "Send off", "手放す", "Soltar", "Laisser partir", "Soltar", "Verabschieden") }

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
}

// MARK: Battle
extension L {
    var battle: String { t("배틀", "Battle", "バトル", "Combate", "Combat", "Batalha", "Kampf") }
    func battleTeamCount(_ count: Int) -> String {
        t("팀 \(count)/6", "Team \(count)/6", "チーム \(count)/6", "Equipo \(count)/6", "Équipe \(count)/6", "Equipe \(count)/6", "Team \(count)/6")
    }
    var battleTeamEmpty: String { t("아래에서 포켓몬을 최대 6마리 골라 팀을 꾸리세요.", "Pick up to 6 Pokémon below to build your team.", "下からポケモンを最大6匹選んでチームを組もう。", "Elige hasta 6 Pokémon abajo para formar tu equipo.", "Choisis jusqu’à 6 Pokémon ci-dessous pour former ton équipe.", "Escolha até 6 Pokémon abaixo para montar sua equipe.", "Wähle unten bis zu 6 Pokémon für dein Team.") }
    var battleYourPokemon: String { t("내 포켓몬", "Your Pokémon", "手持ちのポケモン", "Tus Pokémon", "Tes Pokémon", "Seus Pokémon", "Deine Pokémon") }
    var battlePickHint: String { t("눌러서 추가하거나 빼세요. 팀원을 우클릭하면 선두로 지정할 수 있어요.", "Click to add or remove. Right-click a team member to make it the lead.", "クリックで追加・解除。メンバーを右クリックすると先頭にできます。", "Haz clic para añadir o quitar. Clic derecho en un miembro para ponerlo primero.", "Clique pour ajouter ou retirer. Clic droit sur un membre pour le mettre en tête.", "Clique para adicionar ou remover. Clique com o botão direito para colocar na frente.", "Klicke zum Hinzufügen oder Entfernen. Rechtsklick auf ein Mitglied macht es zum Starter.") }
    var battleLead: String { t("선두", "Lead", "先頭", "Primero", "En tête", "Líder", "Starter") }
    var battleMakeLead: String { t("선두로 지정", "Make lead", "先頭にする", "Poner primero", "Mettre en tête", "Colocar na frente", "Zum Starter machen") }
    var battleRemove: String { t("팀에서 빼기", "Remove from team", "チームから外す", "Quitar del equipo", "Retirer de l’équipe", "Remover da equipe", "Aus dem Team entfernen") }
    var battleAdd: String { t("팀에 추가", "Add to team", "チームに入れる", "Añadir al equipo", "Ajouter à l’équipe", "Adicionar à equipe", "Zum Team hinzufügen") }
    var battleTeamFull: String { t("팀이 가득 찼어요 (6/6).", "Your team is full (6/6).", "チームがいっぱいです（6/6）。", "Tu equipo está completo (6/6).", "Ton équipe est complète (6/6).", "Sua equipe está completa (6/6).", "Dein Team ist voll (6/6).") }
    var battlePreparing: String { t("배틀 데이터 준비 중…", "Preparing battle data…", "バトルデータを準備中…", "Preparando datos de combate…", "Préparation des données de combat…", "Preparando dados de batalha…", "Kampfdaten werden vorbereitet…") }
    var battleReady: String { t("배틀 준비 완료", "Ready for battle", "バトル準備OK", "Listo para combatir", "Prêt au combat", "Pronto para batalhar", "Bereit zum Kampf") }
    var battleDataFailed: String { t("배틀 데이터를 불러오지 못했어요. 연결을 확인하세요.", "Couldn’t load battle data. Check your connection.", "バトルデータを読み込めませんでした。接続を確認してください。", "No se pudieron cargar los datos de combate. Revisa tu conexión.", "Impossible de charger les données de combat. Vérifie ta connexion.", "Não foi possível carregar os dados de batalha. Verifique sua conexão.", "Kampfdaten konnten nicht geladen werden. Prüfe deine Verbindung.") }
    var battleNoCandidates: String { t("먼저 알을 부화시키면 팀에 넣을 수 있어요.", "Hatch your egg first — then it can join your team.", "まずタマゴをかえすと、チームに入れられます。", "Primero haz eclosionar tu huevo para añadirlo al equipo.", "Fais d’abord éclore ton œuf pour l’ajouter à l’équipe.", "Choque seu ovo primeiro para colocá-lo na equipe.", "Brüte zuerst dein Ei aus, dann kann es ins Team.") }
    func battleLevel(_ level: Int) -> String { "Lv. \(level)" }
}

// MARK: Battle — match
extension L {
    var battlePractice: String { t("연습 배틀", "Practice battle", "練習バトル", "Combate de práctica", "Combat d’entraînement", "Batalha de treino", "Übungskampf") }
    var battleFindingOpponent: String { t("상대를 찾는 중…", "Finding an opponent…", "相手を探しています…", "Buscando rival…", "Recherche d’un adversaire…", "Procurando adversário…", "Gegner wird gesucht…") }
    var battleSwitch: String { t("교체", "Switch", "入れ替え", "Cambiar", "Changer", "Trocar", "Wechseln") }
    var battleForfeit: String { t("기권", "Forfeit", "降参", "Rendirse", "Abandonner", "Desistir", "Aufgeben") }
    var battleForfeitConfirm: String { t("정말 기권할까요?", "Forfeit this battle?", "本当に降参しますか？", "¿Rendirte en este combate?", "Abandonner ce combat ?", "Desistir desta batalha?", "Diesen Kampf aufgeben?") }
    var battleBack: String { t("뒤로", "Back", "戻る", "Atrás", "Retour", "Voltar", "Zurück") }
    var battleClose: String { t("닫기", "Close", "閉じる", "Cerrar", "Fermer", "Fechar", "Schließen") }
    var battleRematch: String { t("다시 하기", "Rematch", "再戦", "Revancha", "Revanche", "Revanche", "Revanche") }
    var battleChooseNext: String { t("다음 포켓몬을 고르세요.", "Choose your next Pokémon.", "次のポケモンを選んでください。", "Elige tu siguiente Pokémon.", "Choisis ton prochain Pokémon.", "Escolha seu próximo Pokémon.", "Wähle dein nächstes Pokémon.") }
    var battleUnsupportedMove: String { t("아직 지원하지 않는 기술이에요.", "This move isn’t supported yet.", "この技はまだ使えません。", "Este movimiento aún no es compatible.", "Cette capacité n’est pas encore prise en charge.", "Este golpe ainda não é suportado.", "Diese Attacke wird noch nicht unterstützt.") }
    var battleWon: String { t("승리했다!", "You won!", "勝った！", "¡Ganaste!", "Tu as gagné !", "Você venceu!", "Du hast gewonnen!") }
    var battleLost: String { t("패배했다…", "You lost…", "負けてしまった…", "Perdiste…", "Tu as perdu…", "Você perdeu…", "Du hast verloren…") }
    var battleDraw: String { t("무승부!", "It’s a draw!", "引き分け！", "¡Empate!", "Match nul !", "Empate!", "Unentschieden!") }
    var battleSuperEffective: String { t("효과가 굉장했다!", "It’s super effective!", "こうかは ばつぐんだ！", "¡Es muy eficaz!", "C’est super efficace !", "É super efetivo!", "Das ist sehr effektiv!") }
    var battleNotVeryEffective: String { t("효과가 별로인 듯하다…", "It’s not very effective…", "こうかは いまひとつの ようだ…", "No es muy eficaz…", "Ce n’est pas très efficace…", "Não é muito efetivo…", "Das ist nicht sehr effektiv…") }
    var battleCritical: String { t("급소에 맞았다!", "A critical hit!", "きゅうしょに あたった！", "¡Un golpe crítico!", "Coup critique !", "Um acerto crítico!", "Ein Volltreffer!") }
    var battleFailed: String { t("하지만 실패했다!", "But it failed!", "しかし うまく きまらなかった！", "¡Pero falló!", "Mais cela échoue !", "Mas falhou!", "Es schlägt fehl!") }
    var battleYouForfeited: String { t("기권했다.", "You forfeited.", "降参した。", "Te rendiste.", "Tu as abandonné.", "Você desistiu.", "Du hast aufgegeben.") }
    var battleOpponentForfeited: String { t("상대가 기권했다!", "The opponent forfeited!", "相手が降参した！", "¡El rival se rindió!", "L’adversaire abandonne !", "O adversário desistiu!", "Der Gegner gibt auf!") }

    /// The opposing side's Pokémon, used as the subject of every other battle line.
    func battleOpposing(_ name: String) -> String {
        t("상대 \(name)", "the opposing \(name)", "あいての \(name)", "\(name) rival", "\(name) adverse", "\(name) adversário", "\(name) (Gegner)")
    }
    func battleWhatWillDo(_ name: String) -> String {
        t("\(name)는 무엇을 할까?", "What will \(name) do?", "\(name)は どうする？", "¿Qué hará \(name)?", "Que doit faire \(name) ?", "O que \(name) vai fazer?", "Was soll \(name) tun?")
    }
    func battleGo(_ name: String) -> String {
        t("가랏! \(name)!", "Go! \(name)!", "ゆけっ！ \(name)！", "¡Adelante, \(name)!", "\(name), go !", "Vai, \(name)!", "Los, \(name)!")
    }
    func battleOpponentSentOut(_ name: String) -> String {
        t("상대는 \(name)을(를) 내보냈다!", "The opponent sent out \(name)!", "あいては \(name)を くりだした！", "¡El rival envió a \(name)!", "L’adversaire envoie \(name) !", "O adversário enviou \(name)!", "Der Gegner schickt \(name) in den Kampf!")
    }
    func battleUsed(_ subject: String, _ move: String) -> String {
        t("\(subject)의 \(move)!", "\(subject) used \(move)!", "\(subject)の \(move)！", "¡\(subject) usó \(move)!", "\(subject) utilise \(move) !", "\(subject) usou \(move)!", "\(subject) setzt \(move) ein!")
    }
    func battleMissed(_ subject: String) -> String {
        t("\(subject)의 공격은 빗나갔다!", "\(subject)’s attack missed!", "\(subject)の こうげきは はずれた！", "¡El ataque de \(subject) falló!", "L’attaque de \(subject) échoue !", "O ataque de \(subject) errou!", "Die Attacke von \(subject) ging daneben!")
    }
    func battleNoEffect(_ subject: String) -> String {
        t("\(subject)에게는 효과가 없는 것 같다…", "It doesn’t affect \(subject)…", "\(subject)には こうかが ないようだ…", "No afecta a \(subject)…", "Ça n’affecte pas \(subject)…", "Não afeta \(subject)…", "Hat keine Wirkung auf \(subject)…")
    }
    func battleFainted(_ subject: String) -> String {
        t("\(subject)는 쓰러졌다!", "\(subject) fainted!", "\(subject)は たおれた！", "¡\(subject) se debilitó!", "\(subject) est K.O. !", "\(subject) desmaiou!", "\(subject) wurde besiegt!")
    }
    func battleRecoil(_ subject: String) -> String {
        t("\(subject)는 반동으로 데미지를 입었다!", "\(subject) is damaged by recoil!", "\(subject)は はんどうで ダメージを うけた！", "¡\(subject) se hirió por el retroceso!", "\(subject) est blessé par le contrecoup !", "\(subject) sofreu dano de recuo!", "\(subject) erleidet Rückstoßschaden!")
    }
    func battleHealed(_ subject: String) -> String {
        t("\(subject)의 체력이 회복되었다!", "\(subject) regained health!", "\(subject)の たいりょくが かいふくした！", "¡\(subject) recuperó salud!", "\(subject) récupère des PV !", "\(subject) recuperou energia!", "\(subject) hat KP aufgefüllt!")
    }
    func battleNoMovesLeft(_ subject: String) -> String {
        t("\(subject)는 쓸 수 있는 기술이 없다!", "\(subject) has no moves left!", "\(subject)は だせる わざが ない！", "¡\(subject) no tiene movimientos!", "\(subject) n’a plus de capacité !", "\(subject) não tem mais golpes!", "\(subject) hat keine Attacken mehr!")
    }
    /// `change` is the applied stage delta; 1 / 2 / 3+ pick the main-series wording.
    func battleStatChanged(_ subject: String, _ stat: String, _ change: Int) -> String {
        let size = min(3, abs(change))
        if change > 0 {
            switch size {
            case 1: return t("\(subject)의 \(stat)이(가) 올라갔다!", "\(subject)’s \(stat) rose!", "\(subject)の \(stat)が あがった！", "¡\(stat) de \(subject) subió!", "\(stat) de \(subject) augmente !", "\(stat) de \(subject) aumentou!", "\(stat) von \(subject) steigt!")
            case 2: return t("\(subject)의 \(stat)이(가) 크게 올라갔다!", "\(subject)’s \(stat) rose sharply!", "\(subject)の \(stat)が ぐーんと あがった！", "¡\(stat) de \(subject) subió mucho!", "\(stat) de \(subject) augmente beaucoup !", "\(stat) de \(subject) aumentou muito!", "\(stat) von \(subject) steigt stark!")
            default: return t("\(subject)의 \(stat)이(가) 매우 크게 올라갔다!", "\(subject)’s \(stat) rose drastically!", "\(subject)の \(stat)が ぐぐーんと あがった！", "¡\(stat) de \(subject) subió muchísimo!", "\(stat) de \(subject) augmente énormément !", "\(stat) de \(subject) aumentou drasticamente!", "\(stat) von \(subject) steigt drastisch!")
            }
        }
        switch size {
        case 1: return t("\(subject)의 \(stat)이(가) 떨어졌다!", "\(subject)’s \(stat) fell!", "\(subject)の \(stat)が さがった！", "¡\(stat) de \(subject) bajó!", "\(stat) de \(subject) baisse !", "\(stat) de \(subject) diminuiu!", "\(stat) von \(subject) sinkt!")
        case 2: return t("\(subject)의 \(stat)이(가) 크게 떨어졌다!", "\(subject)’s \(stat) harshly fell!", "\(subject)の \(stat)が がくっと さがった！", "¡\(stat) de \(subject) bajó mucho!", "\(stat) de \(subject) baisse beaucoup !", "\(stat) de \(subject) diminuiu muito!", "\(stat) von \(subject) sinkt stark!")
        default: return t("\(subject)의 \(stat)이(가) 매우 크게 떨어졌다!", "\(subject)’s \(stat) severely fell!", "\(subject)の \(stat)が がくーんと さがった！", "¡\(stat) de \(subject) bajó muchísimo!", "\(stat) de \(subject) baisse énormément !", "\(stat) de \(subject) diminuiu drasticamente!", "\(stat) von \(subject) sinkt drastisch!")
        }
    }
    func battleStatLimit(_ subject: String, _ stat: String, rising: Bool) -> String {
        rising
            ? t("\(subject)의 \(stat)은(는) 더 올라가지 않는다!", "\(subject)’s \(stat) won’t go any higher!", "\(subject)の \(stat)は もう あがらない！", "¡\(stat) de \(subject) no puede subir más!", "\(stat) de \(subject) ne peut plus augmenter !", "\(stat) de \(subject) não pode aumentar mais!", "\(stat) von \(subject) kann nicht weiter steigen!")
            : t("\(subject)의 \(stat)은(는) 더 떨어지지 않는다!", "\(subject)’s \(stat) won’t go any lower!", "\(subject)の \(stat)は もう さがらない！", "¡\(stat) de \(subject) no puede bajar más!", "\(stat) de \(subject) ne peut plus baisser !", "\(stat) de \(subject) não pode diminuir mais!", "\(stat) von \(subject) kann nicht weiter sinken!")
    }
    func battleStatLabel(_ stat: String) -> String {
        switch stat {
        case "accuracy": return t("명중률", "accuracy", "めいちゅうりつ", "Precisión", "Précision", "Precisão", "Genauigkeit")
        case "evasion": return t("회피율", "evasiveness", "かいひりつ", "Evasión", "Esquive", "Evasão", "Fluchtwert")
        default: return statLabel(stat)
        }
    }
}

// MARK: Battle — nearby
extension L {
    var battleOpponentLeft: String { t("상대가 배틀을 떠났다. 승리!", "The opponent left the battle. You win!", "相手がバトルから抜けた。あなたの勝ち！", "El rival abandonó el combate. ¡Ganas!", "L’adversaire a quitté le combat. Tu gagnes !", "O adversário saiu da batalha. Você venceu!", "Der Gegner hat den Kampf verlassen. Du gewinnst!") }
    var battleConnectionProblem: String { t("연결 문제로 배틀이 끝났어요. 승패 없음.", "The battle ended because of a connection problem. No winner.", "接続の問題でバトルが終了しました。勝敗なし。", "El combate terminó por un problema de conexión. Sin ganador.", "Le combat s’est arrêté à cause d’un problème de connexion. Pas de vainqueur.", "A batalha terminou por um problema de conexão. Sem vencedor.", "Der Kampf endete wegen eines Verbindungsproblems. Kein Sieger.") }
    var battleNearbyTitle: String { t("근처 트레이너", "Trainers nearby", "近くのトレーナー", "Entrenadores cercanos", "Dresseurs à proximité", "Treinadores por perto", "Trainer in der Nähe") }
    var battleVisible: String { t("근처 트레이너에게 보이기", "Visible to trainers nearby", "近くのトレーナーに表示", "Visible para entrenadores cercanos", "Visible par les dresseurs à proximité", "Visível para treinadores por perto", "Für Trainer in der Nähe sichtbar") }
    var battleVisibleHint: String { t("같은 Wi-Fi나 가까이 있는 Mac에서 PokeTokenBar를 쓰는 사람에게 트레이너 이름이 보여요.", "Your trainer name is shown to people nearby running PokeTokenBar on a Mac, on the same Wi-Fi or close by.", "同じWi-Fiや近くのMacでPokeTokenBarを使っている人にトレーナー名が表示されます。", "Tu nombre de entrenador se muestra a quien use PokeTokenBar en un Mac cercano o en la misma Wi-Fi.", "Ton nom de dresseur est visible par les personnes proches qui utilisent PokeTokenBar sur Mac, sur le même Wi-Fi ou à côté.", "Seu nome de treinador aparece para quem usa PokeTokenBar num Mac por perto ou na mesma Wi-Fi.", "Dein Trainername ist für Personen in der Nähe sichtbar, die PokeTokenBar auf einem Mac nutzen – im selben WLAN oder nebenan.") }
    var battleTrainerName: String { t("트레이너 이름", "Trainer name", "トレーナー名", "Nombre de entrenador", "Nom de dresseur", "Nome de treinador", "Trainername") }
    var battleSearching: String { t("근처 트레이너를 찾는 중…", "Looking for trainers nearby…", "近くのトレーナーを探しています…", "Buscando entrenadores cercanos…", "Recherche de dresseurs à proximité…", "Procurando treinadores por perto…", "Suche nach Trainern in der Nähe…") }
    var battleChallenge: String { t("도전", "Challenge", "挑戦", "Desafiar", "Défier", "Desafiar", "Herausfordern") }
    var battleNeedsUpdate: String { t("다른 버전", "Other version", "別のバージョン", "Otra versión", "Autre version", "Outra versão", "Andere Version") }
    func battleChallenging(_ name: String) -> String {
        t("\(name)에게 도전하는 중…", "Challenging \(name)…", "\(name)に挑戦中…", "Desafiando a \(name)…", "Défi envoyé à \(name)…", "Desafiando \(name)…", "Fordere \(name) heraus…")
    }
    func battleChallengedBy(_ name: String) -> String {
        t("\(name)이(가) 배틀을 신청했다!", "\(name) wants to battle!", "\(name)が 勝負を しかけてきた！", "¡\(name) quiere combatir!", "\(name) veut se battre !", "\(name) quer batalhar!", "\(name) möchte kämpfen!")
    }
    var battleAccept: String { t("수락", "Accept", "受ける", "Aceptar", "Accepter", "Aceitar", "Annehmen") }
    var battleDecline: String { t("거절", "Decline", "断る", "Rechazar", "Refuser", "Recusar", "Ablehnen") }
    var battleDeclined: String { t("상대가 도전을 받지 않았어요.", "The challenge wasn’t accepted.", "挑戦は受けてもらえませんでした。", "El desafío no fue aceptado.", "Le défi n’a pas été accepté.", "O desafio não foi aceito.", "Die Herausforderung wurde nicht angenommen.") }
    var battleConnecting: String { t("연결 중…", "Connecting…", "接続中…", "Conectando…", "Connexion…", "Conectando…", "Verbinden…") }
    var battleNetworkUnavailable: String { t("근처 트레이너를 찾을 수 없어요. Wi-Fi와 로컬 네트워크 권한을 확인하세요.", "Can’t look for trainers nearby. Check Wi-Fi and the Local Network permission.", "近くのトレーナーを探せません。Wi-Fiとローカルネットワークの許可を確認してください。", "No se pueden buscar entrenadores. Revisa el Wi-Fi y el permiso de red local.", "Impossible de chercher des dresseurs. Vérifie le Wi-Fi et l’autorisation Réseau local.", "Não é possível procurar treinadores. Verifique o Wi-Fi e a permissão de rede local.", "Suche nicht möglich. Prüfe WLAN und die Berechtigung „Lokales Netzwerk“.") }
    var battleIncompatible: String { t("상대의 앱 버전이 달라요. 둘 다 최신 버전으로 업데이트하세요.", "The other trainer runs a different app version. Both of you should update.", "相手のアプリのバージョンが違います。両方とも最新にしてください。", "El otro entrenador usa otra versión. Actualicen ambos.", "L’autre dresseur utilise une autre version. Mettez tous les deux à jour.", "O outro treinador usa outra versão. Atualizem os dois.", "Der andere Trainer nutzt eine andere Version. Aktualisiert beide.") }
    func battleRecord(wins: Int, losses: Int, draws: Int) -> String {
        t("전적 \(wins)승 \(losses)패 \(draws)무", "Record \(wins)W \(losses)L \(draws)D", "戦績 \(wins)勝 \(losses)敗 \(draws)分", "Récord \(wins)V \(losses)D \(draws)E", "Bilan \(wins)V \(losses)D \(draws)N", "Recorde \(wins)V \(losses)D \(draws)E", "Bilanz \(wins)S \(losses)N \(draws)U")
    }
    func battleSecondsLeft(_ seconds: Int) -> String {
        t("\(seconds)초", "\(seconds)s", "\(seconds)秒", "\(seconds) s", "\(seconds) s", "\(seconds)s", "\(seconds) s")
    }
    func battleAgainst(_ name: String) -> String {
        t("\(name)와(과)의 배틀", "Battle with \(name)", "\(name)とのバトル", "Combate con \(name)", "Combat contre \(name)", "Batalha com \(name)", "Kampf gegen \(name)")
    }
}

extension L {
    func battleWaitingFor(_ name: String) -> String {
        t("\(name)의 선택을 기다리는 중…", "Waiting for \(name)…", "\(name)の 行動を 待っています…", "Esperando a \(name)…", "En attente de \(name)…", "Aguardando \(name)…", "Warte auf \(name)…")
    }
}

// MARK: Battle — status and protection
extension L {
    func battleStatusApplied(_ subject: String, _ status: BattleStatus) -> String {
        switch status {
        case .paralysis: return t("\(subject)은(는) 마비되었다!", "\(subject) is paralyzed! It may be unable to move!", "\(subject)は まひして わざが でにくくなった！", "¡\(subject) está paralizado! Quizás no pueda moverse.", "\(subject) est paralysé ! Il aura du mal à attaquer !", "\(subject) está paralisado! Talvez não consiga se mover!", "\(subject) ist paralysiert! Es kann eventuell nicht angreifen!")
        case .burn: return t("\(subject)은(는) 화상을 입었다!", "\(subject) was burned!", "\(subject)は やけどを おった！", "¡\(subject) se ha quemado!", "\(subject) est brûlé !", "\(subject) foi queimado!", "\(subject) hat Verbrennungen erlitten!")
        case .poison: return t("\(subject)은(는) 독에 걸렸다!", "\(subject) was poisoned!", "\(subject)は どくを あびた！", "¡\(subject) ha sido envenenado!", "\(subject) est empoisonné !", "\(subject) foi envenenado!", "\(subject) wurde vergiftet!")
        case .badPoison: return t("\(subject)은(는) 맹독에 걸렸다!", "\(subject) was badly poisoned!", "\(subject)は もうどくを あびた！", "¡\(subject) ha sido gravemente envenenado!", "\(subject) est gravement empoisonné !", "\(subject) foi gravemente envenenado!", "\(subject) wurde schwer vergiftet!")
        case .sleep: return t("\(subject)은(는) 잠들어 버렸다!", "\(subject) fell asleep!", "\(subject)は ねむってしまった！", "¡\(subject) se ha dormido!", "\(subject) s’endort !", "\(subject) adormeceu!", "\(subject) ist eingeschlafen!")
        case .freeze: return t("\(subject)은(는) 얼어붙었다!", "\(subject) was frozen solid!", "\(subject)は こおりづけに なった！", "¡\(subject) ha sido congelado!", "\(subject) est gelé !", "\(subject) foi congelado!", "\(subject) wurde eingefroren!")
        }
    }
    func battleCantMove(_ subject: String, _ reason: BattleCantMoveReason) -> String {
        switch reason {
        case .asleep: return t("\(subject)은(는) 쿨쿨 잠들어 있다.", "\(subject) is fast asleep.", "\(subject)は ぐうぐう ねむっている。", "\(subject) está dormido como un tronco.", "\(subject) dort profondément.", "\(subject) está dormindo profundamente.", "\(subject) schläft tief und fest.")
        case .frozen: return t("\(subject)은(는) 얼어붙어서 움직일 수 없다!", "\(subject) is frozen solid!", "\(subject)は こおって しまって うごかない！", "¡\(subject) está congelado!", "\(subject) est gelé !", "\(subject) está congelado!", "\(subject) ist eingefroren!")
        case .paralyzed: return t("\(subject)은(는) 몸이 저려서 움직일 수 없다!", "\(subject) is paralyzed! It can’t move!", "\(subject)は からだが しびれて うごけない！", "¡\(subject) está paralizado! No se puede mover.", "\(subject) est paralysé ! Il ne peut pas attaquer !", "\(subject) está paralisado! Não consegue se mover!", "\(subject) ist paralysiert! Es kann nicht angreifen!")
        case .flinched: return t("\(subject)은(는) 풀이 죽어 움직일 수 없었다!", "\(subject) flinched and couldn’t move!", "\(subject)は ひるんで うごけなかった！", "¡\(subject) se amedrentó y no pudo moverse!", "\(subject) a la trouille ! Il ne peut pas attaquer !", "\(subject) recuou e não conseguiu se mover!", "\(subject) ist zurückgeschreckt und kann nicht angreifen!")
        case .infatuated, .recharging, .lostFocus: return battleCantMoveMore(subject, reason) ?? ""
        }
    }
    func battleWokeUp(_ subject: String) -> String {
        t("\(subject)은(는) 잠에서 깨어났다!", "\(subject) woke up!", "\(subject)は 目を さました！", "¡\(subject) se ha despertado!", "\(subject) se réveille !", "\(subject) acordou!", "\(subject) ist aufgewacht!")
    }
    func battleThawed(_ subject: String) -> String {
        t("\(subject)의 얼음이 녹았다!", "\(subject) thawed out!", "\(subject)の こおりが とけた！", "¡\(subject) se ha descongelado!", "\(subject) dégèle !", "\(subject) descongelou!", "\(subject) ist wieder aufgetaut!")
    }
    func battleBecameConfused(_ subject: String) -> String {
        t("\(subject)은(는) 혼란에 빠졌다!", "\(subject) became confused!", "\(subject)は こんらんした！", "¡\(subject) está confuso!", "\(subject) devient confus !", "\(subject) ficou confuso!", "\(subject) wurde verwirrt!")
    }
    func battleIsConfused(_ subject: String) -> String {
        t("\(subject)은(는) 혼란에 빠져 있다!", "\(subject) is confused!", "\(subject)は こんらんしている！", "¡\(subject) está confuso!", "\(subject) est confus !", "\(subject) está confuso!", "\(subject) ist verwirrt!")
    }
    var battleHurtByConfusion: String { t("영문도 모른 채 자신을 공격했다!", "It hurt itself in its confusion!", "わけも わからず じぶんを こうげきした！", "¡Está tan confuso que se hirió a sí mismo!", "Il se blesse dans sa confusion !", "Ele se feriu na confusão!", "Es hat sich vor Verwirrung selbst verletzt!") }
    func battleSnappedOut(_ subject: String) -> String {
        t("\(subject)의 혼란이 풀렸다!", "\(subject) snapped out of its confusion!", "\(subject)の こんらんが とけた！", "¡\(subject) ya no está confuso!", "\(subject) n’est plus confus !", "\(subject) não está mais confuso!", "\(subject) ist nicht mehr verwirrt!")
    }
    func battleResidual(_ subject: String, _ status: BattleStatus) -> String {
        status == .burn
            ? t("\(subject)은(는) 화상 데미지를 입었다!", "\(subject) is hurt by its burn!", "\(subject)は やけどの ダメージを うけている！", "¡\(subject) se resiente de las quemaduras!", "\(subject) souffre de sa brûlure !", "\(subject) sofre com a queimadura!", "\(subject) leidet unter seinen Verbrennungen!")
            : t("\(subject)은(는) 독에 의한 데미지를 입었다!", "\(subject) is hurt by poison!", "\(subject)は どくの ダメージを うけている！", "¡\(subject) sufre por el veneno!", "\(subject) souffre du poison !", "\(subject) sofre com o veneno!", "\(subject) leidet unter der Vergiftung!")
    }
    func battleProtecting(_ subject: String) -> String {
        t("\(subject)은(는) 방어 태세에 들어갔다!", "\(subject) protected itself!", "\(subject)は 守りの 体勢に 入った！", "¡\(subject) se está protegiendo!", "\(subject) se protège !", "\(subject) se protegeu!", "\(subject) schützt sich selbst!")
    }
    func battleBracing(_ subject: String) -> String {
        t("\(subject)은(는) 버티기 태세에 들어갔다!", "\(subject) braced itself!", "\(subject)は こらえる 体勢に 入った！", "¡\(subject) se prepara para resistir!", "\(subject) se prépare à encaisser !", "\(subject) se preparou para aguentar!", "\(subject) macht sich bereit, durchzuhalten!")
    }
    func battleBlocked(_ subject: String) -> String {
        t("\(subject)은(는) 공격으로부터 몸을 지켰다!", "\(subject) protected itself!", "\(subject)は 攻撃から 身を 守った！", "¡\(subject) se ha protegido!", "\(subject) s’est protégé !", "\(subject) se protegeu do ataque!", "\(subject) hat sich geschützt!")
    }
    func battleEndured(_ subject: String) -> String {
        t("\(subject)은(는) 공격을 버텼다!", "\(subject) endured the hit!", "\(subject)は 攻撃を こらえた！", "¡\(subject) aguantó el golpe!", "\(subject) encaisse le coup !", "\(subject) aguentou o golpe!", "\(subject) hält den Treffer aus!")
    }
    func battleRested(_ subject: String) -> String {
        t("\(subject)은(는) 잠들어 기운을 되찾았다!", "\(subject) slept and became healthy!", "\(subject)は ねむって 元気に なった！", "¡\(subject) se durmió y recuperó la salud!", "\(subject) dort et récupère !", "\(subject) dormiu e ficou saudável!", "\(subject) schläft und erholt sich!")
    }
    var battleNotYet: String { t("준비 중", "Not yet", "準備中", "Aún no", "Bientôt", "Em breve", "Noch nicht") }
    func battleStatusBadge(_ status: BattleStatus) -> String {
        switch status {
        case .paralysis: return t("마비", "PAR", "まひ", "PAR", "PAR", "PAR", "PAR")
        case .burn: return t("화상", "BRN", "やけど", "QUE", "BRL", "QUE", "BRT")
        case .poison: return t("독", "PSN", "どく", "ENV", "PSN", "ENV", "GIF")
        case .badPoison: return t("맹독", "TOX", "もうどく", "ENV", "PSN", "ENV", "GIF")
        case .sleep: return t("잠듦", "SLP", "ねむり", "DOR", "SOM", "DOR", "SLF")
        case .freeze: return t("얼음", "FRZ", "こおり", "CON", "GEL", "CON", "GFR")
        }
    }
}

// MARK: Battle — special moves and field effects
extension L {
    var battleYourTeam: String { t("우리 팀", "your team", "味方", "tu equipo", "ton équipe", "sua equipe", "dein Team") }
    var battleOpposingTeam: String { t("상대 팀", "the opposing team", "相手", "el equipo rival", "l’équipe adverse", "a equipe adversária", "das gegnerische Team") }
    func battleWithdrew(_ name: String, mine: Bool) -> String {
        mine ? t("돌아와, \(name)!", "\(name), come back!", "もどれ！ \(name)！", "¡\(name), vuelve!", "\(name), reviens !", "\(name), volte!", "\(name), zurück!")
             : t("상대는 \(name)을(를) 돌려보냈다!", "The opponent withdrew \(name)!", "あいては \(name)を ひっこめた！", "¡El rival retiró a \(name)!", "L’adversaire rappelle \(name) !", "O adversário recolheu \(name)!", "Der Gegner ruft \(name) zurück!")
    }
    func battleHitCount(_ count: Int) -> String {
        t("\(count)번 맞았다!", count == 1 ? "Hit 1 time!" : "Hit \(count) times!", "\(count)かい あたった！", "¡Golpeó \(count) veces!", "Touché \(count) fois !", "Acertou \(count) vezes!", "\(count)-mal getroffen!")
    }
    var battleOneHitKO: String { t("일격필살!", "It’s a one-hit KO!", "いちげき ひっさつ！", "¡Fuera de combate de un golpe!", "K.O. en un coup !", "Nocaute com um golpe!", "Ein K.O.-Treffer!") }
    func battleEffectDamage(_ subject: String, _ kind: BattleEffectDamage) -> String? {
        switch kind {
        case .leechSeed: return t("씨뿌리기가 \(subject)의 체력을 빼앗는다!", "\(subject)’s health is sapped by Leech Seed!", "やどりぎが \(subject)の たいりょくを うばう！", "¡Las drenadoras restan salud a \(subject)!", "Vampigraine draine l’énergie de \(subject) !", "A Semente Sanguessuga suga a energia de \(subject)!", "Egelsamen schwächt \(subject)!")
        case .curse: return t("\(subject)은(는) 저주를 받고 있다!", "\(subject) is afflicted by the curse!", "\(subject)は のろわれている！", "¡\(subject) es víctima de la maldición!", "\(subject) est touché par la malédiction !", "\(subject) sofre com a maldição!", "\(subject) leidet unter dem Fluch!")
        case .nightmare: return t("\(subject)은(는) 악몽에 시달리고 있다!", "\(subject) is locked in a nightmare!", "\(subject)は あくむに うなされている！", "¡\(subject) sufre una pesadilla!", "\(subject) est prisonnier d’un cauchemar !", "\(subject) está preso num pesadelo!", "\(subject) wird von einem Albtraum geplagt!")
        case .sandstorm: return t("모래바람이 \(subject)을(를) 덮쳤다!", "\(subject) is buffeted by the sandstorm!", "すなあらしが \(subject)を おそう！", "¡La tormenta de arena zarandea a \(subject)!", "La tempête de sable frappe \(subject) !", "A tempestade de areia atinge \(subject)!", "\(subject) wird vom Sandsturm getroffen!")
        case .hail: return t("싸라기눈이 \(subject)을(를) 덮쳤다!", "\(subject) is pelted by hail!", "あられが \(subject)を おそう！", "¡El granizo golpea a \(subject)!", "La grêle frappe \(subject) !", "O granizo atinge \(subject)!", "\(subject) wird vom Hagel getroffen!")
        case .spikes: return t("\(subject)은(는) 압정뿌리기의 데미지를 입었다!", "\(subject) is hurt by the spikes!", "\(subject)は まきびしの ダメージを うけた！", "¡Las púas hieren a \(subject)!", "\(subject) est blessé par les picots !", "\(subject) foi ferido pelos espinhos!", "\(subject) wird von den Stacheln verletzt!")
        case .stealthRock: return t("뾰족한 바위가 \(subject)을(를) 찔렀다!", "Pointed stones dug into \(subject)!", "とがった いわが \(subject)に くいこんだ！", "¡Unas piedras puntiagudas dañan a \(subject)!", "Des pierres pointues blessent \(subject) !", "Pedras pontiagudas feriram \(subject)!", "Spitze Steine bohren sich in \(subject)!")
        case .crash: return t("\(subject)은(는) 기세가 넘쳐 땅에 부딪혔다!", "\(subject) kept going and crashed!", "\(subject)は いきおいあまって じめんに ぶつかった！", "¡\(subject) falló y se estrelló!", "\(subject) s’écrase au sol !", "\(subject) errou e caiu no chão!", "\(subject) hat daneben getroffen und ist gestürzt!")
        case .curseCost: return t("\(subject)은(는) 자신의 체력을 깎아 저주를 걸었다!", "\(subject) cut its own HP and laid a curse!", "\(subject)は じぶんの たいりょくを けずって のろいを かけた！", "¡\(subject) sacrificó salud para lanzar una maldición!", "\(subject) sacrifie des PV pour lancer une malédiction !", "\(subject) sacrificou energia e lançou uma maldição!", "\(subject) opfert KP und belegt das Ziel mit einem Fluch!")
        case .bellyDrum: return nil
        }
    }
    func battleEffectHeal(_ subject: String, _ kind: BattleEffectHeal) -> String? {
        switch kind {
        case .aquaRing: return t("물의 베일이 \(subject)의 체력을 회복시켰다!", "A veil of water restored \(subject)’s HP!", "みずのベールが \(subject)の たいりょくを かいふくした！", "¡Un velo de agua restauró los PS de \(subject)!", "Un voile d’eau restaure les PV de \(subject) !", "Um véu de água restaurou a energia de \(subject)!", "Ein Wasserschleier füllt die KP von \(subject) auf!")
        case .ingrain: return t("\(subject)은(는) 뿌리로 양분을 흡수했다!", "\(subject) absorbed nutrients with its roots!", "\(subject)は ねから ようぶんを すいとった！", "¡\(subject) absorbió nutrientes con sus raíces!", "\(subject) absorbe des nutriments avec ses racines !", "\(subject) absorveu nutrientes com as raízes!", "\(subject) nimmt über seine Wurzeln Nährstoffe auf!")
        case .wish: return t("\(subject)의 소원이 이루어졌다!", "The wish came true for \(subject)!", "\(subject)の ねがいごとが かなった！", "¡El deseo de \(subject) se hizo realidad!", "Le vœu de \(subject) se réalise !", "O desejo de \(subject) se realizou!", "Der Wunsch von \(subject) geht in Erfüllung!")
        case .leechSeed, .healingWish, .painSplit: return nil
        }
    }
    func battleStagesReset(_ subject: String?) -> String {
        guard let subject else { return t("모든 능력 변화가 원래대로 돌아왔다!", "All stat changes were eliminated!", "すべての ステータスが もとに もどった！", "¡Se anularon todos los cambios de características!", "Tous les changements de stats ont été annulés !", "Todas as mudanças de atributos foram anuladas!", "Alle Statuswertänderungen wurden aufgehoben!") }
        return t("\(subject)의 능력 변화가 원래대로 돌아왔다!", "\(subject)’s stat changes were removed!", "\(subject)の のうりょくへんかが もとに もどった！", "¡Se anularon los cambios de características de \(subject)!", "Les changements de stats de \(subject) ont été annulés !", "As mudanças de atributos de \(subject) foram anuladas!", "Die Statuswertänderungen von \(subject) wurden aufgehoben!")
    }
    var battleNothingHappened: String { t("하지만 아무 일도 일어나지 않았다!", "But nothing happened!", "しかし なにも おこらない！", "¡Pero no pasó nada!", "Mais rien ne se passe !", "Mas nada aconteceu!", "Aber es passiert nichts!") }
    func battleStatusCured(_ subject: String) -> String {
        t("\(subject)의 상태가 원래대로 돌아왔다!", "\(subject)’s status returned to normal!", "\(subject)の じょうたいが もとに もどった！", "¡\(subject) se recuperó de su problema de estado!", "\(subject) n’a plus de problème de statut !", "\(subject) voltou ao normal!", "\(subject) ist wieder gesund!")
    }
    func battleTeamCured(_ team: String) -> String {
        t("\(team)의 상태 이상이 모두 나았다!", "The status problems of \(team) were cured!", "\(team)の じょうたいいじょうが なおった！", "¡Se curaron los problemas de estado de \(team)!", "Les problèmes de statut de \(team) sont soignés !", "Os problemas de estado de \(team) foram curados!", "Die Statusprobleme von \(team) wurden geheilt!")
    }
    func battleCantMoveMore(_ subject: String, _ reason: BattleCantMoveReason) -> String? {
        switch reason {
        case .infatuated: return t("\(subject)은(는) 헤롱헤롱해서 기술을 쓸 수 없었다!", "\(subject) is immobilized by love!", "\(subject)は メロメロで わざが だせなかった！", "¡\(subject) está enamorado y no puede atacar!", "\(subject) est amoureux et n’attaque pas !", "\(subject) está apaixonado e não conseguiu atacar!", "\(subject) ist verliebt und greift nicht an!")
        case .recharging: return t("\(subject)은(는) 공격의 반동으로 움직일 수 없다!", "\(subject) must recharge!", "\(subject)は こうげきの はんどうで うごけない！", "¡\(subject) necesita recuperarse!", "\(subject) doit se recharger !", "\(subject) precisa recarregar!", "\(subject) muss sich erholen!")
        case .lostFocus: return t("\(subject)은(는) 집중이 흐트러져 기술을 쓸 수 없었다!", "\(subject) lost its focus and couldn’t move!", "\(subject)は しゅうちゅうが とぎれて わざが だせない！", "¡\(subject) perdió la concentración y no pudo moverse!", "\(subject) perd sa concentration et n’attaque pas !", "\(subject) perdeu a concentração e não pôde atacar!", "\(subject) hat sich nicht konzentriert und kann nicht angreifen!")
        default: return nil
        }
    }
    func battleCharging(_ subject: String, _ kind: BattleChargeKind) -> String {
        switch kind {
        case .solarBeam: return t("\(subject)은(는) 빛을 흡수했다!", "\(subject) absorbed light!", "\(subject)は ひかりを きゅうしゅうした！", "¡\(subject) absorbió luz solar!", "\(subject) absorbe la lumière !", "\(subject) absorveu luz!", "\(subject) absorbiert Licht!")
        case .razorWind: return t("\(subject)의 주위에서 공기가 소용돌이친다!", "\(subject) whipped up a whirlwind!", "\(subject)の まわりで くうきが うずを まく！", "¡\(subject) provocó un remolino!", "\(subject) crée un tourbillon !", "\(subject) criou um redemoinho!", "\(subject) erzeugt einen Wirbelwind!")
        case .skullBash: return t("\(subject)은(는) 목을 움츠렸다!", "\(subject) tucked in its head!", "\(subject)は くびを ひっこめた！", "¡\(subject) bajó la cabeza!", "\(subject) baisse la tête !", "\(subject) recolheu a cabeça!", "\(subject) zieht den Kopf ein!")
        case .skyAttack: return t("\(subject)을(를) 강렬한 빛이 감쌌다!", "\(subject) became cloaked in a harsh light!", "\(subject)を はげしい ひかりが つつむ！", "¡Una luz intensa envuelve a \(subject)!", "\(subject) est entouré d’une lumière intense !", "\(subject) foi envolvido por uma luz intensa!", "\(subject) wird von grellem Licht umhüllt!")
        case .freezeShock, .iceBurn: return t("\(subject)을(를) 차가운 빛이 감쌌다!", "\(subject) became cloaked in a freezing light!", "\(subject)を つめたい ひかりが つつむ！", "¡Una luz gélida envuelve a \(subject)!", "\(subject) est entouré d’une lumière glaciale !", "\(subject) foi envolvido por uma luz gélida!", "\(subject) wird von eisigem Licht umhüllt!")
        case .fly: return t("\(subject)은(는) 하늘 높이 날아올랐다!", "\(subject) flew up high!", "\(subject)は そらたかく とびあがった！", "¡\(subject) voló muy alto!", "\(subject) s’envole !", "\(subject) voou alto!", "\(subject) fliegt hoch hinauf!")
        case .dig: return t("\(subject)은(는) 땅속으로 파고들었다!", "\(subject) burrowed its way under the ground!", "\(subject)は じめんに もぐった！", "¡\(subject) se escondió bajo tierra!", "\(subject) creuse le sol !", "\(subject) cavou para debaixo da terra!", "\(subject) gräbt sich ein!")
        case .dive: return t("\(subject)은(는) 물속으로 잠수했다!", "\(subject) hid underwater!", "\(subject)は すいちゅうに もぐった！", "¡\(subject) se sumergió!", "\(subject) plonge sous l’eau !", "\(subject) mergulhou!", "\(subject) taucht ab!")
        case .bounce: return t("\(subject)은(는) 높이 뛰어올랐다!", "\(subject) sprang up!", "\(subject)は たかく とびはねた！", "¡\(subject) dio un gran salto!", "\(subject) bondit !", "\(subject) saltou alto!", "\(subject) springt hoch!")
        case .vanish: return t("\(subject)의 모습이 사라졌다!", "\(subject) vanished instantly!", "\(subject)の すがたが きえた！", "¡\(subject) desapareció!", "\(subject) disparaît !", "\(subject) desapareceu!", "\(subject) ist verschwunden!")
        }
    }
    func battleStoringEnergy(_ subject: String) -> String { t("\(subject)은(는) 참고 있다!", "\(subject) is storing energy!", "\(subject)は がまんを している！", "¡\(subject) está acumulando energía!", "\(subject) emmagasine de l’énergie !", "\(subject) está acumulando energia!", "\(subject) speichert Energie!") }
    func battleUnleashedEnergy(_ subject: String) -> String { t("\(subject)의 참기가 풀렸다!", "\(subject) unleashed its energy!", "\(subject)の がまんが とかれた！", "¡\(subject) liberó su energía!", "\(subject) libère son énergie !", "\(subject) liberou sua energia!", "\(subject) entfesselt seine Energie!") }
    func battleFellForFeint(_ subject: String) -> String { t("\(subject)은(는) 페인트에 걸려들었다!", "\(subject) fell for the feint!", "\(subject)は フェイントに ひっかかった！", "¡\(subject) cayó en la finta!", "\(subject) tombe dans le piège !", "\(subject) caiu na finta!", "\(subject) fällt auf die Finte herein!") }
    func battleForesaw(_ subject: String) -> String { t("\(subject)은(는) 미래를 내다보았다!", "\(subject) foresaw an attack!", "\(subject)は みらいに こうげきを よちした！", "¡\(subject) previó un ataque!", "\(subject) prévoit une attaque !", "\(subject) previu um ataque!", "\(subject) sieht einen Angriff voraus!") }
    func battleFutureHit(_ subject: String) -> String { t("\(subject)은(는) 예지된 공격을 받았다!", "\(subject) took the foreseen attack!", "\(subject)は よちされた こうげきを うけた！", "¡\(subject) recibió el ataque previsto!", "\(subject) subit l’attaque prévue !", "\(subject) recebeu o ataque previsto!", "\(subject) wird vom vorhergesehenen Angriff getroffen!") }
    func battleDraggedOut(_ subject: String) -> String { t("\(subject)은(는) 날려가 버렸다!", "\(subject) was blown away!", "\(subject)は ふきとばされた！", "¡\(subject) salió despedido!", "\(subject) est expulsé !", "\(subject) foi expulso!", "\(subject) wurde weggeschleudert!") }
    func battleHazardsCleared(_ team: String) -> String { t("\(team) 주변의 함정이 사라졌다!", "The traps around \(team) disappeared!", "\(team)の まわりの しかけが きえた！", "¡Desaparecieron las trampas alrededor de \(team)!", "Les pièges autour de \(team) ont disparu !", "As armadilhas ao redor de \(team) sumiram!", "Die Fallen um \(team) sind verschwunden!") }
    func battleFellDown(_ subject: String) -> String { t("\(subject)은(는) 땅으로 떨어졌다!", "\(subject) fell straight down!", "\(subject)は ちに おちた！", "¡\(subject) cayó al suelo!", "\(subject) tombe au sol !", "\(subject) caiu no chão!", "\(subject) stürzt zu Boden!") }
    func battlePumped(_ subject: String) -> String { t("\(subject)은(는) 의욕이 넘치고 있다!", "\(subject) is getting pumped!", "\(subject)は はりきっている！", "¡\(subject) se está preparando!", "\(subject) se gonfle à bloc !", "\(subject) está se animando!", "\(subject) ist hochmotiviert!") }
    func battleBarrierStarted(_ team: String, _ barrier: BattleBarrier) -> String {
        switch barrier {
        case .reflect: return t("\(team)은(는) 물리 공격에 강해졌다!", "Reflect made \(team) stronger against physical moves!", "\(team)は ぶつりこうげきに つよくなった！", "¡Reflejo hizo a \(team) más resistente a lo físico!", "Protection rend \(team) plus résistante aux attaques physiques !", "Refletir deixou \(team) mais resistente a golpes físicos!", "Reflektor stärkt \(team) gegen physische Attacken!")
        case .lightScreen: return t("\(team)은(는) 특수 공격에 강해졌다!", "Light Screen made \(team) stronger against special moves!", "\(team)は とくしゅこうげきに つよくなった！", "¡Pantalla de luz hizo a \(team) más resistente a lo especial!", "Mur Lumière rend \(team) plus résistante aux attaques spéciales !", "Tela de Luz deixou \(team) mais resistente a golpes especiais!", "Lichtschild stärkt \(team) gegen Spezial-Attacken!")
        case .safeguard: return t("\(team)은(는) 신비의 베일에 둘러싸였다!", "\(team) cloaked itself in a mystical veil!", "\(team)は しんぴの ベールに つつまれた！", "¡\(team) se cubrió con un velo místico!", "\(team) est protégée par un voile mystique !", "\(team) se cobriu com um véu místico!", "\(team) hüllt sich in einen mystischen Schleier!")
        case .mist: return t("\(team)은(는) 하얀 안개에 둘러싸였다!", "\(team) became shrouded in mist!", "\(team)は しろい きりに つつまれた！", "¡\(team) se cubrió de neblina!", "\(team) est enveloppée de brume !", "\(team) ficou envolta em névoa!", "\(team) ist in Nebel gehüllt!")
        case .tailwind: return t("\(team)의 뒤에서 순풍이 불기 시작했다!", "The tailwind blew from behind \(team)!", "\(team)の うしろから おいかぜが ふきはじめた！", "¡Sopla viento a favor de \(team)!", "Le vent souffle derrière \(team) !", "O vento sopra a favor de \(team)!", "Rückenwind weht hinter \(team)!")
        case .luckyChant: return t("\(team)은(는) 급소에 맞지 않게 되었다!", "\(team) is shielded from critical hits!", "\(team)は きゅうしょに あたらなくなった！", "¡\(team) está a salvo de los golpes críticos!", "\(team) est protégée des coups critiques !", "\(team) está protegida de acertos críticos!", "\(team) ist vor Volltreffern geschützt!")
        }
    }
    func battleBarrierEnded(_ team: String, _ move: String) -> String {
        t("\(team)의 \(move) 효과가 사라졌다!", "The \(move) around \(team) wore off!", "\(team)の \(move)の こうかが きれた！", "¡El efecto de \(move) de \(team) terminó!", "L’effet de \(move) sur \(team) se dissipe !", "O efeito de \(move) em \(team) acabou!", "\(move) von \(team) lässt nach!")
    }
    func battleWeather(_ weather: BattleWeather, started: Bool) -> String {
        switch (weather, started) {
        case (.rain, true): return t("비가 내리기 시작했다!", "It started to rain!", "あめが ふりはじめた！", "¡Empezó a llover!", "Il commence à pleuvoir !", "Começou a chover!", "Es beginnt zu regnen!")
        case (.rain, false): return t("비가 그쳤다.", "The rain stopped.", "あめが やんだ。", "Dejó de llover.", "La pluie s’arrête.", "A chuva parou.", "Der Regen hört auf.")
        case (.sun, true): return t("햇살이 강해졌다!", "The sunlight turned harsh!", "ひざしが つよくなった！", "¡El sol pega fuerte!", "Le soleil brille fort !", "A luz do sol ficou intensa!", "Das Sonnenlicht wird grell!")
        case (.sun, false): return t("햇살이 약해졌다.", "The harsh sunlight faded.", "ひざしが もとに もどった。", "El sol vuelve a brillar como siempre.", "Le soleil redevient normal.", "A luz do sol voltou ao normal.", "Das Sonnenlicht wird wieder normal.")
        case (.sandstorm, true): return t("모래바람이 불기 시작했다!", "A sandstorm kicked up!", "すなあらしが ふきはじめた！", "¡Se levantó una tormenta de arena!", "Une tempête de sable se lève !", "Uma tempestade de areia começou!", "Ein Sandsturm kommt auf!")
        case (.sandstorm, false): return t("모래바람이 가라앉았다.", "The sandstorm subsided.", "すなあらしが おさまった。", "La tormenta de arena amainó.", "La tempête de sable se calme.", "A tempestade de areia passou.", "Der Sandsturm legt sich.")
        case (.hail, true): return t("싸라기눈이 내리기 시작했다!", "It started to hail!", "あられが ふりはじめた！", "¡Empezó a granizar!", "Il commence à grêler !", "Começou a cair granizo!", "Es beginnt zu hageln!")
        case (.hail, false): return t("싸라기눈이 그쳤다.", "The hail stopped.", "あられが やんだ。", "Dejó de granizar.", "La grêle s’arrête.", "O granizo parou.", "Der Hagel hört auf.")
        }
    }
    func battleSport(_ type: String) -> String {
        type == "fire"
            ? t("불꽃의 위력이 약해졌다!", "Fire’s power was weakened!", "ほのおの いりょくが よわまった！", "¡Se debilitó el poder del fuego!", "La puissance du feu est réduite !", "O poder do fogo foi enfraquecido!", "Die Kraft des Feuers wurde geschwächt!")
            : t("전기의 위력이 약해졌다!", "Electricity’s power was weakened!", "でんきの いりょくが よわまった！", "¡Se debilitó el poder de la electricidad!", "La puissance électrique est réduite !", "O poder da eletricidade foi enfraquecido!", "Die Kraft der Elektrizität wurde geschwächt!")
    }
    func battleTrickRoom(started: Bool) -> String {
        started ? t("시공이 뒤틀렸다!", "The dimensions were twisted!", "じくうが ゆがんだ！", "¡Se retorcieron las dimensiones!", "Les dimensions sont faussées !", "As dimensões foram distorcidas!", "Die Dimensionen wurden verzerrt!")
                : t("뒤틀린 시공이 원래대로 돌아왔다!", "The twisted dimensions returned to normal!", "ゆがんだ じくうが もとに もどった！", "¡Las dimensiones volvieron a la normalidad!", "Les dimensions redeviennent normales !", "As dimensões voltaram ao normal!", "Die Dimensionen sind wieder normal!")
    }
    func battleGravity(started: Bool) -> String {
        started ? t("중력이 강해졌다!", "Gravity intensified!", "じゅうりょくが つよくなった！", "¡La gravedad se intensificó!", "La gravité s’intensifie !", "A gravidade aumentou!", "Die Schwerkraft wird stärker!")
                : t("중력이 원래대로 돌아왔다!", "Gravity returned to normal!", "じゅうりょくが もとに もどった！", "¡La gravedad volvió a la normalidad!", "La gravité redevient normale !", "A gravidade voltou ao normal!", "Die Schwerkraft ist wieder normal!")
    }
    func battleUproar(_ subject: String, started: Bool) -> String {
        started ? t("\(subject)은(는) 소란을 피우기 시작했다!", "\(subject) caused an uproar!", "\(subject)は さわぎだした！", "¡\(subject) armó un alboroto!", "\(subject) fait un brouhaha !", "\(subject) causou um alvoroço!", "\(subject) veranstaltet einen Aufruhr!")
                : t("\(subject)은(는) 조용해졌다.", "\(subject) calmed down.", "\(subject)は おとなしくなった。", "\(subject) se calmó.", "\(subject) se calme.", "\(subject) se acalmou.", "\(subject) hat sich beruhigt.")
    }
    func battleTaunted(_ subject: String, ended: Bool) -> String {
        ended ? t("\(subject)의 도발 효과가 풀렸다!", "\(subject) shook off the taunt!", "\(subject)の ちょうはつの こうかが とけた！", "¡\(subject) ya no cae en la mofa!", "\(subject) ne subit plus la provoc !", "\(subject) se livrou da provocação!", "\(subject) lässt sich nicht mehr verhöhnen!")
              : t("\(subject)은(는) 도발에 넘어가 버렸다!", "\(subject) fell for the taunt!", "\(subject)は ちょうはつに のってしまった！", "¡\(subject) cayó en la mofa!", "\(subject) répond à la provoc !", "\(subject) caiu na provocação!", "\(subject) lässt sich verhöhnen!")
    }
    func battleEncored(_ subject: String, ended: Bool) -> String {
        ended ? t("\(subject)의 앙코르 상태가 풀렸다!", "\(subject)’s encore ended!", "\(subject)の アンコールじょうたいが とけた！", "¡Terminó el efecto de Otra vez sobre \(subject)!", "L’effet Encore sur \(subject) prend fin !", "O bis de \(subject) acabou!", "Die Zugabe von \(subject) ist vorbei!")
              : t("\(subject)은(는) 앙코르를 받았다!", "\(subject) received an encore!", "\(subject)は アンコールを うけた！", "¡\(subject) sufre los efectos de Otra vez!", "\(subject) subit l’effet Encore !", "\(subject) recebeu um bis!", "\(subject) gibt eine Zugabe!")
    }
    func battleDisabled(_ subject: String, _ move: String) -> String {
        t("\(subject)의 \(move)을(를) 봉인했다!", "\(subject)’s \(move) was disabled!", "\(subject)の \(move)を ふうじこめた！", "¡Se anuló \(move) de \(subject)!", "La capacité \(move) de \(subject) est bloquée !", "\(move) de \(subject) foi bloqueado!", "\(move) von \(subject) wurde blockiert!")
    }
    func battleDisableEnded(_ subject: String) -> String {
        t("\(subject)의 사슬묶기가 풀렸다!", "\(subject) is no longer disabled!", "\(subject)の かなしばりが とけた！", "¡\(subject) ya no está anulado!", "\(subject) n’est plus entravé !", "\(subject) não está mais bloqueado!", "\(subject) ist nicht mehr blockiert!")
    }
    func battleTormented(_ subject: String) -> String { t("\(subject)은(는) 트집을 잡혔다!", "\(subject) was subjected to torment!", "\(subject)は いちゃもんを つけられた！", "¡\(subject) sufre el tormento!", "\(subject) est tourmenté !", "\(subject) está sendo atormentado!", "\(subject) wird gequält!") }
    func battleImprisoning(_ subject: String) -> String { t("\(subject)은(는) 상대의 기술을 봉인했다!", "\(subject) sealed any moves its target shares with it!", "\(subject)は あいての わざを ふういんした！", "¡\(subject) selló los movimientos que comparte con su rival!", "\(subject) scelle les capacités qu’il partage avec l’adversaire !", "\(subject) selou os golpes em comum com o alvo!", "\(subject) versiegelt gemeinsame Attacken!") }
    func battleHealBlocked(_ subject: String, ended: Bool) -> String {
        ended ? t("\(subject)의 회복봉인이 풀렸다!", "\(subject)’s Heal Block wore off!", "\(subject)の かいふくふうじが とけた！", "¡Se acabó el Anticura de \(subject)!", "L’Anti-Soin de \(subject) prend fin !", "O Bloqueio de Cura de \(subject) acabou!", "Die Heilblockade von \(subject) ist vorbei!")
              : t("\(subject)은(는) 회복이 봉인되었다!", "\(subject) was prevented from healing!", "\(subject)は かいふくを ふうじられた！", "¡\(subject) no se puede curar!", "\(subject) ne peut plus se soigner !", "\(subject) não pode mais se curar!", "\(subject) kann sich nicht mehr heilen!")
    }
    func battleSeeded(_ subject: String) -> String { t("\(subject)에게 씨앗을 심었다!", "\(subject) was seeded!", "\(subject)に たねを うえつけた！", "¡\(subject) fue infectado por drenadoras!", "\(subject) est infecté !", "\(subject) foi semeado!", "\(subject) wurde bepflanzt!") }
    func battleDrowsy(_ subject: String) -> String { t("\(subject)은(는) 졸음이 쏟아지기 시작했다!", "\(subject) grew drowsy!", "\(subject)は ねむけを もよおした！", "¡\(subject) tiene sueño!", "\(subject) commence à somnoler !", "\(subject) ficou sonolento!", "\(subject) wird schläfrig!") }
    func battleIdentified(_ subject: String) -> String { t("\(subject)의 정체를 꿰뚫어 보았다!", "\(subject) was identified!", "\(subject)の しょうたいを みやぶった！", "¡\(subject) ha sido identificado!", "\(subject) est identifié !", "\(subject) foi identificado!", "\(subject) wurde identifiziert!") }
    func battleTrapped(_ subject: String) -> String { t("\(subject)은(는) 더 이상 도망칠 수 없다!", "\(subject) can no longer escape!", "\(subject)は もう にげられない！", "¡\(subject) ya no puede huir!", "\(subject) ne peut plus s’enfuir !", "\(subject) não pode mais fugir!", "\(subject) kann nicht mehr fliehen!") }
    func battleRooted(_ subject: String) -> String { t("\(subject)은(는) 뿌리를 내렸다!", "\(subject) planted its roots!", "\(subject)は ねを はった！", "¡\(subject) echó raíces!", "\(subject) s’enracine !", "\(subject) criou raízes!", "\(subject) schlägt Wurzeln!") }
    func battleAquaRing(_ subject: String) -> String { t("\(subject)은(는) 물의 베일을 둘렀다!", "\(subject) surrounded itself with a veil of water!", "\(subject)は みずの ベールを まとった！", "¡\(subject) se rodeó de un manto de agua!", "\(subject) s’entoure d’un voile d’eau !", "\(subject) se cercou de um véu de água!", "\(subject) umgibt sich mit einem Wasserschleier!") }
    func battleStockpiled(_ subject: String, _ count: Int) -> String { t("\(subject)은(는) \(count)만큼 비축했다!", "\(subject) stockpiled \(count)!", "\(subject)は \(count)つ たくわえた！", "¡\(subject) reservó energía \(count) veces!", "\(subject) stocke \(count) fois !", "\(subject) armazenou \(count)!", "\(subject) hat \(count)-mal gehortet!") }
    func battleCopiedStages(_ subject: String) -> String { t("\(subject)은(는) 상대의 능력 변화를 복사했다!", "\(subject) copied its opponent’s stat changes!", "\(subject)は あいての のうりょくへんかを コピーした！", "¡\(subject) copió los cambios de características del rival!", "\(subject) copie les changements de stats adverses !", "\(subject) copiou as mudanças de atributos do oponente!", "\(subject) kopiert die Statuswertänderungen des Gegners!") }
    func battleTookAim(_ subject: String) -> String { t("\(subject)은(는) 목표를 정했다!", "\(subject) took aim at its target!", "\(subject)は ねらいを さだめた！", "¡\(subject) apuntó a su objetivo!", "\(subject) vise sa cible !", "\(subject) mirou no alvo!", "\(subject) nimmt sein Ziel ins Visier!") }
    func battleDestinyBond(_ subject: String) -> String { t("\(subject)은(는) 상대를 길동무로 삼으려 한다!", "\(subject) is hoping to take its attacker down with it!", "\(subject)は あいてを みちづれに しようとしている！", "¡\(subject) quiere llevarse a su rival consigo!", "\(subject) veut entraîner son adversaire avec lui !", "\(subject) quer levar o oponente junto!", "\(subject) will seinen Angreifer mitnehmen!") }
    func battleTookDownWithIt(_ subject: String) -> String { t("\(subject)은(는) 상대를 길동무로 삼았다!", "\(subject) took its attacker down with it!", "\(subject)は あいてを みちづれに した！", "¡\(subject) se llevó a su rival consigo!", "\(subject) entraîne son adversaire avec lui !", "\(subject) levou o oponente junto!", "\(subject) hat seinen Angreifer mitgenommen!") }
    func battleHealingWish(_ subject: String) -> String { t("\(subject)에게 치유소원이 이루어졌다!", "The healing wish came true for \(subject)!", "\(subject)の いやしのねがいが かなった！", "¡El Deseo cura de \(subject) se hizo realidad!", "Le Vœu Soin se réalise pour \(subject) !", "O Desejo de Cura se realizou para \(subject)!", "Der Heilwunsch geht für \(subject) in Erfüllung!") }
    func battleInfatuated(_ subject: String) -> String { t("\(subject)은(는) 헤롱헤롱해졌다!", "\(subject) fell in love!", "\(subject)は メロメロに なった！", "¡\(subject) se ha enamorado!", "\(subject) tombe amoureux !", "\(subject) se apaixonou!", "\(subject) hat sich verliebt!") }
    func battleLevitating(_ subject: String) -> String { t("\(subject)은(는) 전자력으로 떠올랐다!", "\(subject) levitated with electromagnetism!", "\(subject)は でんじりょくで ういた！", "¡\(subject) levita gracias al electromagnetismo!", "\(subject) lévite grâce à l’électromagnétisme !", "\(subject) levitou com eletromagnetismo!", "\(subject) schwebt durch Elektromagnetismus!") }
    var battlePerishSong: String { t("멸망의노래를 들은 포켓몬은 3턴 후에 쓰러진다!", "All Pokémon that heard the song will faint in three turns!", "ほろびのうたを きいた ポケモンは 3ターンご ほろびる！", "¡Los Pokémon que oyeron la canción se debilitarán en tres turnos!", "Les Pokémon qui entendent le chant seront K.O. dans trois tours !", "Os Pokémon que ouviram a canção vão desmaiar em três turnos!", "Alle Pokémon, die das Lied hören, werden in drei Runden besiegt!") }
    func battlePerishCount(_ subject: String, _ count: Int) -> String { t("\(subject)의 멸망 카운트가 \(count)(으)로 되었다!", "\(subject)’s perish count fell to \(count).", "\(subject)の ほろびの カウントが \(count)に なった！", "La cuenta atrás de \(subject) bajó a \(count).", "Le compte à rebours de \(subject) passe à \(count).", "A contagem de \(subject) caiu para \(count).", "Der Countdown von \(subject) fällt auf \(count).") }
    func battleGuarding(_ subject: String) -> String { t("\(subject)은(는) 팀을 지키고 있다!", "\(subject) is protecting its team!", "\(subject)は みかたを まもっている！", "¡\(subject) protege a su equipo!", "\(subject) protège son équipe !", "\(subject) está protegendo a equipe!", "\(subject) schützt sein Team!") }
    func battleHazardSet(_ team: String, _ hazard: BattleHazard) -> String {
        switch hazard {
        case .spikes: return t("\(team)의 발밑에 압정이 뿌려졌다!", "Spikes were scattered around \(team)!", "\(team)の あしもとに まきびしが ちらばった！", "¡El equipo de \(team) está rodeado de púas!", "Des picots s’éparpillent autour de \(team) !", "Espinhos foram espalhados ao redor de \(team)!", "Um \(team) liegen jetzt Stacheln!")
        case .toxicSpikes: return t("\(team)의 발밑에 독압정이 뿌려졌다!", "Poison spikes were scattered around \(team)!", "\(team)の あしもとに どくびしが ちらばった！", "¡\(team) está rodeado de púas tóxicas!", "Des pics toxiques s’éparpillent autour de \(team) !", "Espinhos venenosos foram espalhados ao redor de \(team)!", "Um \(team) liegen jetzt Giftstacheln!")
        case .stealthRock: return t("\(team)의 주위에 뾰족한 바위가 떠올랐다!", "Pointed stones float in the air around \(team)!", "\(team)の まわりに とがった いわが ただよう！", "¡Unas piedras puntiagudas flotan alrededor de \(team)!", "Des pierres pointues flottent autour de \(team) !", "Pedras pontiagudas flutuam ao redor de \(team)!", "Um \(team) schweben spitze Steine!")
        }
    }
    func battleTransformed(_ subject: String, into target: String) -> String { t("\(subject)은(는) \(target)(으)로 변신했다!", "\(subject) transformed into \(target)!", "\(subject)は \(target)に へんしんした！", "¡\(subject) se transformó en \(target)!", "\(subject) se transforme en \(target) !", "\(subject) se transformou em \(target)!", "\(subject) verwandelt sich in \(target)!") }
    func battleTypeChanged(_ subject: String, _ type: String) -> String { t("\(subject)은(는) \(type) 타입이 되었다!", "\(subject) became the \(type) type!", "\(subject)は \(type)タイプに なった！", "¡\(subject) ahora es de tipo \(type)!", "\(subject) devient de type \(type) !", "\(subject) virou do tipo \(type)!", "\(subject) hat jetzt den Typ \(type)!") }
    func battleLearnedMove(_ subject: String, _ move: String) -> String { t("\(subject)은(는) \(move)을(를) 익혔다!", "\(subject) learned \(move)!", "\(subject)は \(move)を おぼえた！", "¡\(subject) aprendió \(move)!", "\(subject) apprend \(move) !", "\(subject) aprendeu \(move)!", "\(subject) hat \(move) erlernt!") }
    var battleSharedPain: String { t("서로의 체력을 나눠 가졌다!", "The battlers shared their pain!", "おたがいの たいりょくを わけあった！", "¡Los contrincantes compartieron su dolor!", "Les combattants partagent leur douleur !", "Os combatentes dividiram a dor!", "Die Kämpfer teilen ihre Schmerzen!") }
    func battleMaximizedAttack(_ subject: String) -> String { t("\(subject)은(는) 체력을 깎아 공격을 최대로 올렸다!", "\(subject) cut its own HP and maximized its Attack!", "\(subject)は たいりょくを けずって こうげきを さいだいに した！", "¡\(subject) redujo sus PS y maximizó su Ataque!", "\(subject) sacrifie des PV et maximise son Attaque !", "\(subject) sacrificou energia e maximizou seu Ataque!", "\(subject) opfert KP und maximiert seinen Angriff!") }
    func battleMadeWish(_ subject: String) -> String { t("\(subject)은(는) 소원을 빌었다!", "\(subject) made a wish!", "\(subject)は ねがいごとを した！", "¡\(subject) pidió un deseo!", "\(subject) fait un vœu !", "\(subject) fez um desejo!", "\(subject) wünscht sich etwas!") }
    func battleNightmare(_ subject: String) -> String { t("\(subject)은(는) 악몽을 꾸기 시작했다!", "\(subject) began having a nightmare!", "\(subject)は あくむを みはじめた！", "¡\(subject) comenzó a tener pesadillas!", "\(subject) commence à cauchemarder !", "\(subject) começou a ter um pesadelo!", "\(subject) hat einen Albtraum!") }
    func battleSpite(_ subject: String, _ move: String, _ amount: Int) -> String { t("\(subject)의 \(move)의 PP가 \(amount) 줄었다!", "It reduced the PP of \(subject)’s \(move) by \(amount)!", "\(subject)の \(move)を \(amount)けずった！", "¡Los PP de \(move) de \(subject) bajaron en \(amount)!", "Les PP de \(move) de \(subject) baissent de \(amount) !", "Os PP de \(move) de \(subject) caíram em \(amount)!", "Die AP von \(move) von \(subject) sinken um \(amount)!") }
    func battleGrudge(_ subject: String) -> String { t("\(subject)은(는) 상대에게 원한을 품으려 한다!", "\(subject) wants its target to bear a grudge!", "\(subject)は あいてに おんねんを かけようと している！", "¡\(subject) quiere que su rival le guarde rencor!", "\(subject) veut que son adversaire lui en veuille !", "\(subject) quer que o alvo guarde rancor!", "\(subject) will, dass sein Ziel einen Groll hegt!") }
    func battleGrudgeTriggered(_ subject: String, _ move: String) -> String { t("\(subject)의 \(move)은(는) 원념으로 PP가 0이 되었다!", "\(subject)’s \(move) lost all its PP due to the grudge!", "\(subject)の \(move)は おんねんで PPが 0に なった！", "¡\(move) de \(subject) perdió todos sus PP por el rencor!", "\(move) de \(subject) perd tous ses PP à cause de la rancune !", "\(move) de \(subject) perdeu todos os PP pelo rancor!", "\(move) von \(subject) hat wegen des Grolls alle AP verloren!") }
    func battleSwappedStages(_ subject: String) -> String { t("\(subject)은(는) 상대와 능력 변화를 바꿨다!", "\(subject) switched stat changes with its target!", "\(subject)は あいてと のうりょくへんかを いれかえた！", "¡\(subject) intercambió los cambios de características con su rival!", "\(subject) échange ses changements de stats avec la cible !", "\(subject) trocou as mudanças de atributos com o alvo!", "\(subject) tauscht die Statuswertänderungen mit dem Ziel!") }
    func battleSharedStats(_ subject: String) -> String { t("\(subject)은(는) 상대와 능력을 나눠 가졌다!", "\(subject) shared its power with its target!", "\(subject)は あいてと ちからを わかちあった！", "¡\(subject) compartió su poder con el rival!", "\(subject) partage sa puissance avec la cible !", "\(subject) dividiu seu poder com o alvo!", "\(subject) teilt seine Kraft mit dem Ziel!") }
    func battleLighter(_ subject: String) -> String { t("\(subject)은(는) 몸이 가벼워졌다!", "\(subject) became nimble!", "\(subject)は からだが かるくなった！", "¡\(subject) se volvió más ágil!", "\(subject) devient plus agile !", "\(subject) ficou mais ágil!", "\(subject) ist jetzt flinker!") }
    func battleHurledIntoAir(_ subject: String) -> String { t("\(subject)은(는) 공중에 떠올랐다!", "\(subject) was hurled into the air!", "\(subject)は ちゅうに うかびあがった！", "¡\(subject) fue lanzado por los aires!", "\(subject) est projeté en l’air !", "\(subject) foi lançado ao ar!", "\(subject) wurde in die Luft gehoben!") }
    func battleMagicCoat(_ subject: String) -> String { t("\(subject)은(는) 매직코트로 몸을 감쌌다!", "\(subject) shrouded itself with Magic Coat!", "\(subject)は マジックコートに つつまれた！", "¡\(subject) se protegió con Capa mágica!", "\(subject) s’entoure d’un Reflet Magik !", "\(subject) se cobriu com Casaco Mágico!", "\(subject) hüllt sich in einen Magiemantel!") }
    func battleBounced(_ subject: String, _ move: String) -> String { t("\(subject)은(는) \(move)을(를) 튕겨냈다!", "\(subject) bounced the \(move) back!", "\(subject)は \(move)を はねかえした！", "¡\(subject) devolvió \(move)!", "\(subject) renvoie \(move) !", "\(subject) rebateu \(move)!", "\(subject) wirft \(move) zurück!") }
    func battleChargingPower(_ subject: String) -> String { t("\(subject)은(는) 충전을 시작했다!", "\(subject) began charging power!", "\(subject)は じゅうでんを はじめた！", "¡\(subject) comenzó a cargar energía!", "\(subject) commence à se charger !", "\(subject) começou a carregar energia!", "\(subject) lädt sich auf!") }
    func battleMagnitude(_ level: Int) -> String { t("매그니튜드 \(level)!", "Magnitude \(level)!", "マグニチュード \(level)！", "¡Magnitud \(level)!", "Ampleur \(level) !", "Magnitude \(level)!", "Intensität \(level)!") }
}

extension L {
    func battleWeatherName(_ weather: BattleWeather) -> String {
        switch weather {
        case .rain: return t("비", "Rain", "あめ", "Lluvia", "Pluie", "Chuva", "Regen")
        case .sun: return t("쾌청", "Harsh sunlight", "ひざしが つよい", "Sol intenso", "Soleil", "Sol intenso", "Sonnenschein")
        case .sandstorm: return t("모래바람", "Sandstorm", "すなあらし", "Tormenta de arena", "Tempête de sable", "Tempestade de areia", "Sandsturm")
        case .hail: return t("싸라기눈", "Hail", "あられ", "Granizo", "Grêle", "Granizo", "Hagel")
        }
    }
}
