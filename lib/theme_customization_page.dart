import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'services/theme_service.dart';
import 'file_service.dart';

class ThemeCustomizationPage extends StatefulWidget {
  const ThemeCustomizationPage({super.key});

  @override
  State<ThemeCustomizationPage> createState() => _ThemeCustomizationPageState();
}

class _ThemeCustomizationPageState extends State<ThemeCustomizationPage> {
  final ThemeService _themeService = ThemeService();
  ThemeMode _selectedThemeMode = ThemeMode.system;
  ColorSchemePreset? _selectedColorPreset;
  WallpaperPreset? _selectedWallpaper;

  @override
  void initState() {
    super.initState();
    _loadCurrentSettings();
  }

  Future<void> _loadCurrentSettings() async {
    await _themeService.loadPreferences();
    setState(() {
      _selectedThemeMode = _themeService.themeMode;
      // Find matching color preset
      for (final preset in ThemeService.colorPresets) {
        if (_themeService.primaryColor == preset.primary &&
            _themeService.secondaryColor == preset.secondary) {
          _selectedColorPreset = preset;
          break;
        }
      }
      // Find matching wallpaper preset
      if (_themeService.chatWallpaper != null) {
        for (final preset in ThemeService.wallpaperPresets) {
          if (preset.name == _themeService.chatWallpaper) {
            _selectedWallpaper = preset;
            break;
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme & Background'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Reset to Default',
            onPressed: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset Theme'),
                  content: const Text('Reset all theme settings to default?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      style: FilledButton.styleFrom(backgroundColor: Colors.red),
                      child: const Text('Reset'),
                    ),
                  ],
                ),
              );
              if (confirmed == true) {
                await _themeService.reset();
                _loadCurrentSettings();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Theme reset to default')),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Theme Mode Section
          _buildSection(
            title: 'Theme Mode',
            icon: Icons.brightness_6,
            child: Column(
              children: [
                RadioListTile<ThemeMode>(
                  title: const Text('Light'),
                  value: ThemeMode.light,
                  groupValue: _selectedThemeMode,
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => _selectedThemeMode = value);
                      await _themeService.setThemeMode(value);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('Dark'),
                  value: ThemeMode.dark,
                  groupValue: _selectedThemeMode,
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => _selectedThemeMode = value);
                      await _themeService.setThemeMode(value);
                    }
                  },
                ),
                RadioListTile<ThemeMode>(
                  title: const Text('System Default'),
                  value: ThemeMode.system,
                  groupValue: _selectedThemeMode,
                  onChanged: (value) async {
                    if (value != null) {
                      setState(() => _selectedThemeMode = value);
                      await _themeService.setThemeMode(value);
                    }
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Color Scheme Section
          _buildSection(
            title: 'Color Scheme',
            icon: Icons.palette,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a preset color scheme:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: ThemeService.colorPresets.map((preset) {
                    final isSelected = _selectedColorPreset?.name == preset.name;
                    return GestureDetector(
                      onTap: () async {
                        setState(() => _selectedColorPreset = preset);
                        await _themeService.setColorPreset(preset);
                      },
                      child: Container(
                        width: 100,
                        height: 100,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Container(
                              width: 60,
                              height: 40,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(8),
                                gradient: LinearGradient(
                                  colors: [
                                    preset.primary,
                                    preset.secondary,
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              preset.name,
                              style: const TextStyle(fontSize: 11),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 16),
                ListTile(
                  leading: const Icon(Icons.colorize),
                  title: const Text('Custom Colors'),
                  subtitle: const Text('Pick your own colors'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _showCustomColorPicker(),
                ),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Chat Background Section
          _buildSection(
            title: 'Chat Background',
            icon: Icons.wallpaper,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Choose a background for chat screens:',
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 2,
                    crossAxisSpacing: 12,
                    mainAxisSpacing: 12,
                    childAspectRatio: 1.5,
                  ),
                  itemCount: ThemeService.wallpaperPresets.length + 1, // +1 for custom image
                  itemBuilder: (context, index) {
                    if (index == ThemeService.wallpaperPresets.length) {
                      // Custom image option
                      return GestureDetector(
                        onTap: _pickCustomWallpaper,
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade300),
                            color: Colors.grey.shade100,
                          ),
                          child: const Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.add_photo_alternate, size: 32),
                              SizedBox(height: 8),
                              Text('Custom Image', style: TextStyle(fontSize: 12)),
                            ],
                          ),
                        ),
                      );
                    }

                    final preset = ThemeService.wallpaperPresets[index];
                    final isSelected = _selectedWallpaper?.name == preset.name;

                    Widget background;
                    switch (preset.type) {
                      case WallpaperType.none:
                        background = Container(
                          color: Colors.white,
                          child: const Center(
                            child: Text('None', style: TextStyle(fontSize: 12)),
                          ),
                        );
                        break;
                      case WallpaperType.solid:
                        background = Container(
                          color: preset.color ?? Colors.white,
                        );
                        break;
                      case WallpaperType.gradient:
                        background = Container(
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                              colors: preset.colors ?? [Colors.white, Colors.grey],
                            ),
                          ),
                        );
                        break;
                      case WallpaperType.image:
                        background = Container(
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.image),
                        );
                        break;
                    }

                    return GestureDetector(
                      onTap: () async {
                        setState(() => _selectedWallpaper = preset);
                        await _themeService.setWallpaperPreset(preset);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isSelected
                                ? Theme.of(context).colorScheme.primary
                                : Colors.grey.shade300,
                            width: isSelected ? 3 : 1,
                          ),
                          boxShadow: isSelected
                              ? [
                                  BoxShadow(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withOpacity(0.3),
                                    blurRadius: 8,
                                    spreadRadius: 2,
                                  ),
                                ]
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: background,
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required IconData icon,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            child,
          ],
        ),
      ),
    );
  }

  Future<void> _showCustomColorPicker() async {
    final currentPrimary = _themeService.primaryColor ?? ThemeService.colorPresets[0].primary;
    final currentSecondary = _themeService.secondaryColor ?? ThemeService.colorPresets[0].secondary;
    final currentAccent = _themeService.accentColor ?? ThemeService.colorPresets[0].accent;

    Color? newPrimary = currentPrimary;
    Color? newSecondary = currentSecondary;
    Color? newAccent = currentAccent;

    final result = await showDialog<Map<String, Color>>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Custom Colors'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('Primary Color'),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: newPrimary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  // In a real app, you'd use a color picker package
                  // For now, show a simple color selection
                  final color = await _showSimpleColorPicker(context, newPrimary!);
                  if (color != null) {
                    newPrimary = color;
                  }
                },
              ),
              ListTile(
                title: const Text('Secondary Color'),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: newSecondary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final color = await _showSimpleColorPicker(context, newSecondary!);
                  if (color != null) {
                    newSecondary = color;
                  }
                },
              ),
              ListTile(
                title: const Text('Accent Color'),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: newAccent,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey),
                  ),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () async {
                  final color = await _showSimpleColorPicker(context, newAccent!);
                  if (color != null) {
                    newAccent = color;
                  }
                },
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, {
              'primary': newPrimary!,
              'secondary': newSecondary!,
              'accent': newAccent!,
            }),
            child: const Text('Apply'),
          ),
        ],
      ),
    );

    if (result != null) {
      await _themeService.setColors(
        primary: result['primary'],
        secondary: result['secondary'],
        accent: result['accent'],
      );
      setState(() => _selectedColorPreset = null);
    }
  }

  Future<Color?> _showSimpleColorPicker(BuildContext context, Color currentColor) async {
    final colors = [
      Colors.red,
      Colors.pink,
      Colors.purple,
      Colors.deepPurple,
      Colors.indigo,
      Colors.blue,
      Colors.lightBlue,
      Colors.cyan,
      Colors.teal,
      Colors.green,
      Colors.lightGreen,
      Colors.lime,
      Colors.yellow,
      Colors.amber,
      Colors.orange,
      Colors.deepOrange,
      Colors.brown,
      Colors.grey,
      Colors.blueGrey,
      Colors.black,
    ];

    return showDialog<Color>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Select Color'),
        content: Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            return GestureDetector(
              onTap: () => Navigator.pop(context, color),
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: color == currentColor
                        ? Colors.white
                        : Colors.grey.shade400,
                    width: color == currentColor ? 3 : 1,
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  Future<void> _pickCustomWallpaper() async {
    try {
      final fileService = FileService();
      final image = await fileService.pickImage(source: ImageSource.gallery);
      if (image != null) {
        final url = await fileService.uploadImage(image);
        if (url != null) {
          await _themeService.setChatWallpaper(url);
          setState(() => _selectedWallpaper = null);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Wallpaper updated')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Failed to upload wallpaper')),
            );
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    }
  }
}

