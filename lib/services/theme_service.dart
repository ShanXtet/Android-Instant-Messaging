import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Theme Service - Manages app themes, color schemes, and backgrounds
class ThemeService extends ChangeNotifier {
  static final ThemeService _instance = ThemeService._internal();
  factory ThemeService() => _instance;
  ThemeService._internal();

  // Current theme mode
  ThemeMode _themeMode = ThemeMode.system;
  
  // Custom color scheme
  Color? _primaryColor;
  Color? _secondaryColor;
  Color? _accentColor;
  
  // Background/Wallpaper
  String? _chatWallpaper;
  Color? _chatBackgroundColor;
  
  // Predefined color schemes
  static const List<ColorSchemePreset> colorPresets = [
    ColorSchemePreset(
      name: 'Default Purple',
      primary: Color(0xFF7F4AC7),
      secondary: Color(0xFF5B2BAF),
      accent: Color(0xFFEC6FFF),
    ),
    ColorSchemePreset(
      name: 'Blue Ocean',
      primary: Color(0xFF3A7BD5),
      secondary: Color(0xFF00D2FF),
      accent: Color(0xFF00C853),
    ),
    ColorSchemePreset(
      name: 'Green Nature',
      primary: Color(0xFF00C853),
      secondary: Color(0xFFB2FF59),
      accent: Color(0xFF4CAF50),
    ),
    ColorSchemePreset(
      name: 'Orange Sunset',
      primary: Color(0xFFFF6B35),
      secondary: Color(0xFFFF8E53),
      accent: Color(0xFFFFB84D),
    ),
    ColorSchemePreset(
      name: 'Pink Rose',
      primary: Color(0xFFE91E63),
      secondary: Color(0xFFF06292),
      accent: Color(0xFFFFB3BA),
    ),
    ColorSchemePreset(
      name: 'Teal Modern',
      primary: Color(0xFF009688),
      secondary: Color(0xFF4DB6AC),
      accent: Color(0xFF80CBC4),
    ),
  ];

  // Predefined wallpapers
  static const List<WallpaperPreset> wallpaperPresets = [
    WallpaperPreset(name: 'None', type: WallpaperType.none),
    WallpaperPreset(name: 'Solid White', type: WallpaperType.solid, color: Colors.white),
    WallpaperPreset(name: 'Solid Light Gray', type: WallpaperType.solid, color: Color(0xFFF5F5F5)),
    WallpaperPreset(name: 'Solid Dark Gray', type: WallpaperType.solid, color: Color(0xFF424242)),
    WallpaperPreset(name: 'Gradient Blue', type: WallpaperType.gradient, colors: [Color(0xFFE3F2FD), Color(0xFFBBDEFB)]),
    WallpaperPreset(name: 'Gradient Purple', type: WallpaperType.gradient, colors: [Color(0xFFF3E5F5), Color(0xFFE1BEE7)]),
    WallpaperPreset(name: 'Gradient Green', type: WallpaperType.gradient, colors: [Color(0xFFE8F5E9), Color(0xFFC8E6C9)]),
  ];

  // Getters
  ThemeMode get themeMode => _themeMode;
  Color? get primaryColor => _primaryColor;
  Color? get secondaryColor => _secondaryColor;
  Color? get accentColor => _accentColor;
  String? get chatWallpaper => _chatWallpaper;
  Color? get chatBackgroundColor => _chatBackgroundColor;

  /// Get theme data based on current settings
  ThemeData getLightTheme() {
    final primary = _primaryColor ?? colorPresets[0].primary;
    final secondary = _secondaryColor ?? colorPresets[0].secondary;
    final accent = _accentColor ?? colorPresets[0].accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorScheme: ColorScheme.light(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: Colors.white,
        onSurface: Colors.black87,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: primary,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
    );
  }

  ThemeData getDarkTheme() {
    final primary = _primaryColor ?? colorPresets[0].primary;
    final secondary = _secondaryColor ?? colorPresets[0].secondary;
    final accent = _accentColor ?? colorPresets[0].accent;

    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.dark(
        primary: primary,
        secondary: secondary,
        tertiary: accent,
        surface: const Color(0xFF1E1E1E),
        onSurface: Colors.white,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: const Color(0xFF121212),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: primary,
        foregroundColor: Colors.white,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: Colors.white,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: primary, width: 2),
        ),
      ),
    );
  }

  /// Get chat background decoration
  BoxDecoration? getChatBackground() {
    // First check wallpaper presets (by name)
    if (_chatWallpaper != null) {
      for (final preset in wallpaperPresets) {
        if (preset.name == _chatWallpaper) {
          switch (preset.type) {
            case WallpaperType.solid:
              if (preset.color != null) {
                return BoxDecoration(color: preset.color);
              }
              break;
            case WallpaperType.gradient:
              if (preset.colors != null && preset.colors!.length >= 2) {
                return BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: preset.colors!,
                  ),
                );
              }
              break;
            case WallpaperType.image:
              // Image type is handled separately via _chatWallpaper URL
              break;
            case WallpaperType.none:
              return null;
          }
        }
      }
      
      // If not a preset name, check if it's a valid URL for custom image
      final wallpaperUrl = _chatWallpaper!.trim();
      if (wallpaperUrl.isNotEmpty && 
          wallpaperUrl.toLowerCase() != 'none' && 
          wallpaperUrl != 'null' &&
          (wallpaperUrl.startsWith('http://') || 
           wallpaperUrl.startsWith('https://'))) {
        try {
          // Validate URL format
          final uri = Uri.tryParse(wallpaperUrl);
          if (uri != null && uri.hasScheme && uri.hasAuthority) {
            return BoxDecoration(
              image: DecorationImage(
                image: NetworkImage(wallpaperUrl),
                fit: BoxFit.cover,
                onError: (exception, stackTrace) {
                  debugPrint('Error loading wallpaper image: $exception');
                },
              ),
            );
          }
        } catch (e) {
          debugPrint('Invalid wallpaper URL: $wallpaperUrl, error: $e');
        }
      }
    }

    // Check for solid color
    if (_chatBackgroundColor != null) {
      return BoxDecoration(color: _chatBackgroundColor);
    }

    return null;
  }

  /// Set theme mode
  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    await _savePreferences();
    notifyListeners();
  }

  /// Set custom colors
  Future<void> setColors({
    Color? primary,
    Color? secondary,
    Color? accent,
  }) async {
    _primaryColor = primary;
    _secondaryColor = secondary;
    _accentColor = accent;
    await _savePreferences();
    notifyListeners();
  }

  /// Set color preset
  Future<void> setColorPreset(ColorSchemePreset preset) async {
    _primaryColor = preset.primary;
    _secondaryColor = preset.secondary;
    _accentColor = preset.accent;
    await _savePreferences();
    notifyListeners();
  }

  /// Set chat wallpaper
  Future<void> setChatWallpaper(String? wallpaper) async {
    _chatWallpaper = wallpaper;
    await _savePreferences();
    notifyListeners();
  }

  /// Set chat background color
  Future<void> setChatBackgroundColor(Color? color) async {
    _chatBackgroundColor = color;
    await _savePreferences();
    notifyListeners();
  }

  /// Set wallpaper preset
  Future<void> setWallpaperPreset(WallpaperPreset preset) async {
    _chatWallpaper = preset.name;
    _chatBackgroundColor = preset.color;
    await _savePreferences();
    notifyListeners();
  }

  /// Load preferences from storage
  Future<void> loadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final themeStr = prefs.getString('theme_mode');
      if (themeStr != null) {
        _themeMode = ThemeMode.values.firstWhere(
          (e) => e.toString() == 'ThemeMode.$themeStr',
          orElse: () => ThemeMode.system,
        );
      }

      final primaryStr = prefs.getString('primary_color');
      if (primaryStr != null) {
        _primaryColor = Color(int.parse(primaryStr));
      }

      final secondaryStr = prefs.getString('secondary_color');
      if (secondaryStr != null) {
        _secondaryColor = Color(int.parse(secondaryStr));
      }

      final accentStr = prefs.getString('accent_color');
      if (accentStr != null) {
        _accentColor = Color(int.parse(accentStr));
      }

      _chatWallpaper = prefs.getString('chat_wallpaper');
      
      final bgColorStr = prefs.getString('chat_background_color');
      if (bgColorStr != null) {
        _chatBackgroundColor = Color(int.parse(bgColorStr));
      }

      notifyListeners();
    } catch (e) {
      debugPrint('Error loading theme preferences: $e');
    }
  }

  /// Save preferences to storage
  Future<void> _savePreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('theme_mode', _themeMode.toString().split('.').last);
      
      if (_primaryColor != null) {
        await prefs.setString('primary_color', _primaryColor!.value.toString());
      } else {
        await prefs.remove('primary_color');
      }

      if (_secondaryColor != null) {
        await prefs.setString('secondary_color', _secondaryColor!.value.toString());
      } else {
        await prefs.remove('secondary_color');
      }

      if (_accentColor != null) {
        await prefs.setString('accent_color', _accentColor!.value.toString());
      } else {
        await prefs.remove('accent_color');
      }

      if (_chatWallpaper != null) {
        await prefs.setString('chat_wallpaper', _chatWallpaper!);
      } else {
        await prefs.remove('chat_wallpaper');
      }

      if (_chatBackgroundColor != null) {
        await prefs.setString('chat_background_color', _chatBackgroundColor!.value.toString());
      } else {
        await prefs.remove('chat_background_color');
      }
    } catch (e) {
      debugPrint('Error saving theme preferences: $e');
    }
  }

  /// Reset to defaults
  Future<void> reset() async {
    _themeMode = ThemeMode.system;
    _primaryColor = null;
    _secondaryColor = null;
    _accentColor = null;
    _chatWallpaper = null;
    _chatBackgroundColor = null;
    await _savePreferences();
    notifyListeners();
  }
}

/// Color Scheme Preset
class ColorSchemePreset {
  final String name;
  final Color primary;
  final Color secondary;
  final Color accent;

  const ColorSchemePreset({
    required this.name,
    required this.primary,
    required this.secondary,
    required this.accent,
  });
}

/// Wallpaper Preset
class WallpaperPreset {
  final String name;
  final WallpaperType type;
  final Color? color;
  final List<Color>? colors;

  const WallpaperPreset({
    required this.name,
    required this.type,
    this.color,
    this.colors,
  });
}

enum WallpaperType {
  none,
  solid,
  gradient,
  image,
}

