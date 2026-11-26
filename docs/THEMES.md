# MeshHub themes

The previous Light, Dark and Tactical theme choices and the fixed Tactical HUD palette have been removed. The four new app themes are original adaptations inspired by the references below; desktop themes, wallpaper assets and upstream theme code are not installed or bundled.

| Theme | Inspiration | MeshHub treatment |
| --- | --- | --- |
| Firesky | https://omarchythemes.com/themes/firesky — @dothash.win / bjarneo | Charcoal and olive-black surfaces, ember orange actions, muted teal and warm ivory text. Default on launch. |
| Cyberpunk | https://omarchythemes.com/themes/cyberpunk — thatmechguy | Deep violet surfaces, magenta actions and electric cyan details in the shared modern layout. |
| Retro 82 | https://omarchythemes.com/themes/omarchy-retro-82-theme — OldJobobo | Navy, amber, cream and sea green in the shared rounded-card layout. The upstream reference palette includes #00172e, #faa968, #f6dcac and #8cbfb8; muted labels are adjusted for readable contrast. |
| Bliss | https://omarchythemes.com/themes/bliss — mishonki3 | Soft gray and pale neutral surfaces, mint/forest accents, dark text and broad rounded panels. |

Select a theme from the palette icon at the top right, or Settings → Appearance. Selection is session-only, as in the previous theme system. The appearance applies to navigation, forms, buttons, cards, dialogs and Firmware Manager. The radio state, protocol selection and session data are independent of theme changes.

`mesh_theme.dart` owns the four palettes and shared rounded component styles. `modern_shell.dart` contains the welcome panel, adaptive session-summary cards and activity empty state. The desktop uses a floating navigation sidebar with labels on laptop widths; phones use a rounded bottom navigation bar. Retro 82 now shares the modern typography and layout instead of a separate console dashboard. The old `tactical_hud.dart` remains removed. Readiness labels remain tied to real session state; visual decoration does not imply connectivity or RF coverage.

Verification: all four themes have desktop (1200×900) and phone (390×844) render/switch tests, retired-choice absence checks and 4.5:1 minimum contrast checks for body text, muted text and primary button labels. Optional `MESHHUB_THEME_PREVIEWS=/tmp/meshhub-theme-previews flutter test test/theme_preview_test.dart` captures offline empty-session previews on this laptop. No device identifiers, channels or message contents are used in those captures.
