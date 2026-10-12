import QtQuick
import Quickshell.Io

Item {
    id: theme
    required property string path
    readonly property var colors: {
        let result = {background: "#16130b", surface: "#231f17", foreground: "#eae2d4", primary: "#e2c46d", secondary: "#d4c5a1", tertiary: "#accfaf", error: "#ffb4ab", "on-error": "#690005", "on-primary": "#3c2f00", white: "#eae2d4", "charcoal-2": "#989080"};
        let re = /@define-color\s+([\w-]+)\s+(#[0-9a-fA-F]{6});/g;
        let match;
        while ((match = re.exec(palette.text())) !== null) result[match[1]] = match[2];
        let accent = Qt.color(result.primary);
        let gray = accent.r * 0.2126 + accent.g * 0.7152 + accent.b * 0.0722;
        function tint(level) { return Qt.rgba((accent.r * 0.7 + gray * 0.3) * level, (accent.g * 0.7 + gray * 0.3) * level, (accent.b * 0.7 + gray * 0.3) * level, 1); }
        result.accent = accent;
        result.background = tint(0.10);
        result.surface = tint(0.14);
        result.surfaceElevated = tint(0.20);
        result.barSurface = Qt.alpha(result.background, 0.45);
        result.panelSurface = Qt.alpha(result.surface, 0.97);
        result.mutedForeground = Qt.alpha(result.foreground, 0.65);
        result.separator = Qt.alpha(result.primary, 0.25);
        result.hover = Qt.alpha(result.primary, 0.10);
        result.active = result.primary;
        return result;
    }
    FileView { id: palette; path: theme.path; blockLoading: true; watchChanges: true; onFileChanged: reload() }
}
