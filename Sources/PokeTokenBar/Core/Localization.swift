import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `companion.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    func t(_ ko: String, _ en: String, _ ja: String, _ es: String, _ fr: String, _ pt: String, _ de: String, _ ru: String) -> String {
        switch lang {
        case .ko: return ko
        case .en: return en
        case .ja: return ja
        case .es: return es
        case .fr: return fr
        case .pt: return pt
        case .de: return de
        case .ru: return ru
        }
    }

    // MARK: 탭
    var home: String { t("홈", "Home", "ホーム", "Inicio", "Accueil", "Início", "Startseite", "Главная") }
    /// 상위 탭 이름 — 안에서 도감/포획 로그를 세그먼트로 전환하므로 둘을 아우르는 말이어야 한다.
    /// (ko 가 "도감"이면 탭과 세그먼트가 같은 이름이 돼 en/ja 의 Collection/コレクション 과도 어긋난다.)
    var collection: String { t("컬렉션", "Collection", "コレクション", "Colección", "Collection", "Coleção", "Sammlung", "Коллекция") }

    var costUnavailable: String { t("계산 불가", "Unavailable", "計算不可", "No disponible", "Indisponible", "Indisponível", "Nicht verfügbar", "Недоступно") }
    var costEstimateHint: String { t("모델 단가로 환산한 추정 비용입니다. 구독료나 실제 청구액이 아닙니다.", "Estimated from model token rates; not a subscription fee or invoice. Service-tier and other unlogged charges are excluded.", "モデル単価による推定です。購読料や実際の請求額ではありません。", "Estimación por tarifas del modelo; no es la cuota ni la factura real.", "Estimation selon les tarifs du modèle, pas un abonnement ni une facture.", "Estimativa pelas tarifas do modelo; não é assinatura nem fatura.", "Schätzung anhand der Modellpreise, keine Abogebühr oder Rechnung.", "Оценка по тарифам моделей за токены, не плата за подписку и не счёт. Наценки за уровень обслуживания и другие незаписанные расходы не учтены.") }
    var costReportedHint: String { t("도구가 기록한 비용입니다. 실제 청구액과 다를 수 있습니다.", "Cost recorded by the tool; it may differ from the actual bill.", "ツールが記録したコストです。実際の請求額とは異なる場合があります。", "Coste registrado por la herramienta; puede diferir de la factura.", "Coût enregistré par l’outil, pouvant différer de la facture.", "Custo registrado pela ferramenta; pode diferir da fatura.", "Vom Tool gemeldete Kosten; die Rechnung kann abweichen.", "Стоимость по данным инструмента; счёт может отличаться.") }
    var costUnavailableHint: String { t("비용 기록이나 확인된 단가·토큰 구분이 없어 계산할 수 없습니다.", "No usable cost record or verified model rate and token breakdown is available.", "コスト記録、確認済み単価、またはトークン内訳がないため計算できません。", "Faltan el coste, la tarifa verificada o el desglose de tokens.", "Coût, tarif vérifié ou détail des tokens indisponible.", "Faltam custo, tarifa verificada ou detalhamento de tokens.", "Kostenangabe, bestätigter Preis oder Token-Aufteilung fehlen.", "Нет записи о стоимости, а также проверенного тарифа модели и разбивки по токенам.") }
    var costPartialHint: String { t("일부 사용량은 계산할 수 없어 제외했습니다. 표시 금액은 계산 가능한 부분의 합계이며 청구액이 아닙니다.", "Some usage could not be priced and is excluded. This is the known portion of usage cost, not an invoice.", "計算できない使用量を除いた部分合計です。請求額ではありません。", "Total parcial: excluye uso sin precio; no es una factura.", "Total partiel hors usage non chiffrable, pas une facture.", "Total parcial sem o uso não calculável; não é uma fatura.", "Teilsumme ohne nicht berechenbare Nutzung, keine Rechnung.", "Часть расхода не удалось оценить, она исключена. Показана стоимость только известной части. Это не счёт.") }

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour", "Tokens de hoje", "Heute verbrauchte Tokens", "Токены за сегодня") }
    var today: String { t("오늘", "Today", "今日", "Hoy", "Aujourd'hui", "Hoje", "Heute", "Сегодня") }
    func unattributedClaudeUsage(_ tokens: String) -> String {
        t("이번 달 계정 미확인: \(tokens)", "Not linked to an account this month: \(tokens)", "今月アカウント不明: \(tokens)",
          "Sin cuenta asociada este mes: \(tokens)", "Non rattaché à un compte ce mois-ci : \(tokens)",
          "Sem conta associada neste mês: \(tokens)", "Diesen Monat keinem Konto zugeordnet: \(tokens)", "Без привязки к аккаунту в этом месяце: \(tokens)")
    }
    var thisWeek: String { t("이번 주", "This week", "今週", "Esta semana", "Cette semaine", "Esta semana", "Diese Woche", "Эта неделя") }
    var thisMonth: String { t("이번 달", "This month", "今月", "Este mes", "Ce mois-ci", "Este mês", "Dieser Monat", "Этот месяц") }
    /// 일별 추이 막대 행의 제목. 범위가 "이번 달"임을 문구에 담는다 — 롤링 30일로 읽히면 안 된다.
    /// de 는 "Täglich diesen Monat" 이 캡션 폭을 넘겨 줄바꿈된다(실측 79.5pt vs 66.5pt) →
    /// `weekly` 의 fr "Hebdo" 와 같은 이유로 줄인다. 바로 위 줄이 "Dieser Monat" 이라 문맥은 남는다.
    var dailyTrend: String { t("이번 달 일별", "Daily this month", "今月の日別",
                               "Diario de este mes", "Par jour ce mois-ci", "Diário deste mês",
                               "Täglich",
                               "По дням") }
    /// 추이의 최댓값 라벨 — 막대 높이가 상대값이라 절대 스케일을 한 군데는 적어줘야 한다.
    var peakDay: String { t("최다", "Peak", "最多", "Máx.", "Max.", "Máx.", "Max.", "Макс.") }

    // MARK: 한도 섹션
    var limitsOfficial: String { t("한도 (공식)", "Limits (official)", "上限（公式）", "Límites (oficial)", "Limites (officiel)", "Limites (oficiais)", "Limits (offiziell)", "Лимиты (официальные)") }
    var fiveHourNotStarted: String { t("다음 메시지부터 시작", "Starts with your next message", "次のメッセージから開始", "Empieza con tu próximo mensaje", "Démarre au prochain message", "Começa na próxima mensagem", "Beginnt mit der nächsten Nachricht", "Начнётся со следующего сообщения") }
    var fiveHourSession: String { t("5시간 세션", "5-hour session", "5時間セッション", "Sesión de 5 horas", "Session de 5 h", "Sessão de 5 horas", "5-Stunden-Sitzung", "5-часовая сессия") }
    var weekly: String { t("주간", "Weekly", "週間", "Semanal", "Hebdo", "Semanal", "Wöchentlich", "Неделя") }
    var weeklyOpus: String { t("주간 Opus", "Weekly Opus", "週間 Opus", "Opus semanal", "Opus hebdo", "Opus semanal", "Opus: wöchentlich", "Opus: неделя") }
    var weeklySonnet: String { t("주간 Sonnet", "Weekly Sonnet", "週間 Sonnet", "Sonnet semanal", "Sonnet hebdo", "Sonnet semanal", "Sonnet: wöchentlich", "Sonnet: неделя") }
    var claudeCurrentBlock: String { t("Claude 현재 5h 블록", "Claude current 5h block", "Claude 現在の5hブロック", "Bloque actual de 5h de Claude", "Bloc 5 h actuel de Claude", "Bloco atual de 5h do Claude", "Aktueller 5-Stunden-Block von Claude", "Текущий 5-часовой блок Claude") }
    var reset: String { t("리셋", "Reset", "リセット", "Reinicio", "Réinit.", "Renovação", "Zurücksetzen", "Сброс") }
    /// 페이스 눈금 툴팁. "적정 사용량"으로 부르지 않는다 — 덜 쓰라는 권고가 아니라 "이 속도면 리셋
    /// 전에 소진된다"는 기준선이고, 창을 다 채워 쓸 이유가 없는 날에 규범으로 읽히면 안 된다.
    func paceHint(_ percent: String) -> String {
        t("페이스: 창 시간만큼 균등하게 썼다면 지금 \(percent)입니다.",
          "Pace: an even burn across this window would sit at \(percent) now.",
          "ペース：この枠を均等に使っていれば今は \(percent) です。",
          "Ritmo: un consumo uniforme en esta ventana estaría en \(percent) ahora.",
          "Rythme : une consommation régulière sur cette fenêtre serait à \(percent).",
          "Ritmo: um consumo uniforme nesta janela estaria em \(percent) agora.",
          "Tempo: bei gleichmäßigem Verbrauch in diesem Fenster wären es jetzt \(percent).",
          "Темп: при равномерном расходе в этом окне сейчас было бы \(percent).")
    }
    /// 페이스 대비 단계 이름. paceHint 와 같은 이유로 "적정"처럼 규범적인 말은 피하고
    /// 소진 속도만 묘사한다.
    func paceTier(_ tier: PaceTier) -> String {
        switch tier {
        case .wayUnder: return t("여유 많음", "Well under pace", "かなり余裕", "Muy por debajo del ritmo", "Bien sous le rythme", "Bem abaixo do ritmo", "Deutlich unter Tempo", "Намного медленнее темпа")
        case .under: return t("여유", "Under pace", "余裕あり", "Por debajo del ritmo", "Sous le rythme", "Abaixo do ritmo", "Unter Tempo", "Медленнее темпа")
        case .onPace: return t("페이스대로", "On pace", "ペース通り", "Al ritmo", "Dans le rythme", "No ritmo", "Im Tempo", "В темпе")
        case .slightlyOver: return t("조금 빠름", "Slightly fast", "やや速い", "Algo rápido", "Un peu rapide", "Um pouco rápido", "Etwas schnell", "Чуть быстрее")
        case .over: return t("빠름", "Fast", "速い", "Rápido", "Rapide", "Rápido", "Schnell", "Быстро")
        case .wayOver: return t("매우 빠름", "Very fast", "とても速い", "Muy rápido", "Très rapide", "Muito rápido", "Sehr schnell", "Очень быстро")
        }
    }
    /// 페이스 대비 차이(%p). **쓴 양**으로 말한다 — "앞섬/위" 같은 위치 표현은 잔량 모드에서
    /// 채움이 마커보다 짧게 그려질 때 방향이 반대로 읽힌다(#286 부류). 0 이면 문구 없음.
    /// 유럽어는 단계 이름("Under pace")이 이미 "페이스"를 말하므로 여기선 반복하지 않는다.
    func paceDelta(_ points: Int) -> String? {
        if points > 0 {
            return t("페이스보다 \(points)%p 더 씀", "\(points) pts more used", "ペースより\(points)pt多く使用",
                     "\(points) pts más de uso", "\(points) pts de plus utilisés",
                     "\(points) p.p. a mais de uso", "\(points) Pkt. mehr verbraucht", "потрачено на \(points) п.п. больше")
        }
        if points < 0 {
            let n = -points
            return t("페이스보다 \(n)%p 덜 씀", "\(n) pts less used", "ペースより\(n)pt少なく使用",
                     "\(n) pts menos de uso", "\(n) pts de moins utilisés",
                     "\(n) p.p. a menos de uso", "\(n) Pkt. weniger verbraucht", "потрачено на \(n) п.п. меньше")
        }
        return nil
    }
    var limitReached: String { t("한도 도달", "Limit reached", "上限到達", "Límite alcanzado", "Limite atteinte", "Limite atingido", "Limit erreicht", "Лимит исчерпан") }
    var personalSpendLimit: String { t("개인 사용 한도", "Personal spend limit", "個人利用上限", "Límite de gasto personal", "Limite de dépense personnelle", "Limite de gasto pessoal", "Persönliches Ausgabenlimit", "Личный лимит расходов") }
    var staleLimits: String { t("갱신 지연", "Stale", "更新遅延", "Desactualizado", "Périmé", "Desatualizado", "Nicht aktuell", "Устарело") }
    var refresh: String { t("갱신", "Refresh", "更新", "Actualizar", "Actualiser", "Atualizar", "Aktualisieren", "Обновить") }
    var limitsTapToLoad: String { t("공식 한도 불러오기", "Load official limits", "公式上限を読み込む", "Cargar límites oficiales", "Charger les limites officielles", "Carregar limites oficiais", "Offizielle Limits laden", "Загрузить официальные лимиты") }

    /// 프로바이더 상태 페이지 인시던트 지표 → 현지화 라벨(표시 전용).
    func providerStatusLabel(_ indicator: ProviderStatusIndicator) -> String {
        switch indicator {
        case .operational: return t("정상", "Operational", "正常", "Operativo", "Opérationnel", "Operacional", "Betriebsbereit", "Работает штатно")
        case .minor:       return t("일부 장애", "Minor issues", "一部障害", "Problemas menores", "Problèmes mineurs", "Problemas menores", "Kleinere Störungen", "Небольшие сбои")
        case .major:       return t("장애", "Major outage", "障害", "Interrupción grave", "Panne majeure", "Interrupção grave", "Großer Ausfall", "Серьёзный сбой")
        case .critical:    return t("심각한 장애", "Critical outage", "重大障害", "Interrupción crítica", "Panne critique", "Interrupção crítica", "Kritischer Ausfall", "Критический сбой")
        case .maintenance: return t("점검 중", "Maintenance", "メンテナンス", "Mantenimiento", "Maintenance", "Manutenção", "Wartung", "Техобслуживание")
        case .unknown:     return t("상태 불명", "Status unknown", "状態不明", "Estado desconocido", "État inconnu", "Status desconhecido", "Status unbekannt", "Статус неизвестен")
        }
    }
    func plan(_ p: String) -> String { t("플랜 \(p)", "Plan \(p)", "プラン \(p)", "Plan \(p)", "Forfait \(p)", "Plano \(p)", "Tarif \(p)", "Тариф \(p)") }
    func limitsAccount(_ a: String) -> String { t("계정 \(a)", "Account \(a)", "アカウント \(a)", "Cuenta \(a)", "Compte \(a)", "Conta \(a)", "Konto \(a)", "Аккаунт \(a)") }
    func forecastReach(_ time: String) -> String {
        t("현재 속도면 \(time) 한도 도달", "At current rate, limit hit at \(time)", "現在のペースで \(time) に上限到達", "Al ritmo actual, límite alcanzado a las \(time)", "À ce rythme, limite atteinte à \(time)", "No ritmo atual, limite atingido às \(time)", "Bei diesem Tempo erreichst du das Limit um \(time)", "При текущем темпе лимит будет исчерпан в \(time)")
    }
    var forecastNoReach: String {
        t("현재 속도로는 리셋 전 한도 도달 없음", "Won't hit limit before reset at current rate", "現在のペースではリセット前に上限到達なし", "Al ritmo actual, no alcanzarás el límite antes del reinicio", "À ce rythme, tu n'atteindras pas la limite avant la réinit.", "No ritmo atual, você não vai bater o limite antes da renovação", "Bei diesem Tempo erreichst du das Limit nicht vor dem Zurücksetzen", "При текущем темпе лимита хватит до сброса")
    }

    /// Claude oauth/usage 신형 limits[] 엔트리 이름 — kind + 모델 스코프 기반.
    func claudeLimitEntry(kind: String?, model: String?) -> String {
        switch kind {
        case "session": return fiveHourSession
        case "weekly_all": return weekly
        case "weekly_scoped":
            // 모델명이 없으면 레거시 "주간" 행과 이름이 겹치므로 scoped 임을 구분 표기
            guard let model else { return t("주간 (모델별)", "Weekly (scoped)", "週間（モデル別）", "Semanal (por modelo)", "Hebdo (par modèle)", "Semanal (por modelo)", "Wöchentlich (pro Modell)", "Неделя (по моделям)") }
            return t("주간 \(model)", "Weekly \(model)", "週間 \(model)", "Semanal \(model)", "Hebdo \(model)", "Semanal \(model)", "\(model): wöchentlich", "\(model): неделя")
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
            return t("\(h)시간", "\(h)h", "\(h)時間", "\(h)h", "\(h) h", "\(h)h", "\(h) Std.", "\(h) ч")
        case let m?: return t("\(m)분", "\(m)m", "\(m)分", "\(m)m", "\(m) min", "\(m) min", "\(m) Min.", "\(m) мин")
        case nil: return t("한도", "Limit", "上限", "Límite", "Limite", "Limite", "Limit", "Лимит")
        }
    }

    /// Antigravity 한도 그룹 및 윈도우 이름
    var antigravityGeminiGroup: String { t("Gemini 모델군", "Gemini Models", "Gemini モデル群", "Modelos Gemini", "Modèles Gemini", "Modelos Gemini", "Gemini-Modelle", "Модели Gemini") }
    var antigravityThirdPartyGroup: String { t("Claude & GPT 모델군", "Claude & GPT Models", "Claude & GPT モデル群", "Modelos Claude y GPT", "Modèles Claude et GPT", "Modelos Claude e GPT", "Claude- & GPT-Modelle", "Модели Claude и GPT") }
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
        return t("한도", "Limit", "上限", "Límite", "Limite", "Limite", "Limit", "Лимит")
    }

    // MARK: 푸터
    var refreshNow: String { t("지금 새로고침", "Refresh now", "今すぐ更新", "Actualizar ahora", "Actualiser maintenant", "Atualizar agora", "Jetzt aktualisieren", "Обновить сейчас") }
    var updated: String { t("갱신", "Updated", "更新", "Actualizado", "Mis à jour", "Atualizado", "Aktualisiert", "Обновлено") }
    var settings: String { t("설정", "Settings", "設定", "Ajustes", "Réglages", "Ajustes", "Einstellungen", "Настройки") }
    var tokenInput: String { t("입력", "Input", "入力", "Entrada", "Entrée", "Entrada", "Eingabe", "Ввод") }
    var tokenOutput: String { t("출력", "Output", "出力", "Salida", "Sortie", "Saída", "Ausgabe", "Вывод") }
    var tokenCacheWrite: String { t("캐시 쓰기", "Cache write", "キャッシュ書込", "Escritura caché", "Écriture cache", "Gravação cache", "Cache schreiben", "Запись в кэш") }
    var tokenCacheRead: String { t("캐시 읽기", "Cache read", "キャッシュ読込", "Lectura caché", "Lecture cache", "Leitura cache", "Cache lesen", "Чтение кэша") }
    var website: String { t("웹사이트", "Website", "ウェブサイト", "Sitio web", "Site web", "Site", "Website", "Сайт") }
    var sponsor: String { t("후원", "Sponsor", "支援", "Apoyar", "Soutenir", "Apoiar", "Unterstützen", "Поддержать") }
    var evolutionScrollPrevious: String { t("이전 진화 보기", "Show previous evolutions", "前の進化を見る", "Ver evoluciones anteriores", "Voir les évolutions précédentes", "Ver evoluções anteriores", "Vorherige Entwicklungen anzeigen", "Показать предыдущие эволюции") }
    var evolutionScrollNext: String { t("다음 진화 보기", "Show next evolutions", "次の進化を見る", "Ver evoluciones siguientes", "Voir les évolutions suivantes", "Ver próximas evoluções", "Nächste Entwicklungen anzeigen", "Показать следующие эволюции") }

    var back: String { t("뒤로", "Back", "戻る", "Atrás", "Retour", "Voltar", "Zurück", "Назад") }

    // MARK: Usage recap
    var recapOpen: String { t("사용량 돌아보기", "Usage recap", "使用量のふりかえり", "Resumen de uso", "Récap d'utilisation", "Resumo de uso", "Nutzungsrückblick", "Итоги расхода") }
    var recapDetails: String { t("상세", "Details", "詳細", "Detalle", "Détails", "Detalhes", "Details", "Детали") }
    var recapTokensUnit: String { t("토큰", "tokens", "トークン", "tokens", "tokens", "tokens", "Tokens", "токенов") }
    func recapScopeName(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("주간", "Week", "週", "Semana", "Semaine", "Semana", "Woche", "Неделя")
        case .month: t("월간", "Month", "月", "Mes", "Mois", "Mês", "Monat", "Месяц")
        case .year: t("연간", "Year", "年", "Año", "Année", "Ano", "Jahr", "Год")
        }
    }
    /// Shown under a running period, whose chip compares the same number of days.
    func recapCompareSoFar(_ scope: RecapScope) -> String {
        switch scope {
        case .week: t("지난주 같은 기간과 비교", "Compared with the same days last week", "先週の同じ期間と比較",
                      "Comparado con los mismos días de la semana pasada", "Comparé aux mêmes jours de la semaine dernière",
                      "Comparado com os mesmos dias da semana passada", "Verglichen mit denselben Tagen der Vorwoche", "По сравнению с теми же днями прошлой недели")
        case .month: t("지난달 같은 기간과 비교", "Compared with the same days last month", "先月の同じ期間と比較",
                       "Comparado con los mismos días del mes pasado", "Comparé aux mêmes jours du mois dernier",
                       "Comparado com os mesmos dias do mês passado", "Verglichen mit denselben Tagen des Vormonats", "По сравнению с теми же днями прошлого месяца")
        case .year: t("작년 같은 기간과 비교", "Compared with the same days last year", "昨年の同じ期間と比較",
                      "Comparado con los mismos días del año pasado", "Comparé aux mêmes jours de l'an dernier",
                      "Comparado com os mesmos dias do ano passado", "Verglichen mit denselben Tagen des Vorjahres", "По сравнению с теми же днями прошлого года")
        }
    }
    func recapCurrentPeriod(_ scope: RecapScope) -> String {
        switch scope {
        case .week: thisWeek
        case .month: thisMonth
        case .year: t("올해", "This year", "今年", "Este año", "Cette année", "Este ano", "Dieses Jahr", "Этот год")
        }
    }
    var recapPrevious: String { t("이전", "Previous", "前へ", "Anterior", "Précédent", "Anterior", "Vorherige", "Назад") }
    var recapNext: String { t("다음", "Next", "次へ", "Siguiente", "Suivant", "Próximo", "Nächste", "Вперёд") }
    var recapBestDay: String { t("최고의 날", "Best day", "最高の日", "Mejor día", "Meilleur jour", "Melhor dia", "Bester Tag", "Лучший день") }
    var recapActiveDays: String { t("활동한 날", "Active days", "稼働日", "Días activos", "Jours actifs", "Dias ativos", "Aktive Tage", "Активных дней") }
    var recapBestStreak: String { t("최장 연속", "Best streak", "最長連続", "Mejor racha", "Meilleure série", "Melhor sequência", "Beste Serie", "Лучшая серия") }
    var recapGraduates: String { t("졸업", "Graduated", "卒業", "Graduados", "Diplômés", "Formados", "Abschlüsse", "Выпускники") }
    var recapNoData: String { t("기록 없음", "no data", "記録なし", "sin datos", "pas de données", "sem dados", "keine Daten", "нет данных") }
    func recapDays(_ count: Int) -> String {
        t("\(count)일", "\(count)d", "\(count)日", "\(count) d", "\(count) j", "\(count) d", "\(count) T", "\(count) дн.")
    }
    func recapBestDayLine(_ day: String, _ tokens: String) -> String {
        t("최고의 날은 \(day), \(tokens) 토큰.",
          "Your best day was \(day): \(tokens) tokens.",
          "最高の日は \(day)、\(tokens) トークン。",
          "Tu mejor día fue el \(day): \(tokens) tokens.",
          "Ton meilleur jour, c'était \(day) : \(tokens) tokens.",
          "Seu melhor dia foi \(day): \(tokens) tokens.",
          "Dein bester Tag war \(day): \(tokens) Tokens.",
          "Лучший день: \(day), токенов: \(tokens).")
    }
    var recapNoGraduates: String {
        t("이 기간에 졸업한 포켓몬이 없어요.", "No graduation in this period.", "この期間の卒業はありません。",
          "Ninguna graduación en este periodo.", "Aucun diplômé sur cette période.",
          "Nenhuma formatura neste período.", "Kein Abschluss in diesem Zeitraum.", "За этот период выпускников нет.")
    }

    var generalSectionTitle: String { t("일반", "General", "一般", "General", "Général", "Geral", "Allgemein", "Основные") }
    var menuBarSectionTitle: String { t("메뉴바에 표시", "Show in menu bar", "メニューバーに表示", "Mostrar en la barra de menús", "Afficher dans la barre des menus", "Mostrar na barra de menus", "In der Menüleiste anzeigen", "Показывать в строке меню") }
    var advancedSectionTitle: String { t("고급", "Advanced", "詳細", "Avanzado", "Avancé", "Avançado", "Erweitert", "Дополнительно") }
    var advancedDisclosureLabel: String { t("고급 설정 · 진단", "Advanced · diagnostics", "詳細設定・診断", "Avanzado · diagnóstico", "Avancé · diagnostics", "Avançado · diagnóstico", "Erweitert · Diagnose", "Дополнительно · диагностика") }
    var aboutSupportSectionTitle: String { t("정보 & 지원", "About & Support", "情報とサポート", "Acerca de y soporte", "À propos et assistance", "Sobre e suporte", "Info & Support", "О приложении и поддержка") }
    var quit: String { t("종료", "Quit", "終了", "Salir", "Quitter", "Encerrar", "Beenden", "Завершить") }

    // MARK: 설정
    var refreshInterval: String { t("새로고침 간격", "Refresh interval", "更新間隔", "Intervalo de actualización", "Intervalle d'actualisation", "Intervalo de atualização", "Aktualisierungsintervall", "Интервал обновления") }
    var language: String { t("언어", "Language", "言語", "Idioma", "Langue", "Idioma", "Sprache", "Язык") }
    var menuBarItems: String { t("메뉴바 표시 항목 (복수 선택)", "Menu bar items (multi-select)", "メニューバー表示項目（複数選択）", "Elementos de la barra de menús (selección múltiple)", "Éléments de la barre des menus (sélection multiple)", "Itens da barra de menus (seleção múltipla)", "Elemente der Menüleiste (Mehrfachauswahl)", "Элементы строки меню (можно несколько)") }
    var todayTokensShort: String { t("오늘 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour", "Tokens de hoje", "Heutige Tokens", "Токены за сегодня") }
    var todayCost: String { t("오늘 비용 ($)", "Today's cost ($)", "本日のコスト ($)", "Coste de hoy ($)", "Coût du jour ($)", "Custo de hoje ($)", "Heutige Kosten ($)", "Стоимость за сегодня ($)") }
    var limitPercent: String { t("한도 %", "Limit %", "上限 %", "Límite %", "Limite %", "Limite %", "Limit %", "Лимит, %") }
    /// Menu bar items: tokens to the next stage or the hatch (shown "↑12M"), and the Shop's tokens ("¤217M").
    var menuEvolutionTokens: String {
        t("↑ 진화·부화까지 토큰", "↑ Tokens to evolve or hatch", "↑ 進化・孵化までのトークン", "↑ Tokens hasta evolucionar o eclosionar",
          "↑ Tokens avant évolution ou éclosion", "↑ Tokens até evoluir ou chocar", "↑ Tokens bis Entwicklung oder Schlüpfen",
          "↑ Токены до эволюции или вылупления")
    }
    var menuShopTokens: String {
        t("¤ 상점 토큰", "¤ Shop tokens", "¤ ショップのトークン", "¤ Tokens de la tienda", "¤ Tokens en boutique",
          "¤ Tokens da loja", "¤ Shop-Tokens", "¤ Токены магазина")
    }
    var menuLimitColor: String {
        t("퍼센트 색상", "Percent color", "パーセントの色", "Color del porcentaje", "Couleur du pourcentage",
          "Cor da porcentagem", "Prozentfarbe", "Цвет процентов")
    }
    var menuLimitColorHint: String {
        t("팝오버 한도 게이지와 같은 색", "Same colors as the popover limit gauges",
          "ポップオーバーの上限ゲージと同じ色", "Los mismos colores que los medidores de límite",
          "Les mêmes couleurs que les jauges de limite", "As mesmas cores dos medidores de limite",
          "Dieselben Farben wie die Limit-Balken",
          "Те же цвета, что у шкал лимитов во всплывающем окне")
    }
    func menuLimitColorMode(_ mode: UsageStore.MenuLimitColorMode) -> String {
        switch mode {
        case .gauge:
            return t("게이지와 같게", "Match gauges", "ゲージと同じ", "Como los medidores",
                     "Comme les jauges", "Como os medidores", "Wie die Balken", "Как у шкал")
        case .attention:
            return t("주의 단계만", "Only when fast", "速いときだけ", "Solo si va rápido",
                     "Seulement si rapide", "Só quando rápido", "Nur wenn schnell", "Только при быстром темпе")
        case .off:
            return t("끔", "Off", "オフ", "Desactivado", "Désactivé", "Desligado", "Aus", "Выкл.")
        }
    }
    var menuSpriteLabel: String {
        t("메뉴바의 포켓몬", "Pokémon in the menu bar", "メニューバーのポケモン", "Pokémon en la barra de menús",
          "Pokémon dans la barre des menus", "Pokémon na barra de menus", "Pokémon in der Menüleiste", "Покемон в строке меню")
    }
    var menuSpriteHideLabel: String {
        t("메뉴바의 포켓몬 숨기기", "Hide the Pokémon in the menu bar", "メニューバーのポケモンを隠す",
          "Ocultar el Pokémon de la barra de menús", "Masquer le Pokémon de la barre des menus",
          "Ocultar o Pokémon da barra de menus", "Pokémon in der Menüleiste ausblenden", "Скрыть покемона в строке меню")
    }
    var menuSpriteShowLabel: String {
        t("메뉴바에 포켓몬 표시", "Show the Pokémon in the menu bar", "メニューバーにポケモンを表示",
          "Mostrar el Pokémon en la barra de menús", "Afficher le Pokémon dans la barre des menus",
          "Mostrar o Pokémon na barra de menus", "Pokémon in der Menüleiste anzeigen", "Показать покемона в строке меню")
    }
    var menuSpriteHint: String {
        t("숨기면 사용량 글자만 보여요", "Hidden shows the usage text alone", "非表示にすると使用量の文字だけになります",
          "Oculto muestra solo el texto de uso", "Masqué n'affiche que le texte de consommation",
          "Oculto mostra só o texto de uso", "Ausgeblendet zeigt nur den Verbrauchstext", "Если скрыть, останется только текст")
    }
    var menuSpriteAnimated: String { t("움직임", "Animated", "アニメ", "Animado", "Animé", "Animado", "Animiert", "Анимация") }
    var menuSpriteStill: String { t("정지", "Still", "静止", "Fijo", "Fixe", "Parado", "Unbewegt", "Статично") }
    var menuSpriteHidden: String { t("숨김", "Hidden", "非表示", "Oculto", "Masqué", "Oculto", "Ausgeblendet", "Скрыт") }
    var animationQualityLabel: String { t("애니메이션", "Animation", "アニメーション", "Animación", "Animation", "Animação", "Animation", "Анимация") }
    var animationQualityHint: String {
        t("부드러울수록 배터리를 더 씁니다", "Smoother uses more battery",
          "滑らかにするとバッテリー消費が増えます", "Más fluido consume más batería",
          "Plus fluide consomme plus de batterie", "Mais fluido consome mais bateria",
          "Flüssigere Animationen verbrauchen mehr Batterie",
          "Чем плавнее, тем больше расход батареи")
    }
    var animationPowerSaver: String { t("배터리 절약", "Power saver", "バッテリー優先", "Ahorro de batería", "Économie d'énergie", "Economia de bateria", "Energiesparmodus", "Экономия энергии") }
    var animationBalanced: String { t("기본", "Balanced", "標準", "Equilibrado", "Équilibré", "Equilibrado", "Ausgewogen", "Баланс") }
    var animationSmooth: String { t("부드럽게", "Smooth", "滑らか", "Fluido", "Fluide", "Fluido", "Flüssig", "Плавность") }
    var limitDisplayModeLabel: String { t("한도 표시 방식", "Limit display", "上限の表示", "Visualización del límite", "Affichage de la limite", "Exibição do limite", "Limit-Anzeige", "Показ лимитов") }
    var limitDisplayUsed: String { t("사용량", "Used", "使用量", "Usado", "Utilisé", "Usado", "Verbraucht", "Потрачено") }
    var limitDisplayRemaining: String { t("남은 양", "Remaining", "残量", "Restante", "Restant", "Restante", "Verbleibend", "Осталось") }
    /// 팝오버 한도 행의 remaining 모드 표시 — %에 자기설명 접미사를 붙인다.
    func percentRemaining(_ percent: String) -> String {
        t("\(percent) 남음", "\(percent) left", "残り\(percent)", "\(percent) restante", "\(percent) restant", "\(percent) restante", "\(percent) übrig", "осталось \(percent)")
    }
    var allOffHint: String { t("전부 끄면 캐릭터만 표시됩니다", "All off shows only the character", "すべてオフにするとキャラクターのみ表示", "Si desactivas todo, solo se mostrará el personaje", "Tout désactiver n'affiche que le personnage", "Se desativar tudo, só o personagem aparece", "Wenn du alles ausschaltest, wird nur das Pokémon angezeigt", "Если всё выключить, будет виден только персонаж") }
    // MARK: 대표 포켓몬
    var representativePokemonLabel: String {
        t("대표 포켓몬", "Representative Pokémon", "代表ポケモン", "Pokémon representativo", "Pokémon représentatif", "Pokémon representativo", "Repräsentatives Pokémon", "Основной покемон")
    }
    var representativeFollowCurrent: String {
        t("현재 포켓몬 따라가기", "Follow current companion", "現在のポケモンに合わせる", "Seguir al compañero actual", "Suivre le compagnon actuel", "Seguir o companheiro atual", "Aktuellem Begleiter folgen", "Текущий компаньон")
    }
    var representativeChooseFromDex: String {
        t("도감에서 선택…", "Choose in Pokédex…", "図鑑で選ぶ…", "Elegir en la Pokédex…", "Choisir dans le Pokédex…", "Escolher na Pokédex…", "Im Pokédex auswählen…", "Выбрать в Покедексе…")
    }
    var representativeSet: String {
        t("대표로 설정", "Set as representative", "代表ポケモンに設定", "Establecer como representante", "Définir comme représentatif", "Definir como representante", "Als repräsentativ festlegen", "Сделать основным")
    }
    var representativeBadge: String { t("대표", "Representative", "代表", "Representante", "Représentatif", "Representante", "Repräsentativ", "Основной") }
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット", "Mascota flotante", "Compagnon flottant", "Mascote flutuante", "Schwebendes Pokémon", "Питомец на экране") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示", "Mostrar mascota flotante", "Afficher le compagnon flottant", "Mostrar mascote flutuante", "Schwebendes Pokémon anzeigen", "Показывать питомца на экране") }
    var floatingPetHint: String {
        t("포켓몬이 화면 위에 떠 있어요. 드래그로 위치를 옮길 수 있어요",
          "Your Pokémon floats over the screen. Drag to reposition",
          "ポケモンが画面の上に浮かびます。ドラッグで移動できます",
          "Tu Pokémon flota sobre la pantalla. Arrástralo para moverlo",
          "Ton Pokémon flotte au-dessus de l'écran. Fais-le glisser pour le déplacer",
          "Seu Pokémon flutua sobre a tela. Arraste para reposicionar",
          "Dein Pokémon schwebt über dem Bildschirm. Zieh es an die gewünschte Stelle",
          "Покемон парит поверх окон. Перетащите, чтобы переместить")
    }
    var floatingPetSizeLabel: String { t("크기", "Size", "サイズ", "Tamaño", "Taille", "Tamanho", "Größe", "Размер") }
    /// 푸터 눈 아이콘의 툴팁(켜져 있을 때) — 켜는 쪽 문구는 floatingPetEnableLabel 을 그대로 쓴다.
    var floatingPetHideLabel: String {
        t("플로팅 펫 숨기기", "Hide floating pet", "フローティングペットを隠す", "Ocultar mascota flotante",
          "Masquer le compagnon flottant", "Ocultar mascote flutuante", "Schwebendes Pokémon ausblenden", "Скрыть питомца")
    }
    /// 지금은 한도 알림만 말풍선으로 뜨지만, 알림 종류가 늘어도 이 라벨은 그대로 쓴다.
    var floatingPetBubbleAlertsLabel: String {
        t("말풍선으로 알림 받기", "Show notifications as bubbles", "通知を吹き出しで表示", "Mostrar notificaciones como globos", "Afficher les notifications en bulles", "Mostrar notificações em balões", "Benachrichtigungen als Sprechblasen anzeigen", "Показывать уведомления в облачке")
    }
    var floatingPetMenuOpen: String { t("토큰 바 열기", "Open Token Bar", "トークンバーを開く", "Abrir Token Bar", "Ouvrir Token Bar", "Abrir o Token Bar", "Token Bar öffnen", "Открыть Token Bar") }
    var floatingPetMenuHide: String {
        t("플로팅 펫 끄기", "Turn off floating pet", "フローティングペットをオフ", "Desactivar mascota flotante", "Désactiver le compagnon flottant", "Desativar mascote flutuante", "Schwebendes Pokémon ausschalten", "Выключить питомца на экране")
    }
    func floatingPetHoverTokensOnly(_ tokens: String) -> String {
        t("오늘 \(tokens) 토큰", "Today: \(tokens) tokens", "今日: \(tokens) トークン", "Hoy: \(tokens) tokens", "Aujourd'hui : \(tokens) tokens", "Hoje: \(tokens) tokens", "Heute: \(tokens) Tokens", "Токенов сегодня: \(tokens)")
    }
    func floatingPetHoverWithLimit(_ tokens: String, _ percent: String) -> String {
        t("오늘 \(tokens) 토큰 (한도 \(percent))",
          "Today: \(tokens) tokens (limit \(percent))",
          "今日: \(tokens) トークン（上限 \(percent)）",
          "Hoy: \(tokens) tokens (límite \(percent))",
          "Aujourd'hui : \(tokens) tokens (limite \(percent))",
          "Hoje: \(tokens) tokens (limite \(percent))",
          "Heute: \(tokens) Tokens (Limit \(percent))",
          "Токенов сегодня: \(tokens) (лимит \(percent))")
    }

    var disableKeychain: String { t("Keychain 접근 끄기", "Disable Keychain access", "Keychainアクセスを無効化", "Desactivar acceso a Keychain", "Désactiver l'accès au Keychain", "Desativar acesso ao Keychain", "Keychain-Zugriff deaktivieren", "Отключить доступ к Связке ключей") }
    var disableKeychainHint: String { t("켜면 Keychain 접근 허용 팝업이 더 안 뜹니다. 공식 한도(%)만 숨겨지고 토큰·비용은 그대로", "When on, no more Keychain permission pop-ups. Only official limits (%) are hidden; tokens/cost stay", "オンにするとKeychain許可のポップアップが出なくなります。公式上限(%)のみ非表示、トークン・費用はそのまま", "Al activarlo, ya no aparecerán los avisos de permiso de Keychain. Solo se ocultan los límites oficiales (%), los tokens y el coste se mantienen", "Une fois activé, plus de pop-ups d'autorisation Keychain. Seules les limites officielles (%) sont masquées ; les tokens et le coût restent visibles", "Ao ativar, os avisos de permissão do Keychain não aparecem mais. Só os limites oficiais (%) ficam ocultos; tokens e custo continuam", "Wenn aktiviert, erscheinen keine Keychain-Berechtigungsfenster mehr. Nur offizielle Limits (%) werden ausgeblendet; Tokens und Kosten bleiben sichtbar", "Если включено, запросов доступа к Связке ключей не будет. Скрываются только официальные лимиты (%), токены и стоимость остаются") }
    var refreshLimitToken: String { t("한도 토큰 캐시 갱신", "Refresh limit token cache", "上限トークンキャッシュを更新", "Actualizar caché del token de límite", "Actualiser le cache du token de limite", "Atualizar cache do token de limite", "Limit-Token-Cache aktualisieren", "Обновить токен") }
    var onlyOnPress: String { t("누를 때만 Keychain 을 읽어요. 자동 폴링은 안 읽어 팝업이 안 떠요. 토큰 만료 후 이 버튼으로 한도 갱신", "Reads Keychain only when pressed. Auto-polling never does, so no pop-ups. Refresh limits here after the token expires", "押した時のみKeychainを読みます。自動更新では読まずポップアップも出ません。トークン期限切れ後はこのボタンで上限を更新", "Solo lee Keychain al pulsar. El sondeo automático nunca lo hace, así que no aparecen avisos. Usa este botón para actualizar los límites tras la expiración del token", "Lit le Keychain uniquement sur appui. Le polling automatique ne le fait jamais, donc pas de pop-up. Actualise les limites ici après l'expiration du token", "Só lê o Keychain quando você clica no botão. A atualização automática nunca lê, então não aparecem avisos. Use este botão para atualizar os limites depois que o token expirar", "Keychain wird nur auf Knopfdruck gelesen. Die automatische Abfrage greift nicht darauf zu, daher gibt es keine Pop-ups. Aktualisiere die Limits hier, wenn das Token abgelaufen ist", "Связка ключей читается только по нажатию. Автообновление её не трогает, поэтому запросов не будет. Обновите лимиты здесь, когда токен истечёт") }
    var launchAtLogin: String { t("로그인 시 자동 시작", "Launch at login", "ログイン時に自動起動", "Iniciar al arrancar sesión", "Lancer à l'ouverture de session", "Abrir ao iniciar sessão", "Bei der Anmeldung starten", "Запускать при входе в систему") }
    var bundledOnly: String { t(".app 번들로 설치된 경우에만 사용 가능 (scripts/build-app.sh)", "Available only when installed as an .app bundle (scripts/build-app.sh)", ".appバンドルでインストールした場合のみ利用可能 (scripts/build-app.sh)", "Disponible solo si se instaló como paquete .app (scripts/build-app.sh)", "Disponible uniquement si installé comme paquet .app (scripts/build-app.sh)", "Disponível apenas quando instalado como pacote .app (scripts/build-app.sh)", "Nur verfügbar, wenn die App als .app-Bundle installiert ist (scripts/build-app.sh)", "Доступно только при установке в виде .app (scripts/build-app.sh)") }
    var notificationsSection: String { t("알림", "Notifications", "通知", "Notificaciones", "Notifications", "Notificações", "Benachrichtigungen", "Уведомления") }
    // MARK: claude.ai 세션 키 (Keychain 프롬프트 없는 한도 경로)
    var sessionKeyLabel: String { t("claude.ai 세션 키", "claude.ai session key", "claude.ai セッションキー", "Clave de sesión de claude.ai", "Clé de session claude.ai", "Chave de sessão do claude.ai", "claude.ai-Sitzungsschlüssel", "Ключ сессии claude.ai") }
    var sessionKeyHint: String {
        t("Keychain 팝업 없이 공식 한도를 조회합니다. 브라우저 개발자도구 → Application → Cookies → claude.ai → sessionKey 값을 붙여넣으세요.",
          "Fetches official limits with no Keychain pop-up. Paste the value from DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Keychain のポップアップなしで公式上限を取得します。開発者ツール → Application → Cookies → claude.ai → sessionKey の値を貼り付けてください。",
          "Obtiene los límites oficiales sin avisos de Keychain. Pega el valor de DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Récupère les limites officielles sans pop-up Keychain. Colle la valeur depuis DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Busca os limites oficiais sem avisos do Keychain. Cole o valor de DevTools → Application → Cookies → claude.ai → sessionKey.",
          "Ruft offizielle Limits ohne Keychain-Pop-up ab. Füge den Wert aus DevTools → Application → Cookies → claude.ai → sessionKey ein.",
          "Загружает официальные лимиты без запросов Связки ключей. Вставьте значение из DevTools → Application → Cookies → claude.ai → sessionKey.")
    }
    var sessionKeyPerAccountNote: String {
        t("기본 Claude 계정(~/.claude)에 적용됩니다. 다른 계정은 아래에서 각자 키를 넣을 수 있어요.",
          "Applies to the default Claude account (~/.claude). Each other account can have its own key below.",
          "デフォルトの Claude アカウント（~/.claude）に適用されます。ほかのアカウントは下でそれぞれキーを設定できます。",
          "Se aplica a la cuenta de Claude predeterminada (~/.claude). Cada una de las otras cuentas puede tener su propia clave abajo.",
          "Concerne le compte Claude principal (~/.claude). Chaque autre compte peut avoir sa propre clé ci-dessous.",
          "Aplica-se à conta padrão do Claude (~/.claude). Cada uma das outras contas pode ter a própria chave abaixo.",
          "Gilt für das Standard-Claude-Konto (~/.claude). Jedes weitere Konto kann unten einen eigenen Schlüssel haben.",
          "Действует для основного аккаунта Claude (~/.claude). Для остальных аккаунтов ниже можно задать отдельные ключи.")
    }
    /// An additional account's own key row: the account's tab title, or its folder before its limits load.
    func accountSessionKeyLabel(_ account: String) -> String {
        t("\(account) 세션 키", "Session key for \(account)", "\(account) のセッションキー",
          "Clave de sesión de \(account)", "Clé de session de \(account)", "Chave de sessão de \(account)",
          "Sitzungsschlüssel für \(account)",
          "Ключ сессии: \(account)")
    }
    /// 평문 보관을 숨기지 않는다 — 사용자가 무엇을 맡기는지, 어떻게 취소하는지 알아야 한다.
    var sessionKeyStorageNote: String {
        t("키는 이 Mac 의 앱 폴더에 본인만 읽을 수 있는 파일로 저장됩니다(암호화 아님). 브라우저에서 로그아웃하면 즉시 무효화됩니다.",
          "The key is stored in this Mac's app folder as an owner-only file (not encrypted). Logging out in your browser invalidates it immediately.",
          "キーはこの Mac のアプリフォルダに本人のみ読み取り可能なファイルとして保存されます(暗号化なし)。ブラウザでログアウトすると即時無効になります。",
          "La clave se guarda en la carpeta de la app de este Mac como archivo solo para el propietario (sin cifrar). Al cerrar sesión en el navegador se invalida de inmediato.",
          "La clé est enregistrée dans le dossier de l'app sur ce Mac, en fichier lisible par toi seul (non chiffré). Te déconnecter dans le navigateur l'invalide immédiatement.",
          "A chave fica na pasta do app neste Mac, em um arquivo que só você pode ler (sem criptografia). Sair da conta no navegador a invalida na hora.",
          "Der Schlüssel liegt im App-Ordner dieses Macs in einer Datei, die nur du lesen kannst (unverschlüsselt). Meldest du dich im Browser ab, wird er sofort ungültig.",
          "Ключ хранится в папке приложения на этом Mac в файле, доступном только владельцу (без шифрования). Выход из аккаунта в браузере сразу делает его недействительным.")
    }
    var sessionKeySaved: String { t("설정됨", "Saved", "設定済み", "Guardada", "Enregistrée", "Salva", "Gespeichert", "Сохранено") }
    var save: String { t("저장", "Save", "保存", "Guardar", "Enregistrer", "Salvar", "Speichern", "Сохранить") }
    var delete: String { t("삭제", "Delete", "削除", "Eliminar", "Supprimer", "Excluir", "Löschen", "Удалить") }
    var sessionKeyOrganizationLabel: String { t("조직", "Organization", "組織", "Organización", "Organisation", "Organização", "Organisation", "Организация") }
    var sessionKeyMalformedError: String {
        t("세션 키 형식이 아닙니다. sessionKey 쿠키 값 전체를 붙여넣었는지 확인하세요(sk-ant- 로 시작).",
          "That isn't a session key. Check you pasted the whole sessionKey cookie value (starts with sk-ant-).",
          "セッションキーの形式ではありません。sessionKey クッキーの値全体を貼り付けたか確認してください(sk-ant- で始まります)。",
          "Eso no es una clave de sesión. Comprueba que pegaste todo el valor de la cookie sessionKey (empieza por sk-ant-).",
          "Ce n'est pas une clé de session. Vérifie que tu as collé toute la valeur du cookie sessionKey (elle commence par sk-ant-).",
          "Isso não é uma chave de sessão. Confira se você colou todo o valor do cookie sessionKey (começa com sk-ant-).",
          "Das ist kein Sitzungsschlüssel. Prüfe, ob du den vollständigen Wert des sessionKey-Cookies eingefügt hast (beginnt mit sk-ant-).",
          "Это не ключ сессии. Проверьте, что вставили значение cookie sessionKey целиком (начинается с sk-ant-).")
    }
    var sessionKeyExpiredError: String {
        t("세션 키가 만료됐습니다. 브라우저에서 다시 복사해 붙여넣으세요.",
          "The session key expired. Copy a fresh one from your browser and paste it again.",
          "セッションキーの有効期限が切れました。ブラウザから再度コピーして貼り付けてください。",
          "La clave de sesión caducó. Copia una nueva desde el navegador y pégala otra vez.",
          "La clé de session a expiré. Copie-en une nouvelle depuis le navigateur et colle-la à nouveau.",
          "A chave de sessão expirou. Copie uma nova do navegador e cole de novo.",
          "Der Sitzungsschlüssel ist abgelaufen. Kopiere einen neuen aus deinem Browser und füge ihn erneut ein.",
          "Срок действия ключа сессии истёк. Скопируйте новый из браузера и вставьте снова.")
    }
    var sessionKeyNoOrgError: String {
        t("이 키로 한도를 볼 수 있는 조직이 없습니다.",
          "No organization on this key can show limits.",
          "このキーで上限を確認できる組織がありません。",
          "Ninguna organización de esta clave puede mostrar límites.",
          "Aucune organisation liée à cette clé ne peut afficher de limites.",
          "Nenhuma organização desta chave pode mostrar limites.",
          "Keine Organisation dieses Schlüssels kann Limits anzeigen.",
          "Ни одна организация с этим ключом не может показать лимиты.")
    }

    // MARK: 세션 키 만료 안내 — OAuth 만료와 처방이 다르므로 문구·행동을 따로 둔다
    var sessionKeyExpiredTitle: String {
        t("claude.ai 세션 키 만료: 한도가 갱신 안 돼요",
          "claude.ai session key expired: limits aren't refreshing",
          "claude.ai セッションキーの期限切れ：上限が更新されません",
          "La clave de sesión de claude.ai caducó: los límites no se actualizan",
          "Clé de session claude.ai expirée : les limites ne s'actualisent plus",
          "A chave de sessão do claude.ai expirou: os limites não estão atualizando",
          "claude.ai-Sitzungsschlüssel abgelaufen: Limits werden nicht aktualisiert",
          "Ключ сессии claude.ai истёк: лимиты не обновляются")
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
          "Die angezeigten Werte stammen von vor dem Ablauf. Kopiere einen neuen sessionKey aus deinem Browser und füge ihn unter Einstellungen → Erweitert ein.",
          "Показаны данные, полученные до истечения ключа. Скопируйте новый sessionKey из браузера и вставьте его в \"Настройки → Дополнительно\".")
    }
    var sessionKeyExpiredBadge: String {
        t("만료됨", "Expired", "期限切れ", "Caducada", "Expirée", "Expirada", "Abgelaufen", "Истёк")
    }

    // MARK: Claude Keychain 항상 허용 초기화 도움말 (상시 안내)
    var claudeKeychainHelpTitle: String {
        t("왜 주기적으로 암호를 묻나요?",
          "Why does it ask for password periodically?",
          "なぜ定期的にパスワードを求められるのですか？",
          "¿Por qué pide la contraseña periódicamente?",
          "Pourquoi le mot de passe est-il demandé périodiquement ?",
          "Por que pede a senha periodicamente?",
          "Warum wird regelmäßig nach dem Passwort gefragt?",
          "Почему периодически запрашивается пароль?")
    }
    var claudeKeychainHelpBody: String {
        t("Claude CLI가 백그라운드에서 토큰을 교체할 때 macOS 키체인의 '항상 허용' 권한이 초기화됩니다. 세션 키를 등록하면 암호 입력 없이 백그라운드 자동 갱신이 유지됩니다.",
          "When Claude CLI rotates tokens in the background, macOS resets the Keychain 'Always Allow' permission. Registering a session key keeps background limits refreshed without any password prompt.",
          "Claude CLI がバックグラウンドでトークンをローテーションすると、macOS Keychain の「常に許可」権限がリセットされます。セッションキーを登録すると、パスワード入力なしで自動更新が維持されます。",
          "Cuando Claude CLI rota tokens en segundo plano, macOS restablece el permiso 'Permitir siempre' del Llavero. Registrar una clave de sesión mantiene los límites actualizados sin pedir contraseña.",
          "Lorsque Claude CLI renouvelle les jetons en arrière-plan, macOS réinitialise l'autorisation 'Toujours autoriser'. L'enregistrement d'une clé de session permet de maintenir les limites à jour sans mot de passe.",
          "Quando o Claude CLI renova tokens em segundo plano, o macOS redefine a permissão 'Permitir Sempre'. Cadastrar uma chave de sessão mantém a atualização automática sem solicitar senha.",
          "Wenn Claude CLI Tokens im Hintergrund erneuert, setzt macOS die Berechtigung 'Immer erlauben' zurück. Ein registrierter Sitzungsschlüssel hält Limits ohne Passwortabfrage aktuell.",
          "Когда Claude CLI в фоне обновляет токены, macOS сбрасывает разрешение \"Разрешать всегда\" в Связке ключей. Если добавить ключ сессии, лимиты будут обновляться в фоне без запросов пароля.")
    }
    var registerSessionKey: String {
        t("세션 키 등록",
          "Register Session Key",
          "セッションキーを登録",
          "Registrar clave de sesión",
          "Enregistrer la clé de session",
          "Cadastrar chave de sessão",
          "Sitzungsschlüssel registrieren",
          "Добавить ключ сессии")
    }
    var claudeKeychainHelpTooltip: String {
        t("Claude 키체인 인증 안내",
          "Claude Keychain authentication info",
          "Claude Keychain 認証について",
          "Información de autenticación de Keychain de Claude",
          "Info sur l'authentification Keychain Claude",
          "Informações de autenticação do Keychain do Claude",
          "Claude Keychain-Authentifizierungsinformation",
          "Об авторизации Claude через Связку ключей")
    }

    var limitNotificationsLabel: String { t("한도 알림", "Limit alerts", "上限通知", "Alertas de límite", "Alertes de limite", "Alertas de limite", "Limit-Warnungen", "Оповещения о лимитах") }
    var companionNotificationsLabel: String { t("Companion 이벤트 (부화·진화·졸업)", "Companion events (hatch / evolve / graduate)", "コンパニオンイベント（孵化・進化・卒業）", "Eventos del compañero (eclosión / evolución / graduación)", "Événements du compagnon (éclosion / évolution / diplôme)", "Eventos do companheiro (nascimento / evolução / formatura)", "Begleiter-Ereignisse (Schlüpfen / Entwicklung / Abschied)", "События компаньона (вылупление / эволюция / выпуск)") }
    var statusChecksLabel: String { t("프로바이더 상태 확인", "Provider status checks", "プロバイダー状態チェック", "Comprobación de estado de proveedores", "Vérification de l'état des fournisseurs", "Verificação de status dos provedores", "Anbieterstatus prüfen", "Проверка статуса провайдеров") }
    var statusChecksHint: String { t("Claude·OpenAI 장애를 팝오버에 표시 (알림 아님)", "Show Claude / OpenAI incidents in the popover (not a notification)", "Claude・OpenAIの障害をポップオーバーに表示（通知ではない）", "Muestra incidentes de Claude/OpenAI en el popover (no es una notificación)", "Affiche les incidents Claude / OpenAI dans le popover (pas une notification)", "Mostra incidentes do Claude/OpenAI no painel (não é uma notificação)", "Störungen bei Claude / OpenAI im Popover anzeigen (keine Benachrichtigung)", "Показывать инциденты Claude / OpenAI во всплывающем окне (не уведомлением)") }
    var warning: String { t("경고", "Warning", "警告", "Aviso", "Avertissement", "Aviso", "Warnung", "Предупреждение") }
    var critical: String { t("임박", "Critical", "切迫", "Crítico", "Critique", "Crítico", "Kritisch", "Критично") }
    var aggregationNote: String { t("토큰 집계 기준: totalTokens (input + output + cache, 로컬 날짜)", "Token basis: totalTokens (input + output + cache, local date)", "集計基準: totalTokens (input + output + cache, ローカル日付)", "Base de cálculo: totalTokens (input + output + cache, fecha local)", "Base de calcul : totalTokens (input + output + cache, date locale)", "Base de cálculo: totalTokens (input + output + cache, data local)", "Token-Grundlage: totalTokens (input + output + cache, lokales Datum)", "Подсчёт токенов: totalTokens (ввод + вывод + кэш, по местной дате)") }
    var customScanProviderLabel: String { t("프로바이더", "Provider", "プロバイダー", "Proveedor", "Fournisseur", "Provedor", "Anbieter", "Провайдер") }
    var customScanRootsLabel: String { t("추가 스캔 폴더", "Additional scan folders", "追加スキャンフォルダ", "Carpetas de escaneo adicionales", "Dossiers d'analyse supplémentaires", "Pastas extras para escanear", "Zusätzliche Scan-Ordner", "Дополнительные папки для сканирования") }
    var customScanRootsHint: String {
        t("선택한 프로바이더의 로그가 기본 위치 밖에 있을 때만. 콤마·줄바꿈 구분, * 와일드카드. 다른 프로바이더 폴더를 넣지 마세요.",
          "Only for this provider's logs outside the built-in locations. Comma/newline separated, * wildcards. Do not point at another provider's folder.",
          "選択したプロバイダーのログが既定の場所にないときだけ。カンマ・改行区切り、*ワイルドカード。別プロバイダーのフォルダは指定しないでください。",
          "Solo para los registros de este proveedor fuera de las ubicaciones integradas. Separados por coma o salto de línea; comodines *. No indiques la carpeta de otro proveedor.",
          "Uniquement pour les journaux de ce fournisseur en dehors des emplacements intégrés. Séparés par des virgules ou des retours à la ligne ; caractères génériques *. N'indique pas le dossier d'un autre fournisseur.",
          "Só para os logs deste provedor fora dos locais padrão. Separados por vírgula ou quebra de linha; curingas *. Não aponte para a pasta de outro provedor.",
          "Nur für Protokolle dieses Anbieters außerhalb der Standardpfade. Durch Kommas oder Zeilenumbrüche getrennt, * als Platzhalter. Wähle keinen Ordner eines anderen Anbieters.",
          "Только для логов этого провайдера вне стандартных мест. Через запятую или с новой строки, поддерживается подстановка *. Не указывайте папку другого провайдера.")
    }
    var customScanRootsPlaceholder: String { t("~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions", "~/path/to/sessions") }
    func customScanRootsMatches(_ n: Int) -> String {
        t("지금 \(n)개 추가 폴더를 스캔함", "Scans \(n) extra folder(s) now", "現在\(n)個の追加フォルダをスキャン", "Escanea \(n) carpeta(s) extra ahora", "Analyse \(n) dossier(s) supplémentaire(s) maintenant", "Escaneando \(n) pasta(s) extra agora", "Zusätzlich gescannte Ordner: \(n)", "Сканируется дополнительных папок: \(n)")
    }
    // MARK: Additional Claude accounts (Settings → Advanced)
    var additionalClaudeAccountsLabel: String { t("추가 Claude 계정", "Additional Claude accounts", "追加のClaudeアカウント", "Cuentas de Claude adicionales", "Comptes Claude supplémentaires", "Contas extras do Claude", "Weitere Claude-Konten", "Дополнительные аккаунты Claude") }
    var additionalClaudeAccountsHint: String {
        t("다른 Claude Code 로그인(CLAUDE_CONFIG_DIR)은 ~/.claude-* 폴더와 export 된 CLAUDE_CONFIG_DIR 에서 자동으로 찾습니다. 다른 위치의 설정 폴더만 여기 추가하세요(콤마·줄바꿈 구분). 공식 한도에 계정마다 탭이 생기며, 수동 갱신 때 폴더마다 Keychain 접근을 물을 수 있습니다.",
          "Other Claude Code logins (CLAUDE_CONFIG_DIR) are detected in ~/.claude-* folders and from an exported CLAUDE_CONFIG_DIR. Add config folders stored elsewhere here, comma/newline separated. Each account gets its own tab in the official limits; a manual refresh may ask for Keychain access for each folder.",
          "他のClaude Codeログイン(CLAUDE_CONFIG_DIR)は ~/.claude-* フォルダと、エクスポートされた CLAUDE_CONFIG_DIR から自動検出されます。別の場所にある設定フォルダだけをここに追加してください(カンマ・改行区切り)。公式上限にアカウントごとのタブが追加され、手動更新時にフォルダごとにKeychainへのアクセスを確認することがあります。",
          "Los otros inicios de sesión de Claude Code (CLAUDE_CONFIG_DIR) se detectan en las carpetas ~/.claude-* y en un CLAUDE_CONFIG_DIR exportado. Añade aquí las carpetas de configuración guardadas en otro lugar, separadas por coma o salto de línea. Cada cuenta tiene su pestaña en los límites oficiales; una actualización manual puede pedir acceso a Keychain para cada carpeta.",
          "Les autres connexions Claude Code (CLAUDE_CONFIG_DIR) sont détectées dans les dossiers ~/.claude-* et depuis un CLAUDE_CONFIG_DIR exporté. Ajoute ici les dossiers de config rangés ailleurs, séparés par des virgules ou des retours à la ligne. Chaque compte a son onglet dans les limites officielles ; une actualisation manuelle peut demander l'accès au Keychain pour chaque dossier.",
          "Os outros logins do Claude Code (CLAUDE_CONFIG_DIR) são detectados nas pastas ~/.claude-* e num CLAUDE_CONFIG_DIR exportado. Adicione aqui pastas de configuração guardadas em outro lugar, separadas por vírgula ou quebra de linha. Cada conta ganha sua aba nos limites oficiais; uma atualização manual pode pedir acesso ao Keychain para cada pasta.",
          "Weitere Claude-Code-Anmeldungen (CLAUDE_CONFIG_DIR) werden in ~/.claude-*-Ordnern und über ein exportiertes CLAUDE_CONFIG_DIR erkannt. Füge hier Konfigurationsordner an anderen Orten hinzu, durch Kommas oder Zeilenumbrüche getrennt. Jedes Konto bekommt bei den offiziellen Limits einen eigenen Tab; eine manuelle Aktualisierung kann für jeden Ordner nach Keychain-Zugriff fragen.",
          "Другие входы в Claude Code (CLAUDE_CONFIG_DIR) находятся автоматически в папках ~/.claude-* и по экспортированной переменной CLAUDE_CONFIG_DIR. Папки конфигурации в других местах добавьте здесь, через запятую или с новой строки. У каждого аккаунта своя вкладка в официальных лимитах; при ручном обновлении может запрашиваться доступ к Связке ключей для каждой папки.")
    }
    func additionalClaudeAccountsDetected(_ folders: String) -> String {
        t("자동 감지: \(folders)", "Detected: \(folders)", "自動検出: \(folders)", "Detectadas: \(folders)", "Détectés : \(folders)", "Detectadas: \(folders)", "Erkannt: \(folders)", "Найдено: \(folders)")
    }
    var trackedAccountLabel: String { t("추적할 Claude 계정", "Tracked Claude account", "追跡する Claude アカウント", "Cuenta de Claude seguida", "Compte Claude suivi", "Conta do Claude acompanhada", "Verfolgtes Claude-Konto", "Отслеживаемый аккаунт Claude") }
    func trackedAccountToolTip(_ title: String) -> String {
        t("추적할 Claude 계정: \(title)", "Tracked Claude account: \(title)", "追跡する Claude アカウント: \(title)",
          "Cuenta de Claude seguida: \(title)", "Compte Claude suivi : \(title)",
          "Conta do Claude acompanhada: \(title)", "Verfolgtes Claude-Konto: \(title)", "Отслеживаемый аккаунт Claude: \(title)")
    }
    var trackedAccountHint: String {
        t("메뉴바 한도·경고 상태·컴패니언 기분·5시간 예측의 기준이에요.",
          "Drives the menu bar limit, warning state, companion mood and 5h forecast.",
          "メニューバーの上限・警告状態・コンパニオンの様子・5時間予測に使われます。",
          "Define el límite de la barra de menús, el estado de alerta, el ánimo del compañero y la previsión de 5 h.",
          "Pilote la limite de la barre des menus, l'état d'alerte, l'humeur du compagnon et la prévision 5 h.",
          "Define o limite na barra de menus, o estado de alerta, o humor do companheiro e a previsão de 5 h.",
          "Bestimmt das Limit in der Menüleiste, den Warnstatus, die Stimmung des Begleiters und die 5-Stunden-Prognose.",
          "Определяет лимит в строке меню, предупреждения, настроение компаньона и прогноз на 5 ч.")
    }
    var trackedAccountAutomatic: String { t("자동 (마지막 사용)", "Automatic (last used)", "自動（最後に使用）", "Automático (último usado)", "Automatique (dernier utilisé)", "Automático (último usado)", "Automatisch (zuletzt verwendet)", "Автоматически (последний активный)") }
    var trackedAccountHighest: String { t("사용률 최고", "Highest usage", "使用率が最大", "Mayor uso", "Le plus chargé", "Maior uso", "Höchste Auslastung", "Наибольший расход") }
    var additionalClaudeAccountsPlaceholder: String { t("~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work", "~/.claude-work") }
    func additionalClaudeAccountsFound(_ n: Int) -> String {
        t("계정 폴더 \(n)개 찾음", "\(n) account folder(s) found", "アカウントフォルダが\(n)個見つかりました", "\(n) carpeta(s) de cuenta encontrada(s)", "\(n) dossier(s) de compte trouvé(s)", "\(n) pasta(s) de conta encontrada(s)", "Gefundene Kontoordner: \(n)", "Найдено папок аккаунтов: \(n)")
    }
    var close: String { t("닫기", "Close", "閉じる", "Cerrar", "Fermer", "Fechar", "Schließen", "Закрыть") }
    var saveLockUnreadable: String {
        t("저장 파일을 읽을 수 없어요(권한 또는 디스크 문제). 덮어쓰지 않도록 아무것도 저장하지 않아요. 파일을 확인한 뒤 앱을 다시 실행해 주세요.",
          "Your save can't be read (permissions or a disk error). Nothing is written so it isn't overwritten: check the file, then relaunch the app.",
          "セーブファイルを読み込めません（権限またはディスクの問題）。上書きしないよう何も保存しません。ファイルを確認してからアプリを再起動してください。",
          "Tu partida guardada no se puede leer (permisos o un error del disco). No se escribe nada para no sobrescribirla: revisa el archivo y vuelve a abrir la app.",
          "Ta sauvegarde ne peut pas être lue (droits ou erreur du disque). Rien n'est écrit pour ne pas l'écraser : vérifie le fichier, puis relance l'app.",
          "Seu salvamento não pode ser lido (permissões ou erro no disco). Nada é gravado para não sobrescrevê-lo: verifique o arquivo e abra o app de novo.",
          "Dein Spielstand lässt sich nicht lesen (Rechte oder ein Festplattenfehler). Nichts wird gespeichert, damit er nicht überschrieben wird: Prüfe die Datei und starte die App neu.",
          "Сохранение не читается (права или ошибка диска). Ничего не записывается, чтобы его не затереть: проверьте файл и перезапустите приложение.")
    }
    func saveLockNewerBuild(_ commit: String) -> String {
        t("이 저장 파일은 더 새로운 버전의 앱(\(commit))이 썼어요. 잃지 않도록 아무것도 저장하지 않아요. 앱을 업데이트해 주세요.",
          "This save was written by a newer version of the app (\(commit)). Nothing is written so nothing is lost: update the app.",
          "このセーブはより新しいバージョンのアプリ（\(commit)）が書き込みました。何も失わないよう保存しません。アプリをアップデートしてください。",
          "Esta partida la escribió una versión más reciente de la app (\(commit)). No se escribe nada para no perder nada: actualiza la app.",
          "Cette sauvegarde vient d'une version plus récente de l'app (\(commit)). Rien n'est écrit pour ne rien perdre : mets l'app à jour.",
          "Este salvamento foi gravado por uma versão mais nova do app (\(commit)). Nada é gravado para nada se perder: atualize o app.",
          "Dieser Spielstand stammt von einer neueren App-Version (\(commit)). Nichts wird gespeichert, damit nichts verloren geht: Aktualisiere die App.",
          "Это сохранение записала более новая версия приложения (\(commit)). Ничего не записывается, чтобы ничего не потерять: обновите приложение.")
    }
    /// A purchase or a release that did not go through (the wallet or the Pokémon changed meanwhile).
    var actionFailed: String {
        t("실패했어요. 다시 해 보세요.", "That didn't work. Try again.", "うまくいきませんでした。もう一度お試しください。",
          "No funcionó. Inténtalo de nuevo.", "Ça n'a pas marché, réessaie.", "Não deu certo. Tente de novo.",
          "Das hat nicht geklappt. Versuch es noch einmal.", "Не получилось. Попробуйте ещё раз.")
    }

    // MARK: 세이브 이전 (설정 → 백업 & 이전)
    var transferSectionTitle: String { t("백업 & 이전", "Backup & Transfer", "バックアップと移行", "Copia de seguridad y transferencia", "Sauvegarde et transfert", "Backup e transferência", "Sicherung & Übertragung", "Резервная копия и перенос") }
    var exportSaveLabel: String { t("세이브 내보내기", "Export save", "セーブを書き出す", "Exportar partida", "Exporter la sauvegarde", "Exportar save", "Spielstand exportieren", "Экспорт сохранения") }
    var exportSaveHint: String {
        t("도감·누적 토큰·가방·현재 포켓몬을 파일 하나로 저장해요",
          "Saves your Pokédex, lifetime tokens, Bag, and current Pokémon as one file",
          "図鑑・累計トークン・バッグ・現在のポケモンを1つのファイルに保存します",
          "Guarda tu Pokédex, tokens acumulados, Bolsa y Pokémon actual en un solo archivo",
          "Enregistre ton Pokédex, tes tokens cumulés, ton Sac et ton Pokémon actuel dans un seul fichier",
          "Salva sua Pokédex, tokens acumulados, Bolsa e Pokémon atual em um único arquivo",
          "Speichert deinen Pokédex, alle bisherigen Tokens, deinen Beutel und dein aktuelles Pokémon in einer Datei",
          "Сохраняет Покедекс, токены за всё время, сумку и текущего покемона в один файл")
    }
    var exportSaveButton: String { t("내보내기…", "Export…", "書き出す…", "Exportar…", "Exporter…", "Exportar…", "Exportieren…", "Экспортировать…") }
    var importSaveLabel: String { t("세이브 불러오기", "Import save", "セーブを読み込む", "Importar partida", "Importer une sauvegarde", "Importar save", "Spielstand importieren", "Импорт сохранения") }
    var importSaveHint: String {
        t("다른 Mac에서 내보낸 파일을 골라 이 Mac으로 이어서 키워요",
          "Pick a file exported from another Mac and continue here",
          "他のMacから書き出したファイルを選んでこのMacで続けます",
          "Elige un archivo exportado desde otro Mac y continúa aquí",
          "Choisis un fichier exporté depuis un autre Mac et continue ici",
          "Escolha um arquivo exportado de outro Mac e continue por aqui",
          "Wähle eine auf einem anderen Mac exportierte Datei aus und mach hier weiter",
          "Выберите файл, экспортированный на другом Mac, и продолжайте здесь")
    }
    var importSaveButton: String { t("불러오기…", "Import…", "読み込む…", "Importar…", "Importer…", "Importar…", "Importieren…", "Импортировать…") }
    var importConfirmTitle: String {
        t("이 Mac의 진행을 대체할까요?", "Replace this Mac's progress?", "このMacの進行を置き換えますか？", "¿Reemplazar el progreso de este Mac?", "Remplacer la progression de ce Mac ?", "Substituir o progresso deste Mac?", "Fortschritt auf diesem Mac ersetzen?", "Заменить прогресс на этом Mac?")
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
          """,
          """
          Импортируемое сохранение: Покедекс \(incomingDex) · \(incomingTokens) за всё время
          Экспортировано: \(exportedAt) · \(sourceDevice)
          Сейчас на этом Mac: Покедекс \(currentDex) · \(currentTokens) за всё время

          Текущий прогресс на этом Mac будет заменён. Предыдущее состояние останется резервной копией в папке состояния (последние 5).
          """)
    }
    var importConfirmReplace: String { t("대체", "Replace", "置き換える", "Reemplazar", "Remplacer", "Substituir", "Ersetzen", "Заменить") }
    func importSaveDone(dex: Int, tokens: String) -> String {
        t("불러왔어요. 도감 \(dex)마리 · 누적 \(tokens)",
          "Imported: \(dex) in Pokédex · \(tokens) lifetime",
          "読み込みました。図鑑 \(dex)匹 · 累計 \(tokens)",
          "Importado: Pokédex \(dex) · \(tokens) acumulados",
          "Importé : Pokédex \(dex) · \(tokens) cumulés",
          "Importado: Pokédex \(dex) · \(tokens) acumulados",
          "Importiert: \(dex) im Pokédex · \(tokens) insgesamt",
          "Импортировано: Покедекс \(dex) · \(tokens) за всё время")
    }

    // MARK: 스냅샷 백업 (설정 → 자동 백업)
    var snapshotsSectionTitle: String {
        t("자동 백업 (스냅샷)",
          "Automatic Backups (Snapshots)",
          "自動バックアップ（スナップショット）",
          "Copias automáticas (Instantáneas)",
          "Sauvegardes automatiques (Instantanés)",
          "Backups automáticos (Instantâneos)",
          "Automatische Sicherungen (Snapshots)",
          "Автоматические резервные копии (снимки)")
    }
    var createSnapshotButton: String {
        t("스냅샷 만들기",
          "Create snapshot",
          "スナップショットを作成",
          "Crear instantánea",
          "Créer un instantané",
          "Criar instantâneo",
          "Snapshot erstellen",
          "Создать снимок")
    }
    func snapshotHistoryState(expanded: Bool) -> String {
        expanded
            ? t("펼쳐짐", "Expanded", "展開", "Expandido", "Développé", "Expandido", "Erweitert", "Развёрнуто")
            : t("접힘", "Collapsed", "折りたたみ", "Contraído", "Réduit", "Recolhido", "Eingeklappt", "Свёрнуто")
    }
    var createSnapshotHint: String {
        t("진행 상태의 로컬 복원 지점을 즉시 저장해요 (최근 10개 보존)",
          "Saves an instant local restore point of your progress (keeps up to 10)",
          "現在の進行状況の復元ポイントを即座に保存します（最新10件を保持）",
          "Guarda un punto de restauración local de tu progreso (mantiene hasta 10)",
          "Enregistre un point de restauration local de ta progression (jusqu'à 10 conservés)",
          "Salva um ponto de restauração local do seu progresso (mantém até 10)",
          "Speichert einen lokalen Wiederherstellungspunkt deines Fortschritts (behält bis zu 10)",
          "Мгновенно сохраняет локальную точку восстановления прогресса (хранится до 10)")
    }
    var snapshotCreatedToast: String {
        t("스냅샷이 생성되었습니다",
          "Snapshot created",
          "スナップショットを作成しました",
          "Instantánea creada",
          "Instantané créé",
          "Instantâneo criado",
          "Snapshot erstellt",
          "Снимок создан")
    }
    var restoreSnapshotButton: String {
        t("복원",
          "Restore",
          "復元",
          "Restaurar",
          "Restaurer",
          "Restaurar",
          "Wiederherstellen",
          "Восстановить")
    }
    var restoreConfirmTitle: String {
        t("이 스냅샷으로 복원할까요?",
          "Restore this snapshot?",
          "このスナップショットに復元しますか？",
          "¿Restaurar esta instantánea?",
          "Restaurer cet instantané ?",
          "Restaurar este instantâneo?",
          "Diesen Snapshot wiederherstellen?",
          "Восстановить этот снимок?")
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
          """,
          """
          Выбранный снимок: Покедекс \(snapshotDex) · \(snapshotTokens) за всё время
          Создан: \(snapshotDate)
          Текущее состояние: Покедекс \(currentDex) · \(currentTokens) за всё время

          Перед восстановлением текущее состояние будет сохранено как новый снимок.
          """)
    }
    func restoreDoneMessage(dex: Int, tokens: String) -> String {
        t("복원되었습니다. 도감 \(dex)마리 · 누적 \(tokens)",
          "Restored: \(dex) in Pokédex · \(tokens) lifetime",
          "復元しました。図鑑 \(dex)匹 · 累計 \(tokens)",
          "Restaurado: Pokédex \(dex) · \(tokens) acumulados",
          "Restauré : Pokédex \(dex) · \(tokens) cumulés",
          "Restaurado: Pokédex \(dex) · \(tokens) acumulados",
          "Wiederhergestellt: \(dex) im Pokédex · \(tokens) insgesamt",
          "Восстановлено: Покедекс \(dex) · \(tokens) за всё время")
    }
    var noSnapshotsYet: String {
        t("아직 저장된 스냅샷이 없습니다",
          "No snapshots saved yet",
          "保存されたスナップショットはまだありません",
          "Aún no hay instantáneas guardadas",
          "Aucun instantané enregistré pour l'instant",
          "Nenhum instantâneo salvo ainda",
          "Noch keine Snapshots gespeichert",
          "Снимков пока нет")
    }
    func snapshotDexAndTokens(dex: Int, tokens: String) -> String {
        t("도감 \(dex)마리 · 누적 \(tokens)",
          "Pokédex \(dex) · \(tokens) lifetime",
          "図鑑 \(dex)匹 · 累計 \(tokens)",
          "Pokédex \(dex) · \(tokens) acumulados",
          "Pokédex \(dex) · \(tokens) cumulés",
          "Pokédex \(dex) · \(tokens) acumulados",
          "Pokédex \(dex) · \(tokens) insgesamt",
          "Покедекс \(dex) · \(tokens) за всё время")
    }
    var importErrorNotSaveFile: String {
        t("PokeTokenBar 세이브 파일이 아니에요.",
          "That isn't a PokeTokenBar save file.",
          "PokeTokenBar のセーブファイルではありません。",
          "Ese no es un archivo de partida de PokeTokenBar.",
          "Ce n'est pas un fichier de sauvegarde PokeTokenBar.",
          "Esse não é um arquivo de save do PokeTokenBar.",
          "Das ist keine PokeTokenBar-Spielstandsdatei.",
          "Это не файл сохранения PokeTokenBar.")
    }
    var importErrorNewerSchema: String {
        t("더 새로운 버전에서 만든 세이브예요. 앱을 업데이트한 뒤 다시 시도해 주세요.",
          "This save was made by a newer version. Update the app and try again.",
          "より新しいバージョンで作成されたセーブです。アプリを更新してから再試行してください。",
          "Esta partida se creó con una versión más reciente. Actualiza la app e inténtalo de nuevo.",
          "Cette sauvegarde a été créée par une version plus récente. Mets l'app à jour et réessaie.",
          "Esse save foi criado por uma versão mais recente. Atualize o app e tente de novo.",
          "Dieser Spielstand wurde mit einer neueren Version erstellt. Aktualisiere die App und versuche es erneut.",
          "Сохранение создано более новой версией. Обновите приложение и попробуйте снова.")
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
        case SaveTransferError.saveLocked:    return importErrorSaveLocked
        default: return userFacingError(error)
        }
    }
    /// The save is locked (`CompanionStore.SaveLock`): the banner above the tabs says why.
    var importErrorSaveLocked: String {
        t("저장 파일이 잠겨 있어 스냅샷을 포함해 아무것도 쓰지 않아요. 이유는 탭 위의 안내에 있어요.",
          "Your save is locked, so nothing is written, snapshots included. The message above the tabs says why.",
          "セーブがロックされているため、スナップショットも含めて何も書き込みません。理由はタブの上の案内にあります。",
          "Tu partida está bloqueada, así que no se escribe nada, ni siquiera las instantáneas. El mensaje sobre las pestañas explica por qué.",
          "Ta sauvegarde est verrouillée : rien n'est écrit, instantanés compris. Le message au-dessus des onglets dit pourquoi.",
          "Seu salvamento está bloqueado, então nada é gravado, nem os instantâneos. A mensagem acima das abas diz por quê.",
          "Dein Spielstand ist gesperrt, daher wird nichts gespeichert, auch keine Snapshots. Die Meldung über den Tabs sagt, warum.",
          "Сохранение заблокировано, поэтому ничего не записывается, даже снимки. Причина указана в сообщении над вкладками.")
    }
    var importErrorTooLarge: String {
        t("세이브 파일이라기엔 너무 커요. 다른 파일을 고른 것 같아요.",
          "That file is too large to be a save. It looks like the wrong file.",
          "セーブファイルにしては大きすぎます。別のファイルを選んだようです。",
          "Ese archivo es demasiado grande para ser una partida. Parece que elegiste el archivo equivocado.",
          "Ce fichier est trop volumineux pour être une sauvegarde. Ce n'est sans doute pas le bon fichier.",
          "Esse arquivo é grande demais para ser um save. Parece que você escolheu o arquivo errado.",
          "Diese Datei ist zu groß für einen Spielstand. Wahrscheinlich hast du die falsche Datei ausgewählt.",
          "Файл слишком большой для сохранения. Похоже, выбран не тот файл.")
    }
    /// 백업을 못 남기면 불러오기를 중단한다 — 되돌릴 수단 없이 진행을 대체하지 않기 위해서다.
    var importErrorBackupFailed: String {
        t("현재 상태를 백업하지 못해 불러오기를 중단했어요. 진행은 그대로예요. 디스크 여유 공간을 확인해 주세요.",
          "Import stopped because the current state couldn't be backed up. Your progress is untouched. Check free disk space.",
          "現在の状態をバックアップできなかったため読み込みを中止しました。進行はそのままです。ディスクの空き容量を確認してください。",
          "Se detuvo la importación porque no se pudo hacer una copia de seguridad del estado actual. Tu progreso no se ha tocado. Comprueba el espacio libre en disco.",
          "Import interrompu car l'état actuel n'a pas pu être sauvegardé. Ta progression est intacte. Vérifie l'espace disque disponible.",
          "A importação foi interrompida porque não deu para fazer backup do estado atual. Seu progresso está intacto. Verifique o espaço livre em disco.",
          "Der Import wurde abgebrochen, weil der aktuelle Stand nicht gesichert werden konnte. Dein Fortschritt ist unverändert. Prüfe den freien Speicherplatz.",
          "Импорт остановлен: не удалось сделать резервную копию текущего состояния. Прогресс не изменён. Проверьте свободное место на диске.")
    }

    // MARK: 문제점 알리기 (설정 → 메일 리포트)
    var reportProblem: String { t("문제점 알리기", "Report a problem", "問題を報告", "Reportar un problema", "Signaler un problème", "Relatar um problema", "Problem melden", "Сообщить о сбое") }
    var showLogFile: String { t("로그 파일 보기", "Show log file", "ログファイルを表示", "Mostrar archivo de registro", "Afficher le fichier journal", "Mostrar arquivo de log", "Protokolldatei anzeigen", "Показать файл журнала") }
    var reportAttachHint: String {
        t("메일에 로그 파일을 첨부해 주시면 원인 파악에 큰 도움이 돼요.",
          "Attaching the log file to the email helps a lot with diagnosis.",
          "メールにログファイルを添付していただくと原因の特定に役立ちます。",
          "Adjuntar el archivo de registro al correo ayuda mucho a diagnosticar el problema.",
          "Joindre le fichier journal au mail aide beaucoup au diagnostic.",
          "Anexar o arquivo de log ao e-mail ajuda muito no diagnóstico.",
          "Wenn du die Protokolldatei an die E-Mail anhängst, hilft das sehr bei der Fehlersuche.",
          "Файл журнала, приложенный к письму, очень помогает в диагностике.")
    }
    func reportMailFallback(_ address: String) -> String {
        t("메일 앱을 열 수 없어요. \(address) 로 직접 보내주세요.",
          "Couldn't open a mail app. Please email \(address) directly.",
          "メールアプリを開けません。\(address) 宛に直接お送りください。",
          "No se pudo abrir una app de correo. Escribe directamente a \(address).",
          "Impossible d'ouvrir une app de messagerie. Écris directement à \(address).",
          "Não foi possível abrir um app de e-mail. Escreva diretamente para \(address).",
          "Es konnte keine Mail-App geöffnet werden. Schreib bitte direkt an \(address).",
          "Не удалось открыть почтовое приложение. Напишите напрямую на \(address).")
    }
    func reportMailSubject(_ version: String) -> String {
        t("[PokeTokenBar] 문제 리포트 (v\(version))",
          "[PokeTokenBar] Problem report (v\(version))",
          "[PokeTokenBar] 問題レポート (v\(version))",
          "[PokeTokenBar] Reporte de problema (v\(version))",
          "[PokeTokenBar] Rapport de problème (v\(version))",
          "[PokeTokenBar] Relato de problema (v\(version))",
          "[PokeTokenBar] Problembericht (v\(version))",
          "[PokeTokenBar] Сообщение о проблеме (v\(version))")
    }
    func reportMailBody(version: String, os: String) -> String {
        t("""
        문제 내용:
        (겪으신 문제를 적어주세요: 언제, 어떤 화면에서, 어떻게 되었는지)


        ---
        앱 버전: v\(version)
        macOS: \(os)
        로그 파일(첨부 권장): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        What happened:
        (Describe the problem: when, on which screen, and what you saw)


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
        (Describe lo que ocurrió: cuándo, en qué pantalla y qué viste)


        ---
        Versión de la app: v\(version)
        macOS: \(os)
        Archivo de registro (se recomienda adjuntar): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Ce qui s'est passé :
        (Décris le problème : quand, sur quel écran, et ce que tu as vu)


        ---
        Version de l'app : v\(version)
        macOS: \(os)
        Fichier journal (à joindre de préférence) : ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Descrição do problema:
        (Descreva o que aconteceu: quando, em qual tela e o que você viu)


        ---
        Versão do app: v\(version)
        macOS: \(os)
        Arquivo de log (anexe, por favor): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Was ist passiert:
        (Beschreibe das Problem: wann, auf welchem Bildschirm und was du gesehen hast)


        ---
        App-Version: v\(version)
        macOS: \(os)
        Protokolldatei (bitte anhängen): ~/Library/Logs/PokeTokenBar.log
        """,
        """
        Что произошло:
        (Опишите проблему: когда, на каком экране и что вы увидели)


        ---
        Версия приложения: v\(version)
        macOS: \(os)
        Файл журнала (приложите, пожалуйста): ~/Library/Logs/PokeTokenBar.log
        """)
    }

    /// 새로고침 간격 라벨 (초 단위 값 → 표시). 0 = 수동.
    func intervalLabel(_ seconds: TimeInterval) -> String {
        if seconds == 0 { return t("수동", "Manual", "手動", "Manual", "Manuel", "Manual", "Manuell", "Вручную") }
        let m = Int(seconds / 60)
        return t("\(m)분", "\(m) min", "\(m)分", "\(m) min", "\(m) min", "\(m) min", "\(m) Min.", "\(m) мин")
    }

    // MARK: 컴패니언
    var finalForm: String { t("최종 진화체", "Final form", "最終進化", "Forma final", "Forme finale", "Forma final", "Letzte Entwicklungsstufe", "Финальная форма") }
    func stage(_ i: Int, _ k: Int) -> String { t("진화 단계 \(i) / \(k)", "Stage \(i) / \(k)", "進化段階 \(i) / \(k)", "Etapa \(i) / \(k)", "Stade \(i) / \(k)", "Estágio \(i) / \(k)", "Entwicklungsstufe \(i) / \(k)", "Стадия \(i) / \(k)") }
    var unknownNextEvolution: String { t("알 수 없는 다음 진화", "Unknown next evolution", "次の進化先は不明", "Próxima evolución desconocida", "Prochaine évolution inconnue", "Próxima evolução desconhecida", "Nächste Entwicklung unbekannt", "Следующая эволюция неизвестна") }
    var eggIncubating: String { t("🥚 부화 준비 중", "🥚 Incubating", "🥚 孵化の準備中", "🥚 Incubando", "🥚 En incubation", "🥚 Incubando", "🥚 Wird ausgebrütet", "🥚 Инкубация") }
    func eggToHatch(_ amount: String) -> String { t("부화까지 \(amount)", "\(amount) to hatch", "孵化まで \(amount)", "\(amount) para eclosionar", "\(amount) avant l'éclosion", "\(amount) para chocar", "\(amount) bis zum Schlüpfen", "Ещё \(amount) до вылупления") }
    /// 알 부화 임계 도달 후 외부 데이터 요청이 실패한 동안의 다음 새로고침 안내.
    var eggHatchDelayed: String {
        t("⏳ 부화가 지연되고 있어요. 다음 새로고침에서 다시 시도해요",
          "⏳ Hatching is delayed; retrying on the next refresh",
          "⏳ 孵化が遅れています。次回の更新時に再試行します",
          "⏳ La eclosión se retrasa; se reintentará en la próxima actualización",
          "⏳ L’éclosion est retardée : nouvel essai au prochain rafraîchissement",
          "⏳ A eclosão está atrasada; nova tentativa na próxima atualização",
          "⏳ Das Schlüpfen verzögert sich: neuer Versuch bei der nächsten Aktualisierung",
          "⏳ Вылупление задерживается, повторим при следующем обновлении")
    }
    func toNextEvolution(_ amount: String) -> String { t("다음 진화까지 \(amount)", "\(amount) to next evolution", "次の進化まで \(amount)", "\(amount) para la siguiente evolución", "\(amount) avant la prochaine évolution", "\(amount) para a próxima evolução", "\(amount) bis zur nächsten Entwicklung", "Ещё \(amount) до следующей эволюции") }
    /// Tokens left before the next stage, named: "95M to Charmeleon".
    func toStage(_ amount: String, _ name: String) -> String { t("\(name)까지 \(amount)", "\(amount) to \(name)", "\(name)まで \(amount)", "\(amount) para \(name)", "\(amount) avant \(name)", "\(amount) para \(name)", "\(amount) bis \(name)", "Ещё \(amount) до \(name)") }
    func toGraduation(_ amount: String) -> String { t("졸업까지 \(amount)", "\(amount) to graduation", "卒業まで \(amount)", "\(amount) para graduarse", "\(amount) avant le diplôme", "\(amount) para se formar", "\(amount) bis zum Abschied", "Ещё \(amount) до выпуска") }
    /// A growth multiplier with at most two decimals, in the language's number format ("1.05", "3,6").
    func multiplierNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...2)).locale(lang.displayLocale))
    }
    func growthBoost(_ multiplier: Double) -> String {
        let m = multiplierNumber(multiplier)
        return t("\(m)× 성장", "\(m)× growth", "成長 \(m)倍", "Crecimiento ×\(m)", "Croissance ×\(m)", "Crescimento ×\(m)", "\(m)× Wachstum", "Рост ×\(m)")
    }
    /// The Home growth badge of a repeat: the word says why it is orange ("Repeat · 5.25× growth").
    func repeatGrowthBoost(_ multiplier: Double, rank: Int? = nil) -> String {
        let word = t("중복", "Repeat", "ダブり", "Repetido", "Doublon", "Repetido", "Wiederholung", "Повтор")
        // "Repeat ×8": the eighth of its species.
        let counted = rank.map { $0 > 1 ? "\(word) \(catchCount($0))" : word } ?? word
        return "\(counted) · \(growthBoost(multiplier))"
    }
    var bonusTitle: String { t("보너스", "Bonuses", "ボーナス", "Bonificaciones", "Bonus", "Bônus", "Boni", "Бонусы") }
    var bonusOpen: String {
        t("모든 보너스 보기", "See all bonuses", "すべてのボーナスを見る", "Ver todas las bonificaciones",
          "Voir tous les bonus", "Ver todos os bônus", "Alle Boni anzeigen", "Все бонусы")
    }
    var bonusCurrent: String {
        t("지금 포켓몬의 성장", "Current Pokémon's growth", "いまのポケモンの成長", "Crecimiento del Pokémon actual",
          "Croissance du Pokémon actuel", "Crescimento do Pokémon atual", "Wachstum des aktuellen Pokémon", "Рост текущего покемона")
    }
    var bonusRepeat: String {
        t("이미 졸업한 계열", "Line already graduated", "卒業済みの系統", "Línea ya graduada",
          "Lignée déjà diplômée", "Linha já formada", "Linie schon abgeschlossen", "Линия уже выпущена")
    }
    /// Under the growth factors: the bonuses add up, and the repeat boost multiplies the result.
    func bonusSumNote(_ percent: String, repeatMultiplier m: String?) -> String {
        let sum = t("보너스는 더해져요: +\(percent)%.", "Bonuses add up: +\(percent)%.", "ボーナスは足し算です: +\(percent)%。",
                    "Las bonificaciones se suman: +\(percent)%.", "Les bonus s'additionnent : +\(percent)%.",
                    "Os bônus se somam: +\(percent)%.", "Boni addieren sich: +\(percent)%.", "Бонусы складываются: +\(percent)%.")
        guard let m else { return sum }
        return sum + t(" 이미 졸업한 계열이라 전체가 \(m)배가 돼요.", " The line already graduated then multiplies it all by \(m).",
                       "卒業済みの系統なので全体が\(m)倍になります。", " La línea ya graduada lo multiplica todo por \(m).",
                       " La lignée déjà diplômée multiplie ensuite le tout par \(m).", " A linha já formada multiplica tudo por \(m).",
                       " Die schon abgeschlossene Linie multipliziert dann alles mit \(m).", " Уже выпущенная линия затем умножает всё на \(m).")
    }
    var bonusNoGrowth: String {
        t("이 포켓몬에 적용되는 성장 보너스가 없어요.", "No growth bonus applies to this Pokémon.",
          "このポケモンにかかる成長ボーナスはありません。", "Ninguna bonificación de crecimiento se aplica a este Pokémon.",
          "Aucun bonus de croissance ne s'applique à ce Pokémon.", "Nenhum bônus de crescimento se aplica a este Pokémon.",
          "Für dieses Pokémon gilt kein Wachstumsbonus.", "К этому покемону не применяется бонус роста.")
    }
    var bonusNoneYet: String {
        t("아직 보너스가 없어요. 업적을 받아 보세요.", "No bonus yet: claim achievements to get some.",
          "まだボーナスはありません。実績を受け取りましょう。", "Todavía no tienes bonificaciones: reclama logros para conseguirlas.",
          "Aucun bonus pour l'instant : récupère des succès pour en obtenir.", "Ainda sem bônus: resgate conquistas para obtê-los.",
          "Noch keine Boni: hol dir Erfolge, um welche zu bekommen.", "Бонусов пока нет: получайте достижения.")
    }
    func bonusThemeTitle(_ theme: BonusTheme) -> String {
        switch theme {
        case .growth: return t("성장", "Growth", "成長", "Crecimiento", "Croissance", "Crescimento", "Wachstum", "Рост")
        case .eggs: return t("알", "Eggs", "タマゴ", "Huevos", "Œufs", "Ovos", "Eier", "Яйца")
        case .shiny: return t("이로치", "Shiny", "色違い", "Variocolor", "Chromatiques", "Shiny", "Schillernd", "Шайни")
        case .shop: return shop
        case .candies: return t("사탕", "Candies", "アメ", "Caramelos", "Bonbons", "Doces", "Bonbons", "Конфеты")
        }
    }
    func eggThresholdSummary(_ current: String, instead base: String) -> String {
        t("부화: \(base) 대신 \(current)", "Hatching: \(current) instead of \(base)", "孵化: \(base)ではなく\(current)",
          "Eclosión: \(current) en vez de \(base)", "Éclosion : \(current) au lieu de \(base)", "Eclosão: \(current) em vez de \(base)",
          "Schlüpfen: \(current) statt \(base)", "Вылупление: \(current) вместо \(base)")
    }
    func shinyOddsSummary(_ denominator: Int) -> String {
        t("이로치: 1/\(denominator)", "Shiny: 1 in \(denominator)", "色違い: 1/\(denominator)", "Variocolor: 1 de \(denominator)",
          "Chromatique : 1 sur \(denominator)", "Shiny: 1 em \(denominator)", "Schillernd: 1 zu \(denominator)",
          "Шайни: 1 из \(denominator)")
    }
    func graduated(_ name: String) -> String {
        t("\(name) 졸업 → 도감에 보존. 새 알이 도착했어요!",
          "\(name) graduated → saved to the dex. A new egg has arrived!",
          "\(name) 卒業 → 図鑑に保存。新しいタマゴが届きました！",
          "\(name) se graduó → guardado en la Pokédex. ¡Ha llegado un nuevo huevo!",
          "\(name) a été diplômé → conservé dans le Pokédex. Un nouvel œuf est arrivé !",
          "\(name) se formou → guardado na Pokédex. Chegou um novo ovo!",
          "\(name) verabschiedet sich → im Pokédex gespeichert. Ein neues Ei ist da!",
          "\(name) выпускается → запись в Покедексе. Появилось новое яйцо!")
    }
    var dexEmptyTitle: String { t("아직 잡은 포켓몬이 없어요!", "No Pokémon caught yet!", "まだ捕まえたポケモンがいません！", "¡Todavía no has capturado ningún Pokémon!", "Aucun Pokémon capturé pour l'instant !", "Você ainda não capturou nenhum Pokémon!", "Du hast noch kein Pokémon gefangen!", "Пока ни одного покемона!") }
    var dexEmptyHint: String { t("토큰을 써서 첫 포켓몬을 부화시켜 보세요.", "Spend tokens to hatch your first Pokémon.", "トークンを使って最初のポケモンを孵化させましょう。", "Usa tokens para eclosionar tu primer Pokémon.", "Dépense des tokens pour faire éclore ton premier Pokémon.", "Use tokens para chocar seu primeiro Pokémon.", "Verwende Tokens, damit dein erstes Pokémon schlüpft.", "Тратьте токены, чтобы вывести первого покемона.") }

    // MARK: 도감 요약 헤더
    var dexTitle: String { t("도감", "Pokédex", "図鑑", "Pokédex", "Pokédex", "Pokédex", "Pokédex", "Покедекс") }
    func dexTotal(_ n: Int) -> String { t("총 \(n)마리", "\(n) total", "全\(n)匹", "\(n) en total", "\(n) au total", "\(n) no total", "\(n) insgesamt", "Всего: \(n)") }
    /// 포획 로그 = 개체 단위 기록(같은 라인 중복이 정상). 도감 = 종 단위 집계.
    var catchLogTitle: String { t("포획 로그", "Catch log", "捕獲ログ", "Registro de capturas", "Journal de captures", "Registro de capturas", "Fangprotokoll", "Журнал поимок") }
    /// 도감 총계는 개체가 아니라 종 수 — 로그의 dexTotal("총 N마리")과 단위가 다르다.
    /// Species in the Pokédex out of every species that can hatch, above the grid next to `formsCollected`.
    /// Evolution lines in the Pokédex, out of all of them (`CompanionStore.CollectionProgress.lines`).
    func dexLinesProgress(_ count: Int, of total: Int) -> String {
        t("계열 \(count)/\(total)", "Lines \(count)/\(total)", "系統 \(count)/\(total)", "Líneas \(count)/\(total)",
          "Lignées \(count)/\(total)", "Linhas \(count)/\(total)", "Linien \(count)/\(total)", "Линии: \(count)/\(total)")
    }
    var dexLinesHint: String {
        t("진화 계열: 한 마리라도 졸업한 계열이에요(피츄, 피카츄, 라이츄는 한 계열).",
          "Evolution lines with a Pokémon graduated (Pichu, Pikachu and Raichu are one line).",
          "1匹でも卒業した進化の系統です（ピチュー、ピカチュウ、ライチュウで1系統）。",
          "Líneas evolutivas con algún Pokémon graduado (Pichu, Pikachu y Raichu son una línea).",
          "Les lignées d'évolution dont un Pokémon est diplômé (Pichu, Pikachu et Raichu font une lignée).",
          "Linhas evolutivas com algum Pokémon formado (Pichu, Pikachu e Raichu são uma linha).",
          "Entwicklungslinien mit einem verabschiedeten Pokémon (Pichu, Pikachu und Raichu sind eine Linie).",
          "Эволюционные линии, где выпущен хотя бы один покемон (Пичу, Пикачу и Райчу: одна линия).")
    }
    func dexSpeciesProgress(_ count: Int, of total: Int) -> String {
        t("종 \(count)/\(total)", "Species \(count)/\(total)", "種 \(count)/\(total)", "Especies \(count)/\(total)",
          "Espèces \(count)/\(total)", "Espécies \(count)/\(total)", "Spezies \(count)/\(total)", "Виды: \(count)/\(total)")
    }
    func formsCollected(_ count: Int, of total: Int) -> String {
        t("폼 \(count)/\(total)", "Forms \(count)/\(total)", "フォルム \(count)/\(total)",
          "Formas \(count)/\(total)", "Formes \(count)/\(total)", "Formas \(count)/\(total)",
          "Formen \(count)/\(total)",
          "Формы: \(count)/\(total)")
    }
    var chooseForm: String {
        t("폼 선택", "Choose form", "フォルムを選択", "Elegir forma", "Choisir une forme", "Escolher forma", "Form auswählen", "Выбрать форму")
    }
    /// Usual look of a species whose official data names no form (Castform, Rotom, Kyurem, Genesect).
    // Form names PokéAPI lacks or gets wrong (`PokemonForm.appName`).
    var formHoopaConfined: String { t("굴레에 빠진 모습", "Confined", "いましめられし", "Contenido", "Enchaîné", "Contido", "Gebannt", "Скованный") }
    var formHoopaUnbound: String { t("굴레를 벗어난 모습", "Unbound", "ときはなたれし", "Desatado", "Déchaîné", "Liberto", "Entfesselt", "Освобождённый") }
    var formPartner: String { t("파트너", "Partner", "パートナー", "Compañero", "Partenaire", "Parceiro", "Partner", "Партнёр") }
    var formFamilyOfFour: String { t("네 식구", "Family of Four", "４ひきかぞく", "Familia de cuatro", "Famille de Quatre", "Família de quatro", "Viererfamilie", "Семья из четырёх") }
    var formFamilyOfThree: String { t("세 식구", "Family of Three", "３びきかぞく", "Familia de tres", "Famille de Trois", "Família de três", "Dreierfamilie", "Семья из трёх") }
    var formTaurosCombatBreed: String { t("컴뱃종", "Combat Breed", "コンバット種", "Raza Combatiente", "Race Combative", "Raça Combatente", "Gefechtsrasse", "Боевая порода") }
    var formTaurosBlazeBreed: String { t("블레이즈종", "Blaze Breed", "ブレイズ種", "Raza Ardiente", "Race Flamboyante", "Raça Chamejante", "Flammenrasse", "Огненная порода") }
    var formTaurosAquaBreed: String { t("워터종", "Aqua Breed", "ウォーター種", "Raza Acuática", "Race Aquatique", "Raça Aquática", "Flutenrasse", "Водная порода") }

    var normalForm: String {
        t("노말폼", "Normal Form", "ノーマルフォルム", "Forma Normal", "Forme Normale", "Forma Normal", "Normalform", "Обычная форма")
    }
    /// Title of the short message that shows forms just unlocked (Arceus's Plates).
    func formUnlockTitle(count: Int) -> String {
        count == 1
            ? t("새 폼 해금", "New form unlocked", "新しいフォルムを解放", "Nueva forma desbloqueada",
                "Nouvelle forme débloquée", "Nova forma desbloqueada", "Neue Form freigeschaltet", "Новая форма открыта")
            : t("새 폼 \(count)개 해금", "\(count) new forms unlocked", "新しいフォルムを\(count)個解放",
                "\(count) formas nuevas desbloqueadas", "\(count) nouvelles formes débloquées",
                "\(count) novas formas desbloqueadas", "\(count) neue Formen freigeschaltet", "Открыто новых форм: \(count)")
    }
    /// One line above Arceus's forms: where they come from.
    var plateFormsHint: String {
        t("타입별 배지마다 폼이 하나씩 해금돼요.", "Each type's gym badge unlocks a form.",
          "タイプごとのバッジでフォルムが1つ解放されます。", "Cada medalla de tipo desbloquea una forma.",
          "Chaque badge de type débloque une forme.", "Cada insígnia de tipo desbloqueia uma forma.",
          "Jeder Typ-Orden schaltet eine Form frei.", "Каждый значок типа открывает форму.")
    }
    var formNotCollected: String {
        t("미수집", "Not collected", "未収集", "Sin conseguir", "Non collectionnée", "Não coletada", "Noch nicht gesammelt", "Не собрано")
    }
    func dexPageLabel(_ page: Int, _ total: Int) -> String {
        t("\(total)페이지 중 \(page)페이지", "Page \(page) of \(total)", "\(total)ページ中 \(page)ページ", "Página \(page) de \(total)", "Page \(page) sur \(total)", "Página \(page) de \(total)", "Seite \(page) von \(total)", "Страница \(page) из \(total)")
    }
    var dexPagePrev: String { t("이전 페이지", "Previous page", "前のページ", "Página anterior", "Page précédente", "Página anterior", "Vorherige Seite", "Предыдущая страница") }
    var dexPageNext: String { t("다음 페이지", "Next page", "次のページ", "Página siguiente", "Page suivante", "Próxima página", "Nächste Seite", "Следующая страница") }
    /// Pokédex: species seen (raised, or released) but never graduated, beside the graduated count.
    func dexSeenOnly(_ count: Int) -> String {
        t("본 종 \(count)", "\(count) seen", "見ただけ \(count)", "\(count) vistas", "\(count) vues", "\(count) vistas",
          "\(count) gesehen", "увидено: \(count)")
    }
    /// A Pokédex cell's tooltip for a species seen but never graduated: it counts for no achievement yet.
    var dexSeenNotGraduated: String {
        t("본 적만 있음 · 아직 졸업 전", "Seen, not graduated yet", "見ただけ · まだ卒業していない", "Vista, aún sin graduar",
          "Vue, pas encore diplômée", "Vista, ainda não formada", "Gesehen, noch nicht verabschiedet", "Встречен, ещё не выпущен")
    }
    var dexRaising: String { t("키우는 중", "Raising", "育成中", "Criando", "En élevage", "Treinando", "In Aufzucht", "Растёт") }
    /// 포획 로그에서 졸업분과 놓아준 개체를 가르는 표식. 종은 도감에 남고 개체 기록만 이 뱃지를 단다.
    var dexReleased: String { t("놓아줌", "Released", "逃がした", "Liberado", "Relâché", "Solto", "Freigelassen", "Отпущен") }
    /// 포획 로그에서 이전에 이미 잡았던 진화 라인(또는 안농 폼)의 중복 포획 개체임을 나타내는 뱃지.
    var dexDuplicate: String { t("중복", "Duplicate", "重複", "Duplicado", "Doublon", "Duplicado", "Duplikat", "Дубликат") }
    /// Home: the current Pokémon brings nothing new through its whole line (`CompanionStore.activeNews`).
    var activeDuplicateBadge: String {
        t("100% 중복", "100% duplicate", "100%ダブり", "100 % repetido", "100 % doublon", "100% repetido", "100 % doppelt",
          "100% дубликат")
    }
    var activeDuplicateHint: String {
        t("새로운 게 없어요. 종, 폼, 이로치, 코스튬이 이미 도감에 있어 놓아줘도 잃는 게 없어요.",
          "Nothing new: its species, forms, shiny and costumes are already in your Pokédex, so sending it off loses nothing.",
          "新しいものはありません。種、フォルム、色違い、コスチュームはすでに図鑑にあり、手放しても失うものはありません。",
          "Nada nuevo: sus especies, formas, variocolor y disfraces ya están en tu Pokédex, así que soltarlo no te hace perder nada.",
          "Rien de nouveau : ses espèces, formes, chromatique et costumes sont déjà dans ton Pokédex, le laisser partir ne fait rien perdre.",
          "Nada novo: suas espécies, formas, brilhante e fantasias já estão na sua Pokédex, então soltá-lo não faz perder nada.",
          "Nichts Neues: Seine Arten, Formen, Schillernde und Kostüme sind schon in deinem Pokédex, es abzugeben kostet nichts.",
          "Ничего нового: его виды, формы, сияющий вариант и костюмы уже в покедексе, отпустив его, вы ничего не потеряете.")
    }
    var activeNewBadge: String { t("신규", "New", "新規", "Nuevo", "Nouveau", "Novo", "Neu", "Новое") }
    var formMysteryBadge: String {
        t("미스터리 폼", "Mystery form", "謎のフォルム", "Forma misteriosa", "Forme mystère", "Forma misteriosa", "Geheime Form", "Тайная форма")
    }
    /// The real odds a form still hidden brings something new (`FormMystery`).
    func formMysteryOdds(_ mystery: FormMystery) -> String {
        guard !mystery.isCertain else {
            return t("어떤 폼이든 새로운 것을 가져와요", "Something new whatever its form", "どのフォルムでも新しいものをもたらします",
                     "Algo nuevo sea cual sea su forma", "Du nouveau quelle que soit sa forme", "Algo novo qualquer que seja a forma",
                     "Etwas Neues, egal in welcher Form", "Что-то новое при любой форме")
        }
        let c = mystery.chances, n = mystery.outOf
        let ru = c % 10 == 1 && c % 100 != 11 ? "шанс" : (2...4).contains(c % 10) && !(12...14).contains(c % 100) ? "шанса" : "шансов"
        return t("\(n)번 중 \(c)번은 새로운 것을 가져와요", "\(c) \(c == 1 ? "chance" : "chances") in \(n) of bringing something new",
                 "\(n)分の\(c)の確率で新しいものをもたらします", "\(c) \(c == 1 ? "posibilidad" : "posibilidades") de \(n) de traer algo nuevo",
                 "\(c) \(c == 1 ? "chance" : "chances") sur \(n) d'apporter du nouveau", "\(c) \(c == 1 ? "chance" : "chances") em \(n) de trazer algo novo",
                 "\(c) von \(n) Chancen auf etwas Neues", "\(c) \(ru) из \(n) принести что-то новое")
    }
    /// The hint of the Mystery form badge: `reveal` is the stage that shows the form.
    func formMysteryHint(_ reveal: String, _ mystery: FormMystery) -> String {
        let odds = formMysteryOdds(mystery)
        return t("\(KoreanParticle.direction.attach(to: reveal)) 진화하면 폼이 드러나요. \(odds).", "It shows when it becomes \(reveal). \(odds).",
                 "\(reveal)に進化するとフォルムが明らかになります。\(odds)。", "Se revela cuando se convierte en \(reveal). \(odds).",
                 "Elle se révèle quand il devient \(reveal). \(odds).", "Ela se revela quando ele vira \(reveal). \(odds).",
                 "Sie zeigt sich, wenn es zu \(reveal) wird. \(odds).", "Форма откроется, когда он станет \(reveal). \(odds).")
    }
    /// After the evolution's message, at the stage that shows a form that was a mystery.
    var formRevealBringsNew: String {
        t("이 폼은 새로운 것을 가져와요!", "Its form brings something new!", "このフォルムは新しいものをもたらします！", "¡Su forma trae algo nuevo!",
          "Sa forme apporte du nouveau !", "A forma dele traz algo novo!", "Seine Form bringt etwas Neues!", "Эта форма приносит что-то новое!")
    }
    var formRevealNothingNew: String {
        t("이 폼은 이미 도감에 있어요.", "Its form is already in your Pokédex.", "このフォルムはすでに図鑑にあります。", "Su forma ya está en tu Pokédex.",
          "Sa forme est déjà dans ton Pokédex.", "A forma dele já está na sua Pokédex.", "Seine Form ist schon in deinem Pokédex.", "Эта форма уже есть в покедексе.")
    }
    /// What graduating the current Pokémon adds, for the hint of its New badge.
    func activeNewHint(_ names: [String], certain: Bool) -> String {
        let list = names.joined(separator: ", ")
        guard certain else {
            return t("졸업하면 진화에 따라 도감에 추가될 수 있어요: \(list)", "Graduating it can add to your Pokédex, depending on how it evolves: \(list)",
                     "卒業すると、進化によっては図鑑に加わります：\(list)", "Al graduarse puede añadir a tu Pokédex, según cómo evolucione: \(list)",
                     "Diplômé, il peut ajouter à ton Pokédex, selon son évolution : \(list)", "Ao se formar, pode adicionar à sua Pokédex, conforme a evolução: \(list)",
                     "Mit seinem Abschied kann, je nach Entwicklung, in deinen Pokédex kommen: \(list)", "После выпуска в Покедекс может добавиться, в зависимости от эволюции: \(list)")
        }
        return t("졸업하면 도감에 추가돼요: \(list)", "Graduating it adds to your Pokédex: \(list)",
                 "卒業すると図鑑に加わります：\(list)", "Al graduarse añade a tu Pokédex: \(list)",
                 "Diplômé, il ajoutera à ton Pokédex : \(list)", "Ao se formar, adiciona à sua Pokédex: \(list)",
                 "Mit seinem Abschied kommt in deinen Pokédex: \(list)", "После выпуска в Покедекс добавится: \(list)")
    }
    var activeCostumeHint: String {
        t("피카츄로 진화하면 아직 없는 코스튬을 가져와요.", "Becoming Pikachu, it brings a costume you don't have yet.",
          "ピカチュウに進化すると、まだ持っていないコスチュームを持ってきます。",
          "Al convertirse en Pikachu, trae un disfraz que aún no tienes.",
          "En devenant Pikachu, il apporte un costume que tu n'as pas encore.",
          "Ao virar Pikachu, ele traz uma fantasia que você ainda não tem.",
          "Wird es zu Pikachu, bringt es ein Kostüm mit, das du noch nicht hast.",
          "Став Пикачу, он принесёт костюм, которого у вас ещё нет.")
    }
    var activeFirstShiny: String {
        t("첫 이로치", "its first shiny", "初めての色違い", "su primer variocolor", "son premier chromatique",
          "seu primeiro shiny", "sein erstes schillerndes", "первый шайни")
    }
    var rarityCommon: String { t("일반", "Common", "ノーマル", "Común", "Commun", "Comum", "Gewöhnlich", "Обычный") }
    var rarityUncommon: String { t("고급", "Uncommon", "アンコモン", "Poco común", "Peu commun", "Incomum", "Ungewöhnlich", "Необычный") }
    var rarityRare: String { t("희귀", "Rare", "レア", "Raro", "Rare", "Raro", "Selten", "Редкий") }
    var rarityLegendary: String { t("전설", "Legendary", "伝説", "Legendario", "Légendaire", "Lendário", "Legendär", "Легендарный") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体", "Toca para ver solo esta rareza · toca de nuevo para ver todo", "Touche pour n'afficher que cette rareté · touche à nouveau pour tout afficher", "Toque para ver só esta raridade · toque de novo para ver tudo", "Tippe, um nur diese Seltenheit zu sehen · tippe erneut für alle", "Нажмите: только эта редкость · ещё раз: сброс") }
    /// 스프라이트 클릭 → 그 종의 도감 상세. 툴팁·접근성 라벨 공용.
    var dexOpenEntryHint: String { t("컬렉션에서 도감 항목 보기", "View entry in collection", "コレクションで図鑑を見る", "Ver entrada en la colección", "Voir la fiche dans la collection", "Ver registro na coleção", "Eintrag in der Sammlung ansehen", "Открыть запись в коллекции") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い", "Variocolor", "Chromatique", "Shiny", "Schillernd", "Шайни") }
    var dexSearchPlaceholder: String { t("이름 또는 #번호 검색…", "Search name or #…", "名前または#番号で検索…", "Buscar por nombre o #…", "Rechercher par nom ou #…", "Buscar por nome ou #…", "Nach Name oder # suchen…", "Поиск по имени или №…") }
    var sortTitle: String { t("정렬", "Sort", "並び替え", "Ordenar", "Trier", "Ordenar", "Sortieren", "Сортировка") }
    var sortDexNumberAsc: String { t("도감 번호 (낮은 순)", "Number (Low to High)", "図鑑番号（昇順）", "Nº de Pokédex (asc.)", "N° de Pokédex (croissant)", "Nº da Pokédex (crescente)", "Nummer (aufsteigend)", "Номер (по возрастанию)") }
    var sortDexNumberDesc: String { t("도감 번호 (높은 순)", "Number (High to Low)", "図鑑番号（降順）", "Nº de Pokédex (desc.)", "N° de Pokédex (décroissant)", "Nº da Pokédex (decrescente)", "Nummer (absteigend)", "Номер (по убыванию)") }
    var sortNameAsc: String { t("이름 (가나다·A-Z)", "Name (A-Z)", "名前（五十音・A-Z）", "Nombre (A-Z)", "Nom (A-Z)", "Nome (A-Z)", "Name (A-Z)", "Имя (A-Z)") }
    var sortNameDesc: String { t("이름 (역순)", "Name (Z-A)", "名前（逆順）", "Nombre (Z-A)", "Nom (Z-A)", "Nome (Z-A)", "Name (Z-A)", "Имя (Z-A)") }
    var sortRarity: String { t("희귀도 순", "Rarity (High to Low)", "希少度順", "Rareza (mayor a menor)", "Rareté (décroissante)", "Raridade (maior a menor)", "Seltenheit (absteigend)", "Редкость (по убыванию)") }
    var sortDateDesc: String { t("최근 잡은 순", "Most Recent", "最近捕獲", "Más recientes", "Plus récents", "Mais recentes", "Neueste zuerst", "Сначала новые") }
    var sortDateAsc: String { t("오래된 순", "Oldest First", "古い順", "Más antiguos", "Plus anciens", "Mais antigos", "Älteste zuerst", "Сначала старые") }
    var filterShinyOnly: String { t("이로치만", "Shiny only", "色違いのみ", "Solo variocolor", "Chromatique uniquement", "Apenas Shiny", "Nur schillernde", "Только шайни") }
    var filterEvolutionFamily: String { t("진화 라인 포함", "Evolution family", "進化ラインを含める", "Línea evolutiva", "Famille d'évolution", "Linha evolutiva", "Entwicklungsreihe", "Линия эволюции") }
    var noSearchResults: String { t("검색 결과가 없어요", "No Pokémon found", "見つかりませんでした", "No se encontraron Pokémon", "Aucun Pokémon trouvé", "Nenhum Pokémon encontrado", "Keine Pokémon gefunden", "Покемоны не найдены") }
    var clearFilters: String { t("필터 초기화", "Reset filters", "フィルターを解除", "Restablecer filtros", "Réinitialiser les filtres", "Redefinir filtros", "Filter zurücksetzen", "Сбросить фильтры") }
    func label(for option: CompanionStore.DexSortOption) -> String {
        switch option {
        case .numberAsc: return sortDexNumberAsc
        case .numberDesc: return sortDexNumberDesc
        case .nameAsc: return sortNameAsc
        case .nameDesc: return sortNameDesc
        case .rarityDesc: return sortRarity
        case .countDesc: return sortMostCaught
        }
    }
    var sortMostCaught: String {
        t("많이 잡은 순", "Most caught", "捕まえた数順", "Más capturados", "Les plus capturés", "Mais capturados", "Am häufigsten gefangen",
          "Чаще пойманные")
    }
    /// "×8": how many of this Pokémon the Pokédex holds, or which one this record is.
    func catchCount(_ n: Int) -> String { "×\(n)" }
    func dexCaughtTimes(_ n: Int) -> String {
        t("\(n)번 잡았어요", "Caught \(n) times", "\(n)回捕まえた", "Capturado \(n) veces", "Capturé \(n) fois", "Capturado \(n) vezes",
          "\(n)-mal gefangen", "Поймано \(n) раз")
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
        case .countDesc: return sortMostCaught
        }
    }
    var dexNormalLabel: String { t("일반", "Normal", "通常", "Normal", "Normal", "Normal", "Normal", "Обычный") }
    var dexAppearance: String { t("모습", "Appearance", "姿", "Aspecto", "Apparence", "Aparência", "Aussehen", "Внешний вид") }
    /// Shown when no Pokémon of the picked look was caught: Normal on a form caught shiny only.
    var dexAppearancePreview: String { t("미리보기 · 이 모습으로는 잡지 않았어요", "Preview · not caught in this look", "プレビュー・この姿では未入手", "Vista previa · no capturado con este aspecto", "Aperçu · pas attrapé sous cet aspect", "Prévia · não capturado com esta aparência", "Vorschau · in diesem Aussehen nicht gefangen", "Предпросмотр · в этом облике не пойман") }
    // MARK: Pokémon 상세
    var loadingPokemonDetails: String { t("포켓몬 정보를 불러오는 중…", "Loading Pokémon details…", "ポケモン情報を読み込み中…", "Cargando detalles del Pokémon…", "Chargement des détails du Pokémon…", "Carregando detalhes do Pokémon…", "Pokémon-Details werden geladen…", "Загрузка данных покемона…") }
    var pokemonDetailsUnavailable: String { t("포켓몬 정보를 불러오지 못했어요.", "Pokémon details could not be loaded.", "ポケモン情報を読み込めませんでした。", "No se pudieron cargar los detalles.", "Impossible de charger les détails.", "Não foi possível carregar os detalhes.", "Pokémon-Details konnten nicht geladen werden.", "Не удалось загрузить данные покемона.") }
    var pokemonIndividual: String { t("개체", "Individual", "個体", "Ejemplar", "Individu", "Indivíduo", "Individuum", "Особь") }
    var level: String { t("레벨", "Level", "レベル", "Nivel", "Niveau", "Nível", "Level", "Уровень") }
    var gender: String { t("성별", "Gender", "性別", "Sexo", "Sexe", "Gênero", "Geschlecht", "Пол") }
    var nature: String { t("성격", "Nature", "性格", "Naturaleza", "Nature", "Natureza", "Wesen", "Характер") }
    var ability: String { t("특성", "Ability", "特性", "Habilidad", "Talent", "Habilidade", "Fähigkeit", "Способность") }
    var hiddenAbility: String { t("숨겨진 특성", "Hidden Ability", "隠れ特性", "Habilidad oculta", "Talent caché", "Habilidade oculta", "Versteckte Fähigkeit", "Скрытая способность") }
    var hidden: String { t("숨김", "Hidden", "隠れ", "Oculta", "Caché", "Oculta", "Versteckt", "Скрытая") }
    var activeMoves: String { t("배운 기술", "Known moves", "覚えている技", "Movimientos conocidos", "Capacités connues", "Golpes conhecidos", "Erlernte Attacken", "Изученные приёмы") }
    var noLevelMoves: String { t("현재 레벨에서 배운 기술이 없어요.", "No level-up moves learned at this level.", "現在のレベルで覚えた技はありません。", "No hay movimientos aprendidos a este nivel.", "Aucune capacité apprise à ce niveau.", "Nenhum golpe aprendido neste nível.", "Auf diesem Level wurden keine Attacken erlernt.", "На этом уровне ещё нет приёмов, изучаемых по уровню.") }
    var actualStats: String { t("실제 능력치", "Actual stats", "実能力値", "Estadísticas reales", "Stats réelles", "Atributos reais", "Tatsächliche Werte", "Фактические характеристики") }
    var baseStats: String { t("기본 능력치", "Base stats", "種族値", "Estadísticas base", "Stats de base", "Atributos base", "Basiswerte", "Базовые характеристики") }
    var speciesData: String { t("종 정보", "Species data", "種情報", "Datos de especie", "Données de l’espèce", "Dados da espécie", "Speziesdaten", "Данные вида") }
    var height: String { t("키", "Height", "高さ", "Altura", "Taille", "Altura", "Größe", "Рост") }
    var weight: String { t("몸무게", "Weight", "重さ", "Peso", "Poids", "Peso", "Gewicht", "Вес") }
    var baseStatTotal: String { t("합계", "Base total", "合計", "Total base", "Total de base", "Total base", "Basiswertsumme", "Сумма базовых") }
    var possibleAbilities: String { t("가능한 특성", "Possible abilities", "可能な特性", "Habilidades posibles", "Talents possibles", "Habilidades possíveis", "Mögliche Fähigkeiten", "Возможные способности") }
    func completeMoveList(_ count: Int) -> String { t("전체 기술 목록 \(count)개", "Complete move list · \(count)", "全技リスト・\(count)", "Lista completa · \(count)", "Liste complète · \(count)", "Lista completa · \(count)", "Vollständige Attackenliste · \(count)", "Все приёмы · \(count)") }
    func genderLabel(_ gender: PokemonGender?) -> String {
        switch gender {
        case .male: return t("수컷", "Male", "オス", "Macho", "Mâle", "Macho", "Männlich", "Самец")
        case .female: return t("암컷", "Female", "メス", "Hembra", "Femelle", "Fêmea", "Weiblich", "Самка")
        case .genderless: return t("무성", "Genderless", "性別不明", "Sin género", "Asexué", "Sem gênero", "Geschlechtslos", "Бесполый")
        case nil: return "-"
        }
    }
    func statLabel(_ stat: String) -> String {
        switch stat {
        case "hp": return "HP"
        case "attack": return t("공격", "Attack", "こうげき", "Ataque", "Attaque", "Ataque", "Angriff", "Атака")
        case "defense": return t("방어", "Defense", "ぼうぎょ", "Defensa", "Défense", "Defesa", "Vert.", "Защита")
        case "special-attack": return t("특공", "Sp. Atk", "とくこう", "At. Esp.", "Atq. Spé.", "Atq. Esp.", "Sp.-Ang.", "Сп. атака")
        case "special-defense": return t("특방", "Sp. Def", "とくぼう", "Def. Esp.", "Déf. Spé.", "Def. Esp.", "Sp.-Vert.", "Сп. защита")
        case "speed": return t("스피드", "Speed", "すばやさ", "Velocidad", "Vitesse", "Velocidade", "Initiative", "Скорость")
        default: return stat
        }
    }
    func moveMethod(_ detail: PokemonMoveLearnMethod) -> String {
        switch detail.method {
        case "level-up": return detail.level > 0 ? "Lv. \(detail.level)" : t("시작", "Start", "基本", "Inicio", "Départ", "Inicial", "Start", "Старт")
        case "machine": return "TM"
        case "egg": return t("교배", "Egg", "タマゴ", "Huevo", "Œuf", "Ovo", "Ei", "Яйцо")
        case "light-ball-egg": return t("전기구 교배", "Light Ball breeding", "でんきだま遺伝", "Crianza con Bola Luminosa", "Reproduction avec Balle Lumière", "Cruzamento com Bola de Luz", "Zucht mit Kugelblitz", "Разведение со Световым шаром")
        case "form-change": return t("폼 체인지", "Form change", "フォルムチェンジ", "Cambio de forma", "Changement de forme", "Mudança de forma", "Formwechsel", "Смена формы")
        case "tutor": return t("가르침", "Tutor", "教え", "Tutor", "Maître", "Tutor", "Tutor", "Наставник")
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
    var statusEgg: String { t("곧 깨어나요.", "Hatching soon.", "もうすぐ孵化します。", "Está a punto de eclosionar.", "Bientôt l'éclosion.", "Vai chocar logo.", "Schlüpft bald.", "Скоро вылупится.") }
    var statusIdle: String { t("오늘은 조용히 자리를 지켜요.", "Keeping quiet today.", "今日は静かにしています。", "Hoy se mantiene tranquilo.", "Tranquille aujourd'hui.", "Hoje está quietinho.", "Ist heute ganz ruhig.", "Сегодня затишье.") }
    var statusWorking: String { t("오늘의 작업 흔적이 쌓이고 있어요.", "Today's work is piling up.", "本日の作業が積み重なっています。", "El trabajo de hoy se va acumulando.", "Le travail du jour s'accumule.", "O trabalho de hoje está se acumulando.", "Heute kommt einiges an Arbeit zusammen.", "Работы сегодня всё больше.") }
    var statusFocus: String { t("지금은 집중 모드예요.", "In focus mode now.", "今は集中モードです。", "Ahora está en modo concentración.", "En mode concentration.", "Agora está em modo foco.", "Gerade voll konzentriert.", "Сейчас в режиме фокуса.") }
    var statusTired: String { t("한도에 가까워요. 잠깐 쉬어도 괜찮아요.", "Close to the limit. A short break is fine.", "上限が近いです。少し休んでも大丈夫。", "Está cerca del límite. Un pequeño descanso no vendría mal.", "Proche de la limite. Une petite pause ne fait pas de mal.", "Está perto do limite. Uma pausa cai bem.", "Fast am Limit. Eine kurze Pause tut gut.", "Лимит близко. Короткий перерыв не помешает.") }
    var statusSleep: String { t("지금은 자고 있어요.", "Sleeping now.", "今は眠っています。", "Ahora está durmiendo.", "En train de dormir.", "Agora está dormindo.", "Schläft gerade.", "Сейчас спит.") }
    func statusEvolved(_ name: String) -> String { t("\(KoreanParticle.direction.attach(to: name)) 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!", "Эволюционировал в \(name)!") }
    var statusGrew: String { t("성장했어요!", "It grew!", "成長しました！", "¡Ha crecido!", "Il a grandi !", "Cresceu!", "Ist gewachsen!", "Подрос!") }

    // MARK: companion 이벤트 시스템 알림
    var notifHatchTitle: String { t("🥚 부화!", "🥚 Hatched!", "🥚 孵化！", "🥚 ¡Eclosionó!", "🥚 Éclosion !", "🥚 Chocou!", "🥚 Geschlüpft!", "🥚 Вылупился!") }
    func notifHatchBody(_ name: String) -> String { t("알에서 \(KoreanParticle.subject.attach(to: name)) 나왔어요!", "\(name) hatched from the egg!", "タマゴから \(name) が生まれました！", "¡\(name) salió del huevo!", "\(name) est sorti de l'œuf !", "\(name) saiu do ovo!", "\(name) ist aus dem Ei geschlüpft!", "Из яйца вылупился \(name)!") }
    var notifShinyHatchTitle: String { t("✨ 이로치 포켓몬!", "✨ Shiny Pokémon!", "✨ 色違いポケモン！", "✨ ¡Pokémon variocolor!", "✨ Pokémon chromatique !", "✨ Pokémon shiny!", "✨ Schillerndes Pokémon!", "✨ Шайни-покемон!") }
    /// 실제 판정에 쓴 분모를 받는다 — 부적이 있으면 64 가 아니다.
    /// `odds` nil: every hatch is shiny (the Glimmering Charm), so no odds are told.
    func notifShinyHatchBody(_ name: String, odds: UInt64?) -> String {
        guard let odds else {
            return t("이로치 \(KoreanParticle.subject.attach(to: name)) 태어났어요!", "A shiny \(name) hatched!", "色違いの \(name) が生まれました！",
                     "¡Nació un \(name) variocolor!", "Un \(name) chromatique est né !", "Nasceu um \(name) shiny!",
                     "Ein schillerndes \(name) ist geschlüpft!", "Вылупился шайни \(name)!")
        }
        return t("이로치 \(KoreanParticle.subject.attach(to: name)) 태어났어요! (1/\(odds))", "A shiny \(name) hatched! (1 in \(odds))", "色違いの \(name) が生まれました！(1/\(odds))", "¡Nació un \(name) variocolor! (1 entre \(odds))", "Un \(name) chromatique est né ! (1 sur \(odds))", "Nasceu um \(name) shiny! (1 em \(odds))", "Ein schillerndes \(name) ist geschlüpft! (1/\(odds))", "Вылупился шайни \(name)! (шанс 1 к \(odds))")
    }
    var eggImminent: String { t("곧 부화해요!", "About to hatch!", "もうすぐ孵化！", "¡Está a punto de eclosionar!", "Sur le point d'éclore !", "Está quase chocando!", "Schlüpft gleich!", "Вот-вот вылупится!") }
    /// 첫 실행(아직 토큰 적립 0) 안내 — "왜 아무 일도 안 일어나지"를 방지.
    /// `amount` 는 성장 난이도가 반영된 부화 임계(포맷된 값) — 고정 5M 이 아니다.
    func eggFirstRunHint(_ amount: String) -> String {
        t("로컬 AI 코딩 도구의 사용량으로 자라요. 약 \(amount) 토큰을 쓰면 알이 부화해요.",
          "Grows from your local AI coding usage. Your egg hatches after ~\(amount) tokens.",
          "ローカルの AI コーディング使用量で育ちます。約\(amount)トークンでタマゴが孵化します。",
          "Crece con el uso de tus herramientas locales de programación con IA. Tu huevo eclosiona tras unos \(amount) de tokens.",
          "Il grandit avec l'usage de tes outils de code IA locaux. Ton œuf éclôt après environ \(amount) de tokens.",
          "Cresce com o uso das suas ferramentas locais de programação com IA. O ovo choca depois de uns \(amount) de tokens.",
          "Wächst mit der Nutzung deiner lokalen KI-Coding-Tools. Nach etwa \(amount) Tokens schlüpft dein Ei.",
          "Растёт вместе с вашим локальным использованием ИИ для программирования. Яйцо вылупится примерно через \(amount) токенов.") }
    var notifEvolveTitle: String { t("✨ 진화!", "✨ Evolved!", "✨ 進化！", "✨ ¡Evolucionó!", "✨ Évolution !", "✨ Evoluiu!", "✨ Entwicklung!", "✨ Эволюция!") }
    func notifEvolveBody(_ name: String) -> String { t("\(KoreanParticle.direction.attach(to: name)) 진화했어요!", "Evolved into \(name)!", "\(name) に進化しました！", "¡Evolucionó a \(name)!", "A évolué en \(name) !", "Evoluiu para \(name)!", "Hat sich zu \(name) entwickelt!", "Эволюционировал в \(name)!") }
    // 메타몽 위장 리빌 — 진화 못 하는 메타몽이 첫 진화 순간 정체를 드러낸다.
    var notifDittoRevealTitle: String { t("🎭 어라? 메타몽!", "🎭 Huh? It's Ditto!", "🎭 あれ？メタモン！", "🎭 ¿Eh? ¡Es Ditto!", "🎭 Hein ? C'est Métamorph !", "🎭 Ué? É um Ditto!", "🎭 Huch? Ditto!", "🎭 Что? Это Ditto!") }
    func notifDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데, 사실은 메타몽이었어요!", "You thought it was \(disguise)… it was Ditto all along!", "\(disguise) だと思ってた… 実はメタモンでした！", "Pensabas que era \(disguise)… ¡en realidad era Ditto!", "Tu croyais que c'était \(disguise)… c'était Métamorph depuis le début !", "Você achava que era \(disguise)… era um Ditto o tempo todo!", "Du dachtest, es wäre \(disguise), dabei war es die ganze Zeit Ditto!", "Думали, это \(disguise)? А это всё время был Ditto!") }
    var notifShinyDittoRevealTitle: String { t("🎭✨ 어라? 이로치 메타몽!", "🎭✨ Huh? A shiny Ditto!", "🎭✨ あれ？色違いメタモン！", "🎭✨ ¿Eh? ¡Un Ditto variocolor!", "🎭✨ Hein ? Un Métamorph chromatique !", "🎭✨ Ué? Um Ditto shiny!", "🎭✨ Huch? Ein schillerndes Ditto!", "🎭✨ Что? Шайни-Ditto!") }
    /// 확률을 적지 않는다 — 이로치는 부화 때 굴렸고, 그때의 부적 보유 여부는 저장되지 않는다.
    func notifShinyDittoRevealBody(_ disguise: String) -> String { t("\(disguise)인 줄 알았는데, 이로치 메타몽이었어요!", "You thought it was \(disguise)… it was a shiny Ditto!", "\(disguise) だと思ってた… 色違いのメタモンでした！", "Pensabas que era \(disguise)… ¡era un Ditto variocolor!", "Tu croyais que c'était \(disguise)… c'était un Métamorph chromatique !", "Você achava que era \(disguise)… era um Ditto shiny!", "Du dachtest, es wäre \(disguise), dabei war es ein schillerndes Ditto!", "Думали, это \(disguise)? А это шайни-Ditto!") }
    // MARK: Explorer Kit treasures

    var treasureTitle: String { t("새 보물!", "New treasure!", "新しい宝物！", "¡Nuevo tesoro!", "Nouveau trésor !", "Novo tesouro!", "Neuer Schatz!", "Новое сокровище!") }
    /// A Legendary Egg dug up: the jackpot, said without its odds.
    var treasureJackpotTitle: String { t("대박!", "Jackpot!", "大当たり！", "¡Premio gordo!", "Gros lot !", "Sorte grande!", "Hauptgewinn!", "Джекпот!") }
    /// What the Explorer Kit dug up, "Rare Candy ×6, Uncommon Egg": a list, so no count or article to agree.
    func treasureBody(_ treasures: [(kind: ItemKind, count: Int)]) -> String {
        let kit = itemName(.explorerKit)
        let list = treasures.map { $0.count > 1 ? "\(itemName($0.kind)) ×\($0.count)" : itemName($0.kind) }
            .joined(separator: t(", ", ", ", "、", ", ", ", ", ", ", ", ", ", "))
        return t("\(KoreanParticle.direction.attach(to: kit)) 발굴한 보물: \(list). 가방에 들어 있어요.",
                 "Your \(kit) dug up: \(list). It's all in your Bag.",
                 "\(kit)で掘り当てました：\(list)。バッグに入っています。",
                 "Tu \(kit) desenterró: \(list). Ya está en tu bolsa.",
                 "Ton \(kit) a déterré : \(list). Tout est dans ton Sac.",
                 "Seu \(kit) desenterrou: \(list). Já está na sua bolsa.",
                 "Dein \(kit) hat ausgegraben: \(list). Alles liegt in deinem Beutel.",
                 "\"\(kit)\" откопал: \(list). Всё уже в сумке.")
    }
    var treasureOpenBag: String { t("가방 보기", "Open the Bag", "バッグを見る", "Ver la bolsa", "Voir le Sac", "Ver a bolsa", "Beutel öffnen", "Открыть сумку") }

    var notifGraduateTitle: String { t("🎓 졸업!", "🎓 Graduated!", "🎓 卒業！", "🎓 ¡Graduado!", "🎓 Diplômé !", "🎓 Formatura!", "🎓 Abschied!", "🎓 Выпуск!") }
    func notifGraduateBody(_ name: String) -> String { t("\(name): 도감에 보존! 새 알이 도착했어요.", "\(name): saved to your Pokédex! A new egg has arrived.", "\(name)：図鑑に保存！新しいタマゴが届きました。", "\(name): ¡guardado en tu Pokédex! Ha llegado un nuevo huevo.", "\(name) : conservé dans ton Pokédex ! Un nouvel œuf est arrivé.", "\(name): guardado na sua Pokédex! Chegou um novo ovo.", "\(name): in deinem Pokédex gespeichert! Ein neues Ei ist da.", "\(name): запись в Покедексе! Появилось новое яйцо.") }

    // MARK: Claude 한도 토큰 갱신 오류 (친절 안내)
    func limitRefreshHTTPError(_ status: Int) -> String {
        if status == 401 || status == 403 {
            return t(
                "Claude 자격증명이 만료됐거나 권한이 없어요 (\(status)). Claude Code 로그인을 확인하세요. Codex만 쓴다면 무시해도 됩니다. Codex 한도는 따로 표시돼요.",
                "Claude credential is expired or unauthorized (\(status)). Check that you're signed in to Claude Code. If you only use Codex you can ignore this: Codex limits show separately.",
                "Claude の認証情報が期限切れか権限がありません (\(status))。Claude Code にサインインしているか確認してください。Codex のみ使用する場合は無視できます。Codex の上限は別に表示されます。",
                "La credencial de Claude expiró o no tiene permisos (\(status)). Comprueba que has iniciado sesión en Claude Code. Si solo usas Codex, puedes ignorar esto: los límites de Codex se muestran aparte.",
                "L'identifiant Claude a expiré ou n'est pas autorisé (\(status)). Vérifie que tu es connecté à Claude Code. Si tu n'utilises que Codex, ignore ceci : les limites Codex s'affichent séparément.",
                "A credencial do Claude expirou ou não tem permissão (\(status)). Verifique se você fez login no Claude Code. Se você só usa o Codex, pode ignorar: os limites do Codex aparecem à parte.",
                "Deine Claude-Anmeldedaten sind abgelaufen oder nicht berechtigt (\(status)). Prüfe, ob du bei Claude Code angemeldet bist. Wenn du nur Codex verwendest, kannst du das ignorieren: Codex-Limits werden separat angezeigt.",
                "Учётные данные Claude истекли или недействительны (\(status)). Проверьте, что вы вошли в Claude Code. Если вы пользуетесь только Codex, это можно игнорировать: лимиты Codex показываются отдельно.")
        }
        return t("Claude 한도 조회 실패 (\(status)).", "Failed to fetch Claude limits (\(status)).", "Claude の上限取得に失敗しました (\(status))。", "No se pudieron obtener los límites de Claude (\(status)).", "Échec de récupération des limites Claude (\(status)).", "Não foi possível obter os limites do Claude (\(status)).", "Claude-Limits konnten nicht abgerufen werden (\(status)).", "Не удалось получить лимиты Claude (\(status)).")
    }
    var limitRefreshNoCredential: String {
        t("Claude 자격증명을 찾지 못했어요. Claude Code 에 로그인하면 한도가 표시됩니다. Codex만 쓴다면 무시해도 돼요.",
          "No Claude credential found. Sign in to Claude Code to see limits. If you only use Codex you can ignore this.",
          "Claude の認証情報が見つかりません。Claude Code にサインインすると上限が表示されます。Codex のみなら無視して構いません。",
          "No se encontró ninguna credencial de Claude. Inicia sesión en Claude Code para ver los límites. Si solo usas Codex, puedes ignorar esto.",
          "Aucun identifiant Claude trouvé. Connecte-toi à Claude Code pour voir les limites. Si tu n'utilises que Codex, ignore ceci.",
          "Nenhuma credencial do Claude encontrada. Faça login no Claude Code para ver os limites. Se você só usa o Codex, pode ignorar.",
          "Keine Claude-Anmeldedaten gefunden. Melde dich bei Claude Code an, um Limits zu sehen. Wenn du nur Codex verwendest, kannst du das ignorieren.",
          "Учётные данные Claude не найдены. Войдите в Claude Code, чтобы видеть лимиты. Если вы пользуетесь только Codex, это можно игнорировать.")
    }
    var limitRefreshReauthNeeded: String {
        t("Claude 자격증명에 계정 로그인 정보가 없어요. Claude Code 에서 `/login` 으로 다시 로그인하면 한도가 표시됩니다.",
          "Your Claude credential has no account sign-in. Run `/login` in Claude Code to sign in again and limits will appear.",
          "Claude の認証情報にアカウントのサインインが含まれていません。Claude Code で `/login` を実行して再度サインインすると上限が表示されます。",
          "Tu credencial de Claude no tiene una sesión de cuenta asociada. Ejecuta `/login` en Claude Code para volver a iniciar sesión y ver los límites.",
          "Ton identifiant Claude n'a pas de connexion de compte. Lance `/login` dans Claude Code pour te reconnecter et les limites apparaîtront.",
          "A credencial do Claude não está associada a nenhuma conta. Rode `/login` no Claude Code para fazer login de novo. Aí os limites aparecem.",
          "Deine Claude-Anmeldedaten enthalten keine Kontoanmeldung. Führe `/login` in Claude Code aus, um dich erneut anzumelden und die Limits anzuzeigen.",
          "В учётных данных Claude нет входа в аккаунт. Выполните `/login` в Claude Code, чтобы войти снова, и лимиты появятся.")
    }
    var limitRefreshGeneric: String {
        t("Claude 한도 조회에 실패했어요. 잠시 후 다시 시도하세요.",
          "Couldn't fetch Claude limits. Please try again shortly.",
          "Claude の上限取得に失敗しました。しばらくして再試行してください。",
          "No se pudieron obtener los límites de Claude. Inténtalo de nuevo en unos momentos.",
          "Impossible de récupérer les limites Claude. Réessaie dans un instant.",
          "Não foi possível obter os limites do Claude. Tente de novo daqui a pouco.",
          "Claude-Limits konnten nicht abgerufen werden. Versuch es gleich noch einmal.",
          "Не удалось получить лимиты Claude. Попробуйте чуть позже.")
    }
    var limitRefreshRateLimited: String {
        t("Claude 한도 조회가 일시 제한됐어요 (429). 잠시 쉬었다가 자동으로 재시도합니다.",
          "Claude limit checks are temporarily rate-limited (429). Backing off and retrying automatically.",
          "Claude の上限取得が一時的に制限されています (429)。少し待って自動的に再試行します。",
          "Las comprobaciones de límites de Claude están temporalmente limitadas (429). Se reintentará automáticamente en breve.",
          "Les vérifications de limites Claude sont temporairement restreintes (429). Pause puis nouvelle tentative automatique.",
          "As consultas de limite do Claude estão com as requisições restringidas (429). Vamos aguardar e tentar de novo automaticamente.",
          "Claude-Limitabfragen sind vorübergehend eingeschränkt (429). Nach einer kurzen Pause wird es automatisch erneut versucht.",
          "Проверки лимитов Claude временно ограничены по частоте (429). Повторим автоматически с паузой.")
    }

    // MARK: Claude 세션 만료(401) 안내
    var claudeAuthExpiredTitle: String {
        t("Claude 세션 만료: 한도가 갱신 안 돼요",
          "Claude session expired: limits can't refresh",
          "Claude セッション期限切れ：上限を更新できません",
          "Sesión de Claude expirada: los límites no se pueden actualizar",
          "Session Claude expirée : les limites ne s'actualisent pas",
          "Sessão do Claude expirada: não dá para atualizar os limites",
          "Claude-Sitzung abgelaufen: Limits können nicht aktualisiert werden",
          "Сессия Claude истекла: лимиты не обновляются")
    }
    var claudeAuthExpiredHint: String {
        t("표시된 값은 만료 전 기준이에요. 다시 시도하거나, Claude Code 를 한 번 실행하면 자동 갱신됩니다.",
          "Values shown are from before expiry. Retry, or run Claude Code once to refresh automatically.",
          "表示値は期限切れ前のものです。再試行するか、Claude Code を一度実行すると自動更新されます。",
          "Los valores mostrados son de antes de la expiración. Reinténtalo, o ejecuta Claude Code una vez para actualizarlos automáticamente.",
          "Les valeurs affichées datent d'avant l'expiration. Réessaie, ou lance Claude Code une fois pour actualiser automatiquement.",
          "Os valores exibidos são de antes da expiração. Tente de novo ou rode o Claude Code uma vez para atualizá-los automaticamente.",
          "Die angezeigten Werte stammen von vor dem Ablauf. Versuch es erneut oder starte Claude Code einmal, um sie automatisch zu aktualisieren.",
          "Показаны данные до истечения сессии. Повторите попытку или один раз запустите Claude Code: сессия обновится автоматически.")
    }
    func additionalAccountExpiredHint(_ folder: String) -> String {
        t("CLAUDE_CONFIG_DIR=\(folder) 로 Claude Code 를 한 번 실행한 뒤 다시 시도하세요.",
          "Run Claude Code once with CLAUDE_CONFIG_DIR=\(folder), then retry.",
          "CLAUDE_CONFIG_DIR=\(folder) で Claude Code を一度実行してから再試行してください。",
          "Ejecuta Claude Code una vez con CLAUDE_CONFIG_DIR=\(folder) y reinténtalo.",
          "Lance Claude Code une fois avec CLAUDE_CONFIG_DIR=\(folder), puis réessaie.",
          "Rode o Claude Code uma vez com CLAUDE_CONFIG_DIR=\(folder) e tente de novo.",
          "Starte Claude Code einmal mit CLAUDE_CONFIG_DIR=\(folder) und versuch es dann erneut.",
          "Один раз запустите Claude Code с CLAUDE_CONFIG_DIR=\(folder), затем повторите попытку.")
    }
    var retry: String { t("다시 시도", "Retry", "再試行", "Reintentar", "Réessayer", "Tentar de novo", "Erneut versuchen", "Повторить") }

    // MARK: Antigravity 세션 만료(401) 안내 — Claude 쪽과 동일 문안 구조로 통일
    var antigravityAuthExpiredTitle: String {
        t("Antigravity 세션 만료: 한도가 갱신 안 돼요",
          "Antigravity session expired: limits can't refresh",
          "Antigravity セッション期限切れ：上限を更新できません",
          "Sesión de Antigravity expirada: los límites no se pueden actualizar",
          "Session Antigravity expirée : les limites ne s'actualisent pas",
          "Sessão do Antigravity expirada: não dá para atualizar os limites",
          "Antigravity-Sitzung abgelaufen: Limits können nicht aktualisiert werden",
          "Сессия Antigravity истекла: лимиты не обновляются")
    }
    var antigravityAuthExpiredHint: String {
        t("인증 토큰이 만료됐어요. 다시 시도하거나, Antigravity IDE 를 한 번 실행하면 자동 갱신됩니다.",
          "The auth token expired. Retry, or run Antigravity IDE once to refresh automatically.",
          "認証トークンの期限が切れました。再試行するか、Antigravity IDE を一度実行すると自動更新されます。",
          "El token de autenticación expiró. Reinténtalo, o ejecuta Antigravity IDE una vez para actualizarlo automáticamente.",
          "Le jeton d'authentification a expiré. Réessaie, ou lance Antigravity IDE une fois pour actualiser automatiquement.",
          "O token de autenticação expirou. Tente de novo, ou abra o Antigravity IDE uma vez para atualizar automaticamente.",
          "Das Authentifizierungs-Token ist abgelaufen. Versuch es erneut oder starte Antigravity IDE einmal, um es automatisch zu aktualisieren.",
          "Токен авторизации истёк. Повторите попытку или один раз запустите Antigravity IDE: токен обновится автоматически.")
    }

    // MARK: OpenCode Go 공식 한도
    var openCodeGoMonthly: String {
        t("월간", "Monthly", "月間", "Mensual", "Mensuel", "Mensal", "Monatlich", "Месяц")
    }
    var openCodeGoAuthExpiredTitle: String {
        t("OpenCode Go 키 거부: 한도가 갱신 안 돼요",
          "OpenCode Go key rejected: limits can't refresh",
          "OpenCode Go キーが拒否されました：上限を更新できません",
          "Clave de OpenCode Go rechazada: los límites no se pueden actualizar",
          "Clé OpenCode Go refusée : les limites ne s'actualisent pas",
          "Chave do OpenCode Go recusada: não dá para atualizar os limites",
          "OpenCode-Go-Schlüssel abgelehnt: Limits können nicht aktualisiert werden",
          "Ключ OpenCode Go отклонён: лимиты не обновляются")
    }
    var openCodeGoAuthExpiredHint: String {
        t("OpenCode 에서 /connect 로 OpenCode Go 키를 다시 연결해 주세요.",
          "Reconnect your OpenCode Go key with /connect in OpenCode.",
          "OpenCode で /connect を使って OpenCode Go キーを再接続してください。",
          "Vuelve a conectar tu clave de OpenCode Go con /connect en OpenCode.",
          "Reconnecte ta clé OpenCode Go avec /connect dans OpenCode.",
          "Reconecte sua chave do OpenCode Go com /connect no OpenCode.",
          "Verbinde deinen OpenCode-Go-Schlüssel in OpenCode mit /connect neu.",
          "Подключите ключ OpenCode Go заново командой /connect в OpenCode.")
    }

    // MARK: Grok 공식 한도(크레딧)
    func grokCreditPeriod(weekly: Bool, monthly: Bool) -> String {
        if weekly {
            return t("주간 크레딧", "Weekly credits", "週間クレジット", "Créditos semanales", "Crédits hebdo", "Créditos semanais", "Wöchentliche Credits", "Кредиты на неделю")
        }
        if monthly {
            return t("월간 크레딧", "Monthly credits", "月間クレジット", "Créditos mensuales", "Crédits mensuels", "Créditos mensais", "Monatliche Credits", "Кредиты на месяц")
        }
        return t("크레딧", "Credits", "クレジット", "Créditos", "Crédits", "Créditos", "Credits", "Кредиты")
    }
    var grokAuthExpiredTitle: String {
        t("Grok 로그인 만료: 한도가 갱신 안 돼요",
          "Grok login expired: limits can't refresh",
          "Grok のログイン期限切れ：上限を更新できません",
          "Sesión de Grok expirada: los límites no se pueden actualizar",
          "Connexion Grok expirée : les limites ne s'actualisent pas",
          "Login do Grok expirado: não dá para atualizar os limites",
          "Grok-Anmeldung abgelaufen: Limits können nicht aktualisiert werden",
          "Вход в Grok истёк: лимиты не обновляются")
    }
    var grokAuthExpiredHint: String {
        t("Grok CLI 를 한 번 실행하면 로그인이 갱신돼요. 안 되면 grok login 을 실행해 주세요.",
          "Run Grok CLI once to refresh the login, or run grok login.",
          "Grok CLI を一度実行するとログインが更新されます。だめなら grok login を実行してください。",
          "Ejecuta Grok CLI una vez para renovar la sesión, o ejecuta grok login.",
          "Lance Grok CLI une fois pour renouveler la connexion, ou lance grok login.",
          "Abra o Grok CLI uma vez para renovar o login, ou rode grok login.",
          "Starte Grok CLI einmal, um die Anmeldung zu erneuern, oder führe grok login aus.",
          "Запустите Grok CLI один раз, чтобы обновить вход, или выполните grok login.")
    }

    // MARK: Cursor 공식 한도(월간 포함 allowance)
    var cursorMonthlyIncluded: String {
        t("월간 포함 allowance", "Monthly included", "月間 included", "Incluido mensual", "Inclus mensuel", "Incluso mensal", "Monatlich inklusive", "Включено в месяц")
    }
    var cursorAutoUsage: String {
        t("Auto 사용", "Auto usage", "Auto 使用", "Uso Auto", "Usage Auto", "Uso Auto", "Auto-Nutzung", "Расход Auto")
    }
    var cursorApiUsage: String {
        t("API 사용", "API usage", "API 使用", "Uso API", "Usage API", "Uso API", "API-Nutzung", "Расход API")
    }
    func cursorRemainingSpend(_ amount: String) -> String {
        t("\(amount) 남음", "\(amount) left", "残り \(amount)", "Quedan \(amount)", "Reste \(amount)", "Restam \(amount)", "\(amount) übrig", "Осталось \(amount)")
    }
    var cursorAuthExpiredTitle: String {
        t("Cursor 세션 만료: 한도가 갱신 안 돼요",
          "Cursor session expired: limits can't refresh",
          "Cursor セッション期限切れ：上限を更新できません",
          "Sesión de Cursor expirada: los límites no se pueden actualizar",
          "Session Cursor expirée : les limites ne s'actualisent pas",
          "Sessão do Cursor expirada: não dá para atualizar os limites",
          "Cursor-Sitzung abgelaufen: Limits können nicht aktualisiert werden",
          "Сессия Cursor истекла: лимиты не обновляются")
    }
    var cursorAuthExpiredHint: String {
        t("Cursor IDE 에 다시 로그인하거나, 다시 시도해 주세요.",
          "Sign in to Cursor IDE again, or retry.",
          "Cursor IDE に再度サインインするか、再試行してください。",
          "Vuelve a iniciar sesión en Cursor IDE o reinténtalo.",
          "Reconnecte-toi à Cursor IDE ou réessaie.",
          "Entre de novo no Cursor IDE ou tente de novo.",
          "Melde dich erneut in Cursor IDE an oder versuch es noch einmal.",
          "Снова войдите в Cursor IDE или повторите попытку.")
    }

    // MARK: 업데이트 알림
    func updateAvailable(_ version: String, current: String) -> String {
        t("🆕 v\(version) 사용 가능 (현재 \(current))",
          "🆕 v\(version) available (you have \(current))",
          "🆕 v\(version) が利用可能（現在 \(current)）",
          "🆕 v\(version) disponible (tienes \(current))",
          "🆕 v\(version) disponible (tu as \(current))",
          "🆕 v\(version) disponível (você tem \(current))",
          "🆕 v\(version) verfügbar (installiert: \(current))",
          "🆕 Доступна v\(version) (у вас \(current))")
    }
    var updateButton: String { t("업데이트", "Update", "更新", "Actualizar", "Mettre à jour", "Instalar", "Aktualisieren", "Обновить") }
    var skipThisVersion: String { t("이 버전 건너뛰기", "Skip this version", "このバージョンをスキップ", "Omitir esta versión", "Ignorer cette version", "Ignorar esta versão", "Diese Version überspringen", "Пропустить эту версию") }
    func skippedVersion(_ version: String) -> String {
        let prefix = version.contains(".") ? "v" : ""
        return t("\(KoreanParticle.object.attach(to: prefix + version)) 건너뛰었어요",
          "You skipped \(prefix)\(version)",
          "\(prefix)\(version) をスキップしました",
          "Omitiste la \(prefix)\(version)",
          "Tu as ignoré la \(prefix)\(version)",
          "Você ignorou a \(prefix)\(version)",
          "Du hast \(prefix)\(version) übersprungen",
          "Вы пропустили \(prefix)\(version)")
    }
    var showSkippedAgain: String { t("다시 알리기", "Show again", "もう一度表示", "Mostrar de nuevo", "Afficher à nouveau", "Mostrar de novo", "Wieder anzeigen", "Показать снова") }
    /// A failed in-app update, in the banner and Settings: the app was put back as it was (`build-app.sh`).
    var updateFailed: String {
        t("업데이트에 실패했어요. 지금 앱은 그대로예요. 자세한 내용: ~/Library/Logs/PokeTokenLBI-update.log",
          "The update failed. Your current app is unchanged. Details: ~/Library/Logs/PokeTokenLBI-update.log",
          "アップデートに失敗しました。いまのアプリはそのままです。詳細: ~/Library/Logs/PokeTokenLBI-update.log",
          "La actualización falló. Tu app actual no cambió. Detalles: ~/Library/Logs/PokeTokenLBI-update.log",
          "La mise à jour a échoué. Ton app actuelle est intacte. Détails : ~/Library/Logs/PokeTokenLBI-update.log",
          "A atualização falhou. Seu app atual continua igual. Detalhes: ~/Library/Logs/PokeTokenLBI-update.log",
          "Das Update ist fehlgeschlagen. Deine aktuelle App ist unverändert. Details: ~/Library/Logs/PokeTokenLBI-update.log",
          "Обновление не удалось. Текущее приложение не изменилось. Подробности: ~/Library/Logs/PokeTokenLBI-update.log")
    }
    var updating: String { t("업데이트 중…", "Updating…", "更新中…", "Actualizando…", "Mise à jour…", "Atualizando…", "Wird aktualisiert…", "Обновление…") }
    var updatingToolTip: String { t("업데이트 진행 중… (재빌드)", "Update in progress… (rebuilding)", "アップデート進行中… (再ビルド)", "Actualización en curso… (recompilando)", "Mise à jour en cours… (recompilation)", "Atualização em andamento… (recompilando)", "Aktualisierung läuft… (Neukompilierung)", "Идет обновление… (пересборка)") }
    var updateSectionTitle: String { t("업데이트", "Updates", "アップデート", "Actualizaciones", "Mises à jour", "Atualizações", "Aktualisierungen", "Обновления") }
    var updateNotificationsLabel: String { t("업데이트 알림", "Update notifications", "アップデート通知", "Notificaciones de actualización", "Notifications de mise à jour", "Notificações de atualização", "Hinweise auf Aktualisierungen", "Уведомления об обновлениях") }
    var checkForUpdatesLabel: String { t("업데이트 확인", "Check for updates", "アップデートを確認", "Buscar actualizaciones", "Rechercher des mises à jour", "Buscar atualizações", "Nach Aktualisierungen suchen", "Проверять обновления") }
    var checkNowButton: String { t("지금 확인", "Check now", "今すぐ確認", "Comprobar ahora", "Vérifier maintenant", "Buscar agora", "Jetzt prüfen", "Проверить сейчас") }
    func updateFound(_ version: String) -> String {
        let prefix = version.contains(".") ? "v" : ""
        return t("새 버전 \(prefix)\(version) 있어요", "Version \(prefix)\(version) is available", "バージョン \(prefix)\(version) が利用可能です", "La versión \(prefix)\(version) está disponible", "La version \(prefix)\(version) est disponible", "A versão \(prefix)\(version) está disponível", "Version \(prefix)\(version) ist verfügbar", "Доступна версия \(prefix)\(version)")
    }
    func upToDate(_ version: String) -> String {
        let prefix = version.contains(".") ? "v" : ""
        return t("최신 버전이에요 (\(prefix)\(version))", "You're on the latest (\(prefix)\(version))", "最新です (\(prefix)\(version))", "Tienes la última versión (\(prefix)\(version))", "Tu as la dernière version (\(prefix)\(version))", "Você está na última versão (\(prefix)\(version))", "Du hast die neueste Version (\(prefix)\(version))", "У вас последняя версия (\(prefix)\(version))")
    }

    // MARK: 알림
    var notifCritical: String { t("한도 임박", "Limit imminent", "上限切迫", "Límite inminente", "Limite imminente", "Limite iminente", "Limit fast erreicht", "Лимит почти исчерпан") }
    var notifWarning: String { t("한도 경고", "Limit warning", "上限警告", "Aviso de límite", "Alerte de limite", "Aviso de limite", "Limit-Warnung", "Лимит близко") }
    func notifBody(_ name: String, _ percent: String) -> String {
        t("\(name) 한도 \(percent) 사용", "\(name) at \(percent)", "\(name) 上限 \(percent) 使用", "\(name) al \(percent)", "\(name) à \(percent)", "\(name) em \(percent)", "\(name): \(percent) verbraucht", "\(name): \(percent)")
    }
    var claudeFiveHour: String { t("Claude 5시간 세션", "Claude 5-hour session", "Claude 5時間セッション", "Sesión de 5 horas de Claude", "Session de 5 h de Claude", "Sessão de 5 horas do Claude", "Claude-5-Stunden-Sitzung", "Claude: 5-часовая сессия") }
    var claudeWeekly: String { t("Claude 주간", "Claude weekly", "Claude 週間", "Semanal de Claude", "Claude hebdo", "Semanal do Claude", "Claude: wöchentlich", "Claude: неделя") }
    var codexPersonalLimit: String { t("Codex 개인 한도", "Codex personal limit", "Codex 個人上限", "Límite personal de Codex", "Limite personnelle Codex", "Limite pessoal do Codex", "Persönliches Codex-Limit", "Личный лимит Codex") }

    // MARK: 가방 / 아이템
    var bag: String { t("가방", "Bag", "バッグ", "Bolsa", "Sac", "Bolsa", "Beutel", "Сумка") }
    /// The tab holding the Bag and the achievements, earned or not: the trainer's, as the games' Trainer Card.
    var trainerTab: String { t("트레이너", "Trainer", "トレーナー", "Entrenador", "Dresseur", "Treinador", "Trainer", "Тренер") }
    /// One line above the Bag's badges, instead of each badge repeating it.
    var bagBadgesHint: String {
        let step = percentNumber(CollectorBonus.badgeRegionBonus * 100)
        return t("지방마다 그 배지 타입에 약한 포켓몬이 \(step)% 더 빨리 성장해요(레귤러배지는 노말타입 포켓몬).",
                 "Each region claimed makes Pokémon weak to the badge's type grow \(step)% faster (Normal-type Pokémon for the Plain Badge).",
                 "地方ごとに、そのバッジのタイプに弱いポケモンが\(step)%早く育ちます(レギュラーバッジはノーマルタイプ)。",
                 "Cada región reclamada hace que los Pokémon débiles al tipo de la medalla crezcan un \(step)% más rápido (los de tipo Normal con la Medalla Planicie).",
                 "Chaque région récupérée fait grandir de \(step) % les Pokémon faibles contre le type du badge (les Pokémon Normal pour le Badge Plaine).",
                 "Cada região resgatada faz os Pokémon vulneráveis ao tipo da insígnia crescerem \(step)% mais rápido (os do tipo Normal com a Insígnia da Planície).",
                 "Jede abgeholte Region lässt Pokémon mit Schwäche gegen den Typ des Ordens \(step)% schneller wachsen (Normal-Pokémon beim Basisorden).",
                 "Каждый полученный регион ускоряет на \(step)% рост покемонов, уязвимых к типу значка (обычных для Обычного значка).")
    }
    var bagEmptyTitle: String { t("아직 가방이 비어있어요!", "Your bag is empty!", "バッグはまだ空っぽです！", "¡Tu bolsa todavía está vacía!", "Ton sac est encore vide !", "Sua bolsa ainda está vazia!", "Dein Beutel ist noch leer!", "Сумка пуста!") }
    var useItem: String { t("사용하기", "Use", "つかう", "Usar", "Utiliser", "Usar", "Verwenden", "Применить") }
    var use: String { t("사용", "Use", "つかう", "Usar", "Utiliser", "Usar", "Verwenden", "Применить") }
    var cancel: String { t("취소", "Cancel", "キャンセル", "Cancelar", "Annuler", "Cancelar", "Abbrechen", "Отменить") }
    func useOnCurrent(_ name: String) -> String {
        t("\(name)에게 사용할까요?", "Use on \(name)?", "\(name) に使いますか？", "¿Usar en \(name)?", "Utiliser sur \(name) ?", "Usar em \(name)?", "Bei \(name) verwenden?", "Применить к \(name)?")
    }
    var useAfterHatch: String { t("부화 후 사용할 수 있어요", "Usable after hatching", "孵化後に使えます", "Se puede usar después de eclosionar", "Utilisable après l'éclosion", "Dá para usar depois que chocar", "Nach dem Schlüpfen verwendbar", "Можно применить после вылупления") }
    var useNeedsPokemon: String { t("사용할 포켓몬이 없어요", "No Pokémon to use it on", "使えるポケモンがいません", "No hay ningún Pokémon en quien usarlo", "Aucun Pokémon sur qui l'utiliser", "Nenhum Pokémon para usar o item", "Kein Pokémon, bei dem du es verwenden kannst", "Не к кому применить") }

    /// Rare Candy batch preview, including carryover and graduation waste.
    var candyGraduates: String {
        t("이 포켓몬은 졸업할 것으로 예상돼요.", "Expected to graduate.", "卒業する見込みです。",
          "Se espera que se gradúe.", "Devrait terminer sa croissance.",
          "Deve se formar.", "Schließt voraussichtlich sein Training ab.", "Ожидается выпуск.")
    }
    func candyCarryoverXP(_ xp: String) -> String {
        t("예상 진화 후 이월 경험치: \(xp) XP.",
          "Expected after evolution: \(xp) XP carried over.",
          "進化後の予想繰越経験値：\(xp) XP。",
          "Tras evolucionar: \(xp) XP de remanente previsto.",
          "Après évolution : \(xp) XP de report prévu.",
          "Após evoluir: previsão de \(xp) XP restantes.",
          "Nach der Entwicklung: voraussichtlich \(xp) EP übertragen.",
          "После эволюции ожидается перенос \(xp) XP.")
    }
    /// With the crumbs that waste leaves (`RareCandy.crumbXP`), when it leaves any.
    func candyDiscardedXP(_ xp: String, crumbs: Int) -> String {
        let gain = crumbs > 0 ? candyCrumbsGained(crumbs) : nil
        let p = gain.map { " (\($0))" } ?? ""
        return t("졸업 시 남는 \(xp) XP는 사라져요\(p).", "On graduation, \(xp) leftover XP will be discarded\(p).",
                 "卒業時、余った\(xp) XPは失われます\(gain.map { "（\($0)）" } ?? "")。",
                 "Al graduarse, se perderán \(xp) XP sobrantes\(p).",
                 "À la fin de la croissance, les \(xp) XP restants seront perdus\(p).",
                 "Ao se formar, \(xp) XP restantes serão descartados\(p).",
                 "Beim Trainingsabschluss verfallen \(xp) überschüssige EP\(p).",
                 "При выпуске сгорит остаток: \(xp) XP\(p).")
    }
    func candyCrumbsGained(_ n: Int) -> String {
        let ru = n % 10 == 1 && n % 100 != 11 ? "крошка" : (2...4).contains(n % 10) && !(12...14).contains(n % 100) ? "крошки" : "крошек"
        return t("사탕 부스러기 +\(n)", "+\(n) \(n == 1 ? "crumb" : "crumbs")", "アメのかけら +\(n)",
                 "+\(n) \(n == 1 ? "migaja" : "migajas")", "+\(n) \(n == 1 ? "miette" : "miettes")",
                 "+\(n) \(n == 1 ? "migalha" : "migalhas")", "+\(n) Krümel", "+\(n) \(ru)")
    }
    func candyCrumbsCount(_ n: Int, of total: Int) -> String {
        t("사탕 부스러기: \(n)/\(total)", "Crumbs: \(n)/\(total)", "アメのかけら：\(n)/\(total)", "Migajas: \(n)/\(total)",
          "Miettes : \(n)/\(total)", "Migalhas: \(n)/\(total)", "Krümel: \(n)/\(total)", "Крошки: \(n)/\(total)")
    }

    /// 포켓몬 타입 표시명.
    func typeName(_ type: PokemonType) -> String {
        switch type {
        case .normal:   return t("노말", "Normal", "ノーマル", "Normal", "Normal", "Normal", "Normal", "Обычный")
        case .fire:     return t("불꽃", "Fire", "ほのお", "Fuego", "Feu", "Fogo", "Feuer", "Огненный")
        case .water:    return t("물", "Water", "みず", "Agua", "Eau", "Água", "Wasser", "Водный")
        case .grass:    return t("풀", "Grass", "くさ", "Planta", "Plante", "Planta", "Pflanze", "Травяной")
        case .electric: return t("전기", "Electric", "でんき", "Eléctrico", "Électrik", "Elétrico", "Elektro", "Электрический")
        case .ice:      return t("얼음", "Ice", "こおり", "Hielo", "Glace", "Gelo", "Eis", "Ледяной")
        case .fighting: return t("격투", "Fighting", "かくとう", "Lucha", "Combat", "Lutador", "Kampf", "Боевой")
        case .poison:   return t("독", "Poison", "どく", "Veneno", "Poison", "Veneno", "Gift", "Ядовитый")
        case .ground:   return t("땅", "Ground", "じめん", "Tierra", "Sol", "Terra", "Boden", "Земляной")
        case .flying:   return t("비행", "Flying", "ひこう", "Volador", "Vol", "Voador", "Flug", "Летающий")
        case .psychic:  return t("에스퍼", "Psychic", "エスパー", "Psíquico", "Psy", "Psíquico", "Psycho", "Психический")
        case .bug:      return t("벌레", "Bug", "むし", "Bicho", "Insecte", "Inseto", "Käfer", "Насекомый")
        case .rock:     return t("바위", "Rock", "いわ", "Roca", "Roche", "Rocha", "Gestein", "Каменный")
        case .ghost:    return t("고스트", "Ghost", "ゴースト", "Fantasma", "Spectre", "Fantasma", "Geist", "Призрачный")
        case .dragon:   return t("드래곤", "Dragon", "ドラゴン", "Dragón", "Dragon", "Dragão", "Drache", "Драконий")
        case .steel:    return t("강철", "Steel", "はがね", "Acero", "Acier", "Aço", "Stahl", "Стальной")
        case .dark:     return t("악", "Dark", "あく", "Siniestro", "Ténèbres", "Sombrio", "Unlicht", "Тёмный")
        case .fairy:    return t("페어리", "Fairy", "フェアリー", "Hada", "Fée", "Fada", "Fee", "Волшебный")
        }
    }

    /// A forms achievement that puts items in the Bag: every form graduated earns it, its rewards listed.
    func formsRewardDescription(_ kind: ItemKind) -> String {
        let list = rewardsList(kind.achievementRewards)
        return t("모든 폼이 졸업하면 받을 수 있어요. 받으면 가방에 들어와요: \(list).",
                     "Every form graduated earns it. Claiming it puts in your Bag: \(list).",
                     "すべてのフォルムが卒業すると受け取れます。受け取るとバッグに入ります：\(list)。",
                     "Se gana con todas las formas graduadas. Al reclamarlo, recibes en tu bolsa: \(list).",
                     "Toutes les formes diplômées le débloquent. En le réclamant, tu reçois dans ton sac : \(list).",
                     "Todas as formas formadas o liberam. Ao resgatá-lo, você recebe na sua bolsa: \(list).",
                     "Alle Formen verabschiedet schalten es frei. Holst du es ab, kommt in deinen Beutel: \(list).",
                     "Открывается, когда все формы выпущены. Получив его, вы найдёте в сумке: \(list).")
    }

    /// #135's forms achievements, named as the others: "Kyurem's Three Forms".
    func moreFormsName(_ kind: ItemKind) -> String {
        let n = kind.moreFormsSpecies.map { PokemonForm.forms(speciesID: $0).count } ?? 0
        func number(_ words: [String]) -> String { words[max(0, min(words.count - 1, n - 3))] }
        let ko = number(["세", "네", "다섯"]), en = number(["Three", "Four", "Five"]), es = number(["tres", "cuatro", "cinco"])
        let fr = number(["trois", "quatre", "cinq"]), pt = number(["três", "quatro", "cinco"]), de = number(["drei", "vier", "fünf"])
        let ru = number(["Три формы", "Четыре формы", "Пять форм"])
        let names: (ko: String, en: String, ja: String, fr: String, de: String, ru: String) = switch kind {
        case .deoxysFormes: ("테오키스", "Deoxys", "デオキシス", "Deoxys", "Deoxys", "Деоксиса")
        case .wormadamCloaks: ("도롱마담", "Wormadam", "ミノマダム", "Cheniselle", "Burmadame", "Вормадам")
        case .darmanitanModes: ("불비달마", "Darmanitan", "ヒヒダルマ", "Darumacho", "Flampivian", "Дарманитана")
        case .kyuremFusions: ("큐레무", "Kyurem", "キュレム", "Kyurem", "Kyurem", "Кюрема")
        case .genesectDrives: ("게노세크트", "Genesect", "ゲノセクト", "Genesect", "Genesect", "Генесекта")
        case .gourgeistSizes: ("펌킨인", "Gourgeist", "パンプジン", "Banshitrouye", "Pumpdjinn", "Гургейста")
        case .zygardeFormes: ("지가르데", "Zygarde", "ジガルデ", "Zygarde", "Zygarde", "Зигарда")
        case .lycanrocForms: ("루가루암", "Lycanroc", "ルガルガン", "Lougaroc", "Wolwerock", "Ликанрока")
        case .cramorantForms: ("윽우지", "Cramorant", "ウッウ", "Nigosier", "Urgl", "Крэморанта")
        case .calyrexSteeds: ("버드렉스", "Calyrex", "バドレックス", "Sylveroy", "Coronospa", "Калирекса")
        case .squawkabillyPlumages: ("시비꼬", "Squawkabilly", "イキリンコ", "Tapatoès", "Krawalloro", "Скуокабилли")
        case .tatsugiriForms: ("싸리용", "Tatsugiri", "シャリタツ", "Nigirigon", "Nigiragi", "Тацугири")
        case .ogerponMasks: ("오거폰", "Ogerpon", "オーガポン", "Ogerpon", "Ogerpon", "Огерпона")
        case .terapagosForms: ("테라파고스", "Terapagos", "テラパゴス", "Terapagos", "Terapagos", "Терапагоса")
        default: ("", kind.rawValue, "", "", "", "")
        }
        // Spanish and Portuguese keep the English names.
        return t("\(names.ko)의 \(ko) 가지 모습", "\(names.en)'s \(en) Forms", "\(names.ja)の\(n)つのすがた",
                 "Las \(es) formas de \(names.en)", "Les \(fr) formes de \(names.fr)", "As \(pt) formas de \(names.en)",
                 "Die \(de) Formen von \(names.de)", "\(ru) \(names.ru)")
    }

    /// 아이템 표시명 — species 처럼 공식 현지명.
    func itemName(_ kind: ItemKind) -> String {
        switch kind {
        case .deoxysFormes, .wormadamCloaks, .darmanitanModes, .kyuremFusions, .genesectDrives, .gourgeistSizes, .zygardeFormes,
             .lycanrocForms, .cramorantForms, .calyrexSteeds, .squawkabillyPlumages, .tatsugiriForms, .ogerponMasks, .terapagosForms:
            return moreFormsName(kind)
        case .rareCandy: return t("이상한 사탕", "Rare Candy", "ふしぎなアメ", "Caramelo Raro", "Super Bonbon", "Doce Raro", "Sonderbonbon", "Редкая конфета")
        case .mint:      return t("민트", "Mint", "ミント", "Menta", "Menthe", "Menta", "Minze", "Мята")
        case .shinyCharm: return t("이로치 부적", "Shiny Charm", "ひかるおまもり", "Amuleto Iris", "Charme Chroma", "Amuleto Shiny", "Schillerpin", "Шайни-талисман")
        case .legendCharm: return t("천공의피리", "Azure Flute", "てんかいのふえ", "Flauta Azur", "Flûte Azur", "Flauta Celestial", "Azurflöte", "Лазурная флейта")
        case .silverWing: return t("은빛날개", "Silver Wing", "ぎんいろのはね", "Ala Plateada", "Aile d'Argent", "Asa Prateada", "Silberflügel", "Серебряное крыло")
        case .oldSeaMap: return t("오래된해도", "Old Sea Map", "ふるびたかいず", "Mapa Viejo", "Vieille Carte", "Mapa Velho", "Alte Karte", "Старая морская карта")
        case .clearBell: return t("투명한방울", "Clear Bell", "とうめいなスズ", "Campana Clara", "Clochette Claire", "Sino Transparente", "Klarglocke", "Прозрачный колокол")
        case .rainbowWing: return t("무지갯빛날개", "Rainbow Wing", "にじいろのはね", "Ala Arcoíris", "Aile Arc-en-Ciel", "Asa Arco-íris", "Buntflügel", "Радужное крыло")
        case .magmaStone: return t("화산의돌", "Magma Stone", "かざんのおきいし", "Piedra Magma", "Pierre Magma", "Pedra de Magma", "Magmastein", "Магматический камень")
        case .soulDew: return t("마음의물방울", "Soul Dew", "こころのしずく", "Rocío Bondad", "Rosée Âme", "Orvalho da Alma", "Seelentau", "Роса душ")
        case .jadeOrb: return t("초록구슬", "Jade Orb", "もえぎいろのたま", "Esfera Verde", "Orbe Vert", "Esfera de Jade", "Grüne Kugel", "Нефритовая сфера")
        case .gracidea: return t("그라시데아꽃", "Gracidea", "グラシデアのはな", "Gracídea", "Gracidée", "Gracidea", "Gracidea", "Грасидея")
        case .griseousOrb: return t("백금옥", "Griseous Orb", "はっきんだま", "Griseosfera", "Orbe Platiné", "Esfera de Platina", "Platinum-Orb", "Гризеус-сфера")
        case .libertyPass: return t("리버티티켓", "Liberty Pass", "リバティチケット", "Pase Libertad", "Passe Liberté", "Passe da Liberdade", "Gartenpass", "Пропуск Свободы")
        case .revealGlass: return t("비추는거울", "Reveal Glass", "うつしかがみ", "Espejo Veraz", "Miroir Sacré", "Espelho Revelador", "Wahrspiegel", "Зеркало правды")
        case .dnaSplicers: return t("유전자쐐기", "DNA Splicers", "いでんしのくさび", "Punta ADN", "Pointeau ADN", "Fundidor de DNA", "DNS-Keil", "ДНК-сплайсеры")
        case .zygardeCube: return t("지가르데큐브", "Zygarde Cube", "ジガルデキューブ", "Arca de Zygarde", "Boîte Zygarde", "Cubo de Zygarde", "Zygarde-Würfel", "Куб Зигарда")
        case .prisonBottle: return t("굴레의항아리", "Prison Bottle", "いましめのツボ", "Vasija Castigo", "Vase Scellé", "Garrafa Prisão", "Banngefäß", "Сосуд-темница")
        case .sparklingStone: return t("빛나는돌", "Sparkling Stone", "かがやくいし", "Piedra Brillante", "Gemme Lumière", "Pedra Cintilante", "Glitzerstein", "Сверкающий камень")
        case .sunFlute: return t("태양의피리", "Sun Flute", "たいようのふえ", "Flauta Solar", "Flûte du Soleil", "Flauta do Sol", "Sonnenflöte", "Солнечная флейта")
        case .beastBall: return t("울트라볼", "Beast Ball", "ウルトラボール", "Ente Ball", "Ultra Ball", "Bola de Fera", "Ultraball", "Бист-бол")
        case .rustedSword: return t("녹슨검", "Rusted Sword", "くちたけん", "Espada Oxidada", "Épée Rouillée", "Espada Enferrujada", "Rostiges Schwert", "Ржавый меч")
        case .reinsOfUnity: return t("유대의고삐", "Reins of Unity", "キズナのタヅナ", "Riendas Unión", "Rênes de l'Unité", "Rédeas da União", "Zügel des Bundes", "Поводья единства")
        case .boosterEnergy: return t("부스트에너지", "Booster Energy", "ブーストエナジー", "Energía Potenciadora", "Énergie Booster", "Energia Booster", "Energiekapsel", "Бустер-энергия")
        case .tealMask: return t("벽록의가면", "Teal Mask", "みどりのめん", "Máscara Turquesa", "Masque Turquoise", "Máscara Turquesa", "Türkisgrüne Maske", "Бирюзовая маска")
        case .teraOrb: return t("테라스탈오브", "Tera Orb", "テラスタルオーブ", "Orbe Teracristal", "Orbe Téracristal", "Orbe Terastal", "Terakristall-Orb", "Тера-сфера")
        case .relicStatue: return t("고대의석상", "Relic Statue", "こだいのせきぞう", "Efigie Antigua", "Vieux Santon", "Estátua Antiga", "Alte Statue", "Древняя статуя")
        case .lunarWing: return t("초승달깃털", "Lunar Wing", "みかづきのはね", "Pluma Lunar", "Lun'Aile", "Asa Lunar", "Lunarfeder", "Лунное крыло")
        case .meteorite: return t("운석", "Meteorite", "いんせき", "Meteorito", "Météorite", "Meteorito", "Meteorit", "Метеорит")
        case .oaksLetter: return t("오박사의편지", "Oak's Letter", "オーキドのてがみ", "Carta Prof. Oak", "Lettre Chen", "Carta do Prof. Carvalho", "Eichs Brief", "Письмо Оука")
        case .seaIncense: return t("바닷물향로", "Sea Incense", "うしおのおこう", "Incienso Marino", "Encens Mer", "Incenso Marinho", "Seerauch", "Морской фимиам")
        case .shockDrive: return t("번개카세트", "Shock Drive", "イナズマカセット", "FulgoROM", "Module Choc", "Disco Choque", "Blitzmodul", "Шок-драйв")
        case .zRing: return t("Z링", "Z-Ring", "Ｚリング", "Pulsera Z", "Bracelet Z", "Pulseira Z", "Z-Ring", "Z-кольцо")
        case .scrollOfDarkness: return t("악의 족자", "Scroll of Darkness", "あくのかけじく", "Manuscrito Sombras", "Rouleau des Ténèbres", "Pergaminho das Trevas", "Unlicht-Schriftrolle", "Свиток тьмы")
        case .relicVase: return t("고대의항아리", "Relic Vase", "こだいのツボ", "Ánfora", "Vieux Vase", "Vaso Antigo", "Alte Vase", "Древняя ваза")
        case .explorerKit: return t("탐험세트", "Explorer Kit", "たんけんセット", "Kit Explorador", "Kit Explorateur", "Kit de Explorador", "Forscherset", "Набор исследователя")
        case .oldAmber: return t("비밀의호박", "Old Amber", "ひみつのコハク", "Ámbar Viejo", "Vieil Ambre", "Âmbar Antigo", "Altbernstein", "Старый янтарь")
        case .legendPlate: return t("레전드플레이트", "Legend Plate", "レジェンドプレート", "Tabla Legendaria", "Plaque Légende", "Placa Lendária", "Legendentafel", "Легендарная плита")
        case .rotomCatalog: return t("로토무카탈로그", "Rotom Catalog", "ロトムのカタログ", "Catálogo Rotom", "Moti-Catalogue", "Catálogo Rotom", "Rotom-Katalog", "Каталог Ротома")
        case .cometShard: return t("혜성조각", "Comet Shard", "すいせいのかけら", "Fragmento Cometa", "Morceau Comète", "Fragmento de Cometa", "Kometstück", "Осколок кометы")
        case .redNectar: return t("빨강꿀", "Red Nectar", "くれないのミツ", "Néctar Rojo", "Nectar Rouge", "Néctar Vermelho", "Roter Nektar", "Красный нектар")
        case .smoothRock: return t("보송보송바위", "Smooth Rock", "さらさらいわ", "Roca Suave", "Roche Lisse", "Pedra Lisa", "Glattbrocken", "Гладкий камень")
        case .sawsbuckSeasons: return t("바라철록의 사계절", "Sawsbuck's Four Seasons", "メブキジカの四季", "Las cuatro estaciones de Sawsbuck",
                                        "Les quatre saisons de Haydaim", "As quatro estações de Sawsbuck", "Kronjuwilds vier Jahreszeiten", "Четыре сезона Сосбака")
        case .fairyFeather: return t("요정의깃털", "Fairy Feather", "ようせいのハネ", "Pluma Feérica", "Plume Enchantée", "Pena de Fada", "Feenfeder", "Волшебное перо")
        case .furfrouTrims: return t("트리미앙의 열 가지 커트", "Furfrou's Ten Trims", "トリミアンの10のカット", "Los diez cortes de Furfrou",
                                     "Les dix coupes de Couafarel", "Os dez cortes de Furfrou", "Coiffwaffs zehn Schnitte", "Десять стрижек Фурфру")
        case .vivillonPatterns: return t("비비용의 스무 가지 무늬", "Vivillon's Twenty Patterns", "ビビヨンの20のもよう", "Los veinte diseños de Vivillon",
                                         "Les vingt motifs de Prismillon", "Os vinte padrões de Vivillon", "Vivillons zwanzig Muster", "Двадцать узоров Вивиллона")
        case .whippedDream: return t("휘핑팝", "Whipped Dream", "ホイップポップ", "Dulce de Nata", "Chantibonbon", "Sonho Chantili", "Sahnehäubchen", "Взбитая мечта")
        case .excavation: return t("발굴", "Excavation", "発掘", "Excavación", "Fouilles", "Escavação", "Ausgrabung", "Раскопки")
        case .fossilEgg: return t("화석 알", "Fossil Egg", "化石のタマゴ", "Huevo Fósil", "Œuf fossile", "Ovo Fóssil", "Fossil-Ei",
                                  "Яйцо-окаменелость")
        case .unownLetters: return t("안농의 알파벳", "Unown's Alphabet", "アンノーンのアルファベット", "El alfabeto de Unown", "L'alphabet des Zarbi",
                                     "O alfabeto de Unown", "Icognitos Alphabet", "Алфавит Аноуна")
        case .pokemonEgg: return eggName(nil)
        case .uncommonEgg: return eggName(.uncommon)
        case .rareEgg: return eggName(.rare)
        case .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg:
            return EventEgg(item: kind).map(eventEggName) ?? kind.rawValue
        case .typeNullEgg: return t("타입:널의 알", "Type: Null Egg", "タイプ：ヌルのタマゴ", "Huevo de Código Cero", "Œuf de Type:0", "Ovo de Type: Null", "Typ:Null-Ei", "Яйцо Тип: Ноль")
        case .lightBall: return t("전기구슬", "Light Ball", "でんきだま", "Bola Luminosa", "Balle Lumière", "Bola de Luz", "Kugelblitz", "Световой шар")
        case .legendaryEgg: return t("전설의 알", "Legendary Egg", "伝説のタマゴ", "Huevo Legendario", "Œuf légendaire", "Ovo Lendário", "Legendäres Ei", "Легендарное яйцо")
        case .birthdayEgg: return t("생일 알", "Birthday Egg", "誕生日のタマゴ", "Huevo de Cumpleaños", "Œuf d'anniversaire", "Ovo de Aniversário", "Geburtstags-Ei", "Праздничное яйцо")
        case .ovalCharm: return t("둥근부적", "Oval Charm", "まるいおまもり", "Amuleto Oval", "Charme Ovale", "Amuleto Oval", "Ovalpin", "Овальный талисман")
        case .taurosBreeds: return t("켄타로스의 네 품종", "Tauros's Four Breeds", "ケンタロスの4つの品種", "Las cuatro razas de Tauros",
                                     "Les quatre races de Tauros", "As quatro raças de Tauros", "Die vier Rassen von Tauros", "Четыре породы Тауроса")
        case .necrozmaForms: return t("네크로즈마의 네 가지 모습", "Necrozma's Four Forms", "ネクロズマの4つのすがた", "Las cuatro formas de Necrozma",
                                      "Les quatre formes de Necrozma", "As quatro formas de Necrozma", "Die vier Formen von Necrozma", "Четыре формы Некрозмы")
        case .glimmeringCharm: return t("반짝이는부적", "Glimmering Charm", "きらめくおまもり", "Amuleto Cristalino", "Charme Éclatant", "Amuleto Cintilante", "Glitzerpin", "Сверкающий талисман")
        case .boulderBadge: return t("회색배지", "Boulder Badge", "グレーバッジ", "Medalla Roca", "Badge Roche", "Insígnia da Rocha", "Felsorden", "Каменный значок")
        case .cascadeBadge: return t("블루배지", "Cascade Badge", "ブルーバッジ", "Medalla Cascada", "Badge Cascade", "Insígnia da Cascata", "Quellorden", "Каскадный значок")
        case .thunderBadge: return t("오렌지배지", "Thunder Badge", "オレンジバッジ", "Medalla Trueno", "Badge Foudre", "Insígnia do Trovão", "Donnerorden", "Значок молнии")
        case .rainbowBadge: return t("무지개배지", "Rainbow Badge", "レインボーバッジ", "Medalla Arcoíris", "Badge Prisme", "Insígnia do Arco-Íris", "Farborden", "Радужный значок")
        case .soulBadge:    return t("핑크배지", "Soul Badge", "ピンクバッジ", "Medalla Alma", "Badge Âme", "Insígnia da Alma", "Seelenorden", "Значок души")
        case .marshBadge:   return t("골드배지", "Marsh Badge", "ゴールドバッジ", "Medalla Pantano", "Badge Marais", "Insígnia do Pântano", "Sumpforden", "Болотный значок")
        case .volcanoBadge: return t("진홍배지", "Volcano Badge", "クリムゾンバッジ", "Medalla Volcán", "Badge Volcan", "Insígnia do Vulcão", "Vulkanorden", "Вулканический значок")
        case .earthBadge:   return t("그린배지", "Earth Badge", "グリーンバッジ", "Medalla Tierra", "Badge Terre", "Insígnia da Terra", "Erdorden", "Земляной значок")
        case .zephyrBadge:  return t("윙배지", "Zephyr Badge", "ウイングバッジ", "Medalla Céfiro", "Badge Zéphyr", "Insígnia do Zéfiro", "Flügelorden", "Значок зефира")
        case .hiveBadge:    return t("인섹트배지", "Hive Badge", "インセクトバッジ", "Medalla Colmena", "Badge Essaim", "Insígnia da Colmeia", "Insektorden", "Значок улья")
        case .plainBadge:   return t("레귤러배지", "Plain Badge", "レギュラーバッジ", "Medalla Planicie", "Badge Plaine", "Insígnia da Planície", "Basisorden", "Обычный значок")
        case .fogBadge:     return t("팬텀배지", "Fog Badge", "ファントムバッジ", "Medalla Niebla", "Badge Brume", "Insígnia da Névoa", "Phantomorden", "Туманный значок")
        case .stormBadge:   return t("쇼크배지", "Storm Badge", "ショックバッジ", "Medalla Tormenta", "Badge Choc", "Insígnia da Tempestade", "Faustorden", "Штормовой значок")
        case .mineralBadge: return t("스틸배지", "Mineral Badge", "スチールバッジ", "Medalla Mineral", "Badge Minéral", "Insígnia do Mineral", "Stahlorden", "Минеральный значок")
        case .glacierBadge: return t("아이스배지", "Glacier Badge", "アイスバッジ", "Medalla Glaciar", "Badge Glacier", "Insígnia da Geada", "Eisorden", "Ледниковый значок")
        case .risingBadge:  return t("라이징배지", "Rising Badge", "ライジングバッジ", "Medalla Dragón", "Badge Lever", "Insígnia do Dragão", "Drachenorden", "Восходящий значок")
        case .darkBadge:    return t("악배지", "Dark Badge", "あくバッジ", "Medalla Siniestro", "Badge Ténèbres", "Insígnia Sombria", "Unlicht-Orden", "Тёмный значок")
        case .fairyBadge:   return t("페어리배지", "Fairy Badge", "フェアリーバッジ", "Medalla Hada", "Badge Fée", "Insígnia da Fada", "Feenorden", "Волшебный значок")
        case .leafStone:    return t("리프의돌", "Leaf Stone", "リーフのいし", "Piedra Hoja", "Pierre Plante", "Pedra da Folha", "Blattstein", "Камень листьев")
        case .fireStone:    return t("불꽃의돌", "Fire Stone", "ほのおのいし", "Piedra Fuego", "Pierre Feu", "Pedra do Fogo", "Feuerstein", "Огненный камень")
        case .waterStone:   return t("물의돌", "Water Stone", "みずのいし", "Piedra Agua", "Pierre Eau", "Pedra da Água", "Wasserstein", "Водный камень")
        case .thunderStone: return t("천둥의돌", "Thunder Stone", "かみなりのいし", "Piedra Trueno", "Pierre Foudre", "Pedra do Trovão", "Donnerstein", "Громовой камень")
        case .sunStone:     return t("태양의돌", "Sun Stone", "たいようのいし", "Piedra Solar", "Pierre Soleil", "Pedra Solar", "Sonnenstein", "Солнечный камень")
        case .moonStone:    return t("달의돌", "Moon Stone", "つきのいし", "Piedra Lunar", "Pierre Lune", "Pedra da Lua", "Mondstein", "Лунный камень")
        case .iceStone:     return t("얼음의돌", "Ice Stone", "こおりのいし", "Piedra Hielo", "Pierre Glace", "Pedra de Gelo", "Eisstein", "Ледяной камень")
        case .duskStone:    return t("어둠의돌", "Dusk Stone", "やみのいし", "Piedra Noche", "Pierre Nuit", "Pedra do Anoitecer", "Finsterstein", "Сумеречный камень")
        case .dawnStone:    return t("각성의돌", "Dawn Stone", "めざめいし", "Piedra Alba", "Pierre Aube", "Pedra da Alvorada", "Funkelstein", "Камень рассвета")
        case .shinyStone:   return t("빛의돌", "Shiny Stone", "ひかりのいし", "Piedra Día", "Pierre Éclat", "Pedra do Brilho", "Leuchtstein", "Сияющий камень")
        case .greatBall: return t("수퍼볼", "Great Ball", "スーパーボール", "Super Ball", "Super Ball", "Great Ball", "Superball", "Грейт-бол")
        case .ultraBall: return t("하이퍼볼", "Ultra Ball", "ハイパーボール", "Ultra Ball", "Hyper Ball", "Ultra Ball", "Hyperball", "Ультра-бол")
        case .masterBall: return t("마스터볼", "Master Ball", "マスターボール", "Master Ball", "Master Ball", "Master Ball", "Meisterball", "Мастер-бол")
        case .oranBerry: return t("오랭열매", "Oran Berry", "オレンのみ", "Baya Aranja", "Baie Oran", "Fruta Oran", "Sinelbeere", "Ягода Оран")
        case .sitrusBerry: return t("자뭉열매", "Sitrus Berry", "オボンのみ", "Baya Zidra", "Baie Sitrus", "Fruta Sitrus", "Tsitrubeere", "Ягода Ситрус")
        case .revive: return t("기력의조각", "Revive", "げんきのかけら", "Revivir", "Rappel", "Reviver", "Beleber", "Оживитель")
        case .maxRevive: return t("기력의덩어리", "Max Revive", "げんきのかたまり", "Revivir Máximo", "Rappel Max", "Reviver Máximo", "Top-Beleber", "Макс. оживитель")
        case .silverCapsule: return t("은색왕관", "Bottle Cap", "ぎんのおうかん", "Chapa Plateada", "Capsule d'Argent", "Tampinha Prateada", "Silberkronkorken", "Серебряная крышка")
        case .goldCapsule: return t("금색왕관", "Gold Bottle Cap", "きんのおうかん", "Chapa Dorada", "Capsule d'Or", "Tampinha Dourada", "Goldkronkorken", "Золотая крышка")
        case .treasureMap: return t("보물지도", "Treasure Map", "たからのちず", "Mapa del Tesoro", "Carte au trésor", "Mapa do Tesouro", "Schatzkarte", "Карта сокровищ")
        case .explorerChest: return t("탐험가의 상자", "Explorer's Chest", "たんけんかのはこ", "Cofre del Explorador", "Coffre d'explorateur", "Baú do Explorador", "Forscherkiste", "Сундук исследователя")
        case .legendaryKey: return t("전설의 열쇠", "Legendary Key", "でんせつのカギ", "Llave Legendaria", "Clé Légendaire", "Chave Lendária", "Legendenschlüssel", "Легендарный ключ")
        case .battleFormsMedal:
            return t("전투 형태 메달", "Battle Forms Medal", "バトルのすがたメダル", "Medalla de Formas de combate",
                     "Médaille des Formes de combat", "Medalha das Formas de batalha", "Kampfformen-Medaille", "Медаль боевых форм")
        case .costumeMedal:
            return t("코스튬 메달", "Costume Medal", "コスチュームメダル", "Medalla de Disfraces", "Médaille des Costumés",
                     "Medalha das Fantasias", "Kostüm-Medaille", "Медаль костюмов")
        case .costumeLotsMedal:
            return t("계절 메달", "Seasons Medal", "きせつのメダル", "Medalla de Temporadas", "Médaille des Saisons",
                     "Medalha das Estações", "Jahreszeiten-Medaille", "Медаль сезонов")
        case .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal:
            let tier = dungeonTierName(kind.dungeonTier ?? .t1)
            return t("\(tier) 메달", "\(tier) Medal", "\(tier)のメダル", "Medalla \(tier)", "Médaille \(tier)", "Medalha \(tier)",
                     "\(tier)-Medaille", "Медаль: \(tier)")
        }
    }
    /// `rareCandyXP`: what a candy grants now, with the Soul Dew's +50% when owned (`CompanionStore.rareCandyXP`).
    func itemDescription(_ kind: ItemKind, rareCandyXP: Int = RareCandy.xp) -> String {
        switch kind {
        case .deoxysFormes, .wormadamCloaks, .darmanitanModes, .kyuremFusions, .genesectDrives, .gourgeistSizes, .zygardeFormes,
             .lycanrocForms, .cramorantForms, .calyrexSteeds, .squawkabillyPlumages, .tatsugiriForms, .ogerponMasks, .terapagosForms:
            return formsRewardDescription(kind)
        case .rareCandy:
            let xp = TokenFormatter.compact(rareCandyXP)   // 스토어 값에서 파생(Soul Dew 반영, 하드코딩 드리프트 방지)
            return t("현재 포켓몬의 경험치를 \(xp) 올려줘요.",
                     "Raises your Pokémon's EXP by \(xp).",
                     "ポケモンの経験値を\(xp)上げます。",
                     "Aumenta la experiencia de tu Pokémon en \(xp).",
                     "Augmente l'EXP de ton Pokémon de \(xp).",
                     "Aumenta a experiência do seu Pokémon em \(xp).",
                     "Gibt deinem aktuellen Pokémon \(xp) EP.",
                     "Увеличивает опыт покемона на \(xp).")
        case .mint:
            return t("졸업한 포켓몬의 성격을 다른 성격으로 무작위로 바꿔요.",
                     "Changes a graduated Pokémon's nature to another one, at random.",
                     "卒業したポケモンのせいかくを、ランダムに別のせいかくに変えます。",
                     "Cambia la naturaleza de un Pokémon graduado por otra, al azar.",
                     "Change au hasard la nature d'un Pokémon diplômé pour une autre.",
                     "Muda a natureza de um Pokémon formado para outra, ao acaso.",
                     "Ändert das Wesen eines verabschiedeten Pokémon zufällig in ein anderes.",
                     "Случайно меняет характер выпускника на другой.")
        case .shinyCharm:
            return t("이로치 포켓몬이 태어날 확률이 올라가요.",
                     "Raises the chance of hatching a shiny.",
                     "色違いが生まれる確率が上がります。",
                     "Aumenta la probabilidad de que nazca un Pokémon variocolor.",
                     "Augmente les chances qu'un Pokémon chromatique éclose.",
                     "Aumenta a chance de nascer um Pokémon shiny.",
                     "Erhöht die Chance, dass ein schillerndes Pokémon schlüpft.",
                     "Повышает шанс, что вылупится шайни.")
        case .legendCharm:
            return t("전설의 포켓몬이 태어날 확률이 2배가 돼요.",
                     "Doubles the chance of hatching a legendary Pokémon.",
                     "伝説のポケモンが生まれる確率が2倍になります。",
                     "Duplica la probabilidad de eclosionar un Pokémon legendario.",
                     "Double les chances de faire éclore un Pokémon légendaire.",
                     "Dobra a chance de chocar um Pokémon lendário.",
                     "Verdoppelt die Chance auf ein legendäres Pokémon.",
                     "Вдвое повышает шанс вылупления легендарного покемона.")
        case .silverWing:
            return t("모든 포켓몬이 25% 더 빨리 자라고, 알이 2배 빨리 부화합니다.",
                     "Every Pokémon grows 25% faster, and eggs hatch twice as fast.",
                     "すべてのポケモンが25%早く育ち、タマゴが2倍早くかえります。",
                     "Todos los Pokémon crecen un 25% más rápido y los huevos eclosionan el doble de rápido.",
                     "Tous tes Pokémon grandissent 25 % plus vite, et les œufs éclosent 2 fois plus vite.",
                     "Todos os Pokémon crescem 25% mais rápido e os ovos chocam 2 vezes mais rápido.",
                     "Lässt jedes Pokémon 25 % schneller wachsen und Eier doppelt so schnell schlüpfen.",
                     "Все покемоны растут на 25% быстрее, а яйца вылупляются в 2 раза быстрее.")
        case .oldSeaMap:
            return t("토큰으로 얻는 포켓몬 성장 경험치가 20% 늘어납니다.",
                     "The tokens you use grow your Pokémon 20% faster.",
                     "トークンで得るポケモンの成長経験値が20%増えます。",
                     "Los tokens que usas hacen crecer a tu Pokémon un 20% más rápido.",
                     "Les tokens que tu utilises font grandir ton Pokémon 20 % plus vite.",
                     "Os tokens que você usa fazem seu Pokémon crescer 20% mais rápido.",
                     "Lässt dein Pokémon durch verbrauchte Tokens 20 % schneller wachsen.",
                     "Токены растят покемона на 20% быстрее.")
        case .clearBell:
            return t("희귀(Rare) 등급 포켓몬이 25% 더 빨리 성장합니다.",
                     "Rare Pokémon grow 25% faster.",
                     "レアなポケモンが25%早く育ちます。",
                     "Los Pokémon raros crecen un 25% más rápido.",
                     "Les Pokémon Rares grandissent 25% plus vite.",
                     "Os Pokémon Raros crescem 25% mais rápido.",
                     "Lässt seltene Pokémon 25% schneller wachsen.",
                     "Редкие покемоны растут на 25% быстрее.")
        case .rainbowWing:
            return t("상점의 모든 상품이 25% 할인됩니다.",
                     "Everything in the Shop costs 25% less.",
                     "ショップの全商品が25%安くなります。",
                     "Todo en la tienda cuesta un 25% menos.",
                     "Tout coûte 25 % de moins dans la boutique.",
                     "Tudo na loja custa 25% menos.",
                     "Alles im Shop kostet 25 % weniger.",
                     "Всё в магазине стоит на 25% дешевле.")
        case .magmaStone:
            return t("이 모습으로 이미 졸업시킨 적 있는 라인을 육성할 때 토큰 소모가 25% 감소합니다.",
                     "Reduces token cost by 25% when raising a line you have already graduated in this form.",
                     "この姿で卒業させたことのある系統の育成トークン消費が25%減少します。",
                     "Reduce un 25% el coste de tokens al criar una línea que ya graduaste en esta forma.",
                     "Réduit le coût de 25% lors de l'élevage d'une lignée déjà diplômée sous cette forme.",
                     "Reduz em 25% o custo de tokens ao criar uma linha que você já formou nesta forma.",
                     "Reduziert die Token-Kosten um 25%, wenn eine in dieser Form bereits verabschiedete Entwicklungsreihe trainiert wird.",
                     "Снижает расход токенов на 25% при выращивании линии, которую вы уже выпускали в этой форме.")
        case .soulDew:
            return t("사탕 사용 시 얻는 경험치가 50% 증가합니다.",
                     "Boosts EXP gained from using candies by 50%.",
                     "アメ使用時の獲得EXPが50%増加します。",
                     "Aumenta un 50% la EXP obtenida al usar caramelos.",
                     "Augmente l'EXP obtenue via les bonbons de 50%.",
                     "Aumenta em 50% a EXP obtida ao usar doces.",
                     "Erhöht die durch Bonbons erhaltenen EP um 50%.",
                     "Увеличивает опыт от конфет на 50%.")
        case .jadeOrb:
            return t("알 구매 시 토큰 소모가 20% 추가 할인됩니다.",
                     "Grants an additional 20% discount on egg purchases.",
                     "タマゴ購入時の消費トークンがさらに20%割引されます。",
                     "Otorga un 20% de descuento adicional al comprar huevos.",
                     "Offre une réduction supplémentaire de 20% sur l'achat d'œufs.",
                     "Concede 20% de desconto adicional na compra de ovos.",
                     "Gewährt zusätzliche 20% Rabatt beim Kauf von Eiern.",
                     "Даёт дополнительную скидку 20% на покупку яиц.")
        case .gracidea:
            return t("진화할 포켓몬이 첫 단계에서 25% 더 빨리 성장합니다.",
                     "A Pokémon that will evolve grows 25% faster at its first stage.",
                     "進化するポケモンが最初の段階で25%早く育ちます。",
                     "Un Pokémon que evolucionará crece un 25% más rápido en su primera etapa.",
                     "Un Pokémon qui évoluera grandit 25% plus vite à son premier stade.",
                     "Um Pokémon que vai evoluir cresce 25% mais rápido no primeiro estágio.",
                     "Lässt Pokémon, die sich noch entwickeln, in ihrer ersten Stufe 25% schneller wachsen.",
                     "Покемон, который будет эволюционировать, растёт на 25% быстрее на первой стадии.")
        case .griseousOrb:
            return t("고스트·드래곤 타입 포켓몬이 30% 더 빨리 성장합니다.",
                     "Ghost- and Dragon-type Pokémon grow 30% faster.",
                     "ゴースト・ドラゴンタイプのポケモンが30%早く育ちます。",
                     "Los Pokémon de tipo Fantasma y Dragón crecen un 30% más rápido.",
                     "Les Pokémon de type Spectre et Dragon grandissent 30% plus vite.",
                     "Pokémon dos tipos Fantasma e Dragão crescem 30% mais rápido.",
                     "Lässt Geist- und Drachen-Pokémon 30% schneller wachsen.",
                     "Покемоны типов Призрак и Дракон растут на 30% быстрее.")
        case .libertyPass:
            return t("이 모습으로 한 번도 졸업시킨 적 없는 라인을 육성할 때 토큰 소모가 25% 감소합니다.",
                     "Reduces token cost by 25% when raising a line you have never graduated in this form.",
                     "この姿で一度も卒業させていない系統の育成トークン消費が25%減少します。",
                     "Reduce un 25% el coste de tokens al criar una línea que nunca graduaste en esta forma.",
                     "Réduit le coût de 25% lors de l'élevage d'une lignée jamais diplômée sous cette forme.",
                     "Reduz em 25% o custo de tokens ao criar uma linha que você nunca formou nesta forma.",
                     "Reduziert die Token-Kosten um 25%, wenn eine in dieser Form noch nie verabschiedete Entwicklungsreihe trainiert wird.",
                     "Снижает расход токенов на 25% при выращивании линии, которую вы ещё не выпускали в этой форме.")
        case .revealGlass:
            let charm = itemName(.shinyCharm)
            return t("이로치 확률이 두 배가 돼요: 64분의 1이 32분의 1로, \(charm) 보유 시 48분의 1이 24분의 1로.",
                     "Shiny odds double: 1 in 64 becomes 1 in 32, or 1 in 48 becomes 1 in 24 with the \(charm).",
                     "色違いの確率が2倍になります。64分の1が32分の1に、\(charm)と一緒なら48分の1が24分の1になります。",
                     "La probabilidad variocolor se duplica: 1 de 64 pasa a 1 de 32, o 1 de 48 a 1 de 24 con el \(charm).",
                     "Les chances de chromatique doublent : 1 sur 64 devient 1 sur 32, ou 1 sur 48 devient 1 sur 24 avec le \(charm).",
                     "A chance de shiny dobra: 1 em 64 vira 1 em 32, ou 1 em 48 vira 1 em 24 com o \(charm).",
                     "Verdoppelt die Schillerchance: aus 1 zu 64 wird 1 zu 32, mit dem \(charm) aus 1 zu 48 wird 1 zu 24.",
                     "Шанс на шайни удваивается: 1 из 64 становится 1 из 32, а с \"\(charm)\" 1 из 48 становится 1 из 24.")
        case .dnaSplicers:
            return t("토큰으로 얻는 포켓몬 성장 경험치가 50% 늘어납니다.",
                     "The tokens you use grow your Pokémon 50% faster.",
                     "トークンで得るポケモンの成長経験値が50%増えます。",
                     "Los tokens que usas hacen crecer a tu Pokémon un 50% más rápido.",
                     "Les tokens que tu utilises font grandir ton Pokémon 50 % plus vite.",
                     "Os tokens que você usa fazem seu Pokémon crescer 50% mais rápido.",
                     "Lässt dein Pokémon durch verbrauchte Tokens 50 % schneller wachsen.",
                     "Токены растят покемона на 50% быстрее.")
        case .zygardeCube:
            return t("졸업시킨 25종마다 토큰 성장 경험치가 1% 늘어납니다 (최대 +40%).",
                     "Grants +1% growth EXP from token usage for every 25 species you have graduated (up to +40%).",
                     "卒業させた25種ごとにトークンの育成経験値が1%増えます（最大+40%）。",
                     "Otorga +1% de EXP de crecimiento por tokens por cada 25 especies graduadas (hasta +40%).",
                     "+1% d'EXP de croissance via tes tokens par tranche de 25 espèces diplômées (jusqu'à +40%).",
                     "Concede +1% de EXP de crescimento por tokens a cada 25 espécies formadas (até +40%).",
                     "Gibt +1% Wachstums-EP durch Token-Verbrauch je 25 verabschiedete Arten (bis +40%).",
                     "Даёт +1% опыта роста за каждые 25 выпущенных видов (до +40%).")
        case .prisonBottle:
            return t("그 라인이 아직 모으지 못한 모습으로 태어난 포켓몬이 50% 더 빨리 성장합니다(여러 모습이 있는 종).",
                     "A Pokémon that hatched in a form its line hasn't collected yet grows 50% faster (species with alternate forms).",
                     "その系統がまだ集めていない姿で生まれたポケモンが50%早く育ちます（複数の姿がある種）。",
                     "Un Pokémon que nazca en una forma que su línea aún no reunió crece un 50% más rápido (especies con formas alternativas).",
                     "Un Pokémon éclos sous une forme que sa lignée n'a pas encore grandit 50% plus vite (espèces à plusieurs formes).",
                     "Um Pokémon que nascer numa forma que sua linha ainda não coletou cresce 50% mais rápido (espécies com formas alternativas).",
                     "Lässt Pokémon, die in einer Form schlüpfen, die ihre Entwicklungsreihe noch nicht hat, 50% schneller wachsen (Arten mit mehreren Formen).",
                     "Покемон, вылупившийся в форме, которой ещё нет у его линии, растёт на 50% быстрее (виды с несколькими формами).")
        case .sparklingStone:
            let fairy = typeName(.fairy)
            return t("\(fairy)타입 포켓몬이 30% 더 빨리 성장합니다.",
                     "\(fairy)-type Pokémon grow 30% faster.",
                     "\(fairy)タイプのポケモンが30%早く育ちます。",
                     "Los Pokémon de tipo \(fairy) crecen un 30% más rápido.",
                     "Les Pokémon de type \(fairy) grandissent 30% plus vite.",
                     "Pokémon do tipo \(fairy) crescem 30% mais rápido.",
                     "Lässt Pokémon vom Typ \(fairy) 30% schneller wachsen.",
                     "Покемоны типа \(fairy) растут на 30% быстрее.")
        case .sunFlute:
            return t("최종 진화 단계의 포켓몬이 25% 더 빨리 성장합니다.",
                     "A Pokémon at its final stage grows 25% faster.",
                     "最終進化のポケモンが25%早く育ちます。",
                     "Un Pokémon en su última etapa crece un 25% más rápido.",
                     "Un Pokémon à son dernier stade grandit 25% plus vite.",
                     "Um Pokémon no último estágio cresce 25% mais rápido.",
                     "Lässt Pokémon in ihrer letzten Stufe 25% schneller wachsen.",
                     "Покемон на последней стадии растёт на 25% быстрее.")
        case .beastBall:
            return t("울트라비스트가 50% 더 빨리 성장합니다.",
                     "Ultra Beasts grow 50% faster.",
                     "ウルトラビーストが50%早く育ちます。",
                     "Los Ultraentes crecen un 50% más rápido.",
                     "Les Ultra-Chimères grandissent 50% plus vite.",
                     "As Ultracriaturas crescem 50% mais rápido.",
                     "Lässt Ultrabestien 50% schneller wachsen.",
                     "Ультрачудовища растут на 50% быстрее.")
        case .rustedSword:
            return t("전설의 포켓몬이 25% 더 빨리 성장합니다.",
                     "Legendary Pokémon grow 25% faster.",
                     "伝説のポケモンが25%早く育ちます。",
                     "Los Pokémon legendarios crecen un 25% más rápido.",
                     "Les Pokémon légendaires grandissent 25% plus vite.",
                     "Os Pokémon lendários crescem 25% mais rápido.",
                     "Lässt legendäre Pokémon 25% schneller wachsen.",
                     "Легендарные покемоны растут на 25% быстрее.")
        case .reinsOfUnity:
            return t("일반 등급을 뺀 포켓몬이 졸업할 때마다 이상한 사탕을 1개 받습니다.",
                     "Every Pokémon that graduates gives you a Rare Candy, Common ones apart.",
                     "ノーマル以外のポケモンが卒業するたびにふしぎなアメを1個もらえます。",
                     "Recibes un Caramelo Raro cada vez que se gradúa un Pokémon que no sea Común.",
                     "Chaque Pokémon diplômé te donne un Super Bonbon, sauf les Communs.",
                     "Você recebe um Doce Raro sempre que se forma um Pokémon que não seja Comum.",
                     "Gibt für jedes verabschiedete Pokémon ein Sonderbonbon, außer für gewöhnliche.",
                     "За каждого выпущенного покемона, кроме обычных, вы получаете Редкую конфету.")
        case .boosterEnergy:
            return t("패러독스 포켓몬이 50% 더 빨리 성장합니다.",
                     "Paradox Pokémon grow 50% faster.",
                     "パラドックスポケモンが50%早く育ちます。",
                     "Los Pokémon paradójicos crecen un 50% más rápido.",
                     "Les Pokémon Paradoxe grandissent 50% plus vite.",
                     "Os Pokémon Paradoxo crescem 50% mais rápido.",
                     "Lässt paradoxe Pokémon 50% schneller wachsen.",
                     "Парадоксальные покемоны растут на 50% быстрее.")
        case .tealMask:
            let names = CollectorBonus.tealMaskTypeList.map(typeName)
            let (g, w, f, r) = (names[0], names[1], names[2], names[3])
            return t("\(g)·\(w)·\(f)·\(r) 타입 포켓몬이 20% 더 빨리 성장합니다.",
                     "\(g)-, \(w)-, \(f)- and \(r)-type Pokémon grow 20% faster.",
                     "\(g)・\(w)・\(f)・\(r)タイプのポケモンが20%早く育ちます。",
                     "Los Pokémon de tipo \(g), \(w), \(f) y \(r) crecen un 20% más rápido.",
                     "Les Pokémon de type \(g), \(w), \(f) et \(r) grandissent 20% plus vite.",
                     "Pokémon dos tipos \(g), \(w), \(f) e \(r) crescem 20% mais rápido.",
                     "Lässt Pokémon vom Typ \(g), \(w), \(f) und \(r) 20% schneller wachsen.",
                     "Покемоны типов \(g), \(w), \(f) и \(r) растут на 20% быстрее.")
        case .teraOrb:
            return t("진화의 돌로 받은 알이 2배 빨리 부화하고, 그 알에서 나온 포켓몬이 30% 더 빨리 자랍니다.",
                     "Eggs from an evolution stone hatch twice as fast, and the Pokémon from them grow 30% faster.",
                     "進化の石でもらったタマゴが2倍早くかえり、そこから生まれたポケモンが30%早く育ちます。",
                     "Los huevos obtenidos con una piedra evolutiva eclosionan el doble de rápido y sus Pokémon crecen un 30% más rápido.",
                     "Les œufs obtenus avec une pierre d'évolution éclosent 2 fois plus vite, et leurs Pokémon grandissent 30 % plus vite.",
                     "Ovos obtidos com uma pedra de evolução chocam 2 vezes mais rápido e seus Pokémon crescem 30% mais rápido.",
                     "Lässt Eier aus Entwicklungssteinen doppelt so schnell schlüpfen, und ihre Pokémon wachsen 30 % schneller.",
                     "Яйца, полученные за камень эволюции, вылупляются в 2 раза быстрее, а их покемоны растут на 30% быстрее.")
        case .ovalCharm:
            return t("아직 모으지 못한 폼이 있는 포켓몬이 그 폼으로 알에서 태어나요. 그런 계열이 없으면 다른 계열이 태어나요. 생일 알과 화석 알에는 적용되지 않아요.",
                     "Eggs hatch Pokémon with a form you are missing, in a form you don't have; when no line misses one, any other. Birthday and Fossil Eggs keep their own rules.",
                     "まだ集めていないフォルムがあるポケモンが、そのフォルムでタマゴから生まれます。そういう系統がなければほかの系統が生まれます。誕生日と化石のタマゴには効きません。",
                     "De los huevos salen Pokémon con una forma que te falta, en una forma que no tienes; si a ninguna línea le falta una, cualquier otra. No actúa en los huevos de cumpleaños ni fósiles.",
                     "Les œufs font éclore des Pokémon dont il te manque une forme, dans une forme que tu n'as pas ; quand aucune lignée n'en manque, n'importe quelle autre. Il ne joue pas sur les œufs d'anniversaire et fossiles.",
                     "Dos ovos nascem Pokémon com uma forma que falta, numa forma que você não tem; se nenhuma linha tiver forma faltando, qualquer outra. Não vale para os ovos de aniversário e fósseis.",
                     "Lässt Pokémon schlüpfen, denen dir noch eine Form fehlt, in einer Form, die du nicht hast; fehlt keiner Linie eine, dann jedes andere. Bei Geburtstags- und Fossil-Eiern wirkt es nicht.",
                     "Из яиц вылупляются покемоны с недостающей формой, в форме, которой у вас нет; если ни одной линии форма не нужна, то любые другие. На яйца дня рождения и окаменелостей не действует.")
        case .taurosBreeds:
            return t("이미 다 모은 계열(모든 종과 폼이 졸업)이 알에서 2분의 1 대신 3분의 1만큼만 나와요. 새것을 주지 않는 알이 줄어들어요. 네크로즈마의 네 가지 모습과 함께면 5분의 1이에요.",
                     "A line you have whole (every species and form graduated) hatches a third as often instead of half: fewer eggs bring nothing new. With Necrozma's Four Forms, a fifth.",
                     "すでにそろった系統（すべての種とフォルムが卒業）が、タマゴから2分の1ではなく3分の1しか生まれません。新しいものをくれないタマゴが減ります。ネクロズマの4つのすがたと合わせると5分の1です。",
                     "Una línea que ya tienes entera (todas sus especies y formas graduadas) sale de los huevos un tercio de las veces en lugar de la mitad: menos huevos sin nada nuevo. Con Las cuatro formas de Necrozma, un quinto.",
                     "Une lignée que tu as en entier (toutes ses espèces et formes diplômées) sort des œufs trois fois moins souvent au lieu de deux : moins d'œufs sans rien de nouveau. Avec Les quatre formes de Necrozma, cinq fois moins.",
                     "Uma linha que você já tem inteira (todas as espécies e formas formadas) sai dos ovos um terço das vezes em vez da metade: menos ovos sem nada novo. Com As quatro formas de Necrozma, um quinto.",
                     "Eine Linie, die du vollständig hast (alle Spezies und Formen verabschiedet), schlüpft nur noch ein Drittel statt halb so oft: weniger Eier ohne Neues. Mit Die vier Formen von Necrozma ein Fünftel.",
                     "Линия, собранная полностью (все виды и формы выпущены), вылупляется в 3 раза реже вместо 2: меньше яиц без нового. Вместе с \"Четыре формы Некрозмы\" в 5 раз реже.")
        case .necrozmaForms:
            return t("이미 다 모은 계열(모든 종과 폼이 졸업)이 알에서 2분의 1 대신 4분의 1만큼만 나와요. 새것을 주지 않는 알이 줄어들어요. 켄타로스의 네 품종과 함께면 5분의 1이에요.",
                     "A line you have whole (every species and form graduated) hatches a quarter as often instead of half: fewer eggs bring nothing new. With Tauros's Four Breeds, a fifth.",
                     "すでにそろった系統（すべての種とフォルムが卒業）が、タマゴから2分の1ではなく4分の1しか生まれません。新しいものをくれないタマゴが減ります。ケンタロスの4つの品種と合わせると5分の1です。",
                     "Una línea que ya tienes entera (todas sus especies y formas graduadas) sale de los huevos un cuarto de las veces en lugar de la mitad: menos huevos sin nada nuevo. Con Las cuatro razas de Tauros, un quinto.",
                     "Une lignée que tu as en entier (toutes ses espèces et formes diplômées) sort des œufs quatre fois moins souvent au lieu de deux : moins d'œufs sans rien de nouveau. Avec Les quatre races de Tauros, cinq fois moins.",
                     "Uma linha que você já tem inteira (todas as espécies e formas formadas) sai dos ovos um quarto das vezes em vez da metade: menos ovos sem nada novo. Com As quatro raças de Tauros, um quinto.",
                     "Eine Linie, die du vollständig hast (alle Spezies und Formen verabschiedet), schlüpft nur noch ein Viertel statt halb so oft: weniger Eier ohne Neues. Mit Die vier Rassen von Tauros ein Fünftel.",
                     "Линия, собранная полностью (все виды и формы выпущены), вылупляется в 4 раза реже вместо 2: меньше яиц без нового. Вместе с \"Четыре породы Тауроса\" в 5 раз реже.")
        case .glimmeringCharm:
            return t("알에서 태어나는 포켓몬이 모두 이로치입니다.",
                     "Every Pokémon that hatches is shiny.",
                     "タマゴから生まれるポケモンがすべて色違いになります。",
                     "Todos los Pokémon que nacen son variocolor.",
                     "Chaque Pokémon qui éclot est chromatique.",
                     "Todo Pokémon que nascer é shiny.",
                     "Lässt jedes schlüpfende Pokémon schillern.",
                     "Каждый вылупившийся покемон шайни.")
        case .typeNullEgg:
            return t("실버디의 메모리 17개를 모은 보상. 지금 포켓몬을 놓아주고 타입:널이 확정으로 태어나는 알을 받아요.",
                     "The reward for all 17 of Silvally's Memories. Send off your current Pokémon for an egg that hatches a Type: Null.",
                     "シルヴァディのメモリ17個をそろえたごほうび。いまのポケモンを手放して、タイプ：ヌルが必ず生まれるタマゴを受け取ります。",
                     "La recompensa por los 17 discos de Silvally. Suelta a tu Pokémon actual a cambio de un huevo del que saldrá Código Cero.",
                     "La récompense des 17 ROM de Silvallié. Laisse partir ton Pokémon actuel contre un œuf qui fera éclore un Type:0.",
                     "A recompensa pelas 17 Memórias de Silvally. Solte seu Pokémon atual em troca de um ovo que vai chocar um Type: Null.",
                     "Die Belohnung für alle 17 Disks von Amigento. Gib dein aktuelles Pokémon ab für ein Ei, aus dem ein Typ:Null schlüpft.",
                     "Награда за все 17 дисков Сильвалли. Отпустите текущего покемона ради яйца, из которого вылупится Тип: Ноль.")
        case .lightBall:
            let list = rewardsList(kind.achievementRewards)
            return t("피카츄의 코스튬 15벌을 모두 모은 보상. 받으면 가방에 들어와요: \(list).",
                     "The reward for all 15 of Pikachu's costumes. Claiming it puts in your Bag: \(list).",
                     "ピカチュウのコスチューム15着すべてのごほうび。受け取るとバッグに入ります：\(list)。",
                     "La recompensa por los 15 disfraces de Pikachu. Al reclamarla, recibes en tu bolsa: \(list).",
                     "La récompense des 15 costumes de Pikachu. En la réclamant, tu reçois dans ton sac : \(list).",
                     "A recompensa pelas 15 fantasias de Pikachu. Ao resgatá-la, você recebe na sua bolsa: \(list).",
                     "Die Belohnung für alle 15 Kostüme von Pikachu. Holst du sie ab, kommt in deinen Beutel: \(list).",
                     "Награда за все 15 костюмов Пикачу. Получив её, вы найдёте в сумке: \(list).")
        case .birthdayEgg:
            return t("생일 선물. 지금 포켓몬을 놓아주고 이 알을 받아요. 무엇이 태어날지는 비밀이에요.",
                     "Your birthday gift. Send off your current Pokémon for this egg. What hatches from it is a surprise.",
                     "誕生日のプレゼント。いまのポケモンを手放して、このタマゴを受け取ります。なにが生まれるかはお楽しみ。",
                     "Tu regalo de cumpleaños. Suelta a tu Pokémon actual a cambio de este huevo. Lo que saldrá de él es una sorpresa.",
                     "Ton cadeau d'anniversaire. Laisse partir ton Pokémon actuel contre cet œuf. Ce qui en sortira est une surprise.",
                     "Seu presente de aniversário. Solte seu Pokémon atual em troca deste ovo. O que vai sair dele é surpresa.",
                     "Dein Geburtstagsgeschenk. Gib dein aktuelles Pokémon für dieses Ei ab. Was daraus schlüpft, ist eine Überraschung.",
                     "Ваш подарок на день рождения. Отпустите текущего покемона ради этого яйца. Кто из него вылупится, пока секрет.")
        case .legendaryEgg:
            return t("한 지방의 포켓몬을 모두 졸업시킬 때마다 받는 보상. 지금 포켓몬을 놓아주고 전설 또는 환상의 포켓몬이 태어나는 알을 받아요.",
                     "The reward for each region whose every Pokémon has graduated. Send off your current Pokémon for an egg that hatches a legendary or mythical Pokémon.",
                     "ひとつの地方のポケモンをすべて卒業させるたびにもらえるごほうび。いまのポケモンを手放して、伝説か幻のポケモンが生まれるタマゴを受け取ります。",
                     "La recompensa por cada región cuyos Pokémon se han graduado todos. Suelta a tu Pokémon actual a cambio de un huevo del que saldrá un Pokémon legendario o singular.",
                     "La récompense de chaque région dont tous les Pokémon sont diplômés. Laisse partir ton Pokémon actuel contre un œuf qui fera éclore un Pokémon légendaire ou fabuleux.",
                     "A recompensa por cada região com todos os Pokémon formados. Solte seu Pokémon atual em troca de um ovo que vai chocar um Pokémon lendário ou mítico.",
                     "Die Belohnung für jede Region, deren Pokémon alle ihren Abschied hatten. Gib dein aktuelles Pokémon ab für ein Ei, aus dem ein legendäres oder mysteriöses Pokémon schlüpft.",
                     "Награда за каждый регион, все покемоны которого выпущены. Отпустите текущего покемона ради яйца, из которого вылупится легендарный или мифический покемон.")
        case .relicStatue:
            return t("진화하지 않는 포켓몬이 25% 더 빨리 성장합니다.",
                     "A Pokémon that does not evolve grows 25% faster.",
                     "進化しないポケモンが25%早く育ちます。",
                     "Un Pokémon que no evoluciona crece un 25% más rápido.",
                     "Un Pokémon qui n'évolue pas grandit 25% plus vite.",
                     "Um Pokémon que não evolui cresce 25% mais rápido.",
                     "Lässt Pokémon, die sich nicht entwickeln, 25% schneller wachsen.",
                     "Покемон, который не эволюционирует, растёт на 25% быстрее.")
        case .lunarWing:
            let psychic = typeName(.psychic), dark = typeName(.dark)
            return t("\(psychic)·\(dark) 타입 포켓몬이 30% 더 빨리 성장합니다.",
                     "\(psychic)- and \(dark)-type Pokémon grow 30% faster.",
                     "\(psychic)・\(dark)タイプのポケモンが30%早く育ちます。",
                     "Los Pokémon de tipo \(psychic) y \(dark) crecen un 30% más rápido.",
                     "Les Pokémon de type \(psychic) et \(dark) grandissent 30% plus vite.",
                     "Pokémon dos tipos \(psychic) e \(dark) crescem 30% mais rápido.",
                     "Lässt \(psychic)- und \(dark)-Pokémon 30% schneller wachsen.",
                     "Покемоны типов \(psychic) и \(dark) растут на 30% быстрее.")
        case .meteorite:
            return t("토큰 한도를 다 채울 때마다 이상한 사탕을 1개 더 받습니다.",
                     "Every token limit you max out gives you one more Rare Candy.",
                     "トークン上限を使い切るたびにふしぎなアメを1個多くもらえます。",
                     "Recibes un Caramelo Raro más cada vez que agotas un límite de tokens.",
                     "Chaque limite de tokens atteinte te donne un Super Bonbon de plus.",
                     "Você recebe um Doce Raro a mais sempre que esgota um limite de tokens.",
                     "Gibt für jedes ausgeschöpfte Token-Limit ein Sonderbonbon mehr.",
                     "За каждый исчерпанный лимит токенов вы получаете на одну Редкую конфету больше.")
        case .oaksLetter:
            return t("모든 지방의 스타팅 포켓몬이 어느 단계든 25% 더 빨리 성장합니다.",
                     "The starter Pokémon of every region grow 25% faster, at every stage.",
                     "すべての地方の御三家ポケモンがどの段階でも25%早く育ちます。",
                     "Los Pokémon iniciales de todas las regiones crecen un 25% más rápido, en cualquier etapa.",
                     "Les Pokémon de départ de toutes les régions grandissent 25% plus vite, à chaque stade.",
                     "Os Pokémon iniciais de todas as regiões crescem 25% mais rápido, em qualquer estágio.",
                     "Lässt die Starter-Pokémon aller Regionen in jeder Stufe 25% schneller wachsen.",
                     "Стартовые покемоны всех регионов растут на 25% быстрее на любой стадии.")
        case .seaIncense:
            return t("등급이 확정된 알(상점에서 산 알, 업적의 알)이 2배 빨리 부화하고, 그 알에서 나온 포켓몬이 30% 더 빨리 자랍니다.",
                     "Eggs of a guaranteed rarity (bought in the Shop or given by an achievement) hatch twice as fast, and the Pokémon from them grow 30% faster.",
                     "レア度が確定したタマゴ（ショップで買ったタマゴ、実績のタマゴ）が2倍早くかえり、そこから生まれたポケモンが30%早く育ちます。",
                     "Los huevos de rareza garantizada (comprados en la tienda o de un logro) eclosionan el doble de rápido y sus Pokémon crecen un 30% más rápido.",
                     "Les œufs à rareté garantie (achetés en boutique ou offerts par un succès) éclosent 2 fois plus vite, et leurs Pokémon grandissent 30 % plus vite.",
                     "Ovos de raridade garantida (comprados na loja ou de uma conquista) chocam 2 vezes mais rápido e seus Pokémon crescem 30% mais rápido.",
                     "Lässt Eier mit garantierter Seltenheit (aus dem Laden oder von einem Erfolg) doppelt so schnell schlüpfen, und ihre Pokémon wachsen 30 % schneller.",
                     "Яйца гарантированной редкости (из магазина или за достижение) вылупляются в 2 раза быстрее, а их покемоны растут на 30% быстрее.")
        case .shockDrive:
            let candy = itemName(.rareCandy), n = CollectorBonus.shockDriveRechargeOneIn
            return t("\(candy) 하나를 쓸 때마다 \(n)번에 1번은 그 사탕이 가방에 그대로 남아요.",
                     "Each \(candy) you use has 1 chance in \(n) to stay in your Bag.",
                     "\(candy)を使うたびに\(n)回に1回はそのアメがバッグに残ります。",
                     "Cada \(candy) que usas tiene 1 posibilidad entre \(n) de quedarse en tu bolsa.",
                     "Chaque \(candy) utilisé a 1 chance sur \(n) de rester dans ton sac.",
                     "Cada \(candy) usado tem 1 chance em \(n) de continuar na sua bolsa.",
                     "Jedes verwendete \(candy) bleibt mit einer Chance von 1 zu \(n) im Beutel.",
                     "Каждая использованная \"\(candy)\" с шансом 1 из \(n) остаётся в сумке.")
        case .zRing:
            let steel = typeName(.steel), electric = typeName(.electric)
            return t("\(steel)·\(electric) 타입 포켓몬이 30% 더 빨리 성장합니다.",
                     "\(steel)- and \(electric)-type Pokémon grow 30% faster.",
                     "\(steel)・\(electric)タイプのポケモンが30%早く育ちます。",
                     "Los Pokémon de tipo \(steel) y \(electric) crecen un 30% más rápido.",
                     "Les Pokémon de type \(steel) et \(electric) grandissent 30% plus vite.",
                     "Pokémon dos tipos \(steel) e \(electric) crescem 30% mais rápido.",
                     "Lässt \(steel)- und \(electric)-Pokémon 30% schneller wachsen.",
                     "Покемоны типов \(steel) и \(electric) растут на 30% быстрее.")
        case .scrollOfDarkness:
            let fighting = typeName(.fighting)
            return t("\(fighting)타입 포켓몬이 30% 더 빨리 성장합니다.",
                     "\(fighting)-type Pokémon grow 30% faster.",
                     "\(fighting)タイプのポケモンが30%早く育ちます。",
                     "Los Pokémon de tipo \(fighting) crecen un 30% más rápido.",
                     "Les Pokémon de type \(fighting) grandissent 30% plus vite.",
                     "Pokémon do tipo \(fighting) crescem 30% mais rápido.",
                     "Lässt Pokémon vom Typ \(fighting) 30% schneller wachsen.",
                     "Покемоны типа \(fighting) растут на 30% быстрее.")
        case .relicVase:
            return t("중간 진화 단계의 포켓몬이 25% 더 빨리 성장합니다.",
                     "A Pokémon at its middle stage grows 25% faster.",
                     "中間の進化段階のポケモンが25%早く育ちます。",
                     "Un Pokémon en su etapa intermedia crece un 25% más rápido.",
                     "Un Pokémon à son stade intermédiaire grandit 25% plus vite.",
                     "Um Pokémon no estágio intermediário cresce 25% mais rápido.",
                     "Lässt Pokémon in ihrer mittleren Stufe 25% schneller wachsen.",
                     "Покемон на промежуточной стадии растёт на 25% быстрее.")
        case .explorerKit:
            let candy = itemName(.rareCandy), uncommon = eggName(.uncommon), rare = eggName(.rare)
            let legendary = itemName(.legendaryEgg), n = ExplorerKit.graduationsPerTreasure
            return t("포켓몬을 \(n)마리 졸업시킬 때마다 보물을 하나 발굴해요: 대개 \(candy), 가끔 \(uncommon)이나 \(rare), 아주 드물게 \(legendary).",
                     "Every \(n) Pokémon you graduate dig up a treasure: mostly a \(candy), sometimes an \(uncommon) or a \(rare) and, very rarely, a \(legendary).",
                     "ポケモンを\(n)匹卒業させるたびに宝物を1つ掘り当てます：たいてい\(candy)、ときどき\(uncommon)か\(rare)、ごくまれに\(legendary)。",
                     "Cada \(n) Pokémon que gradúas desentierran un tesoro: casi siempre un \(candy), a veces un \(uncommon) o un \(rare) y, muy rara vez, un \(legendary).",
                     "Tous les \(n) Pokémon diplômés, tu déterres un trésor : le plus souvent un \(candy), parfois un \(uncommon) ou un \(rare) et, très rarement, un \(legendary).",
                     "A cada \(n) Pokémon que você forma, você desenterra um tesouro: quase sempre um \(candy), às vezes um \(uncommon) ou um \(rare) e, muito raramente, um \(legendary).",
                     "Alle \(n) verabschiedeten Pokémon gräbst du einen Schatz aus: meist ein \(candy), manchmal ein \(uncommon) oder ein \(rare) und, sehr selten, ein \(legendary).",
                     "Каждые \(n) выпущенных покемонов приносят сокровище: чаще всего \"\(candy)\", иногда \"\(uncommon)\" или \"\(rare)\" и, очень редко, \"\(legendary)\".")
        case .oldAmber:
            return t("알과 바꾸려고 놓아준 포켓몬이 지금 단계에서 쌓은 경험치의 절반을 새로 태어나는 포켓몬에게 넘겨줘요. 태어나자마자 진화하지는 않아요.",
                     "A Pokémon you send off for an egg gives half the EXP of its stage to the Pokémon that hatches, short of evolving it at once.",
                     "タマゴと引き換えに手放したポケモンが今の段階でためた経験値の半分を、生まれるポケモンに引き継ぎます。生まれてすぐ進化はしません。",
                     "Un Pokémon que sueltas por un huevo da la mitad de la experiencia de su etapa al Pokémon que nace, sin que evolucione nada más nacer.",
                     "Un Pokémon que tu laisses partir contre un œuf donne la moitié de l'expérience de son stade au Pokémon qui éclot, sans le faire évoluer dès l'éclosion.",
                     "Um Pokémon que você solta por um ovo passa metade da experiência do estágio dele ao Pokémon que nasce, sem fazê-lo evoluir ao nascer.",
                     "Ein Pokémon, das du für ein Ei abgibst, gibt die Hälfte der Erfahrung seiner Stufe an das Pokémon weiter, das schlüpft, ohne dass es sich gleich entwickelt.",
                     "Покемон, отпущенный ради яйца, передаёт половину опыта своей стадии покемону, который вылупится, но тот не эволюционирует сразу.")
        case .legendPlate:
            let rare = eggName(.rare), uncommon = eggName(.uncommon)
            return t("아르세우스의 보상. 받으면 가방에 \(rare)과 \(uncommon)이 하나씩 들어와요.",
                     "Arceus's reward: claiming it puts a \(rare) and an \(uncommon) in your Bag.",
                     "アルセウスのごほうび。受け取ると\(rare)と\(uncommon)が1個ずつバッグに入ります。",
                     "La recompensa de Arceus: al reclamarla, recibes un \(rare) y un \(uncommon) en tu bolsa.",
                     "La récompense d'Arceus : en la réclamant, tu reçois un \(rare) et un \(uncommon) dans ton sac.",
                     "A recompensa de Arceus: ao resgatá-la, você recebe um \(rare) e um \(uncommon) na sua bolsa.",
                     "Arceus' Belohnung: Holst du sie ab, kommen ein \(rare) und ein \(uncommon) in deinen Beutel.",
                     "Награда Арсеуса: получив её, вы найдёте в сумке \"\(rare)\" и \"\(uncommon)\".")
        case .excavation:
            return t("바위 타입 포켓몬을 4종 졸업시킬 때마다 화석 알을 하나 발굴해요(진화 단계마다 한 종으로 세요). 알에서는 아직 졸업하지 않은 화석 계열이 태어나요. 화석 계열은 이 알과 우정 기념 알에서만 태어나고, 졸업한 뒤에는 모든 알에서 나올 수 있어요.",
                     "Every 4 Rock-type species you graduate dig up a Fossil Egg (each stage of a line counts as a species). It hatches a fossil line you haven't graduated yet: a fossil line hatches only from these eggs and the Friendship Egg, then from any egg once graduated.",
                     "いわタイプのポケモンを4種卒業させるたびに化石のタマゴを1つ発掘します（進化の段階ごとに1種と数えます）。まだ卒業していない化石の系統が生まれます。化石の系統はこのタマゴとなかよし記念のタマゴからしか生まれず、卒業したあとはどのタマゴからも生まれます。",
                     "Cada 4 especies de tipo Roca que gradúas desentierran un Huevo Fósil (cada etapa de una línea cuenta como una especie). De él nace una línea fósil que aún no has graduado: una línea fósil solo nace de estos huevos y del Huevo de la Amistad y, una vez graduada, de cualquier huevo.",
                     "Toutes les 4 espèces de type Roche que tu diplômes, tu déterres un Œuf fossile (chaque stade d'une lignée compte comme une espèce). Il fait éclore une lignée fossile pas encore diplômée : une lignée fossile n'éclot que de ces œufs et de l'Œuf de l'amitié, puis de tous les œufs une fois diplômée.",
                     "A cada 4 espécies do tipo Pedra que você forma, você desenterra um Ovo Fóssil (cada estágio de uma linha conta como uma espécie). Dele nasce uma linha fóssil que você ainda não formou: uma linha fóssil só nasce desses ovos e do Ovo da Amizade e, depois de formada, de qualquer ovo.",
                     "Alle 4 Gestein-Arten, die du verabschiedest, gräbst du ein Fossil-Ei aus (jede Stufe einer Linie zählt als eine Art). Daraus schlüpft eine Fossil-Linie, die du noch nicht verabschiedet hast: Eine Fossil-Linie schlüpft nur aus diesen Eiern und dem Freundschafts-Ei, nach ihrem Abschied dann aus jedem Ei.",
                     "Каждые 4 выпущенных вида каменного типа приносят Яйцо-окаменелость (каждая стадия линии считается видом). Из него вылупляется ещё не выпущенная линия окаменелостей: такая линия вылупляется только из этих яиц и Яйца дружбы, а после выпуска из любых яиц.")
        case .fossilEgg:
            return t("지금 포켓몬을 놓아주고 이 알을 받아요. 아직 졸업하지 않은 화석 계열의 포켓몬이 무작위로 태어나고, 모든 계열을 졸업했다면 아무 화석 계열이나 태어나요.",
                     "Send off your current Pokémon for it: it hatches, at random, a fossil Pokémon of a line you haven't graduated yet, or of any fossil line once all are graduated.",
                     "いまのポケモンを手放してこのタマゴにします。まだ卒業していない化石の系統のポケモンがランダムに生まれ、すべて卒業していればどの化石の系統でも生まれます。",
                     "Suelta a tu Pokémon actual por él: nace al azar un Pokémon fósil de una línea que aún no has graduado, o de cualquier línea fósil si ya las graduaste todas.",
                     "Laisse partir ton Pokémon actuel contre lui : il fait éclore au hasard un Pokémon fossile d'une lignée pas encore diplômée, ou de n'importe quelle lignée fossile une fois toutes diplômées.",
                     "Solte seu Pokémon atual por ele: nasce ao acaso um Pokémon fóssil de uma linha ainda não formada, ou de qualquer linha fóssil quando todas estiverem formadas.",
                     "Gib dein aktuelles Pokémon dafür ab: Daraus schlüpft zufällig ein Fossil-Pokémon einer noch nicht verabschiedeten Linie, oder jeder Fossil-Linie, sobald alle verabschiedet sind.",
                     "Отпустите текущего покемона ради него: из него вылупится случайный покемон-окаменелость из ещё не выпущенной линии, а когда выпущены все, из любой.")
        case .rotomCatalog:
            return t("그 진화 라인이 아직 졸업시킨 적 없는 폼으로 졸업한 포켓몬마다 이상한 사탕을 1개 받습니다.",
                     "Every Pokémon that graduates in a form its line had never graduated gives you one Rare Candy.",
                     "その進化ラインがまだ卒業させていないフォルムで卒業したポケモンごとにふしぎなアメを1個もらえます。",
                     "Cada Pokémon que se gradúa en una forma que su línea nunca había graduado te da un Caramelo Raro.",
                     "Chaque Pokémon diplômé dans une forme que sa lignée n'avait jamais diplômée te donne un Super Bonbon.",
                     "Cada Pokémon que se forma numa forma que sua linha nunca tinha formado te dá um Doce Raro.",
                     "Gibt für jedes Pokémon, das in einer Form verabschiedet wird, die seine Linie noch nie verabschiedet hat, ein Sonderbonbon.",
                     "За каждого покемона, выпущенного в форме, которую его линия ещё не выпускала, вы получаете Редкую конфету.")
        case .cometShard, .redNectar, .smoothRock, .sawsbuckSeasons, .fairyFeather, .furfrouTrims, .vivillonPatterns,
             .whippedDream, .unownLetters:
            return formsRewardDescription(kind)
        case .pokemonEgg: return eggDescription(nil)
        case .uncommonEgg: return eggDescription(.uncommon)
        case .rareEgg: return eggDescription(.rare)
        case .newYearEgg, .valentineEgg, .pokemonDayEgg, .easterEgg, .halloweenEgg, .christmasEgg, .companionEgg, .springEgg, .summerEgg, .autumnEgg, .winterEgg:
            return EventEgg(item: kind).map(eventEggDescription) ?? ""
        case .boulderBadge, .cascadeBadge, .thunderBadge, .rainbowBadge,
             .soulBadge, .marshBadge, .volcanoBadge, .earthBadge,
             .zephyrBadge, .hiveBadge, .plainBadge, .fogBadge,
             .stormBadge, .mineralBadge, .glacierBadge, .risingBadge,
             .darkBadge, .fairyBadge:
            let step = percentNumber(CollectorBonus.badgeRegionBonus * 100)
            // No type is weak to Normal: the Plain Badge boosts Normal-type Pokémon (`PokemonTypeData.isWeak`).
            if kind == .plainBadge {
                return t("지방마다 그 타입의 포켓몬을 모두 등록하면, 노말타입 포켓몬이 \(step)% 더 빨리 성장합니다(노말에 약한 타입은 없어요).",
                         "Each region claimed makes Normal-type Pokémon grow \(step)% faster (no type is weak to Normal).",
                         "地方ごとにそのタイプのポケモンをすべて登録すると、ノーマルタイプのポケモンが\(step)%早く育ちます(ノーマルに弱いタイプはありません)。",
                         "Cada región reclamada hace que los Pokémon de tipo Normal crezcan un \(step)% más rápido (ningún tipo es débil al Normal).",
                         "Chaque région réclamée fait grandir les Pokémon de type Normal \(step) % plus vite (aucun type n'est faible contre le Normal).",
                         "Cada região resgatada faz os Pokémon do tipo Normal crescerem \(step)% mais rápido (nenhum tipo é vulnerável a Normal).",
                         "Jede beanspruchte Region lässt Pokémon vom Typ Normal \(step)% schneller wachsen (kein Typ ist schwach gegen Normal).",
                         "Каждый полученный регион ускоряет рост покемонов обычного типа на \(step)% (ни один тип не уязвим к обычному).")
            }
            return t("지방마다 그 타입의 포켓몬을 모두 등록하면, 그 타입이 약점인 포켓몬이 \(step)% 더 빨리 성장합니다.",
                     "Each region claimed makes Pokémon weak to this type grow \(step)% faster.",
                     "地方ごとにそのタイプのポケモンをすべて登録すると、そのタイプが弱点のポケモンが\(step)%早く育ちます。",
                     "Cada región reclamada hace que los Pokémon débiles a este tipo crezcan un \(step)% más rápido.",
                     "Chaque région réclamée fait grandir les Pokémon faibles contre ce type \(step) % plus vite.",
                     "Cada região resgatada faz os Pokémon vulneráveis a este tipo crescerem \(step)% mais rápido.",
                     "Jede beanspruchte Region lässt Pokémon mit dieser Schwäche \(step)% schneller wachsen.",
                     "Каждый полученный регион ускоряет рост покемонов, уязвимых к этому типу, на \(step)%.")
        case .leafStone, .fireStone, .waterStone, .thunderStone,
             .sunStone, .moonStone, .iceStone, .duskStone,
             .dawnStone, .shinyStone:
            let type = kind.stoneType.map(typeName) ?? ""
            return t("지금 포켓몬을 놓아주고, \(type)타입 포켓몬이 확정으로 태어나는 알을 받아요.",
                     "Send off your current Pokémon for an egg guaranteed to hatch a \(type)-type Pokémon.",
                     "いまのポケモンを手放して、\(type)タイプのポケモンが必ず生まれるタマゴを受け取ります。",
                     "Suelta a tu Pokémon actual a cambio de un huevo del que saldrá seguro un Pokémon de tipo \(type).",
                     "Laisse partir ton Pokémon actuel contre un œuf qui fera éclore à coup sûr un Pokémon de type \(type).",
                     "Solte seu Pokémon atual em troca de um ovo que com certeza vai chocar um Pokémon do tipo \(type).",
                     "Verabschiede dein aktuelles Pokémon für ein Ei, aus dem garantiert ein Pokémon vom Typ \(type) schlüpft.",
                     "Отпустите текущего покемона и получите яйцо, из которого гарантированно вылупится покемон типа \"\(type)\".")
        case .greatBall:
            return t("던전 보스를 잡을 확률이 1.5배가 돼요.", "Raises the odds of catching a dungeon's boss 1.5 times.",
                     "ダンジョンのボスを捕まえる確率が1.5倍になります。", "Multiplica por 1,5 la probabilidad de atrapar al jefe de una mazmorra.",
                     "Multiplie par 1,5 les chances de capturer le boss d'un donjon.", "Multiplica por 1,5 a chance de capturar o chefe de uma masmorra.",
                     "Erhöht die Chance, den Boss eines Dungeons zu fangen, um das 1,5-Fache.", "Увеличивает шанс поймать босса подземелья в 1,5 раза.")
        case .ultraBall:
            return t("던전 보스를 잡을 확률이 2배가 돼요.", "Doubles the odds of catching a dungeon's boss.",
                     "ダンジョンのボスを捕まえる確率が2倍になります。", "Duplica la probabilidad de atrapar al jefe de una mazmorra.",
                     "Double les chances de capturer le boss d'un donjon.", "Dobra a chance de capturar o chefe de uma masmorra.",
                     "Verdoppelt die Chance, den Boss eines Dungeons zu fangen.", "Удваивает шанс поймать босса подземелья.")
        case .masterBall:
            return t("던전 보스를 반드시 잡아요.", "Catches a dungeon's boss for sure.", "ダンジョンのボスを必ず捕まえます。",
                     "Atrapa seguro al jefe de una mazmorra.", "Capture à coup sûr le boss d'un donjon.",
                     "Captura com certeza o chefe de uma masmorra.", "Fängt den Boss eines Dungeons garantiert.",
                     "Гарантированно ловит босса подземелья.")
        case .oranBerry:
            return t("던전에서 HP가 절반 아래로 떨어진 포켓몬이 먹고 HP를 25% 회복해요.",
                     "In a dungeon, a Pokémon under half its HP eats it and gets back 25% of its HP.",
                     "ダンジョンでHPが半分を切ったポケモンが食べ、HPを25%回復します。",
                     "En una mazmorra, un Pokémon por debajo de la mitad de sus PS se la come y recupera el 25 % de sus PS.",
                     "En donjon, un Pokémon sous la moitié de ses PV la mange et récupère 25 % de ses PV.",
                     "Na masmorra, um Pokémon abaixo da metade dos PS a come e recupera 25% dos PS.",
                     "Im Dungeon isst ein Pokémon unter der Hälfte seiner KP sie und erhält 25 % seiner KP zurück.",
                     "В подземелье покемон с меньше чем половиной ОЗ съедает её и восстанавливает 25% ОЗ.")
        case .sitrusBerry:
            return t("던전에서 HP가 절반 아래로 떨어진 포켓몬이 먹고 HP를 50% 회복해요.",
                     "In a dungeon, a Pokémon under half its HP eats it and gets back 50% of its HP.",
                     "ダンジョンでHPが半分を切ったポケモンが食べ、HPを50%回復します。",
                     "En una mazmorra, un Pokémon por debajo de la mitad de sus PS se la come y recupera el 50 % de sus PS.",
                     "En donjon, un Pokémon sous la moitié de ses PV la mange et récupère 50 % de ses PV.",
                     "Na masmorra, um Pokémon abaixo da metade dos PS a come e recupera 50% dos PS.",
                     "Im Dungeon isst ein Pokémon unter der Hälfte seiner KP sie und erhält 50 % seiner KP zurück.",
                     "В подземелье покемон с меньше чем половиной ОЗ съедает её и восстанавливает 50% ОЗ.")
        case .revive:
            return t("던전에서 기절한 포켓몬을 전투 후 HP 절반으로 되살려요.",
                     "In a dungeon, gets a knocked-out Pokémon back up after the battle, with half its HP.",
                     "ダンジョンでひんしのポケモンを戦いのあとHP半分で復活させます。",
                     "En una mazmorra, reanima tras el combate a un Pokémon debilitado con la mitad de sus PS.",
                     "En donjon, relève un Pokémon K.O. après le combat avec la moitié de ses PV.",
                     "Na masmorra, reanima após a batalha um Pokémon desmaiado com metade dos PS.",
                     "Belebt im Dungeon nach dem Kampf ein besiegtes Pokémon mit der Hälfte seiner KP wieder.",
                     "В подземелье после боя поднимает покемона без сознания с половиной ОЗ.")
        case .maxRevive:
            return t("던전에서 기절한 포켓몬을 전투 후 HP를 모두 채워 되살려요.",
                     "In a dungeon, gets a knocked-out Pokémon back up after the battle, with all its HP.",
                     "ダンジョンでひんしのポケモンを戦いのあとHP満タンで復活させます。",
                     "En una mazmorra, reanima tras el combate a un Pokémon debilitado con todos sus PS.",
                     "En donjon, relève un Pokémon K.O. après le combat avec tous ses PV.",
                     "Na masmorra, reanima após a batalha um Pokémon desmaiado com todos os PS.",
                     "Belebt im Dungeon nach dem Kampf ein besiegtes Pokémon mit allen KP wieder.",
                     "В подземелье после боя поднимает покемона без сознания со всеми ОЗ.")
        case .silverCapsule:
            return t("졸업한 포켓몬의 개체값 하나를 31로 올려요.", "Raises one IV of a graduated Pokémon to 31.",
                     "卒業したポケモンの個体値をひとつ31にします。", "Sube a 31 un IV de un Pokémon graduado.",
                     "Monte un IV d'un Pokémon diplômé à 31.", "Sobe um IV de um Pokémon formado para 31.",
                     "Hebt einen DV eines verabschiedeten Pokémon auf 31.", "Поднимает один IV выпускника до 31.")
        case .goldCapsule:
            return t("졸업한 포켓몬의 모든 개체값을 31로 올려요.", "Raises every IV of a graduated Pokémon to 31.",
                     "卒業したポケモンの個体値をすべて31にします。", "Sube a 31 todos los IV de un Pokémon graduado.",
                     "Monte tous les IV d'un Pokémon diplômé à 31.", "Sobe todos os IVs de um Pokémon formado para 31.",
                     "Hebt alle DV eines verabschiedeten Pokémon auf 31.", "Поднимает все IV выпускника до 31.")
        case .treasureMap:
            return t("알프의 유적을 한 번 열어요. 규칙과 보스는 무작위예요.",
                     "Opens the Ruins of Alph once, with rules and a boss drawn at random.",
                     "アルフのいせきを一度だけ開きます。ルールとボスはランダムです。",
                     "Abre una vez las Ruinas Alfa, con reglas y jefe al azar.",
                     "Ouvre une fois les Ruines d'Alpha, aux règles et au boss tirés au hasard.",
                     "Abre uma vez as Ruínas de Alfa, com regras e chefe sorteados.",
                     "Öffnet die Alph-Ruinen einmal, mit zufälligen Regeln und Boss.",
                     "Открывает Руины Альфа один раз, правила и босс случайны.")
        case .explorerChest:
            let kit = itemName(.explorerKit)
            return t("\(kit)의 보물 하나를 무작위로 줘요.", "Gives one of the \(kit)'s treasures, at random.",
                     "\(kit)のおたからをひとつランダムにくれます。", "Da uno de los tesoros del \(kit), al azar.",
                     "Donne un des trésors du \(kit), au hasard.", "Dá um dos tesouros do \(kit), ao acaso.",
                     "Gibt einen zufälligen Schatz des \(kit).", "Даёт одно из сокровищ предмета \"\(kit)\" наугад.")
        case .battleFormsMedal:
            return t("오늘의 던전과 이번 주 던전에서 전투 형태를 얻으세요: 5, 15, 30, 60, 100개와 전부에서 보상.",
                     "Win battle forms in the daily and weekly dungeons: a reward at 5, 15, 30, 60, 100 and all of them.",
                     "今日と今週のダンジョンでバトルのすがたを手に入れよう：5、15、30、60、100、全部でごほうび。",
                     "Gana formas de combate en las mazmorras del día y de la semana: premio a las 5, 15, 30, 60, 100 y todas.",
                     "Gagne des formes de combat dans les donjons du jour et de la semaine : une récompense à 5, 15, 30, 60, 100 et toutes.",
                     "Ganhe formas de batalha nas masmorras do dia e da semana: prêmio com 5, 15, 30, 60, 100 e todas.",
                     "Gewinne Kampfformen in den Tages- und Wochen-Dungeons: eine Belohnung bei 5, 15, 30, 60, 100 und allen.",
                     "Получайте боевые формы в подземельях дня и недели: награда за 5, 15, 30, 60, 100 и все.")
        case .costumeMedal:
            return t("포켓몬 GO의 코스튬 포켓몬을 모으세요: 25, 50, 100마리와 전부에서 보상.",
                     "Collect Pokémon GO's costumed Pokémon: a reward at 25, 50, 100 and all of them.",
                     "ポケモンGOのコスチュームのポケモンを集めよう：25、50、100、全部でごほうび。",
                     "Reúne los Pokémon disfrazados de Pokémon GO: premio a los 25, 50, 100 y todos.",
                     "Collectionne les Pokémon costumés de Pokémon GO : une récompense à 25, 50, 100 et tous.",
                     "Junte os Pokémon fantasiados do Pokémon GO: prêmio aos 25, 50, 100 e todos.",
                     "Sammle die kostümierten Pokémon aus Pokémon GO: eine Belohnung bei 25, 50, 100 und allen.",
                     "Собирай покемонов в костюмах из Pokémon GO: награда за 25, 50, 100 и всех.")
        case .costumeLotsMedal:
            return t("한 달 코스튬 묶음을 다 모을 때마다 보상, 12개 모두 모으면 전설의 알.",
                     "A reward for each month's costumes all collected, a Legendary Egg for the twelfth.",
                     "ひと月のコスチュームをぜんぶ集めるたびにごほうび、12か月目でデンセツのタマゴ。",
                     "Un premio por cada mes de disfraces completo, un Huevo Legendario por el duodécimo.",
                     "Une récompense pour chaque mois de costumés complet, un Œuf légendaire pour le douzième.",
                     "Um prêmio por cada mês de fantasias completo, um Ovo Lendário pelo décimo segundo.",
                     "Eine Belohnung für jeden vollständigen Kostüm-Monat, ein legendäres Ei für den zwölften.",
                     "Награда за каждый полностью собранный месяц костюмов, легендарное яйцо за двенадцатый.")
        case .discoveryMedal, .adventureMedal, .expertMedal, .legendsMedal, .originMedal:
            let tier = kind.dungeonTier ?? .t1
            let n = tier.rawValue
            if DungeonMedals.dungeons(tier).count == 1 {
                return t("T\(n) 던전을 한 번 이기면 보상을 받아요.", "Win the T\(n) dungeon once for a reward.",
                         "T\(n)のダンジョンに一度勝つとごほうび。", "Gana una vez la mazmorra T\(n) para una recompensa.",
                         "Gagne une fois le donjon T\(n) pour une récompense.",
                         "Vença uma vez a masmorra T\(n) para uma recompensa.",
                         "Gewinne den T\(n)-Dungeon einmal für eine Belohnung.",
                         "Пройди подземелье T\(n) один раз, чтобы получить награду.")
            }
            return t("T\(n)의 던전을 각각 한 번씩 이기세요. 던전마다 보상, 전부 이기면 하나 더.",
                     "Win each T\(n) dungeon once: a reward per dungeon, one more for them all.",
                     "T\(n)の各ダンジョンに一度ずつ勝とう。ダンジョンごとにごほうび、全部でもう1つ。",
                     "Gana una vez cada mazmorra T\(n): una recompensa por mazmorra y otra por todas.",
                     "Gagne une fois chaque donjon T\(n) : une récompense par donjon, une de plus pour tous.",
                     "Vença cada masmorra T\(n) uma vez: uma recompensa por masmorra e mais uma por todas.",
                     "Gewinne jeden T\(n)-Dungeon einmal: eine Belohnung pro Dungeon, eine weitere für alle.",
                     "Пройди каждое подземелье T\(n) один раз: награда за каждое и ещё одна за все.")
        case .legendaryKey:
            return t("T4 던전이나 시작의 방에 한 번 들어가요. 들어갈 때 사라지고, 져도 돌아오지 않아요.",
                     "Opens a T4 dungeon or the Hall of Origin once: spent at the entry, kept by the dungeon even after a defeat.",
                     "T4のダンジョンかはじまりのまに一度入れます。入るときに使い、負けても戻りません。",
                     "Abre una vez una mazmorra T4 o la Sala del Origen: se gasta al entrar, aunque se pierda.",
                     "Ouvre une fois un donjon T4 ou la Salle Originelle : dépensée à l'entrée, perdue même en cas de défaite.",
                     "Abre uma vez uma masmorra T4 ou o Salão da Origem: gasta na entrada, perdida mesmo em caso de derrota.",
                     "Öffnet einmal einen T4-Dungeon oder den Saal des Ursprungs: beim Betreten verbraucht, auch bei einer Niederlage.",
                     "Открывает подземелье T4 или Зал Истоков один раз: тратится на входе, даже при поражении.")
        }
    }

    /// 가방 사용 컨트롤의 효과 힌트 — 민트("성격 랜덤 변경", 사탕의 "+XP" 자리).
    var mintEffectHint: String { t("성격 랜덤 변경", "Random nature", "せいかくランダム変更", "Naturaleza aleatoria", "Nature aléatoire", "Natureza aleatória", "Zufälliges Wesen", "Случайный характер") }

    func stoneConfirm(_ monName: String, _ stoneName: String) -> String {
        t("\(KoreanParticle.object.attach(to: monName)) 놓아주고 \(KoreanParticle.object.attach(to: stoneName)) 사용할까요?",
          "Send off \(monName) and use \(stoneName)?",
          "\(monName) を手放して \(stoneName) を使いますか？",
          "¿Soltar a \(monName) y usar \(stoneName)?",
          "Laisser partir \(monName) et utiliser \(stoneName) ?",
          "Soltar \(monName) e usar \(stoneName)?",
          "\(monName) verabschieden und \(stoneName) einsetzen?",
          "Отпустить \(monName) и использовать \(stoneName)?")
    }
    /// 인큐베이션 중 표시하는 타입 보증 배지: 진화의 돌로 품은 알의 확정 타입.
    func eggTypeGuaranteeHint(_ type: PokemonType) -> String {
        let name = typeName(type)
        return t("\(name)타입 확정", "Guaranteed \(name)", "\(name)タイプ確定", "\(name) garantizado", "\(name) garanti", "\(name) garantido", "Garantiert \(name)", "Гарантированный тип: \(name)")
    }

    // MARK: 상점 (재화 = 사용한 토큰)
    var shop: String { t("상점", "Shop", "ショップ", "Tienda", "Boutique", "Loja", "Laden", "Магазин") }
    var spendableTokens: String { t("쓸 수 있는 토큰", "Spendable tokens", "使えるトークン", "Tokens disponibles", "Tokens disponibles", "Tokens disponíveis", "Verfügbare Tokens", "Доступно токенов") }

    // MARK: Prof. Oak's advice (Shop)
    var oakAdviceTitle: String {
        t("오박사의 조언", "Prof. Oak's advice", "オーキド博士のアドバイス", "Consejos del Profesor Oak", "Conseils du Prof. Chen",
          "Conselhos do Prof. Carvalho", "Tipps von Prof. Eich", "Советы профессора Оука")
    }
    // MARK: The travelling merchant (2026-11-09)

    var merchantTitle: String {
        t("떠돌이 상인", "Travelling merchant", "旅の商人", "Mercader ambulante", "Marchand ambulant", "Mercador ambulante",
          "Fahrender Händler", "Странствующий торговец")
    }
    /// His words in his bubble: the ware and what he pays for one.
    func merchantOffer(_ item: String, price: String) -> String {
        t("오늘 매입: \(item), 개당 \(price)", "Today I buy back: \(item), \(price) each.",
          "本日の買い取り：\(item)、1個 \(price)", "Hoy compro: \(item), a \(price) cada uno.",
          "Aujourd'hui je rachète : \(item), \(price) l'unité.", "Hoje eu compro: \(item), \(price) cada.",
          "Heute kaufe ich: \(item), \(price) pro Stück.", "Сегодня покупаю: \"\(item)\", по \(price) за штуку.")
    }
    func merchantHeld(_ count: Int) -> String {
        t("\(count)개 있어요.", "You have \(count).", "\(count)個持っています。", "Tienes \(count).", "Tu en as \(count).",
          "Você tem \(count).", "Du hast \(count).", "У вас \(count) шт.")
    }
    var merchantNoneHeld: String {
        t("가방에 없어요. 다음에 또 올게요.", "You have none. I will come by another day.", "持っていませんね。また別の日に来ます。",
          "No tienes ninguno. Volveré otro día.", "Tu n'en as pas. Je repasserai un autre jour.", "Você não tem nenhum. Volto outro dia.",
          "Du hast keins. Ich komme an einem anderen Tag wieder.", "У вас их нет. Загляну в другой день.")
    }
    var merchantSellOne: String { t("1개 팔기", "Sell 1", "1個売る", "Vender 1", "Vendre 1", "Vender 1", "1 verkaufen", "Продать 1") }
    func merchantSellAll(_ count: Int) -> String {
        t("모두 팔기 (\(count))", "Sell all (\(count))", "すべて売る（\(count)）", "Vender todo (\(count))", "Tout vendre (\(count))",
          "Vender tudo (\(count))", "Alle verkaufen (\(count))", "Продать все (\(count))")
    }
    /// The second press of "Sell all", the total on it: nothing sold goes back.
    func merchantConfirm(_ total: String) -> String {
        t("확인 · +\(total)", "Confirm · +\(total)", "確定 · +\(total)", "Confirmar · +\(total)", "Confirmer · +\(total)",
          "Confirmar · +\(total)", "Bestätigen · +\(total)", "Подтвердить · +\(total)")
    }
    func merchantSold(_ total: String) -> String {
        t("+\(total) 받았어요", "+\(total) received", "+\(total) 受け取りました", "+\(total) recibidos", "+\(total) reçus",
          "+\(total) recebidos", "+\(total) erhalten", "Получено +\(total)")
    }
    var merchantLeaves: String {
        t("자정에 떠나요.", "He leaves at midnight.", "真夜中に去ります。", "Se va a medianoche.", "Il repart à minuit.",
          "Vai embora à meia-noite.", "Er zieht um Mitternacht weiter.", "Уйдёт в полночь.")
    }

    var oakAdviceToggle: String {
        t("오박사의 조언 표시", "Show Prof. Oak's advice", "オーキド博士のアドバイスを表示", "Mostrar los consejos del Profesor Oak",
          "Afficher les conseils du Prof. Chen", "Mostrar os conselhos do Prof. Carvalho", "Tipps von Prof. Eich anzeigen",
          "Показывать советы профессора Оука")
    }
    func oakVerdictLabel(_ verdict: ActiveVerdict) -> String {
        switch verdict {
        case .formMystery:
            return formMysteryBadge
        case .lineToComplete:
            return t("채울 계열", "Line to complete", "未完成の系統", "Línea por completar", "Ligne à compléter", "Linha a completar",
                     "Linie offen", "Линия не собрана")
        case .newForm:
            return t("새 폼", "New form", "新しいフォルム", "Forma nueva", "Forme nouvelle", "Forma nova", "Neue Form", "Новая форма")
        case .costume:
            return t("코스튬 예정", "Costume ahead", "コスチューム付き", "Trae un disfraz", "Costume à gagner", "Traz uma fantasia",
                     "Bringt ein Kostüm", "Принесёт костюм")
        case .newCostume:
            return activeNewCostumeBadge
        case .shinyToKeep:
            return t("지킬 이로치", "Shiny to keep", "残したい色違い", "Variocolor a conservar", "Chromatique à garder",
                     "Shiny para guardar", "Schillernd: behalten", "Шайни: оставить")
        case .keptForAchievement:
            return t("업적용", "Keep for an achievement", "実績のために育てる", "Conservar por un logro", "À garder pour un succès",
                     "Guardar por uma conquista", "Für einen Erfolg behalten", "Оставить ради успеха")
        case .spare:
            return t("중복", "Spare", "ダブり", "Repetido", "En trop", "Repetido", "Doppelt", "Дубликат")
        }
    }
    var oakEggBubble: String {
        t("알이 아직 부화하지 않았구나. 무엇이 나올지 기대되는걸!", "Your egg hasn't hatched yet. I can't wait to see what comes out!",
          "タマゴはまだかえっておらんようじゃ。何が生まれるか楽しみじゃのう！", "Tu huevo aún no ha eclosionado. ¡Qué ganas de ver lo que sale!",
          "Ton œuf n'a pas encore éclos. J'ai hâte de voir ce qui va en sortir !",
          "Seu ovo ainda não chocou. Mal posso esperar para ver o que vai sair!",
          "Dein Ei ist noch nicht geschlüpft. Ich bin gespannt, was herauskommt!",
          "Яйцо ещё не вылупилось. Не терпится увидеть, кто из него появится!")
    }
    /// Prof. Oak's bubble on the Pokémon being raised. `name`: its name in its form; `newFormName`: the species it
    /// brings in its form, for `.newForm`.
    func oakBubble(_ verdict: ActiveVerdict, name: String, newFormName: String, revealName: String = "") -> String {
        switch verdict {
        case .formMystery(let mystery):
            let odds = formMysteryOdds(mystery)
            return t("\(odds). \(KoreanParticle.direction.attach(to: revealName)) 진화할 때까지 기다려 보거라!", "\(odds), wait until it becomes \(revealName)!",
                     "\(odds)。\(revealName)に進化するまで待つのじゃ！", "\(odds), ¡espera a que se convierta en \(revealName)!",
                     "\(odds), attends qu'il devienne \(revealName) !", "\(odds), espere até ele virar \(revealName)!",
                     "\(odds), warte, bis es zu \(revealName) wird!", "\(odds), подождите, пока он не станет \(revealName)!")
        case .lineToComplete(let count) where count.lowerBound != count.upperBound:
            let n = count.upperBound
            return t("\(KoreanParticle.subject.attach(to: name)) 아직 도감에 없는 종을 최대 \(n)종까지 가져올 수 있단다! 절대 놓아주지 말거라.",
                     "Your \(name) can bring \(n == 1 ? "a species" : "up to \(n) species") your Pokédex doesn't have yet! Whatever you do, don't release it.",
                     "\(name)は図鑑にまだない種類を最大\(n)つ連れてくるかもしれんぞ！決して逃がしてはならんぞ。",
                     "¡Tu \(name) puede traer \(n == 1 ? "una especie que aún no tienes" : "hasta \(n) especies que aún no tienes") en tu Pokédex! No lo sueltes por nada del mundo.",
                     "Ton \(name) peut t'apporter \(n == 1 ? "une espèce qui manque" : "jusqu'à \(n) espèces qui manquent") à ton Pokédex ! Surtout, ne le relâche pas.",
                     "Seu \(name) pode trazer \(n == 1 ? "uma espécie que ainda falta" : "até \(n) espécies que ainda faltam") na sua Pokédex! Não o solte de jeito nenhum.",
                     "Dein \(name) kann \(n == 1 ? "eine Art bringen, die deinem Pokédex noch fehlt" : "bis zu \(n) Arten bringen, die deinem Pokédex noch fehlen")! Lass es auf keinen Fall frei.",
                     "\(name) может принести в покедекс новые виды, до \(n)! Ни в коем случае не отпускайте его.")
        case .lineToComplete(let count):
            let n = count.upperBound
            return t("\(KoreanParticle.subject.attach(to: name)) 아직 도감에 없는 종을 \(n)종 가져올 거란다! 절대 놓아주지 말거라.",
                     "Your \(name) will bring \(n == 1 ? "a species" : "\(n) species") your Pokédex doesn't have yet! Whatever you do, don't release it.",
                     "\(name)は図鑑にまだない種類を\(n)つ連れてくるぞ！決して逃がしてはならんぞ。",
                     "¡Tu \(name) traerá \(n == 1 ? "una especie que aún no tienes" : "\(n) especies que aún no tienes") en tu Pokédex! No lo sueltes por nada del mundo.",
                     "Ton \(name) va t'apporter \(n == 1 ? "une espèce qui manque" : "\(n) espèces qui manquent") à ton Pokédex ! Surtout, ne le relâche pas.",
                     "Seu \(name) vai trazer \(n == 1 ? "uma espécie que ainda falta" : "\(n) espécies que ainda faltam") na sua Pokédex! Não o solte de jeito nenhum.",
                     "Dein \(name) bringt \(n == 1 ? "eine Art, die deinem Pokédex noch fehlt" : "\(n) Arten, die deinem Pokédex noch fehlen")! Lass es auf keinen Fall frei.",
                     "\(name) принесёт в покедекс новые виды: \(n)! Ни в коем случае не отпускайте его.")
        case .newForm:
            return t("계열의 종은 모두 있지만 \(KoreanParticle.subject.attach(to: newFormName)) 아직 없구나! 놓아주지 말거라.",
                     "You have every species of its line, but not \(newFormName)! Don't release it.",
                     "系統の種類はそろっておるが、\(newFormName)はまだじゃな！逃がしてはならんぞ。",
                     "Ya tienes todas las especies de su línea, ¡pero no \(newFormName)! No lo sueltes.",
                     "Tu as déjà toutes les espèces de sa lignée, mais pas \(newFormName) ! Ne le relâche pas.",
                     "Você já tem todas as espécies da linha dele, mas não \(newFormName)! Não o solte.",
                     "Du hast schon jede Art seiner Linie, aber nicht \(newFormName)! Lass es nicht frei.",
                     "Все виды его линии у вас уже есть, но не \(newFormName)! Не отпускайте его.")
        case .costume:
            return t("피카츄가 되면 아직 없는 코스튬을 가져온단다. 잘 키우거라!",
                     "Once it becomes Pikachu, it will bring a costume you don't have yet. Keep it!",
                     "ピカチュウになれば、まだ持っておらんコスチュームを持ってくるぞ。大事に育てるのじゃ！",
                     "Cuando se convierta en Pikachu, traerá un disfraz que aún no tienes. ¡Consérvalo!",
                     "Quand il deviendra Pikachu, il t'apportera un costume qui te manque. Garde-le !",
                     "Quando virar Pikachu, vai trazer uma fantasia que você ainda não tem. Fique com ele!",
                     "Wird es zu Pikachu, bringt es ein Kostüm mit, das dir noch fehlt. Behalte es!",
                     "Став Пикачу, он принесёт костюм, которого у вас ещё нет. Оставьте его!")
        case .newCostume:
            return t("이 코스튬은 아직 코스튬 컬렉션에 없단다. 잘 키우거라!",
                     "This costume isn't in your costume collection yet. Keep it!",
                     "このコスチュームはまだコスチュームのコレクションにないぞ。大事に育てるのじゃ！",
                     "Este disfraz aún no está en tu colección de disfraces. ¡Consérvalo!",
                     "Ce costume n'est pas encore dans ta collection costumée. Garde-le !",
                     "Esta fantasia ainda não está na sua coleção de fantasias. Fique com ele!",
                     "Dieses Kostüm fehlt deiner Kostümsammlung noch. Behalte es!",
                     "Этого костюма ещё нет в вашей коллекции костюмов. Оставьте его!")
        case .shinyToKeep:
            return t("계열은 이미 다 모았지만, 이 폼의 첫 이로치로구나. 이렇게 귀한 녀석은 지켜야지!",
                     "You already have its whole line, but it's your first shiny in this form. A rarity like that is worth keeping!",
                     "系統はそろっておるが、このフォルムで初めての色違いじゃ。こんな珍しいポケモンは手放してはならん！",
                     "Ya tienes toda su línea, pero es tu primer variocolor de esta forma. ¡Una rareza así se conserva!",
                     "Tu as déjà toute sa lignée, mais c'est ton premier chromatique sous cette forme. Une telle rareté, ça se garde !",
                     "Você já tem a linha toda, mas é seu primeiro shiny desta forma. Uma raridade assim merece ficar!",
                     "Seine Linie hast du schon, aber es ist dein erstes Schillerndes in dieser Form. So eine Seltenheit behält man!",
                     "Вся его линия у вас уже есть, но это ваш первый шайни в этой форме. Такую редкость стоит оставить!")
        case .keptForAchievement(let kind):
            let achievement = itemName(kind)
            return t("중복이지만, 졸업하면 업적이 열린단다: \(achievement). 끝까지 키우거라!",
                     "It's a Spare, but graduating it unlocks an achievement: \(achievement). Raise it all the way!",
                     "ダブりじゃが、卒業すれば実績が解放されるぞ：\(achievement)。最後まで育てるのじゃ！",
                     "Está repetido, pero al graduarse desbloquea un logro: \(achievement). ¡Críalo hasta el final!",
                     "Il est en trop, mais une fois diplômé, il débloque un succès : \(achievement). Fais-le grandir jusqu'au bout !",
                     "Ele é repetido, mas ao se formar desbloqueia uma conquista: \(achievement). Crie-o até o fim!",
                     "Es ist doppelt, aber sein Abschied schaltet einen Erfolg frei: \(achievement). Zieh es bis zum Ende groß!",
                     "Это дубликат, но после выпуска откроется успех: \"\(achievement)\". Вырастите его до конца!")
        case .spare:
            return t("\(KoreanParticle.subject.attach(to: name)) 새 종도, 새 폼도, 새 이로치도 가져오지 않는구나. 중복이란다.",
                     "Your \(name) brings no new species, form or shiny: it's a Spare.",
                     "\(name)は新しい種類もフォルムも色違いも連れてこんのう。ダブりじゃ。",
                     "Tu \(name) no trae ninguna especie, forma ni variocolor nuevos: está repetido.",
                     "Ton \(name) n'apporte ni espèce, ni forme, ni chromatique nouveaux : il est en trop.",
                     "Seu \(name) não traz espécie, forma nem shiny novos: é repetido.",
                     "Dein \(name) bringt keine neue Art, Form oder Schillernde: Es ist doppelt.",
                     "\(name) не приносит новых видов, форм или шайни: это дубликат.")
        }
    }
    /// The first step for a Pokémon worth keeping.
    func oakRaise(_ name: String) -> String {
        t("\(KoreanParticle.object.attach(to: name)) 키우세요", "Raise \(name)", "\(name)を育てる", "Cría a \(name)",
          "Fais grandir \(name)", "Crie \(name)", "Zieh \(name) groß", "Растите дальше: \(name)")
    }
    func oakGiveCandies(_ n: Int, to name: String) -> String {
        t("\(name)에게 이상한 사탕을 \(n)개 주세요", n == 1 ? "Give \(name) a Rare Candy" : "Give \(name) \(n) Rare Candies",
          "\(name)にふしぎなアメを\(n)個あげよう", n == 1 ? "Dale a \(name) un Caramelo Raro" : "Dale a \(name) \(n) Caramelos Raros",
          n == 1 ? "Donne un Super Bonbon à \(name)" : "Donne \(n) Super Bonbons à \(name)",
          n == 1 ? "Dê a \(name) um Doce Raro" : "Dê a \(name) \(n) Doces Raros",
          n == 1 ? "Gib \(name) ein Sonderbonbon" : "Gib \(name) \(n) Sonderbonbons", "Дайте ему редкие конфеты: \(n)")
    }
    func oakCandiesGoIn(_ n: Int, need: String, xp: String) -> String {
        t("졸업까지 \(need) 남아서 \(n)개(개당 \(xp))가 들어가요.", "It needs \(need) more to graduate: \(n) × \(xp) go in.",
          "卒業まであと\(need)：\(n)×\(xp)が使えます。", "Le faltan \(need) para graduarse: entran \(n) × \(xp).",
          "Il lui reste \(need) avant son diplôme : \(n) × \(xp) y passent.",
          "Faltam \(need) para se formar: entram \(n) × \(xp).",
          "Bis zum Abschied fehlen \(need): \(n) × \(xp) gehen hinein.",
          "До выпуска осталось \(need): \(n) × \(xp) уйдут на него.")
    }
    var oakLastCandyLosesLittle: String {
        t("마지막 사탕은 졸업할 때 10% 이하만 사라져요.", "The last one loses a tenth of its XP at most at graduation.",
          "最後の1個は、卒業時のむだが1割以下です。", "El último pierde como mucho una décima parte al graduarse.",
          "Le dernier en perd un dixième au plus au diplôme.", "O último perde no máximo um décimo ao se formar.",
          "Das letzte verliert beim Abschied höchstens ein Zehntel.", "Последняя потеряет при выпуске не больше десятой части.")
    }
    var oakNoCandyBeforeRelease: String {
        t("놓아주기 전에는 주지 마세요. 경험치가 함께 사라지니 다음 포켓몬을 위해 아껴 두세요.",
          "Not before releasing it: its XP would go with it. Keep them for the next one.",
          "逃がす前にはあげないこと。経験値も一緒に消えるので、次のポケモンのためにとっておこう。",
          "No antes de soltarlo: su experiencia se iría con él. Guárdalos para el siguiente.",
          "Pas avant de le relâcher : son XP partirait avec lui. Garde-les pour le suivant.",
          "Não antes de soltá-lo: a experiência iria embora com ele. Guarde-os para o próximo.",
          "Nicht bevor du es freilässt: Seine Erfahrung ginge mit ihm. Behalte sie für das nächste.",
          "Не раньше, чем отпустите его: опыт уйдёт вместе с ним. Сохраните их для следующего.")
    }
    func oakKeepOtherCandies(_ n: Int) -> String {
        t("나머지 \(n)개는 다음 포켓몬을 위해 아껴 두세요.",
          n == 1 ? "Keep the other one for the next Pokémon." : "Keep the other \(n) for the next Pokémon.",
          "残りの\(n)個は次のポケモンのためにとっておこう。",
          n == 1 ? "Guarda el otro para el siguiente." : "Guarda los otros \(n) para el siguiente.",
          n == 1 ? "Garde l'autre pour le suivant." : "Garde les \(n) autres pour le suivant.",
          n == 1 ? "Guarde o outro para o próximo." : "Guarde os outros \(n) para o próximo.",
          n == 1 ? "Behalte das andere für das nächste." : "Behalte die anderen \(n) für das nächste.",
          "Остальные (\(n)) сохраните для следующего покемона.")
    }
    func oakKeepCandies(_ n: Int) -> String {
        t("이상한 사탕 \(n)개는 아껴 두세요", n == 1 ? "Keep your Rare Candy" : "Keep your \(n) Rare Candies",
          "ふしぎなアメ\(n)個はとっておこう", n == 1 ? "Guarda tu Caramelo Raro" : "Guarda tus \(n) Caramelos Raros",
          n == 1 ? "Garde ton Super Bonbon" : "Garde tes \(n) Super Bonbons",
          n == 1 ? "Guarde seu Doce Raro" : "Guarde seus \(n) Doces Raros",
          n == 1 ? "Behalte dein Sonderbonbon" : "Behalte deine \(n) Sonderbonbons", "Сохраните редкие конфеты: \(n)")
    }
    func oakCandyWouldLose(need: String, xp: String, name: String) -> String {
        t("\(name)에게 남은 건 \(need)뿐이라, \(xp)짜리 사탕은 졸업할 때 일부가 사라져요.",
          "\(name) only needs \(need): a \(xp) Rare Candy would lose part of it at graduation.",
          "\(name)は残り\(need)だけ：\(xp)のアメでは卒業時に一部がむだになります。",
          "A \(name) solo le faltan \(need): un caramelo de \(xp) perdería parte al graduarse.",
          "Il ne reste que \(need) à \(name) : un bonbon de \(xp) en perdrait une partie au diplôme.",
          "\(name) só precisa de \(need): um doce de \(xp) perderia parte ao se formar.",
          "\(name) fehlen nur noch \(need): Ein Bonbon mit \(xp) verlöre beim Abschied einen Teil.",
          "До выпуска осталось всего \(need): конфета на \(xp) потеряет часть опыта.")
    }
    var oakCandiesForTheHatch: String {
        t("곧 부화할 포켓몬에게 쓰세요.", "They will go to the Pokémon about to hatch.", "これから生まれるポケモンに使おう。",
          "Servirán al Pokémon que va a eclosionar.", "Ils serviront au Pokémon qui va éclore.",
          "Vão servir ao Pokémon que vai chocar.", "Sie sind für das Pokémon, das gleich schlüpft.",
          "Они пригодятся покемону, который скоро вылупится.")
    }
    func oakReinsCandy(_ reins: String) -> String {
        t("졸업하면 \(KoreanParticle.subject.attach(to: reins)) 하나 더 줘요.", "When it graduates, the \(reins) give you one more.",
          "卒業すると\(reins)がもう1個くれます。", "Al graduarse, las \(reins) te darán uno más.",
          "Une fois diplômé, les \(reins) t'en donneront un de plus.",
          "Ao se formar, você ganha mais um com as \(reins).", "Bei seinem Abschied geben dir die \(reins) eins mehr.",
          "После выпуска \"\(reins)\" дадут ещё одну.")
    }
    /// Prof. Oak's last words on a Spare: what to do with it.
    func oakReleaseBubble(_ release: OakRelease) -> String {
        switch release {
        case .costumeEgg(_, odds: 0):
            return t("가방에서 대신할 수 있는 알은 코스튬 알뿐이지만, 기다리지 말고 지금 놓아주거라!",
                     "Only a Costume Egg of your Bag can take its place: release it for that one now, no waiting!",
                     "バッグで代わりになるのはコスチュームのタマゴだけじゃ。待たずに今すぐ逃がしてやるのじゃ！",
                     "Solo un huevo disfrazado de tu Bolsa puede ocupar su lugar: ¡suéltalo por él ahora, sin esperar!",
                     "Seul un Œuf costumé de ton Sac peut le remplacer : relâche-le contre lui tout de suite, sans attendre !",
                     "Só um ovo fantasiado da sua Bolsa pode ocupar o lugar dele: solte-o por ele agora, sem esperar!",
                     "Nur ein Kostüm-Ei aus deinem Beutel kann es ersetzen: Lass es jetzt dafür frei, ohne zu warten!",
                     "Заменить его может только костюмное яйцо из сумки: отпустите его ради него прямо сейчас, не ждите!")
        case .bag, .claim, .buy, .dungeonEgg, .costumeEgg:
            return t("새로운 걸 가져올 수 있는 알과 바꿔 놓아주거라!", "Release it for an egg that can bring you something new!",
                     "新しいものを連れてくるかもしれんタマゴと引き換えに、逃がしてやるのじゃ！",
                     "¡Suéltalo por un huevo que pueda traerte algo nuevo!", "Relâche-le contre un œuf qui peut t'apporter du nouveau !",
                     "Solte-o por um ovo que possa trazer algo novo!", "Lass es für ein Ei frei, das dir Neues bringen kann!",
                     "Отпустите его ради яйца, которое может принести что-то новое!")
        case .freeEgg(.pokemonEgg, _):
            let egg = eggName(nil)
            return t("가방의 \(KoreanParticle.subject.attach(to: egg)) 졸업 때 받는 알과 똑같은 뽑기니, 기다리지 말고 지금 놓아주거라!",
                     "The \(egg) in your Bag is the same draw as the egg its graduation gives: release it for that one now, no waiting!",
                     "バッグの\(egg)は卒業でもらえるタマゴと同じ抽選じゃ。待たずに今すぐ逃がしてやるのじゃ！",
                     "El \(egg) de tu Bolsa es el mismo sorteo que el huevo de su graduación: ¡suéltalo por él ahora, sin esperar!",
                     "L'\(egg) de ton Sac fait le même tirage que l'œuf de son diplôme : relâche-le contre lui tout de suite, sans attendre !",
                     "O \(egg) da sua Bolsa é o mesmo sorteio do ovo da formatura dele: solte-o por ele agora, sem esperar!",
                     "Das \(egg) in deinem Beutel ist dieselbe Ziehung wie das Ei seines Abschieds: Lass es jetzt dafür frei, ohne zu warten!",
                     "\"\(egg)\" в сумке даёт тот же розыгрыш, что и яйцо за его выпуск: отпустите его ради него прямо сейчас, не ждите!")
        case .freeEgg:
            return t("가방의 알이 졸업 때 받는 알을 대신할 수 있으니, 기다리지 말고 지금 놓아주거라!",
                     "An egg of your Bag can stand in for the one its graduation gives: release it for that one now, no waiting!",
                     "バッグのタマゴが卒業でもらえるタマゴの代わりになるのじゃ。待たずに今すぐ逃がしてやるのじゃ！",
                     "Un huevo de tu Bolsa puede ocupar el lugar del que da su graduación: ¡suéltalo por él ahora, sin esperar!",
                     "Un œuf de ton Sac peut remplacer celui de son diplôme : relâche-le contre lui tout de suite, sans attendre !",
                     "Um ovo da sua Bolsa pode ocupar o lugar do da formatura dele: solte-o por ele agora, sem esperar!",
                     "Ein Ei aus deinem Beutel kann das ersetzen, das sein Abschied gibt: Lass es jetzt dafür frei, ohne zu warten!",
                     "Яйцо из сумки может заменить яйцо за его выпуск: отпустите его ради него прямо сейчас, не ждите!")
        case .wait:
            return t("알을 살 수 있을 때까지만 키우거라.", "Keep it only until you can afford an egg.",
                     "タマゴが買えるようになるまで育てておくのじゃ。", "Quédatelo solo hasta que puedas comprar un huevo.",
                     "Garde-le juste le temps de pouvoir t'offrir un œuf.", "Fique com ele só até poder comprar um ovo.",
                     "Behalte es nur, bis du dir ein Ei leisten kannst.", "Оставьте его, только пока не сможете купить яйцо.")
        case .finish(_, .noBetterEgg):
            return t("어떤 알도 졸업 때 받는 알보다 새로운 걸 더 자주 가져오지 못하니, 끝까지 키우거라!",
                     "No egg would bring you something new more often than the one its graduation gives: let it finish!",
                     "卒業でもらえるタマゴより新しいものを連れてくるタマゴはない。最後まで育ててやるのじゃ！",
                     "Ningún huevo te traería algo nuevo más a menudo que el que da su graduación: ¡deja que termine!",
                     "Aucun œuf ne t'apporterait du nouveau plus souvent que celui de son diplôme : laisse-le finir !",
                     "Nenhum ovo traria algo novo com mais frequência que o da formatura dele: deixe-o terminar!",
                     "Kein Ei brächte dir öfter Neues als das, das sein Abschied gibt: Lass es fertig werden!",
                     "Ни одно яйцо не принесёт новое чаще, чем яйцо за его выпуск: дайте ему дорасти!")
        case .finish(_, .tooFarAlong):
            return t("이미 너무 많이 자랐으니, 끝까지 키우거라!", "It has grown too far to be worth releasing: let it finish!",
                     "もう育ちすぎて、逃がすのはもったいない。最後まで育ててやるのじゃ！",
                     "Ya ha crecido demasiado para que valga la pena soltarlo: ¡deja que termine!",
                     "Il a déjà trop grandi pour que le relâcher vaille le coup : laisse-le finir !",
                     "Ele já cresceu demais para valer a pena soltá-lo: deixe-o terminar!",
                     "Es ist schon zu weit gewachsen, um es freizulassen: Lass es fertig werden!",
                     "Он уже слишком вырос, чтобы его отпускать: дайте ему дорасти!")
        case .finish(_, .outgrowsTheWait):
            return t("알을 살 수 있을 즈음엔 너무 자라 있을 테니, 끝까지 키우거라!",
                     "By the time you can afford the egg, it will have grown too far: let it finish!",
                     "タマゴが買えるころには育ちすぎておる。最後まで育ててやるのじゃ！",
                     "Cuando puedas pagar el huevo, ya habrá crecido demasiado: ¡deja que termine!",
                     "Le temps de pouvoir t'offrir l'œuf, il aura trop grandi : laisse-le finir !",
                     "Quando você puder pagar o ovo, ele já terá crescido demais: deixe-o terminar!",
                     "Bis du dir das Ei leisten kannst, ist es zu weit gewachsen: Lass es fertig werden!",
                     "Пока вы накопите на яйцо, он слишком вырастет: дайте ему дорасти!")
        }
    }
    func oakUseFromBag(_ item: String) -> String {
        t("가방에서 사용하세요: \(item)", "Use from your Bag: \(item)", "バッグから使おう：\(item)", "Usa desde tu Bolsa: \(item)",
          "Utilise depuis ton Sac : \(item)", "Use da sua Bolsa: \(item)", "Verwende aus deinem Beutel: \(item)",
          "Используйте из сумки: \(item)")
    }
    func oakClaimThenUse(_ egg: String) -> String {
        t("받은 뒤 가방에서 사용하세요: \(egg)", "Take it, then use it from your Bag: \(egg)", "受け取ってバッグから使おう：\(egg)",
          "Recógelo y úsalo desde tu Bolsa: \(egg)", "Prends-le puis utilise-le depuis ton Sac : \(egg)",
          "Pegue e use da sua Bolsa: \(egg)", "Nimm es und verwende es aus deinem Beutel: \(egg)",
          "Заберите и используйте из сумки: \(egg)")
    }
    func oakBuyThenUse(_ egg: String) -> String {
        t("구매한 뒤 가방에서 사용하세요: \(egg)", "Buy it, then use it from your Bag: \(egg)", "買ってバッグから使おう：\(egg)",
          "Cómpralo y úsalo desde tu Bolsa: \(egg)", "Achète-le puis utilise-le depuis ton Sac : \(egg)",
          "Compre e use da sua Bolsa: \(egg)", "Kauf es und verwende es aus deinem Beutel: \(egg)",
          "Купите и используйте из сумки: \(egg)")
    }
    func oakKeepThenBuy(_ name: String, _ egg: String) -> String {
        t("\(KoreanParticle.object.attach(to: name)) 키우다가 사세요: \(egg)", "Keep \(name), then buy: \(egg)",
          "\(name)を育てつつ、あとで買おう：\(egg)", "Quédate con \(name) y luego compra: \(egg)",
          "Garde \(name), puis achète : \(egg)", "Fique com \(name) e depois compre: \(egg)",
          "Behalte \(name) und kauf dann: \(egg)", "Оставьте \(name), потом купите: \(egg)")
    }
    func oakSendsOff(_ name: String, odds: String) -> String {
        t("\(KoreanParticle.object.attach(to: name)) 놓아주고, 태어날 포켓몬이 새로운 걸 가져올 확률은 \(odds)예요.",
          "You send \(name) off, and what hatches has a \(odds) chance to bring you something new.",
          "\(name)を手放し、生まれるポケモンが新しいものを連れてくる確率は\(odds)です。",
          "Sueltas a \(name), y lo que eclosione tiene un \(odds) de probabilidad de traerte algo nuevo.",
          "Tu relâches \(name), et ce qui éclot a \(odds) de chances de t'apporter du nouveau.",
          "Você solta \(name), e o que chocar tem \(odds) de chance de trazer algo novo.",
          "Du lässt \(name) frei, und was schlüpft, bringt dir mit \(odds) Wahrscheinlichkeit etwas Neues.",
          "\(name) будет отпущен, а из яйца с вероятностью \(odds) появится что-то новое.")
    }
    var oakDungeonEggHatches: String {
        t("이 알은 이름에 쓰인 포켓몬이 그대로 태어나요. 이로치로 잡았다면 이로치로요. 뽑기는 없어요.",
          "This egg hatches the Pokémon it is named after, shiny if it was caught shiny: there is no draw.",
          "このタマゴは、名前のポケモンがそのまま生まれます。色違いで捕まえたなら色違いです。抽選はありません。",
          "Este huevo eclosiona el Pokémon que lleva por nombre, variocolor si se capturó variocolor: no hay sorteo.",
          "Cet œuf fait éclore le Pokémon dont il porte le nom, chromatique s'il l'était : pas de tirage.",
          "Este ovo choca o Pokémon que dá nome a ele, shiny se foi capturado shiny: não há sorteio.",
          "Dieses Ei lässt das Pokémon schlüpfen, nach dem es benannt ist, schillernd, wenn es schillernd gefangen wurde: Es gibt keine Ziehung.",
          "Из этого яйца вылупится покемон, в честь которого оно названо, шайни, если он был пойман шайни: розыгрыша нет.")
    }
    var oakCostumeEggHatches: String {
        t("이 알은 열 때 가진 종 중에서 뽑힌 포켓몬이 코스튬을 입고 태어나요. 새로운 종이나 진화는 가져오지 않고, 코스튬은 따지지 않아요.",
          "This egg hatches, in its costume, a Pokémon drawn when it is opened among the species you hold. It never brings a new species or evolution, and its costume is not counted.",
          "このタマゴは、開けるときに持っている種類から選ばれたポケモンがコスチュームを着て生まれます。新しい種や進化は連れてこず、コスチュームは数えません。",
          "Este huevo eclosiona, con su disfraz, un Pokémon sacado al abrirlo entre las especies que tienes. Nunca trae una especie ni una evolución nuevas, y su disfraz no cuenta.",
          "Cet œuf fait éclore, dans son costume, un Pokémon tiré à l'ouverture parmi les espèces que tu as. Il n'apporte jamais d'espèce ni d'évolution nouvelle, et son costume ne compte pas.",
          "Este ovo choca, com a fantasia dele, um Pokémon sorteado ao abrir entre as espécies que você tem. Nunca traz uma espécie ou evolução nova, e a fantasia não conta.",
          "Dieses Ei lässt in seinem Kostüm ein Pokémon schlüpfen, das beim Öffnen unter den Arten gezogen wird, die du hast. Es bringt nie eine neue Art oder Entwicklung, und sein Kostüm zählt nicht.",
          "Из этого яйца вылупится в своём костюме покемон, выбранный при открытии среди видов, которые у вас есть. Новых видов и эволюций оно не приносит, а костюм не учитывается.")
    }
    func oakCostumeEggOdds(_ name: String, odds: String) -> String {
        t("\(KoreanParticle.object.attach(to: name)) 놓아주고, 태어날 포켓몬이 첫 이로치일 확률은 \(odds)예요. 태어난 포켓몬은 코스튬을 얻으려고 졸업까지 키워요.",
          "You send \(name) off, and what hatches has a \(odds) chance to be a first shiny. It is kept until it graduates, for its costume.",
          "\(name)を手放し、生まれるポケモンが初めての色違いである確率は\(odds)です。生まれたポケモンは、そのコスチュームのために卒業まで育てます。",
          "Sueltas a \(name), y lo que eclosione tiene un \(odds) de probabilidad de ser un primer variocolor. Se conserva hasta que se gradúe, por su disfraz.",
          "Tu relâches \(name), et ce qui éclot a \(odds) de chances d'être un premier chromatique. Il est gardé jusqu'au diplôme, pour son costume.",
          "Você solta \(name), e o que chocar tem \(odds) de chance de ser um primeiro shiny. Ele fica guardado até se formar, pela fantasia.",
          "Du lässt \(name) frei, und was schlüpft, ist mit \(odds) Wahrscheinlichkeit ein erstes Schillerndes. Es bleibt bis zum Abschied bei dir, wegen seines Kostüms.",
          "\(name) будет отпущен, а из яйца с вероятностью \(odds) появится первый шайни. Вылупившегося оставят до выпуска ради его костюма.")
    }
    func oakCostumeEggSpare(_ name: String) -> String {
        t("이 알은 새로운 걸 가져오지 못하지만, 가방에서 쓸 수 있는 다른 알이 없고 지금 쓰면 기다리지 않아도 돼요. \(KoreanParticle.object.attach(to: name)) 놓아주면, 태어난 포켓몬은 코스튬을 얻으려고 졸업까지 키워요.",
          "This egg brings nothing new, but no other egg of your Bag can go, and using it now spares you the wait. You send \(name) off, and what hatches is kept until it graduates, for its costume.",
          "このタマゴは新しいものを連れてきませんが、バッグには使えるほかのタマゴがなく、今使えば待たずに済みます。\(name)を手放すと、生まれたポケモンはそのコスチュームのために卒業まで育てます。",
          "Este huevo no trae nada nuevo, pero ningún otro huevo de tu Bolsa puede salir, y usarlo ahora te ahorra la espera. Sueltas a \(name), y lo que eclosione se conserva hasta que se gradúe, por su disfraz.",
          "Cet œuf n'apporte rien de nouveau, mais aucun autre œuf de ton Sac ne peut partir, et l'utiliser tout de suite t'évite d'attendre. Tu relâches \(name), et ce qui éclot est gardé jusqu'au diplôme, pour son costume.",
          "Este ovo não traz nada novo, mas nenhum outro ovo da sua Bolsa pode sair, e usá-lo agora poupa a espera. Você solta \(name), e o que chocar fica guardado até se formar, pela fantasia.",
          "Dieses Ei bringt nichts Neues, aber kein anderes Ei deines Beutels kann gehen, und es jetzt zu verwenden erspart dir das Warten. Du lässt \(name) frei, und was schlüpft, behältst du bis zum Abschied, wegen seines Kostüms.",
          "Это яйцо не приносит ничего нового, но ни одно другое яйцо из сумки не может уйти, а использовать его сейчас значит не ждать. \(name) будет отпущен, а вылупившегося оставят до выпуска ради его костюма.")
    }
    func oakHeldEggIsTheSameDraw(_ egg: String) -> String {
        t("가방의 \(KoreanParticle.subject.attach(to: egg)) 졸업 때 받는 알과 똑같이 뽑지만 지금 바로 뽑아요. 끝까지 키우길 기다릴 필요가 없어요.",
          "The \(egg) in your Bag draws just what the egg its graduation gives would, but right now: no need to wait for it to finish.",
          "バッグの\(egg)は、卒業でもらえるタマゴと同じ抽選を今すぐ行います。最後まで育つのを待つ必要はありません。",
          "El \(egg) de tu Bolsa saca lo mismo que el huevo de su graduación, pero ahora mismo: no hace falta esperar a que termine.",
          "L'\(egg) de ton Sac fait le même tirage que l'œuf de son diplôme, mais tout de suite : inutile d'attendre qu'il finisse.",
          "O \(egg) da sua Bolsa sorteia o mesmo que o ovo da formatura dele, mas agora mesmo: não precisa esperar ele terminar.",
          "Das \(egg) in deinem Beutel zieht dasselbe wie das Ei seines Abschieds, aber sofort: Du musst nicht warten, bis es fertig ist.",
          "\"\(egg)\" в сумке даёт тот же розыгрыш, что и яйцо за выпуск, но сразу же: не нужно ждать, пока он дорастёт.")
    }
    func oakHeldEggStandsIn(_ egg: String) -> String {
        t("졸업 때 받는 \(egg)보다 새로운 걸 더 자주 가져오지는 못하지만, 이미 가방에 있어서 지금 쓰면 기다리지 않아도 돼요.",
          "It does not bring something new more often than the \(egg) its graduation gives, but it is already in your Bag, and using it now spares you the wait.",
          "卒業でもらえる\(egg)より新しいものを連れてくる回数は多くありませんが、すでにバッグにあるので、今使えば待たずに済みます。",
          "No trae algo nuevo más a menudo que el \(egg) que da su graduación, pero ya está en tu Bolsa, y usarlo ahora te ahorra la espera.",
          "Il n'apporte pas du nouveau plus souvent que l'\(egg) de son diplôme, mais il est déjà dans ton Sac : l'utiliser tout de suite t'évite d'attendre.",
          "Ele não traz algo novo com mais frequência que o \(egg) da formatura dele, mas já está na sua Bolsa: usá-lo agora poupa a espera.",
          "Es bringt nicht öfter Neues als das \(egg), das sein Abschied gibt, liegt aber schon in deinem Beutel: Es jetzt zu verwenden erspart dir das Warten.",
          "Оно не приносит новое чаще, чем \"\(egg)\" за выпуск, но уже лежит в сумке: использовать его сейчас значит не ждать.")
    }
    var oakClaimWaits: String {
        t("홈에서 기다리고 있어요.", "It waits for you on Home.", "ホームで待っています。", "Te espera en Inicio.",
          "Il t'attend sur l'Accueil.", "Ele espera por você no Início.", "Es wartet auf der Startseite auf dich.",
          "Оно ждёт вас на главной.")
    }
    func oakEggCosts(_ price: String) -> String {
        t("가격은 \(price)예요.", "It costs \(price).", "値段は\(price)です。", "Cuesta \(price).", "Il coûte \(price).",
          "Custa \(price).", "Es kostet \(price).", "Оно стоит \(price).")
    }
    /// The egg a Spare waits for. `eta`: `oakAtYourPace`, or empty while the pace is unknown.
    func oakWaitForEgg(price: String, short: String, eta: String, odds: String) -> String {
        t("가격은 \(price), 아직 \(short) 부족해요\(eta). 사면 가방에서 사용하세요. 태어날 포켓몬이 새로운 걸 가져올 확률은 \(odds)예요.",
          "It costs \(price): \(short) to go\(eta). Once bought, use it from your Bag: what hatches will have a \(odds) chance to bring you something new.",
          "値段は\(price)、あと\(short)足りません\(eta)。買ったらバッグから使おう。生まれるポケモンが新しいものを連れてくる確率は\(odds)です。",
          "Cuesta \(price): te faltan \(short)\(eta). Cuando lo compres, úsalo desde tu Bolsa: lo que eclosione tendrá un \(odds) de probabilidad de traerte algo nuevo.",
          "Il coûte \(price) : il te manque \(short)\(eta). Une fois acheté, utilise-le depuis ton Sac : ce qui éclot aura \(odds) de chances de t'apporter du nouveau.",
          "Custa \(price): faltam \(short)\(eta). Depois de comprar, use da sua Bolsa: o que chocar terá \(odds) de chance de trazer algo novo.",
          "Es kostet \(price): Dir fehlen noch \(short)\(eta). Hast du es gekauft, verwende es aus deinem Beutel: Was schlüpft, bringt dir mit \(odds) Wahrscheinlichkeit etwas Neues.",
          "Оно стоит \(price): не хватает \(short)\(eta). Купив, используйте его из сумки: из яйца с вероятностью \(odds) появится что-то новое.")
    }
    func oakAtYourPace(_ duration: String) -> String {
        t(" (지금 속도로 약 \(duration))", " (about \(duration) at your pace)", "（今のペースで約\(duration)）",
          " (aprox. \(duration) a tu ritmo)", " (environ \(duration) à ton rythme)", " (cerca de \(duration) no seu ritmo)",
          " (etwa \(duration) bei deinem Tempo)", " (примерно \(duration) в вашем темпе)")
    }
    func oakLetFinish(_ name: String, left: String) -> String {
        t("\(KoreanParticle.object.attach(to: name)) 끝까지 키우세요: \(left) 남았어요", "Let \(name) finish: \(left) to go",
          "\(name)を最後まで育てよう：残り\(left)", "Deja que \(name) termine: le faltan \(left)",
          "Laisse \(name) finir : il lui reste \(left)", "Deixe \(name) terminar: faltam \(left)",
          "Lass \(name) fertig werden: noch \(left)", "Дайте \(name) дорасти: осталось \(left)")
    }
    var oakNoEggBeatsGraduation: String {
        t("가방의 알도, 받을 수 있는 알도, 상점의 알도 졸업 때 받는 알보다 새로운 걸 더 자주 가져오지 못해요. 놓아줘도 얻을 게 없어요.",
          "No egg in your Bag, to take or in the Shop brings something new more often than the egg its graduation gives: nothing to gain by sending it off.",
          "バッグのタマゴも、受け取れるタマゴも、ショップのタマゴも、卒業でもらえるタマゴより新しいものを連れてきません。手放しても得るものはありません。",
          "Ningún huevo de tu Bolsa, por recoger o de la tienda trae algo nuevo más a menudo que el que da su graduación: no ganas nada soltándolo.",
          "Aucun œuf du Sac, à prendre ou de la Boutique n'apporte du nouveau plus souvent que celui que donne son diplôme : rien à gagner à le relâcher.",
          "Nenhum ovo da sua Bolsa, para pegar ou da loja traz algo novo com mais frequência que o da formatura dele: não há o que ganhar soltando-o.",
          "Kein Ei im Beutel, zum Abholen oder im Laden bringt öfter Neues als das, das sein Abschied gibt: Es freizulassen bringt nichts.",
          "Ни одно яйцо в сумке, к получению или в магазине не приносит новое чаще, чем яйцо за выпуск: отпускать его нет смысла.")
    }
    var oakTooFarAlong: String {
        t("지금 놓아주면 졸업까지 남은 것보다 더 많은 성장을 잃어요.",
          "Sent off now, it would lose more growth than it has left before graduating.",
          "今手放すと、卒業までの残りより多くの成長を失います。",
          "Si lo sueltas ahora, perdería más crecimiento del que le falta para graduarse.",
          "Relâché maintenant, il perdrait plus de croissance qu'il ne lui en reste avant son diplôme.",
          "Se for solto agora, perderia mais crescimento do que falta para se formar.",
          "Jetzt freigelassen, verlöre es mehr Wachstum, als ihm bis zum Abschied fehlt.",
          "Если отпустить его сейчас, он потеряет больше роста, чем ему осталось до выпуска.")
    }
    func oakEvenWithAmber(_ amber: String) -> String {
        t("\(KoreanParticle.subject.attach(to: amber)) 넘겨주는 절반을 빼도 마찬가지예요.", "Even with the half your \(amber) carries over.",
          "\(amber)が引き継ぐ半分を除いても同じです。", "Incluso con la mitad que pasa tu \(amber).",
          "Même avec la moitié que garde ton \(amber).", "Mesmo com a metade que seu \(amber) passa adiante.",
          "Auch mit der Hälfte, die dein \(amber) weitergibt.", "Даже с половиной, которую передаст \"\(amber)\".")
    }
    var oakOutgrowsTheWait: String {
        t("잔액이 알값에 닿을 때쯤이면, 놓아줄 때 졸업까지 남은 것보다 더 많은 성장을 잃게 돼요.",
          "By the time your balance pays for the egg, sending it off would lose more growth than it has left.",
          "残高がタマゴの値段に届くころには、手放すと卒業までの残りより多くの成長を失います。",
          "Para cuando tu saldo pague el huevo, soltarlo le haría perder más crecimiento del que le falta.",
          "Le temps que ton solde paie l'œuf, le relâcher lui ferait perdre plus de croissance qu'il ne lui en reste.",
          "Quando seu saldo pagar o ovo, soltá-lo faria perder mais crescimento do que falta.",
          "Bis dein Guthaben das Ei bezahlt, verlöre es freigelassen mehr Wachstum, als ihm noch fehlt.",
          "Когда баланса хватит на яйцо, отпустив его, вы потеряете больше роста, чем ему осталось.")
    }
    func oakWhyEgg(rare: String, uncommon: String, amber: String, plain: String) -> String {
        t("놓아줄까, 끝까지 키울까? 놓아주면 자란 만큼을 잃고(\(KoreanParticle.subject.attach(to: amber)) 있으면 이번 단계의 절반은 다음 포켓몬에게 넘어가요), 졸업하면 알을 하나 받아요. 그래서 남은 것보다 덜 자랐을 때만, 그리고 그 알보다 새로운 걸 더 자주 가져오는 알이 있을 때만 놓아줘요. 가방에서 확률이 가장 높은 알이에요. 받을 수 있는 이벤트 알도 포함하고, 확률이 같으면 가방에서 앞에 있는 알이에요. 없으면 그보다 나은 상점 알 중 가장 까다로운 알: \(rare), 그다음 \(uncommon). 잔액이 되면 사지만, 그때까지 너무 자라면 사지 않아요. 그런 알이 없으면, 가방에서 그 알을 이기지는 못해도 확률이 가장 높은 알(가방의 \(plain)은 졸업 때 받는 알과 똑같이 뽑아요)을 잔액을 기다리거나 끝까지 키우는 대신 바로 써요. 확률이 0인 알은 쓰지 않고, 남은 것보다 덜 자랐을 때만 써요. 확률에는 첫 이로치도 들어가요. 부화한 포켓몬이 이로치로 나오는 확률만큼이에요. 이름에 쓰인 포켓몬이 그대로 태어나는 알도 가방의 알과 함께 순위에 들어가요. 종이나 폼이 새로우면 확률 100%, 이로치 알이 첫 이로치를 가져오면 100%, 아니면 0%라서 이미 가진 계통의 보통 알은 쓰지 않아요. 코스튬 알도 코스튬은 빼고 가방의 알과 함께 순위에 들어가요. 열 때 뽑힐 수 있는 포켓몬 전체에서 첫 이로치가 나올 평균 확률로 따지고, 새로운 종이나 진화는 따지지 않아요. 확률이 0이면 가방의 다른 알이 모두 쓸 수 없을 때만, 졸업 때 받는 알과 확률이 있는 다른 알보다 뒤에 써요. 태어난 포켓몬은 코스튬을 얻으려고 졸업까지 키워요.",
          "Release it or let it finish? Sent off, it loses what it has grown (with the \(amber), half its stage goes to the next one); graduated, it gives you an egg. So it is only released while it has grown less than it has left, and only for an egg that brings something new more often than that one: the one in your Bag with the best chance, an event egg to take included; on a tie, the first in the Bag. If none, the most selective Shop egg that does better: \(rare), then \(uncommon), bought once your balance allows, unless it has grown too far by then. If none beats it, the egg of your Bag with the best chance that does not (the \(plain) of the Bag draws just what its graduation gives) goes right away, instead of waiting for the balance or letting it finish: never one with no chance left, and only while it has grown less than it has left. Each chance counts a first shiny too, as often as a hatch shines. An egg named after the Pokémon it hatches counts with the others of your Bag: 100% if its species or form is new, or if it is shiny and brings a first shiny, else 0%, so a plain one of a line you hold is never used. A Costume Egg ranks with the Bag's eggs too, its costume left out: it counts a first shiny's chance, averaged over everything it may draw when opened, and never a new species or evolution. At 0 it goes last, after the Pokémon Egg and every egg with some chance, when no other egg of your Bag can go. What hatches is kept until it graduates, for its costume.",
          "逃がすか、最後まで育てるか？手放すと育った分を失い（\(amber)があれば今の段階の半分が次に引き継がれます）、卒業すればタマゴが1個もらえます。だから逃がすのは、残りより育っていないうちだけ、しかもそのタマゴより新しいものを連れてくるタマゴがあるときだけです。バッグの中でいちばん確率が高いタマゴで、受け取れるイベントのタマゴも含み、同じ確率ならバッグで先のもの。なければ、それより良いショップのタマゴのうちいちばん絞り込んだもの：\(rare)、次に\(uncommon)。残高が足りたら買いますが、それまでに育ちすぎたら買いません。それがなければ、勝てなくても確率がいちばん高いバッグのタマゴ（バッグの\(plain)は卒業でもらえるタマゴと同じ抽選）を、残高を待ったり最後まで育てたりせず、すぐ使います。確率が0のタマゴは使わず、残りより育っていないうちだけです。確率には初めての色違いも含みます。生まれるポケモンが色違いになる確率の分です。名前のポケモンがそのまま生まれるタマゴも、バッグのタマゴと並んで順位に入ります。種かフォルムが新しければ100%、色違いのタマゴが初めての色違いを連れてくるなら100%、そうでなければ0%なので、持っている系統の通常のタマゴは使いません。コスチュームのタマゴも、コスチュームを除いてバッグのタマゴと並んで順位に入ります。開けるときに選ばれうるポケモンすべてで平均した初めての色違いの確率で考え、新しい種や進化は数えません。確率が0なら、バッグのほかのタマゴがどれも使えないときだけ、卒業でもらえるタマゴや確率のあるほかのタマゴより後に使います。生まれたポケモンは、そのコスチュームのために卒業まで育てます。",
          "¿Soltarlo o dejar que termine? Si lo sueltas, pierde lo que ha crecido (con el \(amber), la mitad de su etapa pasa al siguiente); si se gradúa, te da un huevo. Así que solo se suelta mientras haya crecido menos de lo que le falta, y solo por un huevo que traiga algo nuevo más a menudo que ese: el de tu Bolsa con más probabilidad, incluido un huevo de evento por recoger; si empatan, el primero de la Bolsa. Si no hay, el huevo más selectivo de la tienda que lo mejore: \(rare), luego \(uncommon), comprado en cuanto tu saldo lo permita, salvo que para entonces haya crecido demasiado. Si ninguno lo mejora, se usa enseguida el huevo de tu Bolsa con más probabilidad que no lo mejora (el \(plain) de la Bolsa saca lo mismo que su graduación), en vez de esperar al saldo o dejar que termine: nunca uno sin probabilidad, y solo mientras haya crecido menos de lo que le falta. Cada probabilidad cuenta también un primer variocolor, tan a menudo como una eclosión sale variocolor. Un huevo con el nombre del Pokémon que eclosiona cuenta con los demás de tu Bolsa: 100% si su especie o su forma es nueva, o si es variocolor y trae un primer variocolor, y 0% si no, así que uno normal de una línea que ya tienes nunca se usa. Un huevo disfrazado también entra en la clasificación con los de la Bolsa, sin su disfraz: cuenta la probabilidad de un primer variocolor, promediada sobre todo lo que puede salir al abrirlo, y nunca una especie o evolución nuevas. Con 0 va el último, después del huevo Pokémon y de todo huevo con alguna probabilidad, cuando ningún otro huevo de tu Bolsa puede salir. Lo que eclosiona se conserva hasta que se gradúe, por su disfraz.",
          "Le relâcher ou le laisser finir ? Relâché, il perd ce qu'il a grandi (avec le \(amber), la moitié de son stade passe au suivant) ; diplômé, il te donne un œuf. Il n'est donc relâché que tant qu'il a moins grandi qu'il ne lui reste, et seulement contre un œuf qui apporte du nouveau plus souvent que celui-là : celui du Sac qui a le plus de chances, un œuf d'événement à prendre compris ; à égalité, le premier du Sac. Sinon l'œuf de la Boutique le plus sélectif qui fait mieux : \(rare), puis \(uncommon), acheté dès que ton solde le permet, sauf s'il a trop grandi d'ici là. Si aucun ne fait mieux, l'œuf du Sac qui a le plus de chances sans faire mieux (l'\(plain) du Sac fait le même tirage que son diplôme) est utilisé tout de suite, au lieu d'attendre le solde ou de le laisser finir : jamais un œuf sans aucune chance, et seulement tant qu'il a moins grandi qu'il ne lui reste. Chaque chance compte aussi un premier chromatique, aussi souvent qu'une éclosion brille. Un œuf qui porte le nom du Pokémon qu'il fait éclore compte avec les autres de ton Sac : 100 % si son espèce ou sa forme est nouvelle, ou s'il est chromatique et apporte un premier chromatique, sinon 0 %, donc un œuf normal d'une lignée que tu as n'est jamais utilisé. Un Œuf costumé entre aussi dans le classement avec ceux du Sac, sans son costume : il compte la chance d'un premier chromatique, en moyenne sur tout ce qu'il peut tirer à l'ouverture, et jamais une espèce ou une évolution nouvelle. À 0 il passe en dernier, après l'Œuf Pokémon et tout œuf qui a une chance, quand aucun autre œuf de ton Sac ne peut partir. Ce qui éclot est gardé jusqu'au diplôme, pour son costume.",
          "Soltar ou deixar terminar? Solto, ele perde o que cresceu (com o \(amber), metade da fase passa para o próximo); formado, ele dá um ovo. Então só é solto enquanto cresceu menos do que falta, e só por um ovo que traga algo novo com mais frequência que esse: o da sua Bolsa com mais chance, incluindo um ovo de evento para pegar; em caso de empate, o primeiro da Bolsa. Se não houver, o ovo mais seletivo da loja que faça melhor: \(rare), depois \(uncommon), comprado assim que o saldo permitir, a não ser que até lá ele tenha crescido demais. Se nenhum faz melhor, usa-se já o ovo da Bolsa com mais chance que não faz melhor (o \(plain) da Bolsa sorteia o mesmo que a formatura), em vez de esperar o saldo ou deixar terminar: nunca um sem nenhuma chance, e só enquanto ele cresceu menos do que falta. Cada chance conta também um primeiro shiny, com a mesma frequência com que um ovo choca shiny. Um ovo que leva o nome do Pokémon que choca conta junto com os outros da sua Bolsa: 100% se a espécie ou a forma é nova, ou se é shiny e traz um primeiro shiny, senão 0%, então um comum de uma linha que você já tem nunca é usado. Um ovo fantasiado também entra na classificação com os da Bolsa, sem a fantasia: conta a chance de um primeiro shiny, em média sobre tudo o que ele pode sortear ao abrir, e nunca uma espécie ou evolução nova. Com 0 vai por último, depois do ovo Pokémon e de todo ovo com alguma chance, quando nenhum outro ovo da sua Bolsa pode sair. O que chocar fica guardado até se formar, pela fantasia.",
          "Freilassen oder fertig werden lassen? Freigelassen verliert es, was es gewachsen ist (mit dem \(amber) geht die Hälfte seiner Stufe an das nächste); verabschiedet gibt es dir ein Ei. Es wird also nur freigelassen, solange es weniger gewachsen ist, als ihm fehlt, und nur für ein Ei, das öfter Neues bringt als jenes: das in deinem Beutel mit der besten Chance, ein abholbares Event-Ei eingeschlossen; bei Gleichstand das erste im Beutel. Sonst das wählerischste Ei im Laden, das besser ist: \(rare), dann \(uncommon), gekauft, sobald dein Guthaben reicht, außer es ist bis dahin zu weit gewachsen. Wenn keins besser ist, wird das Ei im Beutel mit der besten Chance, das nicht besser ist (das \(plain) im Beutel zieht dasselbe wie sein Abschied), sofort verwendet, statt aufs Guthaben zu warten oder es fertig werden zu lassen: nie eins ohne Chance, und nur, solange es weniger gewachsen ist, als ihm fehlt. Jede Chance zählt auch ein erstes Schillerndes, so oft wie ein Schlüpfling schillert. Ein Ei, das nach dem Pokémon benannt ist, das daraus schlüpft, zählt mit den anderen in deinem Beutel: 100 %, wenn seine Art oder Form neu ist oder wenn es schillernd ist und ein erstes Schillerndes bringt, sonst 0 %, also wird ein gewöhnliches aus einer Linie, die du hast, nie verwendet. Ein Kostüm-Ei kommt ebenfalls mit denen im Beutel in die Rangliste, ohne sein Kostüm: Es zählt die Chance auf ein erstes Schillerndes, gemittelt über alles, was beim Öffnen gezogen werden kann, und nie eine neue Art oder Entwicklung. Bei 0 kommt es zuletzt, nach dem Pokémon-Ei und jedem Ei mit einer Chance, wenn kein anderes Ei deines Beutels gehen kann. Was schlüpft, behältst du bis zum Abschied, wegen seines Kostüms.",
          "Отпустить или дать дорасти? Отпущенный, он теряет то, что вырос (если есть \"\(amber)\", половина его стадии переходит следующему); после выпуска он даёт яйцо. Поэтому его отпускают, только пока он вырос меньше, чем ему осталось, и только ради яйца, которое приносит новое чаще этого: того, что в сумке с лучшим шансом, включая яйцо события, которое можно забрать; при равенстве первого в сумке. Если такого нет, самого избирательного яйца магазина, которое лучше: \(rare), затем \(uncommon), купленного, как только позволит баланс, если к тому времени он не вырастет слишком. Если лучше нет, сразу используется яйцо из сумки с лучшим шансом, которое не лучше (\"\(plain)\" в сумке даёт тот же розыгрыш, что и выпуск), вместо ожидания баланса или того, чтобы дать дорасти: но не яйцо с нулевым шансом и только пока он вырос меньше, чем ему осталось. Каждый шанс учитывает и первого шайни, так же часто, как вылупляется шайни. Яйцо, названное по покемону, который из него вылупится, учитывается вместе с остальными в сумке: 100%, если вид или форма новые или если оно шайни и принесёт первого шайни, иначе 0%, так что обычное яйцо уже имеющейся линии не используется. Костюмное яйцо тоже участвует в рейтинге вместе с яйцами из сумки, без костюма: учитывается шанс первого шайни, усреднённый по всему, что может выпасть при открытии, и никогда новый вид или эволюция. При 0 оно идёт последним, после яйца покемона и любого яйца с каким-то шансом, когда ни одно другое яйцо из сумки не может уйти. Вылупившегося оставят до выпуска ради его костюма.")
    }
    func oakAmberKeeps(_ amber: String, name: String) -> String {
        t("\(KoreanParticle.subject.attach(to: amber)) \(name)의 이번 단계 경험치 절반을 태어날 포켓몬에게 넘겨줘요.",
          "Your \(amber) passes half the XP \(name) gained at its stage to the one that hatches.",
          "\(amber)が、\(name)の今の段階の経験値の半分を生まれるポケモンに引き継ぎます。",
          "Tu \(amber) pasa la mitad de la experiencia de la etapa de \(name) al que eclosione.",
          "Ton \(amber) passe la moitié de l'XP du stade de \(name) à celui qui éclot.",
          "Seu \(amber) passa metade da experiência da fase de \(name) para o que chocar.",
          "Dein \(amber) gibt die Hälfte der Erfahrung, die \(name) in seiner Stufe gesammelt hat, an das weiter, was schlüpft.",
          "\"\(amber)\" передаст половину опыта \(name) на этой стадии тому, кто вылупится.")
    }
    func oakBuyAhead(_ n: Int, _ egg: String) -> String {
        t("미리 \(n)개 사 두세요: \(egg)", n == 1 ? "Buy one ahead: \(egg)" : "Buy \(n) ahead: \(egg)",
          "前もって\(n)個買っておこう：\(egg)",
          n == 1 ? "Compra uno por adelantado: \(egg)" : "Compra \(n) por adelantado: \(egg)",
          n == 1 ? "Achètes-en un d'avance : \(egg)" : "Achètes-en \(n) d'avance : \(egg)",
          n == 1 ? "Compre um com antecedência: \(egg)" : "Compre \(n) com antecedência: \(egg)",
          n == 1 ? "Kauf eins im Voraus: \(egg)" : "Kauf \(n) im Voraus: \(egg)",
          "Купите заранее (\(n)): \(egg)")
    }
    func oakBagCoversTheNextOnly(_ egg: String, price: String) -> String {
        t("가방에는 다음 한 번 놓아줄 몫만 있어요. 다음 \(egg) 가격: \(price)",
          "Your Bag covers the next send-off only: the next \(egg) costs \(price)",
          "バッグには次の1回分しかありません。次の\(egg)は\(price)",
          "Tu Bolsa solo cubre la próxima vez que sueltes un Pokémon: el próximo \(egg) cuesta \(price)",
          "Ton Sac ne couvre que le prochain relâché : le prochain \(egg) coûte \(price)",
          "Sua Bolsa só cobre a próxima vez que você soltar um Pokémon: o próximo \(egg) custa \(price)",
          "Dein Beutel reicht nur fürs nächste Freilassen: das nächste \(egg) kostet \(price)",
          "В сумке хватит только на следующий раз: следующее \(egg) стоит \(price)")
    }
    func oakSetAside(_ amount: String, count n: Int, egg: String) -> String {
        t("\(n) × \(egg) 몫으로 \(amount) 남겨 두세요", "Keep \(amount) aside for \(n) × \(egg)",
          "\(n) × \(egg)のために\(amount)とっておこう", "Guarda \(amount) para \(n) × \(egg)",
          "Garde \(amount) de côté pour \(n) × \(egg)", "Guarde \(amount) para \(n) × \(egg)",
          "Leg \(amount) für \(n) × \(egg) zurück", "Отложите \(amount) на \(n) × \(egg)")
    }
    /// The eggs to hold for one new Pokémon (`OakBudget.stockTarget`).
    func oakStockFor(_ n: Int, takes: Int, odds: String) -> String {
        n == 1
            ? t("알 하나당 확률이 \(odds)라 하나만 있어도 충분해요.", "At \(odds) a chance, one egg on hand is enough.",
                "1個あたり\(odds)の確率なので、1個あれば十分です。",
                "Con un \(odds) de probabilidad por huevo, basta con tener uno a mano.",
                "À \(odds) de chances par œuf, en avoir un sous la main suffit.",
                "Com \(odds) de chance por ovo, basta ter um à mão.", "Bei \(odds) Chance pro Ei reicht eins auf Vorrat.",
                "С шансом \(odds) на яйцо достаточно одного в запасе.")
            : t("알 하나당 확률이 \(odds)라 새로운 걸 얻으려면 평균 \(takes)개가 필요해요. \(n)개(최대 3개)를 갖춰 두세요.",
                "At \(odds) a chance, it takes about \(takes) eggs for something new: keep \(n) on hand, 3 at most.",
                "1個あたり\(odds)の確率なので、新しいものには平均\(takes)個必要です。\(n)個（最大3個）そろえておこう。",
                "Con un \(odds) de probabilidad por huevo, hacen falta unos \(takes) para algo nuevo: ten \(n) a mano, 3 como máximo.",
                "À \(odds) de chances par œuf, il en faut environ \(takes) pour du nouveau : garde-en \(n) sous la main, 3 au plus.",
                "Com \(odds) de chance por ovo, são precisos uns \(takes) para algo novo: tenha \(n) à mão, no máximo 3.",
                "Bei \(odds) Chance pro Ei braucht es etwa \(takes) für etwas Neues: Halte \(n) auf Vorrat, höchstens 3.",
                "С шансом \(odds) на яйцо для чего-то нового нужно около \(takes): держите \(n) в запасе, не больше 3.")
    }
    func oakStockHeld(_ n: Int) -> String {
        t("가방에 있는 그만큼 좋은 알 \(n)개도 포함돼요.",
          n == 1 ? "The one as good in your Bag counts." : "The \(n) as good in your Bag count.",
          "バッグにある同じくらい良いタマゴ\(n)個も数えます。",
          n == 1 ? "Cuenta el de tu Bolsa, igual de bueno." : "Cuentan los \(n) de tu Bolsa, igual de buenos.",
          n == 1 ? "Celui du Sac, aussi bon, compte." : "Les \(n) du Sac, aussi bons, comptent.",
          n == 1 ? "O da sua Bolsa, tão bom quanto, conta." : "Os \(n) da sua Bolsa, tão bons quanto, contam.",
          n == 1 ? "Das gleich gute in deinem Beutel zählt mit." : "Die \(n) gleich guten in deinem Beutel zählen mit.",
          "Не худшие яйца в сумке тоже считаются (\(n)).")
    }
    func oakAlsoSetAside(_ amount: String) -> String {
        t("나머지 몫으로 \(amount)도 남겨 두세요.", "Keep \(amount) aside for the rest.", "残りの分として\(amount)もとっておこう。",
          "Guarda también \(amount) para el resto.", "Garde aussi \(amount) de côté pour les autres.",
          "Guarde também \(amount) para o resto.", "Leg auch \(amount) für den Rest zurück.", "Отложите и \(amount) на остальные.")
    }
    var oakNotYet: String {
        t("아직 사지 마세요. 다음 포켓몬이 들어오면 이 알은 더 가져올 새 포켓몬이 없을 수도 있어요.",
          "Not yet: once the next Pokémon is in, this egg may have nothing new left to bring.",
          "まだ買わないで。次のポケモンが加わると、このタマゴにはもう新しいものが残っていないかもしれません。",
          "Todavía no: cuando llegue el próximo Pokémon, puede que este huevo ya no tenga nada nuevo que traer.",
          "Pas encore : une fois le prochain Pokémon arrivé, cet œuf n'aura peut-être plus rien de nouveau à apporter.",
          "Ainda não: quando o próximo Pokémon chegar, este ovo talvez não tenha mais nada novo a trazer.",
          "Noch nicht: Sobald das nächste Pokémon da ist, hat dieses Ei vielleicht nichts Neues mehr zu bieten.",
          "Пока не покупайте: после следующего покемона в этом яйце может не остаться ничего нового.")
    }
    func oakBuyAndGiveCandies(_ buy: Int, _ give: Int, to name: String) -> String {
        t("이상한 사탕을 \(buy)개 사서 \(name)에게 \(give)개 주세요",
          buy == 1 ? "Buy a Rare Candy and give \(name) \(give)" : "Buy \(buy) Rare Candies and give \(name) \(give)",
          "ふしぎなアメを\(buy)個買って、\(name)に\(give)個あげよう",
          buy == 1 ? "Compra un Caramelo Raro y dale \(give) a \(name)" : "Compra \(buy) Caramelos Raros y dale \(give) a \(name)",
          buy == 1 ? "Achète un Super Bonbon et donnes-en \(give) à \(name)"
              : "Achète \(buy) Super Bonbons et donnes-en \(give) à \(name)",
          buy == 1 ? "Compre um Doce Raro e dê \(give) a \(name)" : "Compre \(buy) Doces Raros e dê \(give) a \(name)",
          buy == 1 ? "Kauf ein Sonderbonbon und gib \(name) \(give) davon"
              : "Kauf \(buy) Sonderbonbons und gib \(name) \(give) davon",
          "Купите редкие конфеты (\(buy)) и дайте ему \(give)")
    }
    func oakBuyAndKeepCandies(_ n: Int) -> String {
        t("이상한 사탕을 \(n)개 사서 아껴 두세요",
          n == 1 ? "Buy a Rare Candy and keep it" : "Buy \(n) Rare Candies and keep them",
          "ふしぎなアメを\(n)個買って、とっておこう",
          n == 1 ? "Compra un Caramelo Raro y guárdalo" : "Compra \(n) Caramelos Raros y guárdalos",
          n == 1 ? "Achète un Super Bonbon et garde-le" : "Achète \(n) Super Bonbons et garde-les",
          n == 1 ? "Compre um Doce Raro e guarde-o" : "Compre \(n) Doces Raros e guarde-os",
          n == 1 ? "Kauf ein Sonderbonbon und behalte es" : "Kauf \(n) Sonderbonbons und behalte sie",
          "Купите редкие конфеты (\(n)) и сохраните их")
    }
    var oakCandiesFromTheRest: String {
        t("알 값을 치르고 남겨 둔 뒤 남는 토큰이에요.", "What the balance has left once the eggs are paid for and set aside.",
          "タマゴの代金を払い、取り置いたあとに残るぶんです。", "Lo que queda del saldo tras pagar y apartar los huevos.",
          "Ce qui reste du solde une fois les œufs payés et mis de côté.",
          "O que sobra do saldo depois de pagar e separar os ovos.",
          "Was vom Guthaben bleibt, wenn die Eier bezahlt und zurückgelegt sind.", "Остаток баланса после оплаты и резерва яиц.")
    }
    var oakNoShopEggBeatsGraduation: String {
        t("상점의 어떤 알도 졸업 때 받는 알보다 새로운 걸 더 자주 가져오지 못해요.",
          "No Shop egg brings something new more often than the egg a graduation gives.",
          "ショップのどのタマゴも、卒業でもらえるタマゴより新しいものを連れてきません。",
          "Ningún huevo de la tienda trae algo nuevo más a menudo que el que da una graduación.",
          "Aucun œuf de la Boutique n'apporte du nouveau plus souvent que celui que donne un diplôme.",
          "Nenhum ovo da loja traz algo novo com mais frequência que o de uma formatura.",
          "Kein Ei im Laden bringt öfter Neues als das, das ein Abschied gibt.",
          "Ни одно яйцо магазина не приносит новое чаще, чем яйцо за выпуск.")
    }
    func oakShinyCharm(_ charm: String) -> String {
        t("\(charm)도 생각해 보세요", "Think of the \(charm)", "\(charm)も考えておこう", "Piensa en el \(charm)",
          "Pense au \(charm)", "Pense no \(charm)", "Denk an den \(charm)", "Подумайте о \"\(charm)\"")
    }
    func oakShinyCharmWhy(_ price: String) -> String {
        t("종도 폼도 바꾸지 않지만 이로치가 더 자주 나와요. 가격은 \(price)예요.",
          "It changes neither species nor forms, but makes shinies more frequent. It costs \(price).",
          "種類もフォルムも変えませんが、色違いが出やすくなります。値段は\(price)です。",
          "No cambia ni las especies ni las formas, pero hace los variocolores más frecuentes. Cuesta \(price).",
          "Il ne change ni les espèces ni les formes, mais rend les chromatiques plus fréquents. Il coûte \(price).",
          "Não muda nem as espécies nem as formas, mas deixa os shinies mais frequentes. Custa \(price).",
          "Er ändert weder Arten noch Formen, macht Schillernde aber häufiger. Er kostet \(price).",
          "Он не меняет ни виды, ни формы, но шайни будут попадаться чаще. Он стоит \(price).")
    }
    var oakWhyStock: String {
        t("알은 몇 개나 미리? 알이 N번에 한 번 새로운 걸 가져온다면 평균 N개가 필요해요. 가방에 있는 그만큼 좋은 알을 포함해 그만큼(최대 3개) 갖춰 두세요. 다음에 무엇이 나오든 쓸모가 남는 알만 미리 사고, 아니면 그 값을 남겨 두세요. 나머지 토큰은 이상한 사탕에 써요.",
          "How many eggs ahead? If an egg brings something new one time in N, it takes N on average: keep that many on hand, 3 at most, the Bag's as good included. Only buy ahead eggs that stay useful whatever comes next; otherwise set their price aside. The rest of the balance goes into Rare Candies.",
          "タマゴは前もって何個？新しいものを連れてくるのがN回に1回なら、平均N個必要です。バッグの同じくらい良いタマゴも含めて、その数（最大3個）をそろえておこう。次に何が来ても役に立ち続けるタマゴだけ前もって買い、そうでなければ代金をとっておこう。残りはふしぎなアメに。",
          "¿Cuántos huevos por adelantado? Si un huevo trae algo nuevo una vez de cada N, hacen falta N de media: ten esos a mano, 3 como máximo, incluidos los de tu Bolsa igual de buenos. Compra por adelantado solo huevos que sigan sirviendo pase lo que pase; si no, aparta su precio. El resto del saldo va a Caramelos Raros.",
          "Combien d'œufs d'avance ? Si un œuf apporte du nouveau une fois sur N, il en faut N en moyenne : garde-en autant sous la main, 3 au plus, ceux du Sac aussi bons compris. N'en achète d'avance que s'ils resteront utiles quoi qu'il arrive ensuite, sinon mets leur prix de côté. Le reste du solde part en Super Bonbons.",
          "Quantos ovos com antecedência? Se um ovo traz algo novo uma vez em N, são precisos N em média: tenha esses à mão, no máximo 3, incluindo os da sua Bolsa tão bons quanto. Só compre com antecedência ovos que continuem úteis aconteça o que acontecer; senão, separe o preço deles. O resto do saldo vai para Doces Raros.",
          "Wie viele Eier im Voraus? Bringt ein Ei einmal in N Fällen etwas Neues, braucht es im Schnitt N: Halte so viele auf Vorrat, höchstens 3, die gleich guten im Beutel eingerechnet. Kauf nur Eier im Voraus, die nützlich bleiben, was auch kommt; sonst leg ihren Preis zurück. Der Rest des Guthabens geht in Sonderbonbons.",
          "Сколько яиц заранее? Если яйцо приносит новое один раз из N, в среднем нужно N: держите столько в запасе, не больше 3, считая не худшие яйца в сумке. Заранее покупайте только яйца, которые останутся полезными, что бы ни случилось дальше; иначе отложите их цену. Остаток баланса уходит на редкие конфеты.")
    }
    var oakWhyTitle: String { t("왜?", "Why", "なぜ？", "Por qué", "Pourquoi", "Por quê", "Warum", "Почему") }
    var oakWhyCandies: String {
        t("이상한 사탕은 키우는 포켓몬에게 줘요. 단, 곧 놓아줄 중복 포켓몬에게는 주지 마세요. 경험치가 함께 사라지니 다음 포켓몬을 위해 아껴 두세요. 남는 경험치는 진화하면 다음 단계로 넘어가지만, 졸업할 때는 사라져요. 남은 양보다 많이 주지 마세요. 단, 10% 이하만 사라지는 마지막 하나는 괜찮아요.",
          "Rare Candies go to the Pokémon being raised, but not to a Spare you are going to release: its XP would go with it, so keep them for the next one. Extra XP carries over to the next stage when it evolves, but is lost at graduation: never give it more than it still needs, but for a last one that loses a tenth at most.",
          "ふしぎなアメは育てているポケモンに使います。ただし、これから逃がすダブりのポケモンには使わず、次のためにとっておきます。経験値も一緒に消えるからです。余った経験値は進化すると次の段階に持ち越されますが、卒業時には消えます。残りより多くは与えないこと。ただし、むだが1割以下の最後の1個はかまいません。",
          "Los Caramelos Raros van al Pokémon que crías, pero no a uno repetido que vas a soltar: su experiencia se iría con él, así que guárdalos para el siguiente. La experiencia sobrante pasa a la siguiente etapa cuando evoluciona, pero se pierde al graduarse: nunca le des más de lo que le falta, salvo un último que pierda como mucho una décima parte.",
          "Les Super Bonbons vont au Pokémon en cours, sauf à un Pokémon en trop que tu vas relâcher : son XP partirait avec lui, garde-les pour le suivant. L'XP en trop passe au stade suivant quand il évolue, mais elle est perdue au diplôme : n'en donne jamais plus qu'il ne lui reste, sauf un dernier qui en perdrait un dixième au plus.",
          "Os Doces Raros vão para o Pokémon que você cria, mas não para um repetido que você vai soltar: a experiência iria embora com ele, então guarde-os para o próximo. A experiência que sobra passa para a próxima fase quando ele evolui, mas se perde ao se formar: nunca dê mais do que falta, exceto um último que perca no máximo um décimo.",
          "Sonderbonbons bekommt das Pokémon, das du großziehst, aber kein doppeltes, das du freilassen wirst: Seine Erfahrung ginge mit ihm, also behalte sie für das nächste. Überschüssige Erfahrung geht bei einer Entwicklung in die nächste Stufe über, beim Abschied aber verloren: Gib ihm nie mehr, als ihm noch fehlt, außer einem letzten, das höchstens ein Zehntel verliert.",
          "Редкие конфеты даются покемону, которого вы растите, но не дубликату, которого вы отпустите: опыт уйдёт вместе с ним, так что сохраните их для следующего. Лишний опыт переходит на следующую стадию при эволюции, но теряется при выпуске: не давайте больше, чем ему осталось, кроме последней, которая потеряет не больше десятой части.")
    }
    func oakWhy(flute: String) -> String {
        t("중복 포켓몬은 도감에 아무것도 더하지 않아요. 계열의 모든 종이 같은 폼으로 이미 졸업했고, 그 폼의 첫 이로치도 아니며, 피카츄 코스튬이든 코스튬 컬렉션의 코스튬이든 없는 코스튬도 가져오지 않아요. 단 하나의 예외: 같은 전설의 포켓몬을 두 번째로 졸업시키면 \(KoreanParticle.subject.attach(to: flute)) 열리는 경우예요.",
          "A Pokémon is a Spare when it brings your Pokédex nothing: every species of its line is already graduated in its form, it is not your first shiny of that form, and it brings no costume you lack, neither a Pikachu costume nor one for your costume collection. The one exception: a legendary Spare, when its second graduated copy unlocks the \(flute).",
          "ダブりのポケモンは図鑑に何も加えません。系統のすべての種類がそのフォルムで卒業済みで、そのフォルムで初めての色違いでもなく、ピカチュウのものもコスチュームのコレクションのものも、足りないコスチュームを持ってきません。唯一の例外：同じ伝説のポケモンの2匹目の卒業で\(flute)が解放される場合です。",
          "Un Pokémon está repetido cuando no aporta nada a tu Pokédex: cada especie de su línea ya se graduó en su forma, no es tu primer variocolor de esa forma y no trae ningún disfraz que te falte, ni de Pikachu ni de tu colección de disfraces. La única excepción: un legendario repetido, cuando su segunda copia graduada desbloquea la \(flute).",
          "Un Pokémon est en trop quand il n'apporte rien à ton Pokédex : chaque espèce de sa lignée y est déjà diplômée sous sa forme, ce n'est pas ton premier chromatique de cette forme, et il n'apporte aucun costume qui te manque, ni de Pikachu ni de ta collection costumée. Seule exception : un légendaire en trop, quand son deuxième exemplaire diplômé débloque la \(flute).",
          "Um Pokémon é repetido quando não acrescenta nada à sua Pokédex: cada espécie da linha já se formou nessa forma, não é seu primeiro shiny dessa forma e não traz nenhuma fantasia que falte, nem de Pikachu nem da sua coleção de fantasias. A única exceção: um lendário repetido, quando a segunda cópia formada desbloqueia a \(flute).",
          "Ein Pokémon ist doppelt, wenn es deinem Pokédex nichts bringt: Jede Art seiner Linie ist in seiner Form schon verabschiedet, es ist nicht dein erstes Schillerndes dieser Form, und es bringt kein fehlendes Kostüm, weder für Pikachu noch für deine Kostümsammlung. Die einzige Ausnahme: ein doppeltes legendäres Pokémon, wenn sein zweites verabschiedetes Exemplar die \(flute) freischaltet.",
          "Покемон считается дубликатом, если ничего не добавляет в покедекс: все виды его линии в этой форме уже выпущены, это не первый шайни этой формы, и он не принесёт недостающий костюм: ни костюм Пикачу, ни костюм для вашей коллекции костюмов. Единственное исключение: легендарный дубликат, если второй выпущенный экземпляр открывает \"\(flute)\".")
    }
    var buy: String { t("구매", "Buy", "購入", "Comprar", "Acheter", "Comprar", "Kaufen", "Купить") }
    func buyConfirm(_ name: String) -> String { t("\(name) 구매할까요?", "Buy \(name)?", "\(name) を購入しますか？", "¿Comprar \(name)?", "Acheter \(name) ?", "Comprar \(name)?", "\(name) kaufen?", "Купить \"\(name)\"?") }
    func newsCount(_ n: Int) -> String {
        t("새 소식 \(n)개", "\(n) news", "お知らせ\(n)件", "\(n) novedades", "\(n) nouvelles", "\(n) novidades",
          "\(n) Neuigkeiten", "Новостей: \(n)")
    }
    func newsPosition(_ index: Int, _ count: Int) -> String {
        t("\(count)개 중 \(index)", "\(index) of \(count)", "\(count)件中\(index)件目", "\(index) de \(count)", "\(index) sur \(count)",
          "\(index) de \(count)", "\(index) von \(count)", "\(index) из \(count)")
    }
    var countsFor: String { t("이 포켓몬이 채워 주는 목표", "Counts toward", "この子が進める目標", "Cuenta para", "Compte pour",
                              "Conta para", "Zählt für", "Засчитывается в") }
    /// A goal of `CompanionStore.activeGoals`: an item, with its region for a regional one ("Rock Badge, Johto").
    var openAchievementHint: String {
        t("업적 보기", "See the achievement", "実績を見る", "Ver el logro", "Voir le succès", "Ver a conquista",
          "Erfolg ansehen", "Открыть успех")
    }
    func activeGoalName(_ goal: CompanionStore.ActiveGoal) -> String {
        let name = itemName(goal.item)
        guard let generation = goal.generation, goal.item != .excavation else { return name }
        return "\(name), \(regionName(generation: generation))"
    }
    /// The confirmation of a send-off, when the Pokémon still counts for goals.
    func stillCountsFor(_ name: String, _ list: String) -> String {
        t("\(KoreanParticle.subject.attach(to: name)) 아직 채워 주는 목표: \(list).", "\(name) still counts toward \(list).",
          "\(name)はまだこの目標を進めます：\(list)。", "\(name) aún cuenta para \(list).", "\(name) compte encore pour \(list).",
          "\(name) ainda conta para \(list).", "\(name) zählt noch für \(list).", "\"\(name)\" ещё засчитывается в: \(list).")
    }
    /// What the wallet lacks for a purchase ("Il te manque 12.4M").
    func shopMissing(_ amount: String) -> String {
        t("\(amount) 부족해요", "You need \(amount) more", "あと\(amount)足りません", "Te faltan \(amount)", "Il te manque \(amount)",
          "Faltam \(amount)", "Dir fehlen \(amount)", "Не хватает \(amount)")
    }
    /// Why a price is struck: the item that lowers it.
    func discountLine(_ item: ItemKind) -> String {
        let name = itemName(item)
        switch item {
        case .jadeOrb:
            return t("\(name): 알은 20% 더 할인", "\(name): another 20% off eggs", "\(name)：タマゴはさらに20%引き",
                     "\(name): un 20% menos más en huevos", "\(name) : encore 20 % de moins sur les œufs",
                     "\(name): mais 20% a menos nos ovos", "\(name): weitere 20 % weniger auf Eier",
                     "\"\(name)\": ещё 20% на яйца")
        default:
            return t("\(name): 25% 할인", "\(name): 25% off", "\(name)：25%引き", "\(name): 25% menos", "\(name) : 25 % de moins",
                     "\(name): 25% a menos", "\(name): 25 % weniger", "\"\(name)\": скидка 25%")
        }
    }
    func shinyOddsChange(from now: UInt64, to next: UInt64) -> String {
        t("이로치 확률: 1/\(now) → 1/\(next)", "Shiny odds: 1 in \(now) → 1 in \(next)", "色違いの確率：\(now)分の1 → \(next)分の1",
          "Probabilidad variocolor: 1 de \(now) → 1 de \(next)", "Chances chromatiques : 1 sur \(now) → 1 sur \(next)",
          "Chance de shiny: 1 em \(now) → 1 em \(next)", "Schillerchance: 1 zu \(now) → 1 zu \(next)",
          "Шанс на шайни: 1 из \(now) → 1 из \(next)")
    }
    /// The confirmation of a purchase with its total, so it stays in sight while paying.
    func buyConfirm(_ name: String, total: String) -> String {
        t("\(total)에 \(name) 구매할까요?", "Buy \(name) for \(total)?", "\(name)を\(total)で購入しますか？",
          "¿Comprar \(name) por \(total)?", "Acheter \(name) pour \(total) ?", "Comprar \(name) por \(total)?",
          "\(name) für \(total) kaufen?", "Купить \"\(name)\" за \(total)?")
    }
    func remainingAfterPurchase(_ amount: String) -> String {
        t("구매 후 \(amount) 남아요.", "You'll have \(amount) left.", "購入後は\(amount)残ります。", "Te quedarán \(amount).",
          "Il te restera \(amount).", "Vão sobrar \(amount).", "Danach bleiben dir \(amount).", "Останется \(amount).")
    }
    func eggsGoToBag(_ count: Int) -> String {
        count > 1
            ? t("가방에 들어가요.", "They go in your Bag.", "バッグに入ります。", "Van a tu bolsa.", "Ils vont dans ton sac.",
                "Vão para a sua bolsa.", "Sie kommen in deinen Beutel.", "Они попадут в сумку.")
            : t("가방에 들어가요.", "It goes in your Bag.", "バッグに入ります。", "Va a tu bolsa.", "Il va dans ton sac.",
                "Vai para a sua bolsa.", "Es kommt in deinen Beutel.", "Оно попадёт в сумку.")
    }
    var notEnoughTokens: String { t("토큰이 부족해요", "Not enough tokens", "トークンが足りません", "No tienes suficientes tokens", "Pas assez de tokens", "Tokens insuficientes", "Nicht genug Tokens", "Недостаточно токенов") }
    func ownedCount(_ n: Int) -> String { t("보유 ×\(n)", "Owned ×\(n)", "所持 ×\(n)", "En posesión ×\(n)", "Possédés ×\(n)", "Você tem ×\(n)", "Im Beutel ×\(n)", "Есть ×\(n)") }
    var shopPriceLabel: String { t("가격", "Price", "価格", "Precio", "Prix", "Preço", "Preis", "Цена") }
    var ownedAlready: String { t("보유 중", "Owned", "所持済み", "En posesión", "Possédé", "Já tem", "Im Beutel", "Уже есть") }

    // MARK: 업적 (체육관 배지 및 전설의 유물)
    var achievements: String { t("업적", "Achievements", "実績", "Logros", "Succès", "Conquistas", "Erfolge", "Успехи") }
    /// Popover tab title with the rewards ready to claim ("Achievements 2"). No parentheses, so a two-digit
    /// count still fits the tab bar; Russian shows no count at all, its five tab words already fill the bar.
    func achievementsTab(unclaimed: Int) -> String {
        guard unclaimed > 0 else { return achievements }
        let counted = "\(achievements) \(unclaimed)"
        return t(counted, counted, counted, counted, counted, counted, counted, achievements)
    }
    var claim: String { t("받기", "Claim", "受け取る", "Reclamar", "Récupérer", "Resgatar", "Einlösen", "Забрать") }
    var claimAll: String { t("모두 받기", "Claim all", "すべて受け取る", "Reclamar todo", "Tout récupérer", "Resgatar tudo", "Alle einlösen", "Забрать всё") }
    func notifAchievementsClaimedBody(_ count: Int) -> String {
        t("업적 보상 \(count)개를 가방에 받았어요.",
          "\(count) achievement rewards added to your bag.",
          "実績の報酬 \(count) 件をバッグに受け取りました。",
          "¡\(count) recompensas de logros añadidas a tu bolsa!",
          "\(count) récompenses de succès sont dans ton sac.",
          "\(count) recompensas de conquistas adicionadas à sua bolsa.",
          "\(count) Erfolgsbelohnungen wurden deinem Beutel hinzugefügt.",
          "Наград за успехи получено: \(count).")
    }
    var claimed: String { t("획득함", "Claimed", "獲得済み", "Conseguido", "Obtenu", "Resgatado", "Erhalten", "Получено") }
    /// Claim banner: how many rewards are ready and in which sections ("Stones 1, Artifacts 2").
    func readyToClaimSummary(_ count: Int, _ sections: String) -> String {
        t("받을 수 있는 업적 \(count)개 · \(sections)",
          "\(count) ready to claim: \(sections)",
          "受け取れる実績 \(count)件: \(sections)",
          "\(count) por reclamar: \(sections)",
          "\(count) à récupérer : \(sections)",
          "\(count) para resgatar: \(sections)",
          "\(count) zum Einlösen: \(sections)",
          "Можно забрать: \(count) · \(sections)")
    }
    /// What achievements count, under their progress.
    var achievementsGraduatedOnly: String {
        t("졸업한 포켓몬만 집계", "Graduated Pokémon only", "卒業したポケモンのみ", "Solo Pokémon graduados",
          "Pokémon diplômés seulement", "Só Pokémon formados", "Nur verabschiedete Pokémon", "Только выпущенные покемоны")
    }

    func achievementsProgress(_ count: Int, _ total: Int) -> String {
        t("\(total)개 중 \(count)개 완료",
          "\(count) of \(total) completed",
          "\(total)個中\(count)個達成",
          "\(count) de \(total) completados",
          "\(count) sur \(total) complétés",
          "\(count) de \(total) concluídos",
          "\(count) von \(total) abgeschlossen",
          "\(count) из \(total) получено")
    }
    var notifAchievementClaimedTitle: String {
        t("🏆 업적 달성!", "🏆 Achievement Unlocked!", "🏆 実績達成！", "🏆 ¡Logro completado!", "🏆 Succès débloqué !", "🏆 Conquista desbloqueada!", "🏆 Erfolg freigeschaltet!", "🏆 Достижение получено!")
    }
    func notifAchievementClaimedBody(_ name: String, count: Int = 1) -> String {
        // The Korean particle follows the name itself, so the count comes after it ("…을 5개").
        let koObject = KoreanParticle.object.attach(to: name) + (count > 1 ? " \(count)개" : "")
        let shown = count > 1 ? "\(name) ×\(count)" : name
        return t("\(koObject) 가방에 획득했어요.",
          "Obtained \(shown) in your bag.",
          "\(shown) をバッグに獲得しました。",
          "¡Obtuviste \(shown) en tu bolsa!",
          "\(shown) est dans ton sac.",
          "Você obteve \(shown) na sua bolsa.",
          "\(shown) wurde deinem Beutel hinzugefügt.",
          "\"\(shown)\" теперь в вашей сумке.")
    }

    /// The Legend Plate's claim: its two eggs, not the Plate.
    /// What one claim puts in the Bag: "Rare Egg ×2, Rare Candy ×5".
    func rewardsList(_ rewards: [(kind: ItemKind, count: Int)]) -> String {
        rewards.map { $0.count > 1 ? "\(itemName($0.kind)) ×\($0.count)" : itemName($0.kind) }.joined(separator: ", ")
    }

    func notifRewardsBody(_ rewards: [(kind: ItemKind, count: Int)]) -> String {
        let list = rewardsList(rewards)
        return t("가방에 획득했어요: \(list)", "Obtained in your bag: \(list).", "バッグに獲得しました：\(list)",
                 "¡Obtuviste en tu bolsa: \(list)!", "Dans ton sac : \(list).", "Você obteve na sua bolsa: \(list).",
                 "Deinem Beutel hinzugefügt: \(list).", "Теперь в вашей сумке: \(list).")
    }

    /// The goal of a forms achievement.
    var allFormsOfSpeciesGoal: String {
        t("모든 폼 졸업", "Every form graduated", "すべてのフォルムが卒業", "Todas las formas graduadas", "Toutes les formes diplômées",
          "Todas as formas formadas", "Alle Formen verabschiedet", "Все формы выпущены")
    }

    var notifLegendPlateBody: String {
        let rare = eggName(.rare), uncommon = eggName(.uncommon)
        return t("가방에 \(rare)과 \(uncommon)을 획득했어요.",
                 "Obtained a \(rare) and an \(uncommon) in your bag.",
                 "\(rare)と\(uncommon)をバッグに獲得しました。",
                 "¡Obtuviste un \(rare) y un \(uncommon) en tu bolsa!",
                 "Un \(rare) et un \(uncommon) sont dans ton sac.",
                 "Você obteve um \(rare) e um \(uncommon) na sua bolsa.",
                 "Ein \(rare) und ein \(uncommon) wurden deinem Beutel hinzugefügt.",
                 "\"\(rare)\" и \"\(uncommon)\" теперь в вашей сумке.")
    }

    /// Section titles of the Achievements tab. Kept to one word: the three segments and their counts
    /// must fit the 360 pt popover in every language (`testCategoryPickerFitsTheTabWidthInEveryLanguage`).
    func collectorGroupTitle(_ group: CollectorGroup) -> String {
        switch group {
        case .evolutionStones:
            return t("돌", "Stones", "いし", "Piedras", "Pierres", "Pedras", "Steine", "Камни")
        case .legendaryArtifacts:
            return t("유물", "Artifacts", "どうぐ", "Objetos", "Artefacts", "Objetos", "Artefakte", "Реликвии")
        case .gymBadges:
            return t("배지", "Badges", "バッジ", "Medallas", "Badges", "Insígnias", "Orden", "Значки")
        case .forms:
            return t("폼", "Forms", "フォルム", "Formas", "Formes", "Formas", "Formen", "Формы")
        }
    }
    var lockedLabel: String { t("잠김", "Locked", "ロック中", "Bloqueado", "Verrouillé", "Bloqueado", "Gesperrt", "Закрыто") }
    var unlockOr: String { t("또는", "or", "または", "o", "ou", "ou", "oder", "или") }
    /// Region of a generation (1 = Kanto) as the games name it.
    func regionName(generation: Int) -> String {
        switch generation {
        case 2: return t("성도", "Johto", "ジョウト", "Johto", "Johto", "Johto", "Johto", "Джото")
        case 3: return t("호연", "Hoenn", "ホウエン", "Hoenn", "Hoenn", "Hoenn", "Hoenn", "Хоэнн")
        case 4: return t("신오", "Sinnoh", "シンオウ", "Sinnoh", "Sinnoh", "Sinnoh", "Sinnoh", "Синно")
        case 5: return t("하나", "Unova", "イッシュ", "Teselia", "Unys", "Unova", "Einall", "Юнова")
        case 6: return t("칼로스", "Kalos", "カロス", "Kalos", "Kalos", "Kalos", "Kalos", "Калос")
        case 7: return t("알로라", "Alola", "アローラ", "Alola", "Alola", "Alola", "Alola", "Алола")
        case 8: return t("가라르", "Galar", "ガラル", "Galar", "Galar", "Galar", "Galar", "Галар")
        case 9: return t("팔데아", "Paldea", "パルデア", "Paldea", "Paldea", "Paldea", "Paldea", "Пальдея")
        default: return t("관동", "Kanto", "カントー", "Kanto", "Kanto", "Kanto", "Kanto", "Канто")
        }
    }
    /// Goal of a gym badge: every Pokémon of its type from one region.
    func badgeGoal(_ type: PokemonType, generation: Int) -> String {
        let tn = typeName(type), region = regionName(generation: generation)
        return t("\(region)의 모든 \(tn)타입 포켓몬", "Every \(region) \(tn)-type Pokémon", "\(region)のすべての\(tn)タイプのポケモン", "Todos los Pokémon de tipo \(tn) de \(region)", "Tous les Pokémon de type \(tn) de \(region)", "Todos os Pokémon do tipo \(tn) de \(region)", "Alle Pokémon vom Typ \(tn) aus \(region)", "Все покемоны типа \(tn) из региона \(region)")
    }
    func fossilsGoal(_ needed: Int) -> String {
        t("최종 진화한 화석 포켓몬 중 \(needed)마리", "Any \(needed) fully evolved fossil Pokémon", "最終進化の化石ポケモンのうち\(needed)匹",
          "\(needed) Pokémon fósiles totalmente evolucionados cualesquiera", "\(needed) Pokémon fossiles au stade final au choix",
          "\(needed) Pokémon fósseis totalmente evoluídos quaisquer", "\(needed) beliebige voll entwickelte Fossil-Pokémon",
          "Покемоны-окаменелости в последней стадии: любые \(needed)")
    }
    /// Every fossil line's final Pokémon (the Old Amber): "any" would read as a choice.
    func allFossilsGoal(_ count: Int) -> String {
        t("최종 진화한 화석 포켓몬 \(count)마리 모두", "All \(count) fully evolved fossil Pokémon", "最終進化の化石ポケモン\(count)匹すべて",
          "Los \(count) Pokémon fósiles totalmente evolucionados", "Les \(count) Pokémon fossiles au stade final",
          "Os \(count) Pokémon fósseis totalmente evoluídos", "Alle \(count) voll entwickelten Fossil-Pokémon",
          "Все \(count) покемонов-окаменелостей в последней стадии")
    }
    func ultraBeastsGoal(_ needed: Int) -> String {
        t("울트라비스트 중 \(needed)마리", "Any \(needed) Ultra Beasts", "ウルトラビーストのうち\(needed)匹", "\(needed) Ultraentes cualesquiera", "\(needed) Ultra-Chimères au choix", "\(needed) Ultracriaturas quaisquer", "\(needed) beliebige Ultrabestien", "Ультрачудовища: любые \(needed)")
    }
    func paradoxesGoal(_ needed: Int) -> String {
        t("패러독스 포켓몬 중 \(needed)마리", "Any \(needed) Paradox Pokémon", "パラドックスポケモンのうち\(needed)匹", "\(needed) Pokémon paradójicos cualesquiera", "\(needed) Pokémon Paradoxe au choix", "\(needed) Pokémon Paradoxo quaisquer", "\(needed) beliebige paradoxe Pokémon", "Парадоксальные покемоны: любые \(needed)")
    }
    func anyOfGoal(_ needed: Int) -> String {
        t("이 중 \(needed)마리", "Any \(needed) of these", "このうち\(needed)匹", "\(needed) de estos", "\(needed) parmi ceux-ci", "\(needed) destes", "\(needed) davon", "Любые \(needed) из них")
    }
    /// The Shop's section titles (2026-11-05).
    func shopSection(_ section: CompanionStore.ShopSection) -> String {
        switch section {
        case .eggs: t("알", "Eggs", "タマゴ", "Huevos", "Œufs", "Ovos", "Eier", "Яйца")
        case .raising: t("키우는 포켓몬에게", "For the Pokémon raised", "育てているポケモンに", "Para el Pokémon que crías",
                         "Pour le Pokémon en élevage", "Para o Pokémon que você cria", "Für das aufgezogene Pokémon",
                         "Для выращиваемого покемона")
        case .graduated: shopGraduatedSection
        case .dungeons: dungeonsTab
        case .keptForGood: t("영구 아이템", "Kept for good", "ずっと使えるどうぐ", "Para siempre", "Objets permanents",
                             "Para sempre", "Dauerhaft", "Навсегда")
        }
    }
    var ovalCharmEffectHint: String { t("빠진 폼만 부화 · 적용 중", "Missing forms only · active", "未収集フォルムのみ · 適用中", "Solo formas que faltan · activo", "Formes manquantes · actif", "Só formas que faltam · ativo", "Nur fehlende Formen · aktiv", "Только недостающие формы · активен") }
    /// Under Tauros's and Necrozma's artifacts in the Bag: what a complete line's weight is divided by now, both counted.
    func completeLinesEffectHint(_ divisor: Int) -> String {
        t("다 모은 계열 ÷\(divisor) · 적용 중", "Complete lines ÷\(divisor) · active", "そろった系統 ÷\(divisor) · 適用中",
          "Líneas completas ÷\(divisor) · activo", "Lignées complètes ÷\(divisor) · actif", "Linhas completas ÷\(divisor) · ativo",
          "Vollständige Linien ÷\(divisor) · aktiv", "Собранные линии ÷\(divisor) · активен")
    }
    var glimmeringCharmEffectHint: String { t("이로치 확정 · 적용 중", "Always shiny · active", "色違い確定 · 適用中", "Siempre variocolor · activo", "Chromatique garanti · actif", "Sempre shiny · ativo", "Immer schillernd · aktiv", "Всегда шайни · активен") }
    var allSpeciesGoal: String {
        t("모든 종", "Every species", "すべての種", "Todas las especies", "Toutes les espèces", "Todas as espécies", "Alle Spezies", "Все виды")
    }
    var allFormsGoal: String {
        t("모든 폼", "Every form", "すべてのフォルム", "Todas las formas", "Toutes les formes", "Todas as formas", "Alle Formen", "Все формы")
    }
    var allPikachuCostumesGoal: String {
        t("피카츄의 옷 전부", "Every one of Pikachu's costumes", "ピカチュウのいしょう すべて", "Todos los trajes de Pikachu",
          "Tous les costumes de Pikachu", "Todas as fantasias do Pikachu", "Alle Kostüme von Pikachu", "Все костюмы Пикачу")
    }
    var birthdayEggHint: String {
        t("무엇이 태어날까요?", "What will hatch?", "なにが生まれるかな？", "¿Qué saldrá?", "Qu'est-ce qui va éclore ?",
          "O que vai chocar?", "Was wohl schlüpft?", "Кто вылупится?")
    }
    var legendaryEggHint: String {
        t("전설 확정", "Guaranteed legendary", "伝説確定", "Legendario garantizado", "Légendaire garanti",
          "Lendário garantido", "Garantiert legendär", "Гарантированно легендарный")
    }
    var typeNullEggHint: String {
        t("타입:널 확정", "Guaranteed Type: Null", "タイプ：ヌル確定", "Código Cero garantizado", "Type:0 garanti",
          "Type: Null garantido", "Garantiert Typ:Null", "Гарантированно Тип: Ноль")
    }
    var silvallyMemoriesGoal: String {
        t("실버디의 메모리 (타입별 전설 1마리)", "Silvally's Memories (a legendary of each type)",
          "シルヴァディのメモリ (タイプごとに伝説1匹)", "Discos de Silvally (un legendario de cada tipo)",
          "ROM de Silvallié (un légendaire de chaque type)", "Memórias de Silvally (um lendário de cada tipo)",
          "Amigentos Disks (ein Legendäres pro Typ)", "Диски Сильвалли (легендарный каждого типа)")
    }
    /// One line above Silvally's forms: where they come from.
    var memoryFormsHint: String {
        t("타입별 전설의 포켓몬마다 폼이 하나씩 해금돼요.", "Each type's legendary Pokémon unlocks a form.",
          "タイプごとの伝説のポケモンでフォルムが1つ解放されます。", "Cada Pokémon legendario de un tipo desbloquea una forma.",
          "Chaque légendaire d'un type débloque une forme.", "Cada Pokémon lendário de um tipo desbloqueia uma forma.",
          "Jedes legendäre Pokémon eines Typs schaltet eine Form frei.", "Каждый легендарный покемон типа открывает форму.")
    }
    var duplicateLegendaryGoal: String {
        t("같은 전설의 포켓몬 2번 졸업", "Graduate the same legendary Pokémon twice", "同じ伝説のポケモンを2回卒業", "Gradúa dos veces al mismo Pokémon legendario", "Diplômer deux fois le même Pokémon légendaire", "Forme duas vezes o mesmo Pokémon lendário", "Dasselbe legendäre Pokémon zweimal verabschieden", "Выпустите одного и того же легендарного покемона дважды")
    }
    var shinyCharmEffectHint: String { t("이로치 확률 ↑ · 적용 중", "Shiny rate ↑ · active", "色違い率↑ · 適用中", "Prob. variocolor ↑ · activo", "Taux chromatique ↑ · actif", "Chance shiny ↑ · ativo", "Schillerchance ↑ · aktiv", "Шанс шайни ↑ · активен") }
    var legendCharmEffectHint: String { t("전설 출현 2× · 적용 중", "Legendary rate 2× · active", "伝説出現 2× · 適用中", "Prob. legendario 2× · activo", "Taux légendaire 2× · actif", "Chance lendária 2× · ativo", "Legendäre Chance 2× · aktiv", "Шанс легендарных 2× · активен") }
    var silverWingEffectHint: String { t("모두 +25% · 부화 ½ · 적용 중", "All +25% · eggs ½ · active", "全員+25% · タマゴ½ · 適用中", "Todos +25% · huevos ½ · activo", "Tous +25 % · œufs ½ · actif", "Todos +25% · ovos ½ · ativo", "Alle +25 % · Eier ½ · aktiv", "Все +25% · яйца ½ · активно") }
    var oldSeaMapEffectHint: String { t("성장 경험치 +20% · 적용 중", "Growth EXP +20% · active", "育成EXP +20% · 適用中", "EXP crecimiento +20% · activo", "EXP croissance +20% · actif", "EXP crescimento +20% · ativo", "Wachstums-EP +20% · aktiv", "Опыт роста +20% · активен") }
    var clearBellEffectHint: String { t("희귀 성장 +25% · 적용 중", "Rare growth +25% · active", "レア育成 +25% · 適用中", "Crec. raros +25% · activo", "Croissance Rares +25% · actif", "Cresc. raros +25% · ativo", "Seltene wachsen +25% · aktiv", "Рост редких +25% · активен") }
    var rainbowWingEffectHint: String { t("상점 할인 25% · 적용 중", "Shop discount 25% · active", "ショップ25%引 · 適用中", "Descuento tienda 25% · activo", "Réduction boutique 25% · actif", "Desconto loja 25% · ativo", "Ladenrabatt 25% · aktiv", "Скидка в магазине 25% · активна") }
    var magmaStoneEffectHint: String { t("중복 육성 25% 할인 · 적용 중", "Duplicate raising -25% · active", "重複育成25%減 · 適用中", "Crianza repetida -25% · activo", "Élevage doublon -25% · actif", "Criação repetida -25% · ativo", "Doppelte Zucht -25% · aktiv", "Повторный рост -25% · активен") }
    var soulDewEffectHint: String { t("사탕 경험치 +50% · 적용 중", "Candy EXP +50% · active", "アメEXP +50% · 適用中", "EXP caramelo +50% · activo", "EXP bonbon +50% · actif", "EXP doce +50% · ativo", "Bonbon-EP +50% · aktiv", "Опыт конфет +50% · активен") }
    var jadeOrbEffectHint: String { t("알 추가할인 20% · 적용 중", "Egg discount 20% · active", "タマゴ20%引 · 適用中", "Descuento huevos 20% · activo", "Réduction œufs 20% · actif", "Desconto ovos 20% · ativo", "Ei-Rabatt 20% · aktiv", "Скидка на яйца 20% · активна") }
    var gracideaEffectHint: String { t("첫 단계 +25% · 적용 중", "First stage +25% · active", "最初の段階 +25% · 適用中", "Primera etapa +25% · activo", "Premier stade +25% · actif", "Primeiro estágio +25% · ativo", "Erste Stufe +25% · aktiv", "Первая стадия +25% · активна") }
    var griseousOrbEffectHint: String { t("고스트·드래곤 성장 +30% · 적용 중", "Ghost & Dragon growth +30% · active", "ゴースト・ドラゴン育成 +30% · 適用中", "Crec. Fantasma y Dragón +30% · activo", "Croissance Spectre et Dragon +30% · actif", "Cresc. Fantasma e Dragão +30% · ativo", "Geist & Drache +30% · aktiv", "Рост Призраков и Драконов +30% · активен") }
    var libertyPassEffectHint: String { t("아직 졸업 전 육성 25% 할인 · 적용 중", "Not graduated yet -25% · active", "未卒業の育成25%減 · 適用中", "Aún sin graduar -25% · activo", "Pas encore diplômée -25% · actif", "Ainda não formada -25% · ativo", "Noch nicht verabschiedet -25% · aktiv", "Ещё не выпущена -25% · активен") }
    var revealGlassEffectHint: String { t("이로치 분모 ½ · 적용 중", "Shiny denom ½ · active", "色違い分母½ · 適用中", "Denominador shiny ½ · activo", "Dénominateur shiny ½ · actif", "Denominador shiny ½ · ativo", "Schiller-Nenner ½ · aktiv", "Знаменатель шайни ½ · активен") }
    var dnaSplicersEffectHint: String { t("성장 경험치 +50% · 적용 중", "Growth EXP +50% · active", "育成EXP +50% · 適用中", "EXP crecimiento +50% · activo", "EXP croissance +50% · actif", "EXP crescimento +50% · ativo", "Wachstums-EP +50% · aktiv", "Опыт роста +50% · активен") }
    func badgeEffectHint(_ percent: Double, type: PokemonType? = nil) -> String {
        let p = percentNumber(percent)
        if type == .normal {
            return t("노말 성장 +\(p)% · 적용 중", "Normal growth +\(p)% · active", "ノーマル育成 +\(p)% · 適用中", "Crec. Normal +\(p)% · activo", "Croissance Normal +\(p) % · actif", "Cresc. Normal +\(p)% · ativo", "Normal-Wachstum +\(p)% · aktiv", "Рост обычных +\(p)% · активен")
        }
        return t("약점 성장 +\(p)% · 적용 중", "Weakness growth +\(p)% · active", "弱点育成 +\(p)% · 適用中", "Crec. debilidad +\(p)% · activo", "Croissance faiblesse +\(p) % · actif", "Cresc. fraqueza +\(p)% · ativo", "Schwäche-Wachstum +\(p)% · aktiv", "Рост уязвимых +\(p)% · активен")
    }
    /// A percentage with at most one decimal, in the language's number format ("2.5", "2,5").
    func percentNumber(_ value: Double) -> String {
        value.formatted(.number.precision(.fractionLength(0...1)).locale(lang.displayLocale))
    }
    /// A gym badge's growth bonus so far and at most ("+5% / 22.5%").
    func badgeBonus(_ current: Double, of maximum: Double) -> String {
        let c = percentNumber(current), m = percentNumber(maximum)
        return t("+\(c)% / \(m)%", "+\(c)% / \(m)%", "+\(c)% / \(m)%", "+\(c)% / \(m)%", "+\(c) % / \(m) %", "+\(c)% / \(m)%", "+\(c)% / \(m)%", "+\(c)% / \(m)%")
    }
    func zygardeCubeEffectHint(_ percent: Int) -> String { t("성장 경험치 +\(percent)% · 적용 중", "Growth EXP +\(percent)% · active", "育成EXP +\(percent)% · 適用中", "EXP crecimiento +\(percent)% · activo", "EXP croissance +\(percent)% · actif", "EXP crescimento +\(percent)% · ativo", "Wachstums-EP +\(percent)% · aktiv", "Опыт роста +\(percent)% · активен") }
    var newFormBadge: String {
        t("새 폼", "New form", "新しいフォルム", "Nueva forma", "Nouvelle forme", "Nova forma", "Neue Form", "Новая форма")
    }
    var prisonBottleEffectHint: String { t("새 모습 성장 +50% · 적용 중", "New form growth +50% · active", "新しい姿 育成 +50% · 適用中", "Crec. forma nueva +50% · activo", "Croissance forme nouvelle +50% · actif", "Cresc. forma nova +50% · ativo", "Neue Form +50% · aktiv", "Рост новой формы +50% · активен") }
    var sparklingStoneEffectHint: String {
        let fairy = typeName(.fairy)
        return t("\(fairy) 성장 +30% · 적용 중", "\(fairy) growth +30% · active", "\(fairy)育成 +30% · 適用中", "Crec. \(fairy) +30% · activo", "Croissance \(fairy) +30% · actif", "Cresc. \(fairy) +30% · ativo", "\(fairy) +30% · aktiv", "Рост: \(fairy) +30% · активен")
    }
    var sunFluteEffectHint: String { t("최종 단계 +25% · 적용 중", "Final stage +25% · active", "最終段階 +25% · 適用中", "Última etapa +25% · activo", "Dernier stade +25% · actif", "Último estágio +25% · ativo", "Letzte Stufe +25% · aktiv", "Последняя стадия +25% · активна") }
    var beastBallEffectHint: String { t("울트라비스트 +50% · 적용 중", "Ultra Beasts +50% · active", "ウルトラビースト +50% · 適用中", "Ultraentes +50% · activo", "Ultra-Chimères +50% · actif", "Ultracriaturas +50% · ativo", "Ultrabestien +50% · aktiv", "Ультрачудовища +50% · активен") }
    var rustedSwordEffectHint: String { t("전설 성장 +25% · 적용 중", "Legendary growth +25% · active", "伝説育成 +25% · 適用中", "Crec. legendarios +25% · activo", "Croissance légendaires +25% · actif", "Cresc. lendários +25% · ativo", "Legendäre +25% · aktiv", "Рост легендарных +25% · активен") }
    var reinsOfUnityEffectHint: String {
        t("일반 제외 졸업마다 사탕 +1 · 적용 중", "+1 candy per graduation but Common · active", "ノーマル以外の卒業ごとにアメ+1 · 適用中",
          "+1 caramelo por graduación salvo Común · activo", "+1 bonbon par diplômé hors Communs · actif",
          "+1 doce por formatura exceto Comum · ativo", "+1 Bonbon pro Abschluss außer gewöhnlich · aktiv",
          "+1 конфета за выпуск, кроме обычных · активны")
    }
    var boosterEnergyEffectHint: String { t("패러독스 +50% · 적용 중", "Paradox +50% · active", "パラドックス +50% · 適用中", "Paradójicos +50% · activo", "Paradoxe +50% · actif", "Paradoxo +50% · ativo", "Paradox +50% · aktiv", "Парадоксы +50% · активна") }
    var tealMaskEffectHint: String {
        let names = CollectorBonus.tealMaskTypeList.map(typeName).joined(separator: "·")
        return t("\(names) +20% · 적용 중", "\(names) +20% · active", "\(names) +20% · 適用中", "\(names) +20% · activo", "\(names) +20% · actif", "\(names) +20% · ativo", "\(names) +20% · aktiv", "\(names) +20% · активна")
    }
    var teraOrbEffectHint: String { t("돌의 알 ½ · 그 포켓몬 +30% · 적용 중", "Stone egg ½ · its Pokémon +30% · active", "石のタマゴ½ · そのポケモン+30% · 適用中", "Huevo de piedra ½ · su Pokémon +30% · activo", "Œuf de pierre ½ · son Pokémon +30 % · actif", "Ovo de pedra ½ · seu Pokémon +30% · ativo", "Stein-Ei ½ · sein Pokémon +30 % · aktiv", "Яйцо из камня ½ · его покемон +30% · активна") }
    var relicStatueEffectHint: String { t("진화 없음 +25% · 적용 중", "No evolution +25% · active", "進化なし +25% · 適用中", "Sin evolución +25% · activo", "Sans évolution +25% · actif", "Sem evolução +25% · ativo", "Ohne Entwicklung +25% · aktiv", "Без эволюции +25% · активна") }
    var lunarWingEffectHint: String {
        let names = "\(typeName(.psychic))·\(typeName(.dark))"
        return t("\(names) +30% · 적용 중", "\(names) +30% · active", "\(names) +30% · 適用中", "\(names) +30% · activo", "\(names) +30% · actif", "\(names) +30% · ativo", "\(names) +30% · aktiv", "\(names) +30% · активно")
    }
    var meteoriteEffectHint: String { t("한도마다 사탕 +1 · 적용 중", "+1 candy per limit · active", "上限ごとにアメ+1 · 適用中", "+1 caramelo por límite · activo", "+1 bonbon par limite · actif", "+1 doce por limite · ativo", "+1 Bonbon pro Limit · aktiv", "+1 конфета за лимит · активен") }
    var oaksLetterEffectHint: String { t("스타팅 +25% · 적용 중", "Starters +25% · active", "御三家 +25% · 適用中", "Iniciales +25% · activo", "Pokémon de départ +25% · actif", "Iniciais +25% · ativo", "Starter +25% · aktiv", "Стартовые +25% · активно") }
    var seaIncenseEffectHint: String { t("확정 알 ½ · 그 포켓몬 +30% · 적용 중", "Guaranteed egg ½ · its Pokémon +30% · active", "確定タマゴ½ · そのポケモン+30% · 適用中", "Huevo garantizado ½ · su Pokémon +30% · activo", "Œuf à rareté garantie ½ · son Pokémon +30 % · actif", "Ovo garantido ½ · seu Pokémon +30% · ativo", "Garantie-Ei ½ · sein Pokémon +30 % · aktiv", "Яйцо с гарантией ½ · его покемон +30% · активен") }
    var shockDriveEffectHint: String {
        let n = CollectorBonus.shockDriveRechargeOneIn
        return t("사탕 \(n)개 중 1개 충전 · 적용 중", "1 candy in \(n) recharged · active", "アメ\(n)個に1個チャージ · 適用中",
                 "1 caramelo de cada \(n) recargado · activo", "1 bonbon sur \(n) rechargé · actif",
                 "1 doce em \(n) recarregado · ativo", "1 von \(n) Bonbons aufgeladen · aktiv",
                 "1 конфета из \(n) восстанавливается · активен")
    }
    var zRingEffectHint: String {
        let names = "\(typeName(.steel))·\(typeName(.electric))"
        return t("\(names) +30% · 적용 중", "\(names) +30% · active", "\(names) +30% · 適用中", "\(names) +30% · activo", "\(names) +30% · actif", "\(names) +30% · ativo", "\(names) +30% · aktiv", "\(names) +30% · активно")
    }
    var scrollOfDarknessEffectHint: String {
        let fighting = typeName(.fighting)
        return t("\(fighting) 성장 +30% · 적용 중", "\(fighting) growth +30% · active", "\(fighting)育成 +30% · 適用中", "Crec. \(fighting) +30% · activo", "Croissance \(fighting) +30% · actif", "Cresc. \(fighting) +30% · ativo", "\(fighting) +30% · aktiv", "Рост: \(fighting) +30% · активен")
    }
    var relicVaseEffectHint: String { t("중간 단계 +25% · 적용 중", "Middle stage +25% · active", "中間段階 +25% · 適用中", "Etapa intermedia +25% · activo", "Stade intermédiaire +25% · actif", "Estágio intermediário +25% · ativo", "Mittlere Stufe +25% · aktiv", "Средняя стадия +25% · активна") }
    /// The Explorer Kit: the graduations toward its next treasure.
    func explorerKitEffectHint(_ done: Int, of total: Int) -> String {
        t("다음 보물 \(done)/\(total) · 적용 중", "Next treasure \(done)/\(total) · active", "次の宝物 \(done)/\(total) · 適用中",
          "Próximo tesoro \(done)/\(total) · activo", "Prochain trésor \(done)/\(total) · actif",
          "Próximo tesouro \(done)/\(total) · ativo", "Nächster Schatz \(done)/\(total) · aktiv",
          "Следующее сокровище \(done)/\(total) · активен")
    }
    var oldAmberEffectHint: String {
        t("경험치 50% 이어받기 · 적용 중", "50% of the EXP passed on · active", "経験値50%引き継ぎ · 適用中",
          "50% de la experiencia transmitida · activo", "50 % de l'expérience transmise · actif",
          "50% da experiência passada · ativo", "50% der Erfahrung weitergegeben · aktiv", "50% опыта передаётся · активен")
    }
    /// The Legend Plate never sits in the Bag: its claim gives these two eggs.
    var legendPlateHint: String { "\(eggName(.rare)) + \(eggName(.uncommon))" }
    var fossilEggHint: String {
        t("아직 졸업하지 않은 화석 계열", "A fossil line not graduated yet", "まだ卒業していない化石の系統",
          "Una línea fósil aún sin graduar", "Une lignée fossile pas encore diplômée", "Uma linha fóssil ainda não formada",
          "Eine noch nicht verabschiedete Fossil-Linie", "Ещё не выпущенная линия окаменелостей")
    }
    /// On a forms goal too long to draw: the forms still missing.
    func missingFormsHint(_ names: [String]) -> String {
        let list = names.joined(separator: ", ")
        return t("아직 없는 폼: \(list)", "Still missing: \(list)", "まだないフォルム：\(list)", "Faltan: \(list)",
                 "Il manque : \(list)", "Faltam: \(list)", "Es fehlen: \(list)", "Не хватает: \(list)")
    }
    var excavationEggOpened: String {
        t("사용함", "Opened", "開けた", "Abierto", "Ouvert", "Aberto", "Geöffnet", "Открыто")
    }
    var excavationEggInBag: String {
        t("가방에", "In the Bag", "バッグの中", "En la Bolsa", "Dans le sac", "Na Bolsa", "Im Beutel", "В сумке")
    }
    var excavationEggReady: String {
        t("받을 수 있음", "To claim", "受け取れる", "Por reclamar", "À récupérer", "Para resgatar", "Abholbereit", "Можно забрать")
    }
    var excavationEggToEarn: String {
        t("앞으로 받을 알", "To earn", "これから", "Por ganar", "À gagner", "A ganhar", "Noch zu verdienen", "Впереди")
    }
    func excavationNextEgg(_ count: Int, of needed: Int) -> String {
        t("다음 알: 바위 타입 \(count)/\(needed)종", "Next egg: \(count)/\(needed) Rock-type species",
          "次のタマゴ: いわタイプ \(count)/\(needed)種", "Próximo huevo: \(count)/\(needed) especies de tipo Roca",
          "Prochain œuf : \(count)/\(needed) espèces de type Roche", "Próximo ovo: \(count)/\(needed) espécies do tipo Pedra",
          "Nächstes Ei: \(count)/\(needed) Gestein-Arten", "Следующее яйцо: \(count)/\(needed) видов каменного типа")
    }
    func excavationLines(_ owned: Int, of total: Int) -> String {
        t("졸업한 화석 계열: \(owned)/\(total)", "Fossil lines graduated: \(owned)/\(total)", "卒業した化石の系統: \(owned)/\(total)",
          "Líneas fósiles graduadas: \(owned)/\(total)", "Lignées fossiles diplômées : \(owned)/\(total)",
          "Linhas fósseis formadas: \(owned)/\(total)", "Verabschiedete Fossil-Linien: \(owned)/\(total)",
          "Выпущенные линии окаменелостей: \(owned)/\(total)")
    }
    var rotomCatalogEffectHint: String {
        t("새 폼 졸업마다 사탕 +1 · 적용 중", "+1 candy per new form graduated · active", "新フォルムの卒業ごとにアメ+1 · 適用中",
          "+1 caramelo por forma nueva graduada · activo", "+1 bonbon par nouvelle forme diplômée · actif",
          "+1 doce por forma nova formada · ativo", "+1 Bonbon pro neu verabschiedeter Form · aktiv",
          "+1 конфета за новую выпущенную форму · активен")
    }
    // 알 (리롤) — tier = 보증 등급 하한(nil = 보증 없는 기본 알).
    // 이름은 `rarityLabel(r) + " 알"` 식 조합으로 만들지 않는다: 한국어·영어는 맞아떨어져도 일본어에서
    // 조사가 어긋난다(レアのタマゴ vs 자연스러운 レアなタマゴ). 세 언어를 명시 트리플로 적는다.
    func eggName(_ tier: Rarity?) -> String {
        switch tier {
        case nil, .common?: return t("포켓몬 알", "Pokémon Egg", "ポケモンのタマゴ", "Huevo Pokémon", "Œuf Pokémon", "Ovo Pokémon", "Pokémon-Ei", "Яйцо покемона")
        case .uncommon?:  return t("고급 알", "Uncommon Egg", "アンコモンのタマゴ", "Huevo poco común", "Œuf peu commun", "Ovo incomum", "Ungewöhnliches Ei", "Необычное яйцо")
        case .rare?:      return t("희귀 알", "Rare Egg", "レアのタマゴ", "Huevo raro", "Œuf rare", "Ovo raro", "Seltenes Ei", "Редкое яйцо")
        case .legendary?: return t("전설 알", "Legendary Egg", "でんせつのタマゴ", "Huevo legendario", "Œuf légendaire", "Ovo lendário", "Legendäres Ei", "Легендарное яйцо")   // 미판매(FreshEgg.shopTiers)
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
                     "Verabschiede dein aktuelles Pokémon und starte mit einem neuen Ei.",
                     "Отпустите текущего покемона и начните заново с новым яйцом.")
        }
        let r = rarityLabel(tier)
        return t("지금 포켓몬을 놓아주고 \(r) 이상이 확정으로 나오는 알을 받아요.",
                 "Send off your current Pokémon for an egg guaranteed to hatch \(r) or better.",
                 "いまのポケモンを手放して \(r) 以上が確定で孵るタマゴをもらいます。",
                 "Suelta a tu Pokémon actual y consigue un huevo garantizado de \(r) o superior.",
                 "Laisse partir ton Pokémon actuel pour un œuf garanti \(r) ou mieux.",
                 "Solte seu Pokémon atual e ganhe um ovo que garante \(r) ou melhor.",
                 "Verabschiede dein aktuelles Pokémon und erhalte ein Ei, aus dem garantiert ein Pokémon der Seltenheitsstufe \(r) oder höher schlüpft.",
                 "Отпустите текущего покемона и получите яйцо с гарантией: \(r) или выше.")
    }
    /// A duration in its two largest units: "1 d 19 h", "6 h 12 min".
    func longDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = lang.displayLocale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 2
        formatter.allowedUnits = [.day, .hour, .minute]
        return formatter.string(from: max(60, seconds)) ?? ""
    }
    var raisingTitle: String { t("육성 기록", "Raising record", "育成記録", "Diario de crianza", "Carnet d'élevage", "Diário de criação", "Aufzuchtbuch", "Дневник выращивания") }
    var raisingHatched: String { t("부화", "Hatched", "孵化", "Eclosión", "Éclos", "Chocou", "Geschlüpft", "Вылупился") }
    var raisingGraduated: String { t("졸업", "Graduated", "卒業", "Graduado", "Diplômé", "Formado", "Verabschiedet", "Выпущен") }
    var raisingReleased: String { t("놓아줌", "Sent off", "手放した", "Soltado", "Relâché", "Solto", "Freigelassen", "Отпущен") }
    var raisingInProgress: String { t("키우는 중", "Raising", "育成中", "En crianza", "En cours", "Em criação", "Wird aufgezogen", "Растёт") }
    func raisingTook(_ duration: String) -> String {
        t("\(duration) 걸림", "in \(duration)", "\(duration)で", "en \(duration)", "en \(duration)", "em \(duration)", "in \(duration)", "за \(duration)")
    }
    func raisingSince(_ duration: String) -> String {
        t("\(duration)째", "for \(duration)", "\(duration)経過", "desde hace \(duration)", "depuis \(duration)", "há \(duration)",
          "seit \(duration)", "уже \(duration)")
    }
    var raisingTokens: String { t("토큰", "Tokens", "トークン", "Tokens", "Jetons", "Tokens", "Tokens", "Токены") }
    var raisingCost: String { t("예상 비용", "Estimated cost", "推定コスト", "Costo estimado", "Coût estimé", "Custo estimado", "Geschätzte Kosten", "Оценка стоимости") }
    var raisingModel: String { t("모델", "Model", "モデル", "Modelo", "Modèle", "Modelo", "Modell", "Модель") }
    func raisingMostly(_ name: String) -> String {
        t("주로 \(name)", "mostly \(name)", "主に\(name)", "sobre todo \(name)", "surtout \(name)", "principalmente \(name)",
          "vor allem \(name)", "в основном \(name)")
    }
    /// A duration in its largest unit, rounded: "40 min", "9 h", "3 d", in the language's units. Under a minute: one.
    func shortDuration(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = lang.displayLocale
        formatter.calendar = calendar
        formatter.unitsStyle = .short
        formatter.maximumUnitCount = 1
        let rounded: TimeInterval
        switch seconds {
        case ..<3_600: rounded = max(60, (seconds / 60).rounded() * 60); formatter.allowedUnits = [.minute]
        case ..<172_800: rounded = (seconds / 3_600).rounded() * 3_600; formatter.allowedUnits = [.hour]
        default: rounded = (seconds / 86_400).rounded() * 86_400; formatter.allowedUnits = [.day]
        }
        return formatter.string(from: rounded) ?? ""
    }
    /// The time before the next stage at the user's pace, under the Pokémon.
    func etaAbout(_ duration: String) -> String {
        t("약 \(duration)", "about \(duration)", "約\(duration)", "unas \(duration)", "environ \(duration)",
          "cerca de \(duration)", "etwa \(duration)", "около \(duration)")
    }
    /// The card of the Rare Candies a tool without limits pays by its tokens.
    var tokenCandiesTitle: String {
        t("토큰으로 받는 이상한 사탕", "Rare Candies from tokens", "トークンでもらうふしぎなアメ", "Caramelos Raros por tokens",
          "Super Bonbons par jetons", "Doces Raros por tokens", "Sonderbonbons durch Tokens", "Редкие конфеты за токены")
    }
    /// The rule: one candy for so many tokens.
    func tokenCandiesRule(_ tokens: String) -> String {
        t("\(tokens) 토큰마다 1개", "1 every \(tokens) tokens", "\(tokens)トークンごとに1個", "1 cada \(tokens) tokens",
          "1 tous les \(tokens) jetons", "1 a cada \(tokens) tokens", "1 alle \(tokens) Tokens", "1 за каждые \(tokens) токенов")
    }
    func tokenCandiesNext(_ remaining: String, earned: Int) -> String {
        t("다음까지 \(remaining) · \(earned)개 받음", "next in \(remaining) · \(earned) earned", "次まで\(remaining) · \(earned)個獲得",
          "siguiente en \(remaining) · \(earned) ganados", "prochain dans \(remaining) · \(earned) gagnés",
          "próximo em \(remaining) · \(earned) ganhos", "nächstes in \(remaining) · \(earned) verdient",
          "следующая через \(remaining) · получено: \(earned)")
    }
    var tokenCandiesHelp: String {
        t("이 도구에는 앱이 읽을 수 있는 한도가 없어요. 그래서 토큰이 바로 이상한 사탕이 되고, Claude Max 5x 요금제와 같은 속도로 들어와요. 한도가 없는 도구들의 토큰을 모두 합산해요.",
          "This tool has no limit the app can read, so its tokens pay Rare Candies themselves, at the pace Claude pays a Max 5x plan. The tokens of every tool without limits add up.",
          "このツールにはアプリが読める上限がありません。そのためトークンがそのままふしぎなアメになり、ClaudeのMax 5xプランと同じペースで届きます。上限のないツールのトークンはすべて合算されます。",
          "Esta herramienta no tiene un límite que la app pueda leer: sus tokens pagan Caramelos Raros al ritmo con que Claude paga un plan Max 5x. Se suman los tokens de todas las herramientas sin límites.",
          "Cet outil n'a pas de limite que l'app sait lire : ses jetons rapportent des Super Bonbons, au rythme où Claude les paie sur un forfait Max 5x. Les jetons de tous les outils sans limite s'additionnent.",
          "Esta ferramenta não tem um limite que o app consiga ler: seus tokens pagam Doces Raros no ritmo em que o Claude paga um plano Max 5x. Os tokens de todas as ferramentas sem limite se somam.",
          "Dieses Tool hat kein Limit, das die App lesen kann: Seine Tokens bringen selbst Sonderbonbons, im Tempo, in dem Claude einen Max-5x-Tarif bezahlt. Die Tokens aller Tools ohne Limit zählen zusammen.",
          "У этого инструмента нет лимита, который приложение может прочитать: его токены сами приносят Редкие конфеты, с той же скоростью, что Claude на тарифе Max 5x. Токены всех инструментов без лимитов суммируются.")
    }
    /// Where the candies came from, in their notification.
    var tokenCandiesSource: String {
        t("한도 없는 도구", "tools without limits", "上限のないツール", "herramientas sin límites", "outils sans limite",
          "ferramentas sem limite", "Tools ohne Limit", "инструменты без лимитов")
    }
    /// The Rare Candies a limit window paid, of those a whole window pays.
    func candyTally(_ paid: Int, of whole: Int) -> String {
        t("\(whole)개 중 \(paid)개", "\(paid) of \(whole)", "\(whole)個中\(paid)個", "\(paid) de \(whole)", "\(paid) sur \(whole)",
          "\(paid) de \(whole)", "\(paid) von \(whole)", "\(paid) из \(whole)")
    }
    /// The usage at which the window pays its next candy.
    func candyNext(_ percent: String) -> String {
        t("다음: \(percent)", "next at \(percent)", "次は\(percent)", "siguiente al \(percent)", "prochain à \(percent)",
          "próximo em \(percent)", "nächstes bei \(percent)", "следующая при \(percent)")
    }
    var candyWindowComplete: String {
        t("모두 받음", "all earned", "すべて獲得", "todos ganados", "tous gagnés", "todos ganhos", "alle verdient", "все получены")
    }
    func candyTallyHelp(_ candy: String) -> String {
        t("이 한도 창에서 받은 \(candy)이에요. 창이 찰수록 하나씩 들어와요.",
          "The \(candy) this limit window paid: one comes each time it fills a little more.",
          "この上限ウィンドウでもらった\(candy)です。ウィンドウが埋まるごとに1個ずつ届きます。",
          "Los \(candy) que pagó esta ventana de límite: llega uno cada vez que se llena un poco más.",
          "Les \(candy) gagnés sur cette fenêtre de limite : un de plus à chaque cran rempli.",
          "Os \(candy) que esta janela de limite pagou: chega um a cada vez que ela enche mais um pouco.",
          "Die \(candy), die dieses Limitfenster gezahlt hat: Mit jeder Stufe, die es sich füllt, kommt eines dazu.",
          "\"\(candy)\", полученные за это окно лимита: по одной за каждую заполненную ступень.")
    }
    /// A share of an egg's odds, whole: "<1%" for a share that rounds to none, ">99%" for one short of all.
    func oddsPercent(_ value: Int, share: Double) -> String {
        let shown = value == 0 && share > 0 ? "<1" : value >= 100 && share < 1 ? ">99" : "\(value)"
        return lang == .fr ? shown.replacingOccurrences(of: "<", with: "< ").replacingOccurrences(of: ">", with: "> ") + " %"
                           : shown + "%"
    }
    /// One rarity of an egg's odds: "Commun 78 %".
    func hatchOddsRarity(_ rarity: Rarity, _ percent: String) -> String { "\(rarityLabel(rarity)) \(percent)" }
    /// The share of an egg's odds that is a species never graduated.
    func hatchOddsNewSpecies(_ percent: String) -> String {
        t("새 종 \(percent)", "New species: \(percent)", "新しい種: \(percent)", "Especie nueva: \(percent)",
          "Nouvelle espèce : \(percent)", "Espécie nova: \(percent)", "Neue Art: \(percent)", "Новый вид: \(percent)")
    }
    var hatchOddsHelp: String {
        t("지금 부화한다면 나올 확률이에요. 도감에 따라 달라져요. 새 종: 아직 한 번도 졸업시키지 않은 포켓몬.",
          "The odds if the egg hatched now; they follow your Pokédex. New species: a Pokémon you never graduated.",
          "いま孵った場合の確率です。図鑑に合わせて変わります。新しい種: まだ一度も卒業させていないポケモン。",
          "Probabilidades si el huevo eclosionara ahora; cambian con tu Pokédex. Especie nueva: un Pokémon que nunca graduaste.",
          "Les chances si l'œuf éclosait maintenant ; elles suivent ton Pokédex. Nouvelle espèce : un Pokémon jamais diplômé.",
          "As chances se o ovo chocasse agora; elas seguem sua Pokédex. Espécie nova: um Pokémon que você nunca formou.",
          "Die Chancen, wenn das Ei jetzt schlüpfen würde; sie folgen deinem Pokédex. Neue Art: ein Pokémon, das du nie verabschiedet hast.",
          "Шансы, если бы яйцо вылупилось сейчас; они зависят от покедекса. Новый вид: покемон, которого вы ещё не выпускали.")
    }
    /// Under a greyed-out Fossil Egg while a Fossil Egg's own Pokémon grows (#90).
    var fossilEggInProgress: String {
        t("화석 알이 이미 진행 중이에요", "A Fossil Egg is already in progress", "化石のタマゴがすでに進行中です",
          "Ya hay un Huevo Fósil en curso", "Un œuf fossile est déjà en cours", "Já há um Ovo Fóssil em andamento",
          "Ein Fossil-Ei läuft bereits", "Яйцо-окаменелость уже в процессе")
    }
    /// Under a Shop egg: bought, it waits in the Bag, and the Pokémon is sent off only when the egg is used.
    var eggGoesToBag: String {
        t("구매한 알은 가방에 들어가요. 원할 때 써서 지금 포켓몬을 놓아줘요.",
          "A bought egg goes in your Bag: use it whenever you want to send off your current Pokémon.",
          "買ったタマゴはバッグに入ります。いまのポケモンを手放したいときに使ってください。",
          "El huevo comprado va a tu mochila: úsalo cuando quieras soltar a tu Pokémon actual.",
          "L'œuf acheté va dans ton sac : utilise-le quand tu veux laisser partir ton Pokémon actuel.",
          "O ovo comprado vai para a sua mochila: use quando quiser soltar seu Pokémon atual.",
          "Ein gekauftes Ei kommt in deinen Beutel: Benutze es, wann immer du dein aktuelles Pokémon verabschieden willst.",
          "Купленное яйцо попадает в сумку: используйте его, когда захотите отпустить текущего покемона.")
    }
    /// The Bag's hint under the Pokémon Egg, which guarantees no rarity.
    var eggAnyRarityHint: String {
        t("등급 무작위", "Any rarity", "レアリティはランダム", "Rareza al azar", "Rareté au hasard", "Raridade aleatória",
          "Beliebige Seltenheit", "Любая редкость")
    }
    /// 알 상태의 상점 알 카드 비활성 사유 — 항목은 보이되 구매 버튼 아래에 한 줄로 붙는다(EggCard).
    var eggShopLockedHint: String {
        t("지금 품고 있는 알이 부화하면 살 수 있어요.",
          "Available once your current egg hatches.",
          "いま抱えているタマゴが孵ると購入できます。",
          "Disponible cuando eclosione tu huevo actual.",
          "Disponible une fois ton œuf actuel éclos.",
          "Disponível quando seu ovo atual chocar.",
          "Verfügbar, sobald dein aktuelles Ei geschlüpft ist.",
          "Станет доступно, когда вылупится текущее яйцо.")
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
          "A released Pokémon stays in your Pokédex and can hatch again at the same odds; only the growth progress is lost.",
          "手放したポケモンも図鑑に残り、同じ確率でまた出会えます。失われるのは育てた進み具合だけです。",
          "El Pokémon liberado permanece en la Pokédex y puede volver a salir con la misma probabilidad; solo se pierde el progreso de crianza.",
          "Un Pokémon relâché reste dans le Pokédex et peut réapparaître avec la même probabilité ; seule la progression est perdue.",
          "O Pokémon solto continua na Pokédex e pode voltar a aparecer com a mesma chance; só o progresso de criação se perde.",
          "Ein freigelassenes Pokémon bleibt im Pokédex und kann mit gleicher Wahrscheinlichkeit wieder schlüpfen; nur der Aufzuchtfortschritt geht verloren.",
          "Отпущенный покемон остаётся в Покедексе и может вылупиться снова с тем же шансом; теряется только прогресс роста.")
    }
    /// 인큐베이션 중 표시하는 보증 배지 — 어떤 알을 품고 있는지 한 줄로.
    func eggGuaranteeHint(_ tier: Rarity) -> String {
        if tier == .legendary { return legendaryEggHint }   // nothing is better than legendary
        let r = rarityLabel(tier)
        return t("\(r) 이상 확정", "\(r) or better", "\(r) 以上確定", "\(r) o superior garantizado", "\(r) ou mieux garanti", "\(r) ou melhor garantido", "Garantiert \(r) oder besser", "\(r) или выше")
    }
    func eggConfirm(_ monName: String, _ eggName: String) -> String {
        t("\(KoreanParticle.object.attach(to: monName)) 놓아주고 \(KoreanParticle.direction.attach(to: eggName)) 바꿀까요?",
          "Send off \(monName) for the \(eggName)?",
          "\(monName) を手放して \(eggName) にしますか？",
          "¿Soltar a \(monName) y cambiarlo por \(eggName)?",
          "Laisser partir \(monName) pour le \(eggName) ?",
          "Soltar \(monName) e trocar pelo \(eggName)?",
          "\(monName) verabschieden und gegen \(eggName) tauschen?",
          "Отпустить \(monName) и взять \"\(eggName)\"?")
    }
    var freshEggShinyWarning: String { t("⚠️ 이로치 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This one is shiny! Really send it off?", "⚠️ 色違いです！本当に手放しますか？", "⚠️ ¡Este es variocolor! ¿Seguro que quieres soltarlo?", "⚠️ Celui-ci est chromatique ! Vraiment le laisser partir ?", "⚠️ Esse é shiny! Quer mesmo soltar?", "⚠️ Dieses Pokémon ist schillernd! Wirklich verabschieden?", "⚠️ Это шайни! Точно отпустить?") }
    var freshEggLegendaryWarning: String { t("⚠️ 전설 포켓몬이에요! 정말 놓아줄까요?", "⚠️ This is a Legendary Pokémon! Really send it off?", "⚠️ 伝説のポケモンです！本当に手放しますか？", "⚠️ ¡Es un Pokémon legendario! ¿Seguro que quieres soltarlo?", "⚠️ C'est un Pokémon légendaire ! Vraiment le laisser partir ?", "⚠️ Esse é um Pokémon lendário! Quer mesmo soltar?", "⚠️ Dieses Pokémon ist legendär! Wirklich verabschieden?", "⚠️ Это легендарный покемон! Точно отпустить?") }
    var freshEggDiscardShiny: String { t("이로치 놓아주기", "Send shiny off", "手放す", "Soltar variocolor", "Le laisser partir", "Soltar o shiny", "Verabschieden", "Отпустить шайни") }
    var freshEggDiscardValuable: String { t("놓아주기", "Send off", "手放す", "Soltar", "Laisser partir", "Soltar", "Verabschieden", "Отпустить") }

    // MARK: 사탕 획득 알림 ("왜 받는지" = 토큰 한도를 다 채운 수고에 대한 보상)
    func notifCandyTitle(item: String, count: Int) -> String {
        t("🍬 \(item) \(count)개를 받았어요!",
          "🍬 You got \(count)× \(item)!",
          "🍬 \(item)を\(count)個もらいました！",
          "🍬 ¡Has recibido \(count)× \(item)!",
          "🍬 Tu as reçu \(count)× \(item) !",
          "🍬 Você ganhou \(count)× \(item)!",
          "🍬 Du hast \(count)× \(item) erhalten!",
          "🍬 Вы получили: \(item) ×\(count)!")
    }
    /// Why candies came: the limit windows whose usage paid them, paid as they go (`RareCandy.candiesDue`).
    func notifCandyBody(window: String) -> String {
        t("\(window) 사용량으로 받은 사탕이에요. 포켓몬에게 써서 진화시켜 보세요!",
          "Earned with your usage: \(window). Use them to evolve your Pokémon!",
          "\(window)の使用量でもらったアメです。ポケモンに使って進化させよう！",
          "Ganados con tu uso: \(window). ¡Úsalos para evolucionar a tu Pokémon!",
          "Gagnés grâce à ton utilisation : \(window). Utilise-les pour faire évoluer ton Pokémon !",
          "Ganhos com o seu uso: \(window). Use no seu Pokémon para evoluir!",
          "Mit deiner Nutzung verdient: \(window). Verwende sie, um dein Pokémon zu entwickeln!",
          "Получены за использование: \(window). Используйте их, чтобы эволюционировать покемона!")
    }
}

/// The copy button of the card of the Pokémon raised (2026-11-09).
extension L {
    var catchImageCopyHint: String {
        t("이 포켓몬 이미지를 복사", "Copy an image of this Pokémon", "このポケモンの画像をコピー", "Copiar una imagen de este Pokémon",
          "Copier une image de ce Pokémon", "Copiar uma imagem deste Pokémon", "Ein Bild dieses Pokémon kopieren",
          "Скопировать изображение этого покемона")
    }
    var cardImageCopyHint: String {
        t("이 카드 이미지를 복사", "Copy an image of this card", "このカードの画像をコピー", "Copiar una imagen de esta tarjeta",
          "Copier une image de cette carte", "Copiar uma imagem deste cartão", "Ein Bild dieser Karte kopieren",
          "Скопировать изображение этой карточки")
    }
    var catchImageCopied: String {
        t("복사했어요", "Copied", "コピーしました", "Copiada", "Copiée", "Copiada", "Kopiert", "Скопировано")
    }
}

/// The Mint, back for the graduated Pokémon (2026-11-09).
extension L {
    var mintUse: String {
        t("성격 바꾸기", "Change the nature", "せいかくを変える", "Cambiar la naturaleza", "Changer la nature", "Mudar a natureza",
          "Wesen ändern", "Сменить характер")
    }
    func mintChanged(_ from: String?, _ to: String) -> String {
        let was = from.map { "\($0) → " } ?? ""
        return t("성격: \(was)\(to)", "Nature: \(was)\(to)", "せいかく：\(was)\(to)", "Naturaleza: \(was)\(to)",
                 "Nature : \(was)\(to)", "Natureza: \(was)\(to)", "Wesen: \(was)\(to)", "Характер: \(was)\(to)")
    }
    var natureNeutral: String {
        t("효과 없음", "no effect", "効果なし", "sin efecto", "sans effet", "sem efeito", "ohne Wirkung", "без эффекта")
    }
    var mintNoTarget: String {
        t("졸업한 포켓몬이 없어요", "No graduated Pokémon", "卒業したポケモンがいません", "Ningún Pokémon graduado",
          "Aucun Pokémon diplômé", "Nenhum Pokémon formado", "Kein verabschiedetes Pokémon", "Нет выпускников")
    }
}
