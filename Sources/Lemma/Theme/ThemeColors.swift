import SwiftUI
import AppKit
import LemmaCore

/// The workbench colours Lemma reads, under VS Code's names, so that any VS Code colour theme dresses the window.
enum TC: String, CaseIterable {
    // Base
    case foreground, descriptionForeground, disabledForeground, errorForeground, focusBorder
    case widgetShadow = "widget.shadow", widgetBorder = "widget.border", iconForeground = "icon.foreground"
    case sashHoverBorder = "sash.hoverBorder", contrastBorder, contrastActiveBorder
    case textLinkForeground = "textLink.foreground", textLinkActiveForeground = "textLink.activeForeground"
    case textPreformatForeground = "textPreformat.foreground", textPreformatBackground = "textPreformat.background"
    case textBlockQuoteBackground = "textBlockQuote.background", textBlockQuoteBorder = "textBlockQuote.border"
    case textCodeBlockBackground = "textCodeBlock.background", textSeparatorForeground = "textSeparator.foreground"
    case progressBarBackground = "progressBar.background", badgeBackground = "badge.background", badgeForeground = "badge.foreground"
    // Title bar and command center
    case titleBarActiveBackground = "titleBar.activeBackground", titleBarActiveForeground = "titleBar.activeForeground"
    case titleBarInactiveBackground = "titleBar.inactiveBackground", titleBarInactiveForeground = "titleBar.inactiveForeground"
    case titleBarBorder = "titleBar.border"
    case commandCenterBackground = "commandCenter.background", commandCenterForeground = "commandCenter.foreground"
    case commandCenterBorder = "commandCenter.border", commandCenterActiveBackground = "commandCenter.activeBackground"
    case commandCenterActiveForeground = "commandCenter.activeForeground", commandCenterActiveBorder = "commandCenter.activeBorder"
    // Activity bar
    case activityBarBackground = "activityBar.background", activityBarForeground = "activityBar.foreground"
    case activityBarInactiveForeground = "activityBar.inactiveForeground", activityBarBorder = "activityBar.border"
    case activityBarActiveBorder = "activityBar.activeBorder", activityBarActiveBackground = "activityBar.activeBackground"
    case activityBarBadgeBackground = "activityBarBadge.background", activityBarBadgeForeground = "activityBarBadge.foreground"
    // Side bar
    case sideBarBackground = "sideBar.background", sideBarForeground = "sideBar.foreground", sideBarBorder = "sideBar.border"
    case sideBarTitleForeground = "sideBarTitle.foreground", sideBarTitleBackground = "sideBarTitle.background"
    case sideBarSectionHeaderBackground = "sideBarSectionHeader.background", sideBarSectionHeaderForeground = "sideBarSectionHeader.foreground"
    case sideBarSectionHeaderBorder = "sideBarSectionHeader.border"
    // Lists and trees
    case listActiveSelectionBackground = "list.activeSelectionBackground", listActiveSelectionForeground = "list.activeSelectionForeground"
    case listActiveSelectionIconForeground = "list.activeSelectionIconForeground"
    case listInactiveSelectionBackground = "list.inactiveSelectionBackground", listInactiveSelectionForeground = "list.inactiveSelectionForeground"
    case listHoverBackground = "list.hoverBackground", listHoverForeground = "list.hoverForeground"
    case listFocusOutline = "list.focusOutline", listFocusAndSelectionOutline = "list.focusAndSelectionOutline"
    case listHighlightForeground = "list.highlightForeground", listFocusHighlightForeground = "list.focusHighlightForeground"
    case listErrorForeground = "list.errorForeground", listWarningForeground = "list.warningForeground", listDropBackground = "list.dropBackground"
    case treeIndentGuidesStroke = "tree.indentGuidesStroke"
    // Editor
    case editorBackground = "editor.background", editorForeground = "editor.foreground"
    case editorLineNumberForeground = "editorLineNumber.foreground", editorLineNumberActiveForeground = "editorLineNumber.activeForeground"
    case editorLineHighlightBackground = "editor.lineHighlightBackground", editorLineHighlightBorder = "editor.lineHighlightBorder"
    case editorSelectionBackground = "editor.selectionBackground", editorInactiveSelectionBackground = "editor.inactiveSelectionBackground"
    case editorFindMatchBackground = "editor.findMatchBackground", editorFindMatchHighlightBackground = "editor.findMatchHighlightBackground"
    case editorRangeHighlightBackground = "editor.rangeHighlightBackground", editorCursorForeground = "editorCursor.foreground"
    case editorIndentGuideBackground = "editorIndentGuide.background1", editorGutterBackground = "editorGutter.background"
    case editorGutterAddedBackground = "editorGutter.addedBackground", editorGutterModifiedBackground = "editorGutter.modifiedBackground"
    case editorGutterDeletedBackground = "editorGutter.deletedBackground", editorGutterFoldingControlForeground = "editorGutter.foldingControlForeground"
    case editorErrorForeground = "editorError.foreground", editorWarningForeground = "editorWarning.foreground"
    case editorInfoForeground = "editorInfo.foreground", editorHintForeground = "editorHint.foreground"
    case editorCodeLensForeground = "editorCodeLens.foreground"
    case editorInlayHintBackground = "editorInlayHint.background", editorInlayHintForeground = "editorInlayHint.foreground"
    case editorLinkActiveForeground = "editorLink.activeForeground"
    case editorWidgetBackground = "editorWidget.background", editorWidgetForeground = "editorWidget.foreground", editorWidgetBorder = "editorWidget.border"
    case editorHoverWidgetBackground = "editorHoverWidget.background", editorHoverWidgetBorder = "editorHoverWidget.border"
    case editorHoverWidgetForeground = "editorHoverWidget.foreground", editorHoverWidgetStatusBarBackground = "editorHoverWidget.statusBarBackground"
    case editorStickyScrollBackground = "editorStickyScroll.background", editorStickyScrollHoverBackground = "editorStickyScrollHover.background"
    case editorStickyScrollShadow = "editorStickyScroll.shadow"
    case editorBracketHighlight1 = "editorBracketHighlight.foreground1", editorBracketHighlight2 = "editorBracketHighlight.foreground2"
    case editorBracketHighlight3 = "editorBracketHighlight.foreground3"
    case editorSuggestWidgetBackground = "editorSuggestWidget.background", editorSuggestWidgetBorder = "editorSuggestWidget.border"
    case editorSuggestWidgetSelectedBackground = "editorSuggestWidget.selectedBackground", editorSuggestWidgetHighlightForeground = "editorSuggestWidget.highlightForeground"
    case editorStackFrameHighlightBackground = "editor.stackFrameHighlightBackground"
    case editorFocusedStackFrameHighlightBackground = "editor.focusedStackFrameHighlightBackground"
    // Peek view
    case peekViewBorder = "peekView.border", peekViewTitleBackground = "peekViewTitle.background"
    case peekViewTitleLabelForeground = "peekViewTitleLabel.foreground", peekViewTitleDescriptionForeground = "peekViewTitleDescription.foreground"
    case peekViewEditorBackground = "peekViewEditor.background", peekViewResultBackground = "peekViewResult.background"
    case peekViewResultFileForeground = "peekViewResult.fileForeground", peekViewResultLineForeground = "peekViewResult.lineForeground"
    case peekViewResultSelectionBackground = "peekViewResult.selectionBackground", peekViewResultSelectionForeground = "peekViewResult.selectionForeground"
    case peekViewResultMatchHighlightBackground = "peekViewResult.matchHighlightBackground"
    // Minimap, scrollbars, overview ruler
    case minimapBackground = "minimap.background", minimapSliderBackground = "minimapSlider.background"
    case minimapSliderHoverBackground = "minimapSlider.hoverBackground", minimapSliderActiveBackground = "minimapSlider.activeBackground"
    case minimapFindMatchHighlight = "minimap.findMatchHighlight", minimapSelectionHighlight = "minimap.selectionHighlight"
    case minimapErrorHighlight = "minimap.errorHighlight", minimapWarningHighlight = "minimap.warningHighlight"
    case scrollbarShadow = "scrollbar.shadow", scrollbarSliderBackground = "scrollbarSlider.background"
    case scrollbarSliderHoverBackground = "scrollbarSlider.hoverBackground", scrollbarSliderActiveBackground = "scrollbarSlider.activeBackground"
    case editorOverviewRulerBorder = "editorOverviewRuler.border", editorOverviewRulerFindMatchForeground = "editorOverviewRuler.findMatchForeground"
    case editorOverviewRulerErrorForeground = "editorOverviewRuler.errorForeground", editorOverviewRulerWarningForeground = "editorOverviewRuler.warningForeground"
    case editorOverviewRulerInfoForeground = "editorOverviewRuler.infoForeground", editorOverviewRulerModifiedForeground = "editorOverviewRuler.modifiedForeground"
    case editorOverviewRulerAddedForeground = "editorOverviewRuler.addedForeground"
    case editorOverviewRulerSelectionHighlightForeground = "editorOverviewRuler.selectionHighlightForeground"
    // Editor groups and tabs
    case editorGroupBorder = "editorGroup.border", editorGroupDropBackground = "editorGroup.dropBackground"
    case editorGroupHeaderTabsBackground = "editorGroupHeader.tabsBackground", editorGroupHeaderTabsBorder = "editorGroupHeader.tabsBorder"
    case editorGroupHeaderNoTabsBackground = "editorGroupHeader.noTabsBackground"
    case tabActiveBackground = "tab.activeBackground", tabActiveForeground = "tab.activeForeground", tabActiveBorder = "tab.activeBorder"
    case tabActiveBorderTop = "tab.activeBorderTop", tabInactiveBackground = "tab.inactiveBackground", tabInactiveForeground = "tab.inactiveForeground"
    case tabHoverBackground = "tab.hoverBackground", tabHoverForeground = "tab.hoverForeground", tabHoverBorder = "tab.hoverBorder"
    case tabUnfocusedActiveBackground = "tab.unfocusedActiveBackground", tabUnfocusedActiveForeground = "tab.unfocusedActiveForeground"
    case tabUnfocusedActiveBorderTop = "tab.unfocusedActiveBorderTop", tabUnfocusedInactiveForeground = "tab.unfocusedInactiveForeground"
    case tabBorder = "tab.border", tabActiveModifiedBorder = "tab.activeModifiedBorder"
    case breadcrumbForeground = "breadcrumb.foreground", breadcrumbBackground = "breadcrumb.background"
    case breadcrumbFocusForeground = "breadcrumb.focusForeground", breadcrumbActiveSelectionForeground = "breadcrumb.activeSelectionForeground"
    case breadcrumbPickerBackground = "breadcrumbPicker.background"
    // Panel
    case panelBackground = "panel.background", panelBorder = "panel.border"
    case panelTitleActiveForeground = "panelTitle.activeForeground", panelTitleInactiveForeground = "panelTitle.inactiveForeground"
    case panelTitleActiveBorder = "panelTitle.activeBorder", panelInputBorder = "panelInput.border", panelSectionBorder = "panelSection.border"
    case panelSectionHeaderBackground = "panelSectionHeader.background"
    // Status bar
    case statusBarBackground = "statusBar.background", statusBarForeground = "statusBar.foreground", statusBarBorder = "statusBar.border"
    case statusBarNoFolderBackground = "statusBar.noFolderBackground", statusBarNoFolderForeground = "statusBar.noFolderForeground"
    case statusBarDebuggingBackground = "statusBar.debuggingBackground", statusBarDebuggingForeground = "statusBar.debuggingForeground"
    case statusBarDebuggingBorder = "statusBar.debuggingBorder"
    case statusBarItemHoverBackground = "statusBarItem.hoverBackground", statusBarItemActiveBackground = "statusBarItem.activeBackground"
    case statusBarItemRemoteBackground = "statusBarItem.remoteBackground", statusBarItemRemoteForeground = "statusBarItem.remoteForeground"
    case statusBarItemRemoteHoverBackground = "statusBarItem.remoteHoverBackground"
    case statusBarItemProminentBackground = "statusBarItem.prominentBackground", statusBarItemProminentForeground = "statusBarItem.prominentForeground"
    case statusBarItemErrorBackground = "statusBarItem.errorBackground", statusBarItemErrorForeground = "statusBarItem.errorForeground"
    case statusBarItemWarningBackground = "statusBarItem.warningBackground", statusBarItemWarningForeground = "statusBarItem.warningForeground"
    // Inputs and buttons
    case inputBackground = "input.background", inputForeground = "input.foreground", inputBorder = "input.border"
    case inputPlaceholderForeground = "input.placeholderForeground"
    case inputOptionActiveBackground = "inputOption.activeBackground", inputOptionActiveBorder = "inputOption.activeBorder"
    case inputOptionActiveForeground = "inputOption.activeForeground", inputOptionHoverBackground = "inputOption.hoverBackground"
    case inputValidationErrorBackground = "inputValidation.errorBackground", inputValidationErrorBorder = "inputValidation.errorBorder"
    case dropdownBackground = "dropdown.background", dropdownForeground = "dropdown.foreground", dropdownBorder = "dropdown.border"
    case dropdownListBackground = "dropdown.listBackground"
    case buttonBackground = "button.background", buttonForeground = "button.foreground", buttonHoverBackground = "button.hoverBackground"
    case buttonBorder = "button.border", buttonSeparator = "button.separator"
    case buttonSecondaryBackground = "button.secondaryBackground", buttonSecondaryForeground = "button.secondaryForeground"
    case buttonSecondaryHoverBackground = "button.secondaryHoverBackground"
    case checkboxBackground = "checkbox.background", checkboxBorder = "checkbox.border", checkboxForeground = "checkbox.foreground"
    case toolbarHoverBackground = "toolbar.hoverBackground", toolbarActiveBackground = "toolbar.activeBackground"
    case keybindingLabelBackground = "keybindingLabel.background", keybindingLabelForeground = "keybindingLabel.foreground"
    case keybindingLabelBorder = "keybindingLabel.border", keybindingLabelBottomBorder = "keybindingLabel.bottomBorder"
    case actionBarToggledBackground = "actionBar.toggledBackground"
    // Quick input and menus
    case quickInputBackground = "quickInput.background", quickInputForeground = "quickInput.foreground"
    case quickInputTitleBackground = "quickInputTitle.background"
    case quickInputListFocusBackground = "quickInputList.focusBackground", quickInputListFocusForeground = "quickInputList.focusForeground"
    case quickInputListFocusIconForeground = "quickInputList.focusIconForeground"
    case pickerGroupForeground = "pickerGroup.foreground", pickerGroupBorder = "pickerGroup.border"
    case menuBackground = "menu.background", menuForeground = "menu.foreground", menuSelectionBackground = "menu.selectionBackground"
    case menuSelectionForeground = "menu.selectionForeground", menuSeparatorBackground = "menu.separatorBackground", menuBorder = "menu.border"
    // Notifications
    case notificationsBackground = "notifications.background", notificationsForeground = "notifications.foreground"
    case notificationsBorder = "notifications.border", notificationCenterBorder = "notificationCenter.border"
    case notificationCenterHeaderBackground = "notificationCenterHeader.background", notificationCenterHeaderForeground = "notificationCenterHeader.foreground"
    case notificationToastBorder = "notificationToast.border", notificationLinkForeground = "notificationLink.foreground"
    case notificationsErrorIconForeground = "notificationsErrorIcon.foreground", notificationsWarningIconForeground = "notificationsWarningIcon.foreground"
    case notificationsInfoIconForeground = "notificationsInfoIcon.foreground"
    // Welcome page and walkthroughs
    case welcomePageBackground = "welcomePage.background", welcomePageTileBackground = "welcomePage.tileBackground"
    case welcomePageTileHoverBackground = "welcomePage.tileHoverBackground", welcomePageTileBorder = "welcomePage.tileBorder"
    case welcomePageProgressBackground = "welcomePage.progress.background", welcomePageProgressForeground = "welcomePage.progress.foreground"
    case walkthroughStepTitleForeground = "walkthrough.stepTitle.foreground"
    // Settings editor
    case settingsHeaderForeground = "settings.headerForeground", settingsModifiedItemIndicator = "settings.modifiedItemIndicator"
    case settingsHeaderBorder = "settings.headerBorder", settingsSashBorder = "settings.sashBorder"
    case settingsDropdownBackground = "settings.dropdownBackground", settingsDropdownBorder = "settings.dropdownBorder"
    case settingsTextInputBackground = "settings.textInputBackground", settingsTextInputBorder = "settings.textInputBorder"
    case settingsCheckboxBackground = "settings.checkboxBackground", settingsCheckboxBorder = "settings.checkboxBorder"
    case settingsRowHoverBackground = "settings.rowHoverBackground", settingsFocusedRowBackground = "settings.focusedRowBackground"
    case settingsFocusedRowBorder = "settings.focusedRowBorder"
    // Debugging
    case debugToolBarBackground = "debugToolBar.background", debugToolBarBorder = "debugToolBar.border"
    case debugIconBreakpointForeground = "debugIcon.breakpointForeground", debugIconBreakpointDisabledForeground = "debugIcon.breakpointDisabledForeground"
    case debugIconBreakpointCurrentStackframeForeground = "debugIcon.breakpointCurrentStackframeForeground"
    case debugIconStartForeground = "debugIcon.startForeground", debugIconPauseForeground = "debugIcon.pauseForeground"
    case debugIconStopForeground = "debugIcon.stopForeground", debugIconRestartForeground = "debugIcon.restartForeground"
    case debugIconStepOverForeground = "debugIcon.stepOverForeground", debugIconStepIntoForeground = "debugIcon.stepIntoForeground"
    case debugIconStepOutForeground = "debugIcon.stepOutForeground", debugIconContinueForeground = "debugIcon.continueForeground"
    case debugIconStepBackForeground = "debugIcon.stepBackForeground"
    case debugTokenExpressionName = "debugTokenExpression.name", debugTokenExpressionValue = "debugTokenExpression.value"
    case debugTokenExpressionString = "debugTokenExpression.string", debugTokenExpressionNumber = "debugTokenExpression.number"
    case debugTokenExpressionBoolean = "debugTokenExpression.boolean", debugTokenExpressionError = "debugTokenExpression.error"
    case debugViewStateLabelForeground = "debugView.stateLabelForeground", debugViewStateLabelBackground = "debugView.stateLabelBackground"
    case debugViewValueChangedHighlight = "debugView.valueChangedHighlight"
    case debugConsoleInfoForeground = "debugConsole.infoForeground", debugConsoleWarningForeground = "debugConsole.warningForeground"
    case debugConsoleErrorForeground = "debugConsole.errorForeground"
    // Testing
    case testingIconPassed = "testing.iconPassed", testingIconFailed = "testing.iconFailed", testingIconErrored = "testing.iconErrored"
    case testingIconQueued = "testing.iconQueued", testingIconUnset = "testing.iconUnset", testingIconSkipped = "testing.iconSkipped"
    case testingRunAction = "testing.runAction", testingPeekBorder = "testing.peekBorder"
    // Terminal
    case terminalBackground = "terminal.background", terminalForeground = "terminal.foreground", terminalBorder = "terminal.border"
    case terminalSelectionBackground = "terminal.selectionBackground", terminalCursorForeground = "terminalCursor.foreground"
    case terminalAnsiRed = "terminal.ansiRed", terminalAnsiGreen = "terminal.ansiGreen", terminalAnsiYellow = "terminal.ansiYellow"
    case terminalAnsiBlue = "terminal.ansiBlue", terminalAnsiMagenta = "terminal.ansiMagenta", terminalAnsiCyan = "terminal.ansiCyan"
    case terminalAnsiBrightBlack = "terminal.ansiBrightBlack"
    // Notebooks
    case notebookEditorBackground = "notebook.editorBackground", notebookCellBorderColor = "notebook.cellBorderColor"
    case notebookFocusedCellBorder = "notebook.focusedCellBorder", notebookFocusedEditorBorder = "notebook.focusedEditorBorder"
    case notebookCellEditorBackground = "notebook.cellEditorBackground", notebookCellHoverBackground = "notebook.cellHoverBackground"
    case notebookFocusedCellBackground = "notebook.focusedCellBackground", notebookSelectedCellBackground = "notebook.selectedCellBackground"
    case notebookCellToolbarSeparator = "notebook.cellToolbarSeparator", notebookOutputContainerBackgroundColor = "notebook.outputContainerBackgroundColor"
    case notebookOutputContainerBorderColor = "notebook.outputContainerBorderColor", notebookCellInsertionIndicator = "notebook.cellInsertionIndicator"
    case notebookStatusSuccessIconForeground = "notebookStatusSuccessIcon.foreground", notebookStatusErrorIconForeground = "notebookStatusErrorIcon.foreground"
    case notebookStatusRunningIconForeground = "notebookStatusRunningIcon.foreground"
    // Charts
    case chartsForeground = "charts.foreground", chartsLines = "charts.lines", chartsRed = "charts.red", chartsBlue = "charts.blue"
    case chartsYellow = "charts.yellow", chartsOrange = "charts.orange", chartsGreen = "charts.green", chartsPurple = "charts.purple"
    // Symbol icons
    case symbolIconClassForeground = "symbolIcon.classForeground", symbolIconFunctionForeground = "symbolIcon.functionForeground"
    case symbolIconMethodForeground = "symbolIcon.methodForeground", symbolIconVariableForeground = "symbolIcon.variableForeground"
    case symbolIconConstantForeground = "symbolIcon.constantForeground", symbolIconKeywordForeground = "symbolIcon.keywordForeground"
    case symbolIconNumberForeground = "symbolIcon.numberForeground", symbolIconModuleForeground = "symbolIcon.moduleForeground"
    case symbolIconNamespaceForeground = "symbolIcon.namespaceForeground", symbolIconStructForeground = "symbolIcon.structForeground"
    case symbolIconInterfaceForeground = "symbolIcon.interfaceForeground", symbolIconEnumeratorForeground = "symbolIcon.enumeratorForeground"
    case symbolIconTypeParameterForeground = "symbolIcon.typeParameterForeground", symbolIconFieldForeground = "symbolIcon.fieldForeground"
    case symbolIconEventForeground = "symbolIcon.eventForeground", symbolIconFileForeground = "symbolIcon.fileForeground"
    case symbolIconKeyForeground = "symbolIcon.keyForeground", symbolIconPropertyForeground = "symbolIcon.propertyForeground"
    case symbolIconReferenceForeground = "symbolIcon.referenceForeground", symbolIconTextForeground = "symbolIcon.textForeground"
    case symbolIconOperatorForeground = "symbolIcon.operatorForeground", symbolIconBooleanForeground = "symbolIcon.booleanForeground"
    case symbolIconStringForeground = "symbolIcon.stringForeground", symbolIconArrayForeground = "symbolIcon.arrayForeground"
    case symbolIconSnippetForeground = "symbolIcon.snippetForeground"
    // Decorations
    case gitDecorationAddedResourceForeground = "gitDecoration.addedResourceForeground"
    case gitDecorationModifiedResourceForeground = "gitDecoration.modifiedResourceForeground"
    case gitDecorationDeletedResourceForeground = "gitDecoration.deletedResourceForeground"
    case gitDecorationUntrackedResourceForeground = "gitDecoration.untrackedResourceForeground"
    case problemsErrorIconForeground = "problemsErrorIcon.foreground", problemsWarningIconForeground = "problemsWarningIcon.foreground"
    case problemsInfoIconForeground = "problemsInfoIcon.foreground"
    case extensionButtonProminentBackground = "extensionButton.prominentBackground"
    case extensionButtonProminentForeground = "extensionButton.prominentForeground"
    case extensionButtonProminentHoverBackground = "extensionButton.prominentHoverBackground"
    case extensionIconStarForeground = "extensionIcon.starForeground", extensionIconVerifiedForeground = "extensionIcon.verifiedForeground"
    case chatRequestBackground = "chat.requestBackground", chatRequestBorder = "chat.requestBorder"
    case chatSlashCommandBackground = "chat.slashCommandBackground", chatSlashCommandForeground = "chat.slashCommandForeground"
    case bannerBackground = "banner.background", bannerForeground = "banner.foreground", bannerIconForeground = "banner.iconForeground"
    case editorCommentsWidgetRangeBackground = "editorCommentsWidget.rangeBackground"

    var id: String { rawValue }
}

/// What a code token is, for the Lab's Python, a derivation's LaTeX and Markdown notes.
enum TokenRole: CaseIterable {
    case keyword, control, string, number, comment, function, builtin, type, constant, parameter, variable, `operator`
    case punctuation, decorator, command, mathSymbol, heading, emphasis, strong, link, code

    /// TextMate scopes, most specific first, as themes colour them.
    var scopes: [String] {
        switch self {
        case .keyword: ["keyword", "storage.type", "storage"]
        case .control: ["keyword.control", "keyword"]
        case .string: ["string.quoted", "string"]
        case .number: ["constant.numeric", "constant"]
        case .comment: ["comment", "punctuation.definition.comment"]
        case .function: ["entity.name.function", "support.function"]
        case .builtin: ["support.function.builtin", "support.function", "entity.name.function"]
        case .type: ["entity.name.type.class", "entity.name.type", "support.class", "support.type", "entity.name.class"]
        case .constant: ["constant.language", "variable.language", "constant"]
        case .parameter: ["variable.parameter", "variable"]
        case .variable: ["variable.other", "variable"]
        case .operator: ["keyword.operator", "keyword"]
        case .punctuation: ["punctuation", "meta.brace"]
        case .decorator: ["entity.name.function.decorator", "meta.decorator", "punctuation.decorator", "storage.type"]
        case .command: ["support.function.general.tex", "support.function.be.latex", "support.function", "keyword.control", "keyword"]
        case .mathSymbol: ["constant.character.math.tex", "variable.parameter.function.latex", "variable", "constant"]
        case .heading: ["markup.heading", "entity.name.section", "keyword"]
        case .emphasis: ["markup.italic", "emphasis"]
        case .strong: ["markup.bold", "strong"]
        case .link: ["markup.underline.link", "string.other.link", "markup.link"]
        case .code: ["markup.inline.raw", "markup.fenced_code", "string"]
        }
    }
}

/// A resolved theme: every workbench colour the window reads, computed once when the theme changes. Each colour's
/// stand-in (an alias, or one derived from the theme's kind) is resolved here too, and the AppKit and SwiftUI colours
/// are made on first use and kept: views read dozens of colours at every redraw, and each read used to make new
/// colour objects (and, for colours the theme leaves out, scan their names and parse hex strings).
struct WorkbenchColors {
    let theme: ColorTheme
    private let values: [TC: RGBA]
    private let resolved: [TC: RGBA]
    private let tokens: [TokenRole: RGBA]
    private let made = MadeColors()

    var kind: ThemeKind { theme.kind }
    var isDark: Bool { theme.kind.isDark }
    var isHighContrast: Bool { theme.kind.isHighContrast }

    init(theme: ColorTheme, defaults: ColorDefaults) {
        self.theme = theme
        let resolver = ColorResolver(theme: theme, defaults: defaults)
        var values: [TC: RGBA] = [:]
        for key in TC.allCases { if let colour = resolver.color(key.rawValue) { values[key] = colour } }
        self.values = values
        var resolved = values
        for key in TC.allCases where resolved[key] == nil {
            if let fallback = WorkbenchColors.fallbacks[key], let value = values[fallback] { resolved[key] = value }
            else { resolved[key] = WorkbenchColors.lastResort(key, dark: theme.kind.isDark, values: values) }
        }
        self.resolved = resolved
        let foreground = values[.editorForeground] ?? values[.foreground] ?? (theme.kind.isDark ? RGBA(0.8, 0.8, 0.8) : RGBA(0.2, 0.2, 0.2))
        var tokens: [TokenRole: RGBA] = [:]
        for role in TokenRole.allCases { tokens[role] = theme.tokenColor(role.scopes) ?? theme.defaultTokenForeground ?? foreground }
        self.tokens = tokens
    }

    /// A colour, with a sensible stand-in when neither the theme nor VS Code's defaults give one.
    func rgba(_ key: TC) -> RGBA { resolved[key] ?? WorkbenchColors.lastResort(key, dark: isDark, values: values) }

    /// Whether the theme or VS Code's defaults actually define this colour (borders are often deliberately absent).
    func has(_ key: TC) -> Bool { values[key] != nil }

    subscript(_ key: TC) -> Color { made.color(key) { Color(nsColor: ns(key)) } }
    func ns(_ key: TC) -> NSColor { made.ns(key) { rgba(key).nsColor } }
    func token(_ role: TokenRole) -> NSColor { made.token(role) { (tokens[role] ?? rgba(.editorForeground)).nsColor } }
    func tokenStyle(_ role: TokenRole) -> String? { theme.tokenStyle(for: role.scopes.first ?? "")?.fontStyle }

    /// An optional border: clear when the theme leaves it undefined, as VS Code draws nothing then.
    func border(_ key: TC) -> Color { has(key) ? self[key] : .clear }

    /// Colours the theme names by aliases that VS Code resolves itself.
    static let fallbacks: [TC: TC] = [
        .titleBarActiveBackground: .sideBarBackground, .titleBarActiveForeground: .foreground,
        .titleBarInactiveBackground: .titleBarActiveBackground, .titleBarInactiveForeground: .descriptionForeground,
        .commandCenterBackground: .inputBackground, .commandCenterForeground: .titleBarActiveForeground,
        .commandCenterActiveBackground: .toolbarHoverBackground, .commandCenterActiveForeground: .commandCenterForeground,
        .activityBarBackground: .sideBarBackground, .activityBarForeground: .foreground, .activityBarInactiveForeground: .descriptionForeground,
        .activityBarActiveBorder: .focusBorder, .activityBarBadgeBackground: .badgeBackground, .activityBarBadgeForeground: .badgeForeground,
        .sideBarBackground: .editorBackground, .sideBarForeground: .foreground, .sideBarTitleForeground: .sideBarForeground,
        .sideBarSectionHeaderForeground: .sideBarForeground,
        .listActiveSelectionForeground: .foreground, .listInactiveSelectionForeground: .foreground, .listHoverForeground: .foreground,
        .listActiveSelectionIconForeground: .listActiveSelectionForeground,
        .editorForeground: .foreground, .editorLineNumberActiveForeground: .editorForeground,
        .editorWidgetBackground: .editorBackground, .editorWidgetForeground: .foreground,
        .editorHoverWidgetBackground: .editorWidgetBackground, .editorHoverWidgetForeground: .editorWidgetForeground,
        .editorHoverWidgetBorder: .editorWidgetBorder, .editorHoverWidgetStatusBarBackground: .editorHoverWidgetBackground,
        .editorStickyScrollBackground: .editorBackground, .editorStickyScrollHoverBackground: .listHoverBackground,
        .peekViewEditorBackground: .editorBackground, .peekViewResultBackground: .editorWidgetBackground,
        .peekViewTitleBackground: .editorWidgetBackground, .peekViewTitleLabelForeground: .foreground,
        .peekViewTitleDescriptionForeground: .descriptionForeground, .peekViewBorder: .focusBorder,
        .peekViewResultSelectionBackground: .listActiveSelectionBackground, .peekViewResultSelectionForeground: .listActiveSelectionForeground,
        .minimapBackground: .editorBackground,
        .editorGroupHeaderTabsBackground: .sideBarBackground, .editorGroupHeaderNoTabsBackground: .editorBackground,
        .tabActiveBackground: .editorBackground, .tabActiveForeground: .foreground, .tabInactiveBackground: .editorGroupHeaderTabsBackground,
        .tabInactiveForeground: .descriptionForeground, .tabHoverForeground: .tabActiveForeground,
        .tabUnfocusedActiveBackground: .tabActiveBackground, .tabUnfocusedActiveForeground: .tabActiveForeground,
        .tabUnfocusedInactiveForeground: .tabInactiveForeground,
        .breadcrumbBackground: .editorBackground, .breadcrumbForeground: .descriptionForeground, .breadcrumbFocusForeground: .foreground,
        .breadcrumbActiveSelectionForeground: .foreground, .breadcrumbPickerBackground: .editorWidgetBackground,
        .panelBackground: .editorBackground, .panelTitleActiveForeground: .foreground, .panelTitleInactiveForeground: .descriptionForeground,
        .panelTitleActiveBorder: .panelTitleActiveForeground,
        .statusBarBackground: .activityBarBackground, .statusBarForeground: .foreground,
        .statusBarNoFolderBackground: .statusBarBackground, .statusBarNoFolderForeground: .statusBarForeground,
        .statusBarDebuggingBackground: .statusBarItemRemoteBackground, .statusBarDebuggingForeground: .statusBarItemRemoteForeground,
        .statusBarItemRemoteBackground: .buttonBackground, .statusBarItemRemoteForeground: .buttonForeground,
        .statusBarItemRemoteHoverBackground: .statusBarItemHoverBackground,
        .inputBackground: .editorBackground, .inputForeground: .foreground, .inputPlaceholderForeground: .descriptionForeground,
        .dropdownBackground: .inputBackground, .dropdownForeground: .foreground, .dropdownListBackground: .dropdownBackground,
        .buttonBackground: .focusBorder, .buttonHoverBackground: .buttonBackground,
        .buttonSecondaryBackground: .inputBackground, .buttonSecondaryForeground: .foreground, .buttonSecondaryHoverBackground: .buttonSecondaryBackground,
        .checkboxBackground: .dropdownBackground, .checkboxForeground: .dropdownForeground, .checkboxBorder: .dropdownBorder,
        .keybindingLabelForeground: .foreground,
        .quickInputBackground: .editorWidgetBackground, .quickInputForeground: .editorWidgetForeground,
        .quickInputListFocusBackground: .listActiveSelectionBackground, .quickInputListFocusForeground: .listActiveSelectionForeground,
        .quickInputListFocusIconForeground: .quickInputListFocusForeground, .pickerGroupForeground: .textLinkForeground,
        .menuBackground: .editorWidgetBackground, .menuForeground: .foreground,
        .menuSelectionBackground: .listActiveSelectionBackground, .menuSelectionForeground: .listActiveSelectionForeground,
        .notificationsBackground: .editorWidgetBackground, .notificationsForeground: .editorWidgetForeground,
        .notificationCenterHeaderBackground: .notificationsBackground, .notificationCenterHeaderForeground: .notificationsForeground,
        .notificationLinkForeground: .textLinkForeground,
        .notificationsErrorIconForeground: .editorErrorForeground, .notificationsWarningIconForeground: .editorWarningForeground,
        .notificationsInfoIconForeground: .editorInfoForeground,
        .welcomePageBackground: .editorBackground, .welcomePageTileBackground: .editorWidgetBackground,
        .welcomePageTileHoverBackground: .listHoverBackground, .welcomePageProgressForeground: .textLinkForeground,
        .walkthroughStepTitleForeground: .foreground,
        .settingsHeaderForeground: .foreground, .settingsModifiedItemIndicator: .focusBorder,
        .settingsDropdownBackground: .dropdownBackground, .settingsTextInputBackground: .inputBackground,
        .settingsCheckboxBackground: .checkboxBackground, .settingsRowHoverBackground: .listHoverBackground,
        .settingsFocusedRowBackground: .listHoverBackground,
        .debugToolBarBackground: .editorWidgetBackground,
        .problemsErrorIconForeground: .editorErrorForeground, .problemsWarningIconForeground: .editorWarningForeground,
        .problemsInfoIconForeground: .editorInfoForeground,
        .terminalBackground: .panelBackground, .terminalForeground: .foreground,
        .notebookEditorBackground: .editorBackground, .notebookCellEditorBackground: .textCodeBlockBackground,
        .notebookFocusedCellBorder: .focusBorder, .notebookStatusRunningIconForeground: .foreground,
        .chartsForeground: .foreground, .extensionButtonProminentBackground: .buttonBackground,
        .extensionButtonProminentForeground: .buttonForeground, .extensionButtonProminentHoverBackground: .buttonHoverBackground,
        .textLinkActiveForeground: .textLinkForeground, .editorLinkActiveForeground: .textLinkForeground,
        .listHighlightForeground: .textLinkForeground, .listFocusHighlightForeground: .listHighlightForeground,
        .editorCodeLensForeground: .descriptionForeground, .editorInlayHintForeground: .descriptionForeground,
        .editorSuggestWidgetBackground: .editorWidgetBackground, .editorSuggestWidgetHighlightForeground: .listHighlightForeground,
        .editorSuggestWidgetSelectedBackground: .quickInputListFocusBackground,
        .bannerBackground: .listActiveSelectionBackground, .bannerForeground: .listActiveSelectionForeground,
        .debugIconBreakpointForeground: .editorErrorForeground, .testingIconPassed: .chartsGreen, .testingIconFailed: .editorErrorForeground
    ]

    /// When nothing names a colour: a neutral derived from the theme's kind.
    static func lastResort(_ key: TC, dark: Bool, values: [TC: RGBA]) -> RGBA {
        let background = values[.editorBackground] ?? (dark ? RGBA(0.12, 0.12, 0.12) : RGBA(1, 1, 1))
        let foreground = values[.foreground] ?? values[.editorForeground] ?? (dark ? RGBA(0.8, 0.8, 0.8) : RGBA(0.23, 0.23, 0.23))
        let name = key.rawValue.lowercased()
        if name.contains("error") || name.hasSuffix("red") || name.contains("failed") || name.contains("breakpoint") { return RGBA(hex: dark ? "#F14C4C" : "#E51400")! }
        if name.contains("warning") || name.hasSuffix("yellow") || name.hasSuffix("orange") { return RGBA(hex: dark ? "#CCA700" : "#BF8803")! }
        if name.contains("passed") || name.hasSuffix("green") || name.contains("added") || name.contains("success") { return RGBA(hex: dark ? "#73C991" : "#388A34")! }
        if name.contains("info") || name.hasSuffix("blue") || name.contains("focus") || name.contains("link") { return RGBA(hex: dark ? "#3794FF" : "#1A85FF")! }
        if name.hasSuffix("purple") || name.hasSuffix("magenta") { return RGBA(hex: dark ? "#B180D7" : "#652D90")! }
        if name.contains("border") || name.contains("separator") || name.contains("guide") || name.contains("shadow") { return foreground.transparent(0.15) }
        if name.contains("hover") || name.contains("selection") || name.contains("highlight") { return foreground.transparent(0.1) }
        if name.contains("foreground") || name.contains("stroke") { return foreground }
        return background
    }
}

/// The colour objects of one resolved theme, made on first use. Pages and miniatures draw off the main thread too
/// (`ThemeSnapshot`), hence the lock.
private final class MadeColors: @unchecked Sendable {
    private let lock = NSLock()
    private var colors: [TC: Color] = [:]
    private var nsColors: [TC: NSColor] = [:]
    private var tokens: [TokenRole: NSColor] = [:]

    func color(_ key: TC, _ make: () -> Color) -> Color {
        if let made = lock.withLock({ colors[key] }) { return made }
        let color = make()
        lock.withLock { colors[key] = color }
        return color
    }

    func ns(_ key: TC, _ make: () -> NSColor) -> NSColor {
        if let made = lock.withLock({ nsColors[key] }) { return made }
        let color = make()
        lock.withLock { nsColors[key] = color }
        return color
    }

    func token(_ role: TokenRole, _ make: () -> NSColor) -> NSColor {
        if let made = lock.withLock({ tokens[role] }) { return made }
        let color = make()
        lock.withLock { tokens[role] = color }
        return color
    }
}

extension RGBA {
    var nsColor: NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }
    var color: Color { Color(nsColor: nsColor) }
    init(_ color: NSColor) {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        self.init(Double(srgb.redComponent), Double(srgb.greenComponent), Double(srgb.blueComponent), Double(srgb.alphaComponent))
    }
}

private struct WorkbenchColorsKey: EnvironmentKey {
    static var defaultValue: WorkbenchColors { MainActor.assumeIsolated { ThemeManager.shared.colors } }
}

extension EnvironmentValues {
    /// The workbench's resolved colour theme; views read it to follow theme changes immediately.
    var theme: WorkbenchColors {
        get { self[WorkbenchColorsKey.self] }
        set { self[WorkbenchColorsKey.self] = newValue }
    }
}
