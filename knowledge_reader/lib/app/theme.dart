import 'package:flutter/material.dart';

/// Reading themes supported by the reader.
enum ReaderTheme { light, dark, sepia }

extension ReaderThemeX on ReaderTheme {
  String get label => switch (this) {
        ReaderTheme.light => '浅色',
        ReaderTheme.dark => '深色',
        ReaderTheme.sepia => '护眼',
      };

  Brightness get brightness => this == ReaderTheme.dark ? Brightness.dark : Brightness.light;

  Color get background => switch (this) {
        ReaderTheme.light => const Color(0xFFFDFDFD),
        ReaderTheme.dark => const Color(0xFF14161A),
        ReaderTheme.sepia => const Color(0xFFF6EEDC),
      };

  Color get foreground => switch (this) {
        ReaderTheme.light => const Color(0xFF1B1D21),
        ReaderTheme.dark => const Color(0xFFE6E8EB),
        ReaderTheme.sepia => const Color(0xFF453A2A),
      };

  Color get muted => foreground.withValues(alpha: 0.62);

  Color get divider => foreground.withValues(alpha: 0.12);
}

/// Reading preferences persisted in shared preferences.
class ReaderPreferences {
  const ReaderPreferences({
    this.fontScale = 1.0,
    this.lineHeight = 1.6,
    this.theme = ReaderTheme.light,
  });

  final double fontScale;
  final double lineHeight;
  final ReaderTheme theme;

  ReaderPreferences copyWith({double? fontScale, double? lineHeight, ReaderTheme? theme}) =>
      ReaderPreferences(
        fontScale: fontScale ?? this.fontScale,
        lineHeight: lineHeight ?? this.lineHeight,
        theme: theme ?? this.theme,
      );

  Map<String, dynamic> toJson() => {
        'fontScale': fontScale,
        'lineHeight': lineHeight,
        'theme': theme.name,
      };

  factory ReaderPreferences.fromJson(Map<String, dynamic> json) => ReaderPreferences(
        fontScale: (json['fontScale'] as num?)?.toDouble() ?? 1.0,
        lineHeight: (json['lineHeight'] as num?)?.toDouble() ?? 1.6,
        theme: ReaderTheme.values.firstWhere(
          (value) => value.name == json['theme'],
          orElse: () => ReaderTheme.light,
        ),
      );
}

ThemeData buildAppTheme(ReaderTheme theme) {
  final scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF2F6FEB),
    brightness: theme.brightness,
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: theme.background,
    appBarTheme: AppBarTheme(
      backgroundColor: theme.background,
      foregroundColor: theme.foreground,
      elevation: 0,
      centerTitle: false,
    ),
    listTileTheme: ListTileThemeData(iconColor: theme.muted),
  );
}
