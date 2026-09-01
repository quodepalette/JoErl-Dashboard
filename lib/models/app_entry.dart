import 'package:flutter/material.dart';

enum AppCategory { media, gamingTools, utilities, dev }

extension AppCategoryLabel on AppCategory {
  String get label => switch (this) {
        AppCategory.media => 'Media',
        AppCategory.gamingTools => 'Gaming Tools',
        AppCategory.utilities => 'Utilities',
        AppCategory.dev => 'Dev',
      };

  static AppCategory fromString(String value) {
    switch (value.toLowerCase()) {
      case 'media':
        return AppCategory.media;
      case 'gaming':
      case 'gamingtools':
      case 'gaming tools':
        return AppCategory.gamingTools;
      case 'dev':
        return AppCategory.dev;
      case 'utilities':
      default:
        return AppCategory.utilities;
    }
  }
}

/// One tile on the dashboard. Loaded from apps.json so new apps can be
/// registered without touching Dart code.
class AppEntry {
  final String id;
  final String name;
  final String description;
  final String exePath;
  final String? folderPath;
  final AppCategory category;
  final String iconGlyph; // emoji fallback, used if iconAsset is missing/fails to load
  final String? iconAsset; // path to a PNG, e.g. 'assets/icons/video_player.png'
  final Color accentColor;
  final String? processName; // used to detect "already running"
  final bool inProgress;
  final bool trayOnly; // true = no visible window to focus (e.g. tray-only tools)

  const AppEntry({
    required this.id,
    required this.name,
    required this.description,
    required this.exePath,
    this.folderPath,
    required this.category,
    required this.iconGlyph,
    this.iconAsset,
    required this.accentColor,
    this.processName,
    this.inProgress = false,
    this.trayOnly = false,
  });

  factory AppEntry.fromJson(Map<String, dynamic> json) {
    return AppEntry(
      id: json['id'] as String,
      name: json['name'] as String,
      description: json['description'] as String? ?? '',
      exePath: json['exePath'] as String? ?? '',
      folderPath: json['folderPath'] as String?,
      category: AppCategoryLabel.fromString(json['category'] as String? ?? 'utilities'),
      iconGlyph: json['icon'] as String? ?? '🗂️',
      iconAsset: json['iconAsset'] as String?,
      accentColor: _colorFromHex(json['accentColor'] as String? ?? '#39FF88'),
      processName: json['processName'] as String?,
      inProgress: json['inProgress'] as bool? ?? false,
      trayOnly: json['trayOnly'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'description': description,
        'exePath': exePath,
        'folderPath': folderPath,
        'category': category.name,
        'icon': iconGlyph,
        'iconAsset': iconAsset,
        'accentColor':
            '#${(accentColor.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
        'processName': processName,
        'inProgress': inProgress,
        'trayOnly': trayOnly,
      };

  static Color _colorFromHex(String hex) {
    final cleaned = hex.replaceAll('#', '');
    return Color(int.parse('FF$cleaned', radix: 16));
  }

  /// Turns a display name into a stable-ish id (e.g. "JoErl Clipboard" ->
  /// "joerl-clipboard"), disambiguated against any existing ids.
  static String slugId(String name, Iterable<String> existingIds) {
    final base = name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9]+'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');
    final safeBase = base.isEmpty ? 'app' : base;
    if (!existingIds.contains(safeBase)) return safeBase;
    var i = 2;
    while (existingIds.contains('$safeBase-$i')) {
      i++;
    }
    return '$safeBase-$i';
  }
}
