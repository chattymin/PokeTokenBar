import Foundation

/// 앱 전체 UI 문자열 — 언어별. 단일 소스(AppLanguage)에서 파생한다.
/// 뷰는 `companion.l.<key>` 로 접근하며, language 변경 시 @Observable 로 자동 재렌더된다.
/// 포켓몬 이름은 PokéAPI 다국어 데이터(EvoLine.localizedName)에서 별도로 온다.
struct L {
    let lang: AppLanguage
    init(_ lang: AppLanguage) { self.lang = lang }

    /// 포크 전용 문자열용 6인자 오버로드 — 독일어는 영어로 폴백한다.
    /// 업스트림이 독일어(#234)를 추가하면서 `t` 가 7인자가 됐는데, 이 포크에만 있는 문자열까지
    /// 지어낸 번역으로 채우지는 않는다. 번역이 준비되면 개별 문자열을 7인자로 올리면 된다.
    private func t(_ ko: String, _ en: String, _ ja: String, _ es: String, _ fr: String, _ pt: String) -> String {
        t(ko, en, ja, es, fr, pt, en)
    }

    private func t(_ ko: String, _ en: String, _ ja: String, _ es: String, _ fr: String, _ pt: String, _ de: String) -> String {
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

    // MARK: 헤더 (오늘/주/월)
    var todayTokens: String { t("오늘 사용한 토큰", "Today's tokens", "本日のトークン", "Tokens de hoy", "Tokens du jour", "Tokens de hoje", "Heute verbrauchte Tokens") }
    var thisWeek: String { t("이번 주", "This week", "今週", "Esta semana", "Cette semaine", "Esta semana", "Diese Woche") }
    var thisMonth: String { t("이번 달", "This month", "今月", "Este mes", "Ce mois-ci", "Este mês", "Dieser Monat") }

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
    var monthly: String { t("월간", "Monthly", "月間", "Mensual", "Mensuel", "Mensal") }

    // MARK: 한도 이력 (로컬 기록)
    var limitHistory: String { t("한도 이력", "Limit history", "上限履歴", "Historial de límites", "Historique des limites", "Histórico de limites") }
    /// 아직 완료된 창이 없을 때. 이력은 서버가 주는 게 아니라 앱이 폴링하며 쌓는 것이라,
    /// "왜 비어 있나"를 설명해 주지 않으면 고장으로 읽힌다.
    var limitHistoryCollecting: String { t("기록 중 — 첫 한도 창이 리셋되면 표시된다", "Recording — appears once the first window resets", "記録中 — 最初の上限枠がリセットされると表示されます", "Registrando: aparecerá cuando se reinicie la primera ventana", "Enregistrement — s'affiche après la première réinitialisation", "Gravando — aparece quando a primeira janela reiniciar") }
    /// 관측 공백(앱 미실행)으로 잘린 창이 섞였을 때. 최고치는 하한이라는 뜻이라 반드시 알린다.
    var limitHistoryPartial: String { t("일부 구간은 앱이 꺼져 있어 관측되지 않음", "Some spans were not observed (app not running)", "一部の区間はアプリ未起動のため未観測", "Algunos tramos no se observaron (app cerrada)", "Certaines périodes non observées (app fermée)", "Alguns trechos não observados (app fechado)") }
    func limitHistoryRecent(_ n: Int) -> String { t("최근 \(n)회", "Last \(n)", "直近 \(n) 回", "Últimas \(n)", "\(n) dernières", "Últimas \(n)") }
    func limitHistoryPeak(_ p: String) -> String { t("최고 \(p)", "Peak \(p)", "最高 \(p)", "Máx. \(p)", "Max \(p)", "Máx. \(p)") }
    func limitHistoryMedian(_ p: String) -> String { t("중앙값 \(p)", "Median \(p)", "中央値 \(p)", "Mediana \(p)", "Médiane \(p)", "Mediana \(p)") }
    /// "12회 중 3회가 경고선(80%) 이상" — 요금제가 맞는지 판단하는 핵심 한 줄.
    func limitHistoryAtOrAbove(count: Int, total: Int, threshold: String) -> String {
        t("\(total)회 중 \(count)회가 \(threshold) 이상",
          "\(count) of \(total) reached \(threshold)",
          "\(total) 回中 \(count) 回が \(threshold) 以上",
          "\(count) de \(total) alcanzaron \(threshold)",
          "\(count) sur \(total) ont atteint \(threshold)",
          "\(count) de \(total) atingiram \(threshold)")
    }

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
    var back: String { t("뒤로", "Back", "戻る", "Atrás", "Retour", "Voltar", "Zurück") }
    var generalSectionTitle: String { t("일반", "General", "一般", "General", "Général", "Geral", "Allgemein") }
    var providersSectionTitle: String { t("프로바이더", "Providers", "プロバイダー", "Proveedores", "Fournisseurs", "Provedores", "Anbieter") }
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
    // MARK: 플로팅 펫
    var floatingPetSectionTitle: String { t("플로팅 펫", "Floating Pet", "フローティングペット", "Mascota flotante", "Compagnon flottant", "Mascote flutuante", "Schwebendes Pokémon") }
    var floatingPetEnableLabel: String { t("플로팅 펫 표시", "Show floating pet", "フローティングペットを表示", "Mostrar mascota flotante", "Afficher le compagnon flottant", "Mostrar mascote flutuante", "Schwebendes Pokémon anzeigen") }
    var phoneServerSectionTitle: String { t("iPhone 연결", "iPhone Connection", "iPhone 接続", "Conexión con iPhone", "Connexion iPhone", "Conexão com iPhone") }
    var phoneServerEnableLabel: String { t("아이폰 연결 허용", "Allow iPhone to connect", "iPhone の接続を許可", "Permitir conexión del iPhone", "Autoriser la connexion de l'iPhone", "Permitir conexão do iPhone") }
    var phoneServerHint: String {
        t("같은 네트워크의 아이폰 앱이 사용량을 가져갈 수 있게 포트 7845 를 엽니다. 페어링 코드를 아는 기기만 읽을 수 있어요.",
          "Opens port 7845 so the iPhone app on your network can fetch your usage. Only devices with the pairing code can read it.",
          "同じネットワーク上の iPhone アプリが使用量を取得できるようポート 7845 を開きます。ペアリングコードを知る端末だけが読めます。",
          "Abre el puerto 7845 para que la app de iPhone en tu red obtenga tu uso. Solo los dispositivos con el código pueden leerlo.",
          "Ouvre le port 7845 pour que l'app iPhone de ton réseau récupère ton utilisation. Seuls les appareils avec le code peuvent la lire.",
          "Abre a porta 7845 para o app do iPhone na sua rede buscar seu uso. Só aparelhos com o código conseguem ler.")
    }
    var phonePairingCodeLabel: String { t("페어링 코드", "Pairing code", "ペアリングコード", "Código de vinculación", "Code d'association", "Código de pareamento") }
    var phonePairingCodeHint: String {
        t("아이폰 앱 설정에 이 코드를 입력하세요. 같은 네트워크의 다른 기기가 사용량을 읽지 못하게 막아줍니다.",
          "Enter this code in the iPhone app's settings. It stops other devices on your network from reading your usage.",
          "iPhone アプリの設定にこのコードを入力してください。同じネットワーク上の他の端末が使用量を読み取るのを防ぎます。",
          "Introduce este código en los ajustes de la app de iPhone. Impide que otros dispositivos de tu red lean tu uso.",
          "Saisis ce code dans les réglages de l'app iPhone. Il empêche les autres appareils du réseau de lire ton utilisation.",
          "Digite este código nas configurações do app do iPhone. Impede que outros aparelhos na sua rede leiam seu uso.")
    }
    var phonePairingRegenerate: String { t("재발급", "Regenerate", "再発行", "Regenerar", "Régénérer", "Gerar novo") }
    var phonePairingRegenerateHint: String {
        t("코드가 노출됐을 때 새로 발급해요 — 아이폰에 새 코드를 다시 입력해야 합니다.",
          "Issue a new code if the current one leaked — you'll need to re-enter it on your iPhone.",
          "コードが漏れた場合は再発行します — iPhone に新しいコードを入力し直す必要があります。",
          "Genera un código nuevo si el actual se filtró — tendrás que volver a introducirlo en el iPhone.",
          "Génère un nouveau code si l'actuel a fuité — tu devras le saisir à nouveau sur ton iPhone.",
          "Gere um código novo se o atual vazou — você precisará digitá-lo de novo no iPhone.")
    }
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
    // MARK: Antigravity 자격증명 보관·폐기 (설정 → 고급)

    var antigravityCredentialTitle: String { t("Antigravity 연결", "Antigravity connection", "Antigravity 接続", "Conexión con Antigravity", "Connexion Antigravity", "Conexão com o Antigravity", "Antigravity-Verbindung") }
    /// 무엇이 보관돼 있고 무엇을 허용하는지 — 스코프를 이름으로 밝힌다. 이 파일은 회전하지 않는
    /// 자격증명이라, 사용자가 폐기 주기를 정하려면 "무엇을 들고 있는지" 를 알아야 한다.
    var antigravityCredentialHint: String {
        t("Antigravity 자격증명을 이 Mac에 평문으로 보관합니다(소유자 전용, 백업 제외). 이 토큰은 만료·교체되지 않으며 Google 계정의 cloud-platform 권한을 포함합니다.",
          "Antigravity credentials are stored on this Mac in plain text (owner-only, excluded from backups). This token never expires or rotates and carries your Google account's cloud-platform scope.",
          "Antigravity の認証情報をこの Mac に平文で保存します(所有者のみ・バックアップ対象外)。このトークンは失効も更新もされず、Google アカウントの cloud-platform 権限を含みます。",
          "Las credenciales de Antigravity se guardan en este Mac en texto plano (solo el propietario, excluidas de las copias de seguridad). Este token no caduca ni rota, e incluye el permiso cloud-platform de tu cuenta de Google.",
          "Les identifiants Antigravity sont stockés en clair sur ce Mac (propriétaire uniquement, exclus des sauvegardes). Ce jeton n'expire ni ne tourne, et porte la permission cloud-platform de votre compte Google.",
          "As credenciais do Antigravity ficam guardadas neste Mac em texto simples (somente o proprietário, fora dos backups). Esse token não expira nem é rotacionado e carrega o escopo cloud-platform da sua conta Google.",
          "Antigravity-Anmeldedaten werden auf diesem Mac im Klartext gespeichert (nur Eigentümer, von Backups ausgenommen). Dieses Token läuft nie ab, wird nicht rotiert und umfasst die cloud-platform-Berechtigung deines Google-Kontos.")
    }
    func antigravityCredentialAge(days: Int) -> String {
        t("\(days)일째 보관 중", "Stored for \(days) days", "\(days)日間保存中", "Guardado desde hace \(days) días", "Stocké depuis \(days) jours", "Guardado há \(days) dias", "Seit \(days) Tagen gespeichert")
    }
    var antigravityCredentialNone: String { t("보관 중인 자격증명 없음", "No stored credential", "保存された認証情報はありません", "No hay credenciales guardadas", "Aucun identifiant stocké", "Nenhuma credencial guardada", "Keine gespeicherten Anmeldedaten") }
    var antigravityCredentialNoneAgeUnknown: String { t("보관 중 (시작일 미기록)", "Stored (start date not recorded)", "保存中(開始日は未記録)", "Guardado (fecha de inicio no registrada)", "Stocké (date de début non enregistrée)", "Guardado (data de início não registrada)", "Gespeichert (Startdatum nicht erfasst)") }
    var antigravityRevoke: String { t("연결 해제", "Disconnect", "接続を解除", "Desconectar", "Déconnecter", "Desconectar", "Trennen") }
    /// 확인 문구는 **Antigravity 도 함께 끊긴다** 는 사실을 반드시 말한다 — 우리가 보관한 토큰은
    /// 우리 것이 아니라 Antigravity 의 것이고, 폐기하면 그쪽 로그인도 죽는다.
    var antigravityRevokeConfirm: String {
        t("Google에서 이 토큰을 폐기하고 로컬 보관본을 삭제합니다. 같은 자격증명을 쓰는 Antigravity도 로그아웃되어 다시 로그인해야 합니다. 되돌릴 수 없습니다.",
          "This revokes the token at Google and deletes the local copy. Antigravity uses the same credential, so it will be signed out and need to sign in again. This cannot be undone.",
          "Google 側でこのトークンを失効させ、ローカルの保存分を削除します。同じ認証情報を使う Antigravity もサインアウトされ、再ログインが必要になります。取り消せません。",
          "Esto revoca el token en Google y borra la copia local. Antigravity usa la misma credencial, así que se cerrará la sesión y tendrás que volver a iniciarla. No se puede deshacer.",
          "Cette action révoque le jeton chez Google et supprime la copie locale. Antigravity utilise le même identifiant : il sera déconnecté et devra se reconnecter. Action irréversible.",
          "Isso revoga o token no Google e apaga a cópia local. O Antigravity usa a mesma credencial, então ele será desconectado e precisará entrar novamente. Não dá para desfazer.",
          "Damit wird das Token bei Google widerrufen und die lokale Kopie gelöscht. Antigravity nutzt dieselben Anmeldedaten und wird abgemeldet – eine erneute Anmeldung ist nötig. Nicht rückgängig zu machen.")
    }
    var antigravityRevokeDone: String { t("폐기 완료 — Google에서 토큰이 무효화되고 로컬 보관본을 지웠습니다.", "Revoked — the token is invalid at Google and the local copy is deleted.", "失効しました — Google 側でトークンが無効になり、ローカルの保存分も削除しました。", "Revocado: el token ya no es válido en Google y se borró la copia local.", "Révoqué — le jeton est invalide chez Google et la copie locale est supprimée.", "Revogado — o token é inválido no Google e a cópia local foi apagada.", "Widerrufen – das Token ist bei Google ungültig und die lokale Kopie wurde gelöscht.") }
    var antigravityRevokeNothing: String { t("보관 중인 자격증명이 없습니다.", "There was no stored credential.", "保存された認証情報はありませんでした。", "No había credenciales guardadas.", "Aucun identifiant n'était stocké.", "Não havia credencial guardada.", "Es waren keine Anmeldedaten gespeichert.") }
    func antigravityRevokeFailed(_ reason: String) -> String {
        t("폐기하지 못했습니다(\(reason)) — 토큰은 아직 유효합니다. 로컬 보관본은 지우지 않았습니다.",
          "Could not revoke (\(reason)) — the token is still valid. The local copy was kept.",
          "失効できませんでした(\(reason)) — トークンは有効なままです。ローカルの保存分は残しています。",
          "No se pudo revocar (\(reason)): el token sigue siendo válido. Se conservó la copia local.",
          "Échec de la révocation (\(reason)) — le jeton reste valide. La copie locale a été conservée.",
          "Não foi possível revogar (\(reason)) — o token continua válido. A cópia local foi mantida.",
          "Widerruf fehlgeschlagen (\(reason)) – das Token ist weiterhin gültig. Die lokale Kopie wurde behalten.")
    }

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
        default: return error.localizedDescription
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
    var rarityLegendary: String { t("전설", "Legendary", "伝説", "Legendario", "Légendaire", "Lendário", "Legendär") }
    var dexFilterHint: String { t("탭하면 이 희귀도만 보기 · 다시 탭하면 전체", "Tap to show only this rarity · tap again to clear", "タップでこの希少度のみ表示・再タップで全体", "Toca para ver solo esta rareza · toca de nuevo para ver todo", "Touche pour n'afficher que cette rareté · touche à nouveau pour tout afficher", "Toque para ver só esta raridade · toque de novo para ver tudo", "Tippe, um nur diese Seltenheit zu sehen · tippe erneut für alle") }
    /// 도감 칸의 ✨ 를 읽어주는 명사 — 이모지는 스크린리더가 일관되게 읽지 못한다.
    var dexShinyLabel: String { t("이로치", "Shiny", "色違い", "Variocolor", "Chromatique", "Shiny", "Schillernd") }
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
    /// 403 = 인증은 됐고 권한이 없다. "다시 로그인"을 암시하면 안 된다 — 실측(2026-08-31)에서 서버는
    /// "유효한 라이선스가 없다"고 답했고, 재로그인으로는 절대 풀리지 않는다.
    var limitRefreshForbidden: String {
        t("이 계정은 한도 조회 권한이 없어요 (403). 다시 로그인해도 해결되지 않습니다 — 로그에 서버 응답이 남아요.",
          "This account isn't allowed to read limits (403). Signing in again won't help — the server's reason is in the log.",
          "このアカウントには上限を取得する権限がありません (403)。再ログインしても解決しません — サーバーの理由はログにあります。",
          "Esta cuenta no tiene permiso para leer los límites (403). Volver a iniciar sesión no ayudará — el motivo del servidor está en el registro.",
          "Ce compte n'est pas autorisé à lire les limites (403). Se reconnecter n'y changera rien — la raison du serveur est dans le journal.",
          "Esta conta não tem permissão para ler os limites (403). Entrar de novo não vai ajudar — o motivo do servidor está no log.")
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
    var opencodeGoFiveHour: String { t("OpenCode Go 5시간", "OpenCode Go 5-hour", "OpenCode Go 5時間", "OpenCode Go 5 horas", "OpenCode Go 5 h", "OpenCode Go 5 h") }
    var opencodeGoWeekly: String { t("OpenCode Go 주간", "OpenCode Go weekly", "OpenCode Go 週間", "OpenCode Go semanal", "OpenCode Go hebdo", "OpenCode Go semanal") }
    var opencodeGoMonthly: String { t("OpenCode Go 월간", "OpenCode Go monthly", "OpenCode Go 月間", "OpenCode Go mensual", "OpenCode Go mensuel", "OpenCode Go mensal") }

    // MARK: 폰·위젯 한도 라벨 (compact — 프로바이더 접두어 포함, Mac 이 현지화해 페이로드로 보낸다)
    var phoneClaude5h: String { t("Claude 5시간", "Claude 5h", "Claude 5時間", "Claude 5h", "Claude 5 h", "Claude 5 h") }
    var phoneClaudeWeekly: String { t("Claude 주간", "Claude Weekly", "Claude 週間", "Claude semanal", "Claude hebdo", "Claude semanal") }
    var phoneClaudeOpusWeekly: String { t("Claude Opus 주간", "Claude Opus Weekly", "Claude Opus 週間", "Claude Opus semanal", "Claude Opus hebdo", "Claude Opus semanal") }
    var phoneClaudeSonnetWeekly: String { t("Claude Sonnet 주간", "Claude Sonnet Weekly", "Claude Sonnet 週間", "Claude Sonnet semanal", "Claude Sonnet hebdo", "Claude Sonnet semanal") }
    /// 모델별 주간(weekly_scoped) — "Claude 주간 <모델>". 모델명이 없으면 접미어만.
    func phoneClaudeScoped(model: String?) -> String {
        guard let model else { return t("Claude 주간(모델별)", "Claude Weekly (scoped)", "Claude 週間（モデル別）", "Claude semanal (por modelo)", "Claude hebdo (par modèle)", "Claude semanal (por modelo)") }
        return t("Claude 주간 \(model)", "Claude Weekly \(model)", "Claude 週間 \(model)", "Claude semanal \(model)", "Claude hebdo \(model)", "Claude semanal \(model)")
    }
    var phoneCodex: String { t("Codex 5시간", "Codex 5h", "Codex 5時間", "Codex 5h", "Codex 5 h", "Codex 5 h") }
    var phoneCodexSecondary: String { t("Codex 주간", "Codex Weekly", "Codex 週間", "Codex semanal", "Codex hebdo", "Codex semanal") }
    var phoneGo5h: String { t("Go 5시간", "Go 5h", "Go 5時間", "Go 5h", "Go 5 h", "Go 5 h") }
    var phoneGoWeekly: String { t("Go 주간", "Go Weekly", "Go 週間", "Go semanal", "Go hebdo", "Go semanal") }
    var phoneGoMonthly: String { t("Go 월간", "Go Monthly", "Go 月間", "Go mensual", "Go mensuel", "Go mensal") }
    /// Antigravity 버킷 — "Antigravity <그룹> <창>". 그룹은 Gemini / Claude & GPT / 원문 표시명.
    func phoneAntigravity(group: String, window: String?, bucketId: String) -> String {
        let windowText: String
        if window == "5h" || bucketId.contains("5h") {
            windowText = t("5시간", "5h", "5時間", "5h", "5 h", "5 h")
        } else if window == "weekly" || bucketId.contains("weekly") {
            windowText = t("주간", "Weekly", "週間", "semanal", "hebdo", "semanal")
        } else {
            windowText = t("한도", "Limit", "上限", "Límite", "Limite", "Limite")
        }
        return "Antigravity \(group) \(windowText)"
    }
    var phoneAntigravityGeminiGroup: String { "Gemini" }
    var phoneAntigravityThirdPartyGroup: String { "Claude & GPT" }

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
}
