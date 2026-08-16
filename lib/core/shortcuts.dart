import 'dart:io';

/// Formats a keyboard shortcut for display, using macOS symbols (⌘⌥⇧) on
/// macOS and word labels (Ctrl+Alt+Shift+) on Windows/Linux — matching each
/// platform's own convention and the actual modifier each [GlobalShortcuts]
/// binding in main.dart registers per platform (meta on macOS, control
/// elsewhere).
///
/// [key] is the trailing key label, e.g. `'D'`, `','`, `'Shift+S'` for a
/// key that already needs its own modifier prefix folded in.
String shortcutLabel(String key, {bool shift = false, bool alt = false}) {
  final isMac = Platform.isMacOS;
  final mod = isMac ? '⌘' : 'Ctrl+';
  final shiftMod = shift ? (isMac ? '⇧' : 'Shift+') : '';
  final altMod = alt ? (isMac ? '⌥' : 'Alt+') : '';
  return '$mod$altMod$shiftMod$key';
}
