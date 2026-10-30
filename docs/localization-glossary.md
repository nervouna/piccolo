# Localization glossary

The terms the interface uses, in the eight languages it ships in. Use the term of a row
everywhere that concept appears, in every language, so that Piccolo reads the same from one
screen to the next. A new string that needs a term not listed here adds the row first.

The terms are macOS's own translations of the same things, taken from the system's
localization tables (see the Source column and the notes at the end). Where a term has no
system table, its translation is Piccolo's own and the Source column says so. Keep the
keyboard symbols (⌃ ⌥ ⇧ ⌘) and the name "Piccolo" as they are in every language.

| Term (English) | en | zh-Hans | zh-Hant | ja | fr | es | pt-BR | de | Source | Notes |
|---|---|---|---|---|---|---|---|---|---|---|
| Settings | Settings | 设置 | 設定 | 設定 | Réglages | Ajustes | Ajustes | Einstellungen | System Settings; AppKit MenuCommands (Settings…) | The app's window and its menu item. |
| System Settings | System Settings | 系统设置 | 系統設定 | システム設定 | Réglages Système | Ajustes del Sistema | Ajustes do Sistema | Systemeinstellungen | System Settings | The macOS app. |
| Accessibility | Accessibility | 辅助功能 | 輔助使用 | アクセシビリティ | Accessibilité | Accesibilidad | Acessibilidade | Bedienungshilfen | System Settings | The macOS permission and its pane. |
| Login Items | Login Items | 登录项 | 登入項目 | ログイン項目 | Ouverture | Ítems de inicio | Itens de Início | Anmeldeobjekte | LoginItems.appex | The macOS pane. |
| Launch at login | Launch at login | 登录时打开 | 在登入時打開 | ログイン時に開く | Ouvrir avec la session | Abrir al iniciar sesión | Abrir no Início da Sessão | Bei der Anmeldung öffnen | LoginItems.appex (Open at Login) | The switch in General. Apple's phrase for the same thing is "Open at Login". |
| Restart | Restart | 重新启动 | 重新啟動 | 再起動 | Redémarrer | Reiniciar | Reiniciar | neu starten | AppKit Menus (Restart); loginwindow (Restart) | The verb, as in "Restart Now". |
| Restart Now | Restart Now | 立即重新启动 | 立即重新啟動 | 今すぐ再起動 | Redémarrer | Reiniciar ahora | Reiniciar Agora | Jetzt neu starten | SoftwareUpdateSettingsExtension.appex (Restart Now) | The button of the restart prompt. |
| Quit | Quit | 退出 | 結束 | 終了 | Quitter | Salir | Encerrar | Beenden | AppKit Document (Quit) | "Quit Piccolo" is "Quit" and the name: Encerrar Piccolo, Piccoloを終了. |
| General | General | 通用 | 一般 | 一般 | Général | General | Geral | Allgemein | GeneralSettings.appex (General) | The Settings tab with the language and the login item. |
| Display | Display | 显示器 | 顯示器 | ディスプレイ | Moniteur | Pantalla | Tela | Display | ControlCenter (Display) | A monitor, as the system shows it. The pane is "Displays". |
| Window | Window | 窗口 | 視窗 | ウインドウ | Fenêtre | Ventana | Janela | Fenster | AppKit MenuCommands (Window) | |
| Shortcut | Shortcut | 快捷键 | 快速鍵 | ショートカット | Raccourci | Atajo | Atalho | Tastaturkurzbefehl | Accessibility (Shortcut); KeyboardSettings (Keyboard shortcut, de) | A global keyboard shortcut. In de, bare "Kurzbefehl" is the name of the Shortcuts app. |
| Default | Default | 默认 | 預設 | デフォルト | par défaut | Por omisión | padrão | Standard | AppKit FontManager (Default); KeyboardSettings (Default) | "System default" in the language picker means the language of the system. |
| Restore | Restore | 恢复 | 回復 | 復元 | Restaurer | Restaurar | Restaurar | Wiederherstellen | AppKit Revisions (Restore) | The button of the confirmation. |
| Restore Window | Restore Window | 恢复窗口 | 回復視窗 | ウインドウを復元 | Restaurer la fenêtre | Restaurar ventana | Restaurar janela | Fenster wiederherstellen | Piccolo (Restore + Window rows) | The action that puts a window back where Piccolo found it. |
| Nothing to restore | Nothing to restore | 没有可恢复的内容 | 沒有可回復的內容 | 復元するものがありません | Rien à restaurer | Nada que restaurar | Nada para restaurar | Nichts wiederherzustellen | Piccolo (Restore row) | The notice of Restore Window when there is no earlier position. |
| Grid | Grid | 网格 | 網格 | グリッド | grille | cuadrícula | grade | Raster | Piccolo | The layout of rows and columns. Apple's "grid" is the gridlines. |
| Rows | Rows | 行数 | 列數 | 行数 | lignes | filas | linhas | Zeilen | Piccolo | Also "Rows first" (fill order). |
| Columns | Columns | 列数 | 欄數 | 列数 | colonnes | columnas | colunas | Spalten | Piccolo | Also "Columns first". Grid columns, as in a table: Taiwan writes rows 列 and columns 欄, Japanese rows 行 and columns 列. Finder's 直欄 and カラム name its column view, not a count. |
| Arrange | Arrange | 排列 | 排列 | 配置 | Organiser | Disponer | Organizar | Anordnen | AppKit MenuCommands (Arrange) | Arrange windows in a grid. Apple's Spanish noun is Disposición. |
| Divider | Divider | 分隔线 | 分隔線 | 区切り線 | séparateur | divisor | divisor | Trennlinie | Piccolo | The line between linked windows. |
| Resize step | Resize step | 调整步长 | 調整步長 | 調整ステップ | pas de redimensionnement | paso de redimensionamiento | passo de redimensionamento | Schrittweite | Piccolo | The fraction a divider moves by. |
| Window animation | Window animation | 窗口动画 | 視窗動畫 | ウインドウのアニメーション | animation des fenêtres | animación de ventanas | animação de janelas | Fensteranimation | Piccolo | The speed setting; its values are Off, Fast, Medium and Slow (see the notes). |
| Window gap | Window gap | 窗口间距 | 視窗間距 | ウインドウの隙間 | marge des fenêtres | margen entre ventanas | margem entre janelas | Fensterabstand | DesktopSettings.appex (Tiled windows have margins) for ja (隙間), de (Abstand), fr (marge), es (márgenes) and pt-BR (margens); zh-Hans and zh-Hant are Piccolo's own | The space in points between windows Piccolo places and to the screen edges. Apple's zh-Hans 边缘空白 and zh-Hant 邊界 name the margin around a tiled window, not the space between two windows, so Piccolo says 间距 / 間距 (spacing). The unit "pt" is written as it is in every language. |
| Destination | Destination | 目标位置 | 目標位置 | 移動先 | destination | destino | destino | Ziel | Piccolo | Where the windows go, shown while a shortcut is held. |
| Preview | Preview | 预览 | 預覽 | プレビュー | Aperçu | Previsualización | Pré-visualización | Vorschau | AppKit MenuCommands (Preview); Finder (es noun) | |
| Frame | Frame | 窗口位置 | 視窗位置 | 位置とサイズ | position | posición | posição | Position | Piccolo (Finder: Size) | A window's place and size on the screen. |
| Custom | Custom | 自定义 | 自訂 | カスタム | personnalisé | personalizado | personalizado | Benutzerdefiniert | Piccolo | A frame that is not a preset. |
| Half | Half | 半屏 | 半部 | 半分 | moitié | mitad | metade | Hälfte | Piccolo | "Left Half", "Top Half", ... |
| Third | Third | 三分之一 | 三分之一 | 3分の1 | tiers | tercio | terço | Drittel | Piccolo | "Left Third", "Center Third", ... |
| Left | Left | 左侧 | 左側 | 左 | Gauche | Izquierda | Esquerda | Links | AppKit MenuCommands (Left) | |
| Right | Right | 右侧 | 右側 | 右 | Droite | Derecha | Direita | Rechts | AppKit MenuCommands (Right) | |
| Above | Above | 上方 | 上方 | 上 | au-dessus | arriba | acima | oben | Piccolo | The display above the source, in "Display Above". No table we checked has the word. |
| Below | Below | 下方 | 下方 | 下 | en dessous | abajo | abaixo | unten | Piccolo | The display below the source, in "Display Below". No table we checked has the word. |
| Top | Top | 顶部 | 頂部 | 上 | Haut | Superior | Superior | Oben | AppKit MenuCommands (Top) | |
| Center | Center | 居中 | 中央 | 中央に配置 | Centrer | Centrar | Centralizar | Zentriert | AppKit MenuCommands (Center) | |
| Maximize | Maximize | 最大化 | 最大化 | 最大化 | Maximiser | Maximizar | Maximizar | Maximieren | Piccolo | Apple's Move & Resize command for the same frame is Fill (Füllen, Remplir, …), but Piccolo's English says Maximize, so the translations say maximize too. |
| Config file | Config | 配置 | 設定檔 | 設定ファイル | configuration | configuración | configuração | Konfiguration | Piccolo | The file on disk. The label is "Config" / "Configuration". |
| Granted | Granted | 已授权 | 已允許 | 許可済み | Autorisée | Permitida | Permitida | Erlaubt | KeyboardSettings / SecurityPrivacyExtension (Allow) | Apple's word for the permission is "Allow"; the tables have no "Granted". Not granted: 未授权, 未允許, 未許可, Non autorisée, No permitida, Não permitida, Nicht erlaubt. |
| Escape | Esc | Esc | Esc | Esc | Esc | Esc | Esc | Esc | Accessibility (hotkey.key.escape); FunctionKeyNames (Esc, pt-BR) | Key name. |
| Delete | Delete | Delete | Delete | Delete | Supprimer | Suprimir | Apagar | Löschen | Terminal (⌫ Delete) | Key name. |
| Space | Space | 空格 | 空白鍵 | Space | Espace | Espacio | Espaço | Leertaste | AppKit FunctionKeyNames (Space) | Key name. Apple keeps "Space" in Japanese. |
| Enter | Enter | Enter | Enter | Enter | Entrée | Intro | Enter | Enter | Piccolo | Key name, the keypad key. No table we checked has it. |
| Help | Help | Help | Help | Help | Aide | Ayuda | Ajuda | Hilfetaste | AppKit FunctionKeyNames (Help) | Key name. |
| Clear | Clear | Clear | Clear | Clear | Effacer | Borrar | Limpar | Löschen | Terminal (Numeric Keypad Clear) | Key name, the keypad key. |
| Keypad | Keypad | Keypad | 數字鍵盤 | テンキー | pavé numérique | teclado numérico | Teclado Numérico | numerische Tastatur | Terminal (Numeric Keypad) | Keys of the numeric keypad. |
| Language | Language | 语言 | 語言 | 言語 | Langue | Idioma | Idioma | Sprache | AccessibilitySettingsExtension (Language); InternationalSettingsExtension (Language & Region) | The language picker in General. |
| Search | Search | 搜索 | 搜尋 | 検索 | Rechercher | Buscar | Buscar | Suchen | AppKit Common (Search) | The search field's prompt on the Shortcuts tab. |
| Reveal in Finder | Reveal in Finder | 在访达中显示 | 在Finder中顯示 | Finderに表示 | Afficher dans le Finder | Mostrar en el Finder | Mostrar no Finder | im Finder anzeigen | AppKit Menus (Show “%@” in Finder) | The menu item for the config file. |

## Source tables

The Source column names the table each translation comes from. The short names stand for these
files, all under `/System`:

- `AppKit …`: `Library/Frameworks/AppKit.framework/Resources/<name>.loctable`
- `System Settings`: `Applications/System Settings.app/Contents/Resources/Localizable.loctable`
- `<name>.appex`: `Library/ExtensionKit/Extensions/<name>.appex/Contents/Resources/` (its
  `Localizable.loctable`, or `InfoPlist.loctable` for the app's display name)
- `ControlCenter`: `Library/CoreServices/ControlCenter.app/Contents/Resources/<name>.loctable`
- `Terminal`: `Applications/Utilities/Terminal.app/Contents/Resources/keyDescriptions.loctable`
- `Finder`: `Library/CoreServices/Finder.app/Contents/Resources/<lang>.lproj/LocalizableMerged.strings`
- `loginwindow`: `Library/CoreServices/loginwindow.app/Contents/Resources/loginwindow.loctable`

The name in brackets is the key or the English text the translation was read from.
`Piccolo` means no table has the term: the translation is ours and is kept consistent by this file.

## Notes

- Where our English is not the phrase Apple uses for the same thing, the Source column gives
  Apple's phrase and its translation: Launch at login is "Open at Login", Reveal Config in Finder
  is "Show in Finder", and "Granted" is Apple's "Allow" as an adjective. The English texts stay as
  they are. Where Apple's phrase means something else than ours, ours wins: Maximize stays
  maximize (Apple's "Fill" is a different word), and Restart in zh-Hant is 重新啟動 (Apple's
  重新開機 is restarting the computer).
- Shortcut in German is Tastaturkurzbefehl (Apple's "Keyboard shortcut"), not the bare
  Kurzbefehl, which macOS uses for the Shortcuts app. The Shortcuts tab is Tastaturkurzbefehle
  for the same reason.
- Key names come from the system's key tables. Escape is "Esc" in every language (the
  Accessibility table for keyboard shortcuts), Delete is the name of the ⌫ key, Help and Space
  come from FunctionKeyNames, Keypad and Clear from the Terminal's Numeric Keypad names. Enter is
  not in any table we checked; its translation is ours. In Japanese Space, Help, Clear and
  Delete stay in English, as the key-name tables show them.
- Restore Defaults: macOS says Standard wiederherstellen, Rétablir les réglages par défaut,
  Restaurar valores por omisión, Restaurar Padrões, デフォルトに戻す and 回復預設值 (the
  KeyboardSettings and Accessibility tables). "Restore Default Shortcuts…" uses the same words
  for "Default", and "Restore" is the button word of Revisions.
- Apple's "grid" is the gridlines (格線, Gitter). The layout grid of Piccolo has no table and
  keeps 網格 in zh-Hant and Raster in de.
- Settings… keeps the ellipsis of the English text (…) in zh-Hant. macOS writes ⋯ there.
- Window animation values, in the order es, pt-BR, fr, de, ja, zh-Hant:
  Off: Desactivada, Desativada, Désactivée, Aus, オフ, 關閉.
  Fast: Rápida, Rápida, Rapide, Schnell, 速い, 快.
  Medium: Media, Média, Moyenne, Mittel, 中, 中.
  Slow: Lenta, Lenta, Lente, Langsam, 遅い, 慢.
  The Spanish, French and Brazilian Portuguese adjectives agree with "animação" and "animación"
  (feminine), so Apple's masculine Slow of the key-repeat table (pt-BR Lento) is not used.
- Keypad key names (Keypad, Enter, Help, Clear) stay in English in zh-Hans, and in zh-Hant
  for Enter, Help and Clear.
- Japanese: 設定 is Settings; the config file is always 設定ファイル, so the two never mix.
- French and Spanish: the adjectives agree with their nouns. fenêtre, Accessibilité and
  animation are feminine (autorisée, désactivée, lente; permitida, desactivada, lenta).
- Plural forms: French, Spanish, Brazilian Portuguese and German need `one` and `other`;
  Japanese and both Chinese languages have only `other`. `CatalogTests` checks this.
