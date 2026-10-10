"""make-themes.py Sources/Lemma/Resources/Themes: writes Lemma's signature themes (lemma-dark.json, lemma-light.json).

The structure (which VS Code colour ids a modern theme sets) comes from VS Code's Dark 2026 / Light 2026 themes in the
same folder; every colour is then re-expressed in Lemma's palette: warm graphite or paper neutrals at the same OKLab
lightness, VS Code's blue accent replaced by Lemma's olive, semantic colours kept but tuned, and the tokens that make the
identity (bars, buttons, selection, focus, status bar) set by hand.
"""
import json
import math
import sys
from pathlib import Path

folder = Path(sys.argv[1])

# ---------------------------------------------------------------- OKLab / OKLCH (Björn Ottosson)

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4

def linear_to_srgb(c):
    return 12.92 * c if c <= 0.0031308 else 1.055 * (c ** (1 / 2.4)) - 0.055

def rgb_to_oklab(r, g, b):
    r, g, b = srgb_to_linear(r), srgb_to_linear(g), srgb_to_linear(b)
    l = 0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b
    m = 0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b
    s = 0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b
    l_, m_, s_ = l ** (1 / 3), m ** (1 / 3), s ** (1 / 3)
    return (0.2104542553 * l_ + 0.7936177850 * m_ - 0.0040720468 * s_,
            1.9779984951 * l_ - 2.4285922050 * m_ + 0.4505937099 * s_,
            0.0259040371 * l_ + 0.7827717662 * m_ - 0.8086757660 * s_)

def oklab_to_rgb(L, a, b):
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    r = 4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s
    g = -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s
    bl = -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s
    return tuple(linear_to_srgb(max(0.0, min(1.0, x))) for x in (r, g, bl))

def to_oklch(r, g, b):
    L, a, bb = rgb_to_oklab(r, g, b)
    C = math.hypot(a, bb)
    h = math.degrees(math.atan2(bb, a)) % 360
    return L, C, h

def in_gamut(L, C, h):
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    l_ = L + 0.3963377774 * a + 0.2158037573 * b
    m_ = L - 0.1055613458 * a - 0.0638541728 * b
    s_ = L - 0.0894841775 * a - 1.2914855480 * b
    l, m, s = l_ ** 3, m_ ** 3, s_ ** 3
    rgb = (4.0767416621 * l - 3.3077115913 * m + 0.2309699292 * s,
           -1.2684380046 * l + 2.6097574011 * m - 0.3413193965 * s,
           -0.0041960863 * l - 0.7034186147 * m + 1.7076147010 * s)
    return all(-1e-4 <= x <= 1 + 1e-4 for x in rgb)

def oklch(L, C, h, alpha=1.0):
    """Hex for an OKLCH colour, reducing chroma until it fits sRGB."""
    L = max(0.0, min(1.0, L))
    while C > 0 and not in_gamut(L, C, h):
        C -= 0.002
    a, b = C * math.cos(math.radians(h)), C * math.sin(math.radians(h))
    r, g, bl = oklab_to_rgb(L, a, b)
    text = "#" + "".join(f"{round(x * 255):02X}" for x in (r, g, bl))
    if alpha < 0.999:
        text += f"{round(alpha * 255):02X}"
    return text

def parse(hexstr):
    t = hexstr.strip().lstrip("#")
    if len(t) in (3, 4):
        t = "".join(ch * 2 for ch in t)
    r, g, b = (int(t[i:i + 2], 16) / 255 for i in (0, 2, 4))
    a = int(t[6:8], 16) / 255 if len(t) == 8 else 1.0
    return r, g, b, a

def luminance(hexstr):
    r, g, b, _ = parse(hexstr)
    return 0.2126 * srgb_to_linear(r) + 0.7152 * srgb_to_linear(g) + 0.0722 * srgb_to_linear(b)

def contrast(x, y):
    a, b = luminance(x), luminance(y)
    return (max(a, b) + 0.05) / (min(a, b) + 0.05)

# ---------------------------------------------------------------- palettes

NEUTRAL_HUE = 88          # warm, a little towards yellow: paper and graphite rather than blue-grey
ACCENT_HUE = 116          # Lemma's olive (the icon's #535315 sits at ~110; a touch greener reads cleaner on screens)

def palette(dark):
    if dark:
        n = lambda L, C=0.0050: oklch(L, C, NEUTRAL_HUE)
        p = {
            "bar": n(0.188), "side": n(0.203), "editor": n(0.222), "widget": n(0.252), "input": n(0.238),
            "hover": n(0.268), "active": n(0.298), "border": n(0.288), "borderStrong": n(0.350),
            "fg": n(0.925, 0.009), "fgSide": n(0.865, 0.009), "muted": n(0.705, 0.010), "faint": n(0.565, 0.009),
            "disabled": n(0.455, 0.007),
            "accent": oklch(0.835, 0.135, ACCENT_HUE), "accentHover": oklch(0.875, 0.125, ACCENT_HUE),
            "accentText": n(0.180), "accentDeep": oklch(0.62, 0.12, ACCENT_HUE),
            "link": oklch(0.850, 0.115, ACCENT_HUE), "linkActive": oklch(0.910, 0.100, ACCENT_HUE),
            "error": oklch(0.720, 0.140, 28), "warning": oklch(0.820, 0.120, 80), "info": oklch(0.780, 0.090, 235),
            "success": oklch(0.790, 0.130, 145),
        }
    else:
        n = lambda L, C=0.0085: oklch(L, C, NEUTRAL_HUE)
        p = {
            "bar": n(0.958), "side": n(0.968), "editor": n(0.986, 0.006), "widget": "#FFFFFF", "input": "#FFFFFF",
            "hover": n(0.935, 0.010), "active": n(0.910, 0.012), "border": n(0.912, 0.010), "borderStrong": n(0.860, 0.012),
            "fg": n(0.245, 0.012), "fgSide": n(0.300, 0.012), "muted": n(0.500, 0.014), "faint": n(0.640, 0.012),
            "disabled": n(0.760, 0.010),
            "accent": oklch(0.500, 0.105, ACCENT_HUE), "accentHover": oklch(0.450, 0.100, ACCENT_HUE),
            "accentText": "#FFFFFF", "accentDeep": oklch(0.42, 0.11, ACCENT_HUE),
            "link": oklch(0.470, 0.100, ACCENT_HUE), "linkActive": oklch(0.400, 0.095, ACCENT_HUE),
            "error": oklch(0.520, 0.180, 28), "warning": oklch(0.580, 0.130, 70), "info": oklch(0.520, 0.130, 245),
            "success": oklch(0.520, 0.130, 145),
        }
    return p

def with_alpha(hexstr, alpha):
    return hexstr[:7] + f"{round(alpha * 255):02X}"

# ---------------------------------------------------------------- remapping the template

def remap(key, value, dark, p):
    """Re-expresses one template colour in Lemma's palette."""
    if not isinstance(value, str) or not value.startswith("#"):
        return value
    r, g, b, a = parse(value)
    L, C, h = to_oklch(r, g, b)
    # Transparent overlays of pure white or black (hover tints, shadows) keep their role.
    if C < 0.01 and (L > 0.985 or L < 0.02) and a < 0.999:
        return value
    if C < 0.04:
        chroma = 0.0050 if dark else 0.0085
        if L > 0.985:
            return value
        return oklch(L, chroma * (0.6 + 0.8 * L), NEUTRAL_HUE, a)
    if 185 <= h <= 285:  # VS Code's blue accent family
        lowered = key.lower()
        foreground_like = lowered.endswith("foreground") or "border" in lowered or "outline" in lowered or lowered.endswith(".fg")
        if foreground_like:
            target_l = max(L, 0.78) if dark else min(L, 0.52)
        else:
            target_l = L
        return oklch(target_l, min(0.14, C * 1.05), ACCENT_HUE, a)
    # Semantic colours (red, orange, yellow, green, purple) stay, slightly softened in the dark theme.
    return oklch(L, C * (0.92 if dark else 1.0), h, a)

def build(dark):
    template = json.loads((folder / ("dark-2026.json" if dark else "light-2026.json")).read_text())
    p = palette(dark)
    colors = {key: remap(key, value, dark, p) for key, value in template["colors"].items()}
    A = p["accent"]
    overrides = {
        # Base
        "foreground": p["fg"], "descriptionForeground": p["muted"], "disabledForeground": p["disabled"],
        "errorForeground": p["error"], "focusBorder": A, "contrastBorder": "#00000000", "contrastActiveBorder": "#00000000",
        "icon.foreground": p["muted"] if dark else p["fgSide"], "widget.border": p["border"],
        "widget.shadow": "#00000066" if dark else "#3A33201F", "selection.background": with_alpha(A, 0.32 if dark else 0.24),
        "sash.hoverBorder": A, "progressBar.background": A,
        "textLink.foreground": p["link"], "textLink.activeForeground": p["linkActive"],
        "textPreformat.foreground": p["fg"], "textPreformat.background": p["hover"],
        "textBlockQuote.background": p["widget"], "textBlockQuote.border": with_alpha(A, 0.6),
        "textCodeBlock.background": p["input"], "textSeparator.foreground": p["borderStrong"],
        "badge.background": with_alpha(A, 0.22 if dark else 0.16), "badge.foreground": p["link"] if dark else p["accentDeep"],
        # Title bar and command center
        "titleBar.activeBackground": p["bar"], "titleBar.activeForeground": p["fgSide"],
        "titleBar.inactiveBackground": p["bar"], "titleBar.inactiveForeground": p["faint"], "titleBar.border": p["border"],
        "commandCenter.background": p["input"] if dark else "#FFFFFF", "commandCenter.foreground": p["muted"],
        "commandCenter.border": p["border"] if dark else p["borderStrong"],
        "commandCenter.activeBackground": p["hover"], "commandCenter.activeForeground": p["fg"],
        "commandCenter.activeBorder": p["borderStrong"],
        # Activity bar
        "activityBar.background": p["bar"], "activityBar.foreground": p["fg"], "activityBar.inactiveForeground": p["faint"],
        "activityBar.border": p["border"], "activityBar.activeBorder": A, "activityBar.activeBackground": "#00000000",
        "activityBarBadge.background": A, "activityBarBadge.foreground": p["accentText"],
        "activityBarTop.activeBorder": A,
        # Side bar
        "sideBar.background": p["side"], "sideBar.foreground": p["fgSide"], "sideBar.border": p["border"],
        "sideBarTitle.foreground": p["fgSide"], "sideBarTitle.background": p["side"],
        "sideBarSectionHeader.background": p["side"], "sideBarSectionHeader.foreground": p["fgSide"],
        "sideBarSectionHeader.border": p["border"],
        # Lists
        "list.activeSelectionBackground": with_alpha(A, 0.20 if dark else 0.17),
        "list.activeSelectionForeground": p["fg"], "list.activeSelectionIconForeground": p["fg"],
        "list.inactiveSelectionBackground": p["active"] if dark else p["hover"],
        "list.inactiveSelectionForeground": p["fg"],
        "list.hoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.045 if dark else 0.05),
        "list.hoverForeground": p["fg"], "list.focusOutline": with_alpha(A, 0.85), "list.focusAndSelectionOutline": with_alpha(A, 0.85),
        "list.highlightForeground": p["link"], "list.focusHighlightForeground": p["link"],
        "list.dropBackground": with_alpha(A, 0.18), "tree.indentGuidesStroke": p["borderStrong"],
        # Editor
        "editor.background": p["editor"], "editor.foreground": p["fg"],
        "editorLineNumber.foreground": p["faint"], "editorLineNumber.activeForeground": p["fg"],
        "editor.lineHighlightBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.04 if dark else 0.04),
        "editor.selectionBackground": with_alpha(A, 0.30 if dark else 0.26),
        "editor.inactiveSelectionBackground": with_alpha(A, 0.16 if dark else 0.14),
        "editor.findMatchBackground": with_alpha(p["warning"], 0.45 if dark else 0.40),
        "editor.findMatchHighlightBackground": with_alpha(p["warning"], 0.22 if dark else 0.22),
        "editor.rangeHighlightBackground": with_alpha(A, 0.08), "editorCursor.foreground": A,
        "editorGutter.background": p["editor"],
        "editorWidget.background": p["widget"], "editorWidget.foreground": p["fg"], "editorWidget.border": p["border"],
        "editorHoverWidget.background": p["widget"], "editorHoverWidget.border": p["borderStrong"] if dark else p["border"],
        "editorHoverWidget.foreground": p["fg"], "editorHoverWidget.statusBarBackground": p["input"] if dark else p["side"],
        "editorStickyScroll.background": p["editor"], "editorStickyScrollHover.background": p["hover"],
        "editorSuggestWidget.background": p["widget"], "editorSuggestWidget.border": p["border"],
        "editorSuggestWidget.selectedBackground": with_alpha(A, 0.20), "editorSuggestWidget.highlightForeground": p["link"],
        "editorLink.activeForeground": p["link"], "editorCodeLens.foreground": p["muted"],
        "editorInlayHint.background": with_alpha(A, 0.12), "editorInlayHint.foreground": p["muted"],
        "editor.stackFrameHighlightBackground": with_alpha(p["warning"], 0.20 if dark else 0.28),
        "editor.focusedStackFrameHighlightBackground": with_alpha(p["success"], 0.18 if dark else 0.22),
        "editorError.foreground": p["error"], "editorWarning.foreground": p["warning"], "editorInfo.foreground": p["info"],
        # Peek view
        "peekView.border": A, "peekViewTitle.background": p["widget"], "peekViewTitleLabel.foreground": p["fg"],
        "peekViewTitleDescription.foreground": p["muted"], "peekViewEditor.background": p["editor"],
        "peekViewResult.background": p["side"], "peekViewResult.selectionBackground": with_alpha(A, 0.22),
        "peekViewResult.matchHighlightBackground": with_alpha(p["warning"], 0.3),
        # Minimap, scrollbars, overview ruler
        "minimap.background": p["editor"],
        "minimapSlider.background": with_alpha("#FFFFFF" if dark else "#3A3320", 0.07 if dark else 0.08),
        "minimapSlider.hoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.11 if dark else 0.12),
        "minimapSlider.activeBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.15 if dark else 0.16),
        "scrollbarSlider.background": with_alpha("#FFFFFF" if dark else "#3A3320", 0.10 if dark else 0.14),
        "scrollbarSlider.hoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.16 if dark else 0.22),
        "scrollbarSlider.activeBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.22 if dark else 0.30),
        "scrollbar.shadow": "#00000000", "editorOverviewRuler.border": "#00000000",
        # Editor groups and tabs
        "editorGroup.border": p["border"], "editorGroupHeader.tabsBackground": p["bar"],
        "editorGroupHeader.tabsBorder": p["border"], "editorGroupHeader.noTabsBackground": p["editor"],
        "tab.activeBackground": p["editor"], "tab.activeForeground": p["fg"], "tab.activeBorderTop": A,
        "tab.activeBorder": p["editor"], "tab.inactiveBackground": p["bar"], "tab.inactiveForeground": p["faint"] if dark else p["muted"],
        "tab.hoverBackground": p["side"], "tab.hoverForeground": p["fg"], "tab.border": p["border"],
        "tab.unfocusedActiveBackground": p["editor"], "tab.unfocusedActiveForeground": p["muted"],
        "tab.unfocusedActiveBorderTop": with_alpha(A, 0.45), "tab.unfocusedInactiveForeground": p["faint"],
        "breadcrumb.background": p["editor"], "breadcrumb.foreground": p["muted"], "breadcrumb.focusForeground": p["fg"],
        "breadcrumb.activeSelectionForeground": p["fg"], "breadcrumbPicker.background": p["widget"],
        # Panel
        "panel.background": p["side"], "panel.border": p["border"], "panelTitle.activeForeground": p["fg"],
        "panelTitle.inactiveForeground": p["faint"] if dark else p["muted"], "panelTitle.activeBorder": A,
        "panelInput.border": p["border"], "panelSection.border": p["border"], "panelSectionHeader.background": p["side"],
        # Status bar
        "statusBar.background": p["bar"], "statusBar.foreground": p["muted"], "statusBar.border": p["border"],
        "statusBar.noFolderBackground": p["bar"], "statusBar.noFolderForeground": p["muted"],
        "statusBar.debuggingBackground": oklch(0.62 if dark else 0.55, 0.15, 55), "statusBar.debuggingForeground": "#FFFFFF",
        "statusBar.debuggingBorder": oklch(0.62 if dark else 0.55, 0.15, 55),
        "statusBarItem.hoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.08 if dark else 0.08),
        "statusBarItem.activeBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.14 if dark else 0.14),
        "statusBarItem.remoteBackground": A, "statusBarItem.remoteForeground": p["accentText"],
        "statusBarItem.remoteHoverBackground": p["accentHover"],
        "statusBarItem.prominentBackground": with_alpha(A, 0.25), "statusBarItem.prominentForeground": p["fg"],
        "statusBarItem.errorBackground": p["error"], "statusBarItem.errorForeground": "#FFFFFF",
        "statusBarItem.warningBackground": p["warning"], "statusBarItem.warningForeground": p["accentText"] if dark else "#FFFFFF",
        # Inputs and buttons
        "input.background": p["input"], "input.foreground": p["fg"], "input.border": p["border"] if dark else p["borderStrong"],
        "input.placeholderForeground": p["faint"],
        "inputOption.activeBackground": with_alpha(A, 0.22), "inputOption.activeBorder": with_alpha(A, 0.7),
        "inputOption.activeForeground": p["fg"], "inputOption.hoverBackground": p["hover"],
        "inputValidation.errorBackground": oklch(0.30, 0.06, 28) if dark else oklch(0.95, 0.03, 28),
        "inputValidation.errorBorder": p["error"],
        "dropdown.background": p["input"], "dropdown.foreground": p["fg"], "dropdown.border": p["border"] if dark else p["borderStrong"],
        "dropdown.listBackground": p["widget"],
        "button.background": A, "button.foreground": p["accentText"], "button.hoverBackground": p["accentHover"],
        "button.border": "#00000000", "button.separator": with_alpha(p["accentText"], 0.4),
        "button.secondaryBackground": p["hover"] if dark else oklch(0.93, 0.010, NEUTRAL_HUE),
        "button.secondaryForeground": p["fg"], "button.secondaryHoverBackground": p["active"] if dark else oklch(0.90, 0.012, NEUTRAL_HUE),
        "checkbox.background": p["input"], "checkbox.border": p["borderStrong"], "checkbox.foreground": p["fg"],
        "checkbox.selectBackground": A,
        "toolbar.hoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.07 if dark else 0.07),
        "toolbar.activeBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.12 if dark else 0.12),
        "actionBar.toggledBackground": with_alpha(A, 0.20),
        "keybindingLabel.background": with_alpha("#FFFFFF" if dark else "#3A3320", 0.06 if dark else 0.05),
        "keybindingLabel.foreground": p["fg"], "keybindingLabel.border": p["borderStrong"],
        "keybindingLabel.bottomBorder": p["borderStrong"],
        "extensionButton.prominentBackground": A, "extensionButton.prominentForeground": p["accentText"],
        "extensionButton.prominentHoverBackground": p["accentHover"],
        # Quick input and menus
        "quickInput.background": p["widget"], "quickInput.foreground": p["fg"], "quickInputTitle.background": p["widget"],
        "quickInputList.focusBackground": with_alpha(A, 0.18 if dark else 0.15), "quickInputList.focusForeground": p["fg"],
        "quickInputList.focusIconForeground": p["fg"], "pickerGroup.foreground": p["link"], "pickerGroup.border": p["border"],
        "menu.background": p["widget"], "menu.foreground": p["fg"], "menu.selectionBackground": with_alpha(A, 0.22),
        "menu.selectionForeground": p["fg"], "menu.separatorBackground": p["border"], "menu.border": p["border"],
        # Notifications
        "notifications.background": p["widget"], "notifications.foreground": p["fg"], "notifications.border": p["border"],
        "notificationCenterHeader.background": p["side"], "notificationCenterHeader.foreground": p["fg"],
        "notificationLink.foreground": p["link"], "notificationToast.border": p["border"],
        "notificationsErrorIcon.foreground": p["error"], "notificationsWarningIcon.foreground": p["warning"],
        "notificationsInfoIcon.foreground": p["info"],
        # Welcome page, settings, walkthroughs
        "welcomePage.background": p["editor"], "welcomePage.tileBackground": p["widget"] if dark else "#FFFFFF",
        "welcomePage.tileHoverBackground": p["hover"], "welcomePage.tileBorder": p["border"],
        "welcomePage.progress.background": p["border"], "welcomePage.progress.foreground": A,
        "walkthrough.stepTitle.foreground": p["fg"],
        "settings.headerForeground": p["fg"], "settings.modifiedItemIndicator": A,
        "settings.dropdownBackground": p["input"], "settings.dropdownBorder": p["border"],
        "settings.textInputBackground": p["input"], "settings.textInputBorder": p["border"],
        "settings.checkboxBackground": p["input"], "settings.checkboxBorder": p["borderStrong"],
        "settings.rowHoverBackground": with_alpha("#FFFFFF" if dark else "#3A3320", 0.03),
        # Testing, debugging, charts and the terminal (the Lab console)
        "testing.iconPassed": p["success"], "testing.iconFailed": p["error"], "testing.iconQueued": p["warning"],
        "testing.iconUnset": p["faint"],
        "debugToolBar.background": p["widget"], "debugToolBar.border": p["border"],
        "debugIcon.breakpointForeground": p["error"], "debugIcon.startForeground": p["success"],
        "charts.foreground": p["fg"], "charts.lines": with_alpha(p["muted"], 0.5), "charts.red": p["error"],
        "charts.blue": p["info"], "charts.yellow": p["warning"], "charts.orange": oklch(0.74 if dark else 0.60, 0.14, 55),
        "charts.green": p["success"], "charts.purple": oklch(0.72 if dark else 0.52, 0.13, 305),
        "terminal.background": p["side"], "terminal.foreground": p["fg"], "terminalCursor.foreground": A,
        "terminal.selectionBackground": with_alpha(A, 0.28),
        "notebook.focusedCellBorder": with_alpha(A, 0.8), "notebook.cellBorderColor": p["border"],
        "notebook.cellEditorBackground": p["input"] if dark else oklch(0.975, 0.006, NEUTRAL_HUE),
        "notebook.selectedCellBackground": with_alpha(A, 0.06), "notebook.cellToolbarSeparator": p["border"],
        "gitDecoration.addedResourceForeground": p["success"], "gitDecoration.modifiedResourceForeground": p["warning"],
        "gitDecoration.deletedResourceForeground": p["error"],
        "editorGutter.addedBackground": p["success"], "editorGutter.modifiedBackground": p["info"],
        "editorGutter.deletedBackground": p["error"],
        "editorOverviewRuler.findMatchForeground": with_alpha(p["warning"], 0.8),
        "editorOverviewRuler.errorForeground": p["error"], "editorOverviewRuler.warningForeground": p["warning"],
        "editorOverviewRuler.infoForeground": p["info"], "editorOverviewRuler.modifiedForeground": p["info"],
        "editorOverviewRuler.addedForeground": p["success"],
        "minimap.findMatchHighlight": p["warning"], "minimap.selectionHighlight": with_alpha(A, 0.6),
        "minimap.errorHighlight": p["error"], "minimap.warningHighlight": p["warning"],
    }
    colors.update(overrides)
    # Syntax colours for the Lab's code and the derivation editor: calm, distinct, readable on the editor.
    if dark:
        syntax = {"comment": oklch(0.60, 0.020, NEUTRAL_HUE), "keyword": oklch(0.78, 0.110, 320), "string": oklch(0.80, 0.120, 135),
                  "number": oklch(0.80, 0.110, 60), "constant": oklch(0.80, 0.110, 25), "function": oklch(0.82, 0.100, 230),
                  "type": oklch(0.85, 0.100, 95), "operator": oklch(0.80, 0.060, 200), "parameter": oklch(0.85, 0.070, 50),
                  "heading": oklch(0.85, 0.120, ACCENT_HUE)}
    else:
        syntax = {"comment": oklch(0.58, 0.020, NEUTRAL_HUE), "keyword": oklch(0.48, 0.150, 320), "string": oklch(0.50, 0.120, 140),
                  "number": oklch(0.55, 0.130, 55), "constant": oklch(0.52, 0.160, 25), "function": oklch(0.48, 0.130, 250),
                  "type": oklch(0.52, 0.110, 85), "operator": oklch(0.48, 0.080, 210), "parameter": oklch(0.55, 0.110, 45),
                  "heading": oklch(0.45, 0.120, ACCENT_HUE)}
    token_colors = [
        {"scope": ["comment", "punctuation.definition.comment"], "settings": {"fontStyle": "italic", "foreground": syntax["comment"]}},
        {"scope": ["keyword", "storage.type", "storage.modifier", "keyword.control"], "settings": {"foreground": syntax["keyword"]}},
        {"scope": ["string", "string.quoted"], "settings": {"foreground": syntax["string"]}},
        {"scope": ["constant.numeric"], "settings": {"foreground": syntax["number"]}},
        {"scope": ["constant.language", "variable.language"], "settings": {"foreground": syntax["constant"]}},
        {"scope": ["entity.name.function", "support.function"], "settings": {"foreground": syntax["function"]}},
        {"scope": ["entity.name.type", "entity.name.class", "support.class", "support.type"], "settings": {"foreground": syntax["type"]}},
        {"scope": ["keyword.operator", "punctuation"], "settings": {"foreground": syntax["operator"]}},
        {"scope": ["variable.parameter"], "settings": {"foreground": syntax["parameter"]}},
        {"scope": ["markup.heading"], "settings": {"fontStyle": "bold", "foreground": syntax["heading"]}},
    ]
    name = "Lemma Dark" if dark else "Lemma Light"
    return {"name": name, "type": "dark" if dark else "light", "colors": dict(sorted(colors.items())), "tokenColors": token_colors}

for dark in (True, False):
    theme = build(dark)
    target = folder / ("lemma-dark.json" if dark else "lemma-light.json")
    target.write_text(json.dumps(theme, indent=1, ensure_ascii=False) + "\n")
    c = theme["colors"]
    print(f"{theme['name']}: {len(c)} colours -> {target.name}")
    for fg, bg in (("foreground", "editor.background"), ("sideBar.foreground", "sideBar.background"),
                   ("descriptionForeground", "sideBar.background"), ("button.foreground", "button.background"),
                   ("textLink.foreground", "editor.background"), ("statusBar.foreground", "statusBar.background"),
                   ("tab.inactiveForeground", "tab.inactiveBackground"), ("focusBorder", "editor.background"),
                   ("activityBar.inactiveForeground", "activityBar.background"), ("editorLineNumber.foreground", "editor.background")):
        print(f"  {fg:34s} on {bg:28s} {c[fg]} / {c[bg]}  contrast {contrast(c[fg], c[bg]):.2f}")
