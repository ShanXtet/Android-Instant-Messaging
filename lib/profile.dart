// profile.dart - Simple Profile Page matching the design
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';
import 'package:cached_network_image/cached_network_image.dart';

import 'api.dart';
import 'auth_store.dart';
import 'socket_service.dart';
import 'login_page.dart';
import 'file_service.dart';
import 'models/user_profile.dart';
import 'theme_customization_page.dart';

class ProfilePage extends StatefulWidget {
  final String? peerId; // If provided, show peer's profile instead of own profile
  final String? peerName; // Optional peer name for display
  final String? peerEmail; // Optional peer email for display

  const ProfilePage({
    super.key,
    this.peerId,
    this.peerName,
    this.peerEmail,
  });

  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  UserProfile? _profile;
  bool _loading = true;
  bool _uploadingAvatar = false;
  String? _error;
  int _selectedMediaTab = 0;
  bool get _isOwnProfile => widget.peerId == null;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await AuthStore.getToken();
      if (token == null) {
        _navigateToLogin();
        return;
      }

      final response = _isOwnProfile
          ? await http.get(
              Uri.parse('$apiBase/api/auth/me'),
              headers: {'Authorization': 'Bearer $token'},
            )
          : await http.get(
              Uri.parse('$apiBase/api/users/by-ids?ids=${widget.peerId}'),
              headers: {'Authorization': 'Bearer $token'},
            );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        Map<String, dynamic> userData;
        
        if (_isOwnProfile) {
          userData = Map<String, dynamic>.from(data['user'] ?? data);
          await AuthStore.setUser(userData);
        } else {
          // For peer profile, the response is a map with peerId as key
          final map = Map<String, dynamic>.from(data);
          userData = Map<String, dynamic>.from(map[widget.peerId] ?? {});
          // If not found in response, create a basic profile from provided info
          if (userData.isEmpty) {
            userData = {
              '_id': widget.peerId,
              'name': widget.peerName ?? widget.peerEmail ?? 'Unknown User',
              'email': widget.peerEmail ?? '',
            };
          }
        }
        
        setState(() {
          _profile = UserProfile.fromJson(userData);
        });
      } else if (response.statusCode == 401) {
        await AuthStore.clear();
        if (mounted) _navigateToLogin();
        return;
      } else {
        setState(() {
          _error = 'Failed to load profile (${response.statusCode})';
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error loading profile: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  void _showAvatarOptions() {
    // Only allow avatar editing for own profile
    if (!_isOwnProfile) return;
    
    final hasAvatar = _profile?.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(hasAvatar ? 'Change profile photo' : 'Add profile photo'),
                onTap: () {
                  Navigator.pop(context);
                  _updateAvatar();
                },
              ),
              if (hasAvatar)
                ListTile(
                  leading: Icon(Icons.delete, color: theme.colorScheme.error),
                  title: Text(
                    'Remove profile photo',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeAvatar();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateAvatar() async {
    if (_profile == null) return;

    try {
      final fileService = FileService();
      final image = await fileService.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _uploadingAvatar = true);

      final url = await fileService.uploadImage(image);
      if (url == null) {
        if (mounted) {
          setState(() {
            _uploadingAvatar = false;
            _error = 'Failed to upload image';
          });
        }
        return;
      }

      final headers = await authHeaders();
      final response = await http.patch(
        Uri.parse('$apiBase/api/users/me'),
        headers: headers,
        body: jsonEncode({'avatarUrl': url}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = Map<String, dynamic>.from(data['user'] ?? data);
        setState(() {
          _profile = UserProfile.fromJson(userData);
        });
        await AuthStore.setUser(userData);
        _showSnackBar('Profile picture updated');
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to update profile picture';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_profile == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Remove Profile Photo'),
          content: const Text('Are you sure you want to remove your profile photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _uploadingAvatar = true);

    try {
      final headers = await authHeaders();
      final response = await http.patch(
        Uri.parse('$apiBase/api/users/me'),
        headers: headers,
        body: jsonEncode({'avatarUrl': null}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = Map<String, dynamic>.from(data['user'] ?? data);
        setState(() {
          _profile = UserProfile.fromJson(userData);
        });
        await AuthStore.setUser(userData);
        _showSnackBar('Profile photo removed');
      } else {
        if (mounted) {
          setState(() {
            _error = 'Failed to remove profile photo';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _logout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Log Out'),
          content: const Text('Are you sure you want to log out?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              child: const Text('Log Out'),
            ),
          ],
        );
      },
    );

    if (confirmed == true) {
      await AuthStore.clear();
      SocketService.I.disconnect();
      if (mounted) _navigateToLogin();
    }
  }

  void _navigateToLogin() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginPage()),
      (_) => false,
    );
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _navigateToEditProfile() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EditProfilePage(profile: _profile!),
      ),
    ).then((_) => _loadProfile()); // Reload profile after editing
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_loading) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Profile', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        body: Center(child: CircularProgressIndicator(color: theme.colorScheme.primary)),
      );
    }

    if (_profile == null) {
      return Scaffold(
        backgroundColor: theme.colorScheme.surface,
        appBar: AppBar(
          backgroundColor: theme.colorScheme.surface,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.colorScheme.onSurface),
            onPressed: () => Navigator.pop(context),
          ),
          title: Text('Profile', style: TextStyle(color: theme.colorScheme.onSurface)),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, size: 64, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 16),
              Text(
                _error ?? 'Failed to load profile',
                style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadProfile,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    // For peer profiles, show the new design matching the image
    if (!_isOwnProfile) {
      return _buildPeerProfileView(context);
    }

    // Split name into first and last name
    final nameParts = _profile!.name.split(' ');
    final firstName = nameParts.isNotEmpty ? nameParts[0] : '';
    final lastName = nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(_isOwnProfile ? 'My Profile' : 'Profile'),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 24),
            // Profile Picture and Info Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  // Profile Picture
                  Stack(
                    children: [
                      Container(
                        width: 80,
                        height: 80,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: theme.colorScheme.outline.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: ClipOval(
                          child: _profile!.avatarUrl != null &&
                                  _profile!.avatarUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: _profile!.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      _buildAvatarPlaceholder(),
                                )
                              : _buildAvatarPlaceholder(),
                        ),
                      ),
                      // Camera Icon Overlay (only for own profile)
                      if (_isOwnProfile)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: _uploadingAvatar ? null : _showAvatarOptions,
                          child: Container(
                            width: 28,
                            height: 28,
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primary,
                              shape: BoxShape.circle,
                              border: Border.all(color: theme.colorScheme.surface, width: 2),
                            ),
                            child: _uploadingAvatar
                                ? Padding(
                                    padding: const EdgeInsets.all(6),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: theme.colorScheme.onPrimary,
                                    ),
                                  )
                                : Icon(
                                    Icons.camera_alt,
                                    size: 14,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                          ),
                        ),
          ),
        ],
      ),
                  const SizedBox(width: 16),
                  // Name and Email
                  Expanded(
          child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
            children: [
                        Text(
                          _profile!.name.isNotEmpty ? _profile!.name : 'No name',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _profile!.email,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                ),
              ),
            ],
          ),
        ),
            const SizedBox(height: 24),
            // Edit Profile Button (only for own profile)
            if (_isOwnProfile)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _navigateToEditProfile,
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.green,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: Text(
                    'Edit Profile',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            // Menu Items
            _buildMenuItem(
              context: context,
              icon: Icons.download,
              title: 'Downloads',
              onTap: () {
                _showSnackBar('Downloads feature coming soon');
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.language,
              title: 'Language',
              onTap: () {
                _showSnackBar('Language settings coming soon');
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.location_on,
              title: 'Location',
              onTap: () {
                _showSnackBar('Location settings coming soon');
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.palette,
              title: 'Theme & Background',
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const ThemeCustomizationPage(),
                  ),
                );
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.delete_outline,
              title: 'Clear Cache',
              onTap: () async {
                final confirmed = await showDialog<bool>(
      context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Clear Cache'),
                    content: const Text('Are you sure you want to clear cache?'),
          actions: [
            TextButton(
                        onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear'),
            ),
          ],
      ),
    );
                if (confirmed == true) {
                  _showSnackBar('Cache cleared');
                }
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.history,
              title: 'Clear history',
              onTap: () async {
                final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
                    title: const Text('Clear History'),
                    content: const Text('Are you sure you want to clear history?'),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      FilledButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('Clear'),
        ),
                    ],
      ),
    );
                if (confirmed == true) {
                  _showSnackBar('History cleared');
                }
              },
            ),
            _buildMenuItem(
              context: context,
              icon: Icons.logout,
              title: 'Log Out',
              iconColor: Colors.red,
              textColor: Colors.red,
              onTap: _logout,
              ),
            const SizedBox(height: 24),
            // App Version
              Text(
              'App version 003',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
                        child: Text(
          _profile?.getInitials() ?? '?',
          style: TextStyle(
            fontSize: 32,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }

  Widget _buildMenuItem({
    required BuildContext context,
    required IconData icon,
    required String title,
    required VoidCallback onTap,
    Color? iconColor,
    Color? textColor,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor ?? colorScheme.onSurface,
              size: 24,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  color: textColor ?? colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            Icon(
              Icons.chevron_right,
              color: colorScheme.onSurfaceVariant,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPeerProfileView(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final initials = _profile!.getInitials();
    final username = _profile!.email.split('@').first;
    
    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        backgroundColor: colorScheme.surface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colorScheme.onSurface),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Profile', style: TextStyle(color: colorScheme.onSurface)),
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            // Large circular avatar with initials
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                color: const Color(0xFF764BA2), // Purple color
                shape: BoxShape.circle,
              ),
              child: _profile!.avatarUrl != null && _profile!.avatarUrl!.isNotEmpty
                  ? ClipOval(
                      child: CachedNetworkImage(
                        imageUrl: _profile!.avatarUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (context, url, error) => Center(
                          child: Text(
                            initials,
                            style: const TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    )
                  : Center(
                      child: Text(
                        initials,
                        style: const TextStyle(
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 16),
            // Contact name
            Text(
              _profile!.name.isNotEmpty ? _profile!.name : 'Unknown User',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            // Last seen
            Text(
              'last seen today at ${DateTime.now().hour}:${DateTime.now().minute.toString().padLeft(2, '0')}',
              style: TextStyle(
                fontSize: 14,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 24),
            // Action buttons row
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _buildActionButton(
                    context: context,
                    icon: Icons.volume_off,
                    label: 'mute',
                    onTap: () {
                      // Handle mute
                    },
                  ),
                  _buildActionButton(
                    context: context,
                    icon: Icons.search,
                    label: 'search',
                    onTap: () {
                      // Tell chat screen to open search box
                      Navigator.pop(context, 'search');
                    },
                  ),
                  _buildActionButton(
                    context: context,
                    icon: Icons.more_vert,
                    label: 'more',
                    onTap: () {
                      // Handle more
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Contact details section
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Add to Contacts
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () {
                        // Handle add to contacts
                      },
                      child: Text(
                        'Phone Number',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Block User
                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () {
                        // Handle block user
                      },
                      child: Text(
                        'Block User',
                        textAlign: TextAlign.left,
                        style: TextStyle(
                          fontSize: 16,
                          color: colorScheme.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            // Media tabs
            _buildMediaTabs(context),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton({
    required BuildContext context,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 60,
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: colorScheme.onSurface, size: 24),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMediaTabs(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final tabs = ['Media', 'Files', 'Voice', 'Links', 'Groups'];
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: tabs.asMap().entries.map((entry) {
          final index = entry.key;
          final tab = entry.value;
          final isSelected = index == _selectedMediaTab;
          
          return Expanded(
            child: GestureDetector(
              onTap: () {
                setState(() {
                  _selectedMediaTab = index;
                });
              },
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? colorScheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                ),
                child: Text(
                  tab,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 14,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

// Edit Profile Page
class EditProfilePage extends StatefulWidget {
  final UserProfile profile;

  const EditProfilePage({super.key, required this.profile});

  @override
  State<EditProfilePage> createState() => _EditProfilePageState();
}

class _EditProfilePageState extends State<EditProfilePage> {
  late TextEditingController _firstNameController;
  late TextEditingController _lastNameController;
  late TextEditingController _phoneController;
  bool _saving = false;
  bool _uploadingAvatar = false;
  UserProfile? _currentProfile;

  @override
  void initState() {
    super.initState();
    _currentProfile = widget.profile;
    
    // Split name into first and last
    final nameParts = widget.profile.name.split(' ');
    _firstNameController = TextEditingController(
      text: nameParts.isNotEmpty ? nameParts[0] : '',
    );
    _lastNameController = TextEditingController(
      text: nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
    );
    _phoneController = TextEditingController(text: widget.profile.phone ?? '');
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    super.dispose();
  }

  void _showAvatarOptions() {
    final hasAvatar = _currentProfile?.avatarUrl != null && _currentProfile!.avatarUrl!.isNotEmpty;
    
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        final theme = Theme.of(context);
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(Icons.photo_library),
                title: Text(hasAvatar ? 'Change profile photo' : 'Add profile photo'),
                onTap: () {
                  Navigator.pop(context);
                  _updateAvatar();
                },
              ),
              if (hasAvatar)
                ListTile(
                  leading: Icon(Icons.delete, color: theme.colorScheme.error),
                  title: Text(
                    'Remove profile photo',
                    style: TextStyle(color: theme.colorScheme.error),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _removeAvatar();
                  },
                ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Future<void> _updateAvatar() async {
    if (_currentProfile == null) return;

    try {
      final fileService = FileService();
      final image = await fileService.pickImage(source: ImageSource.gallery);
      if (image == null) return;

      setState(() => _uploadingAvatar = true);

      final url = await fileService.uploadImage(image);
      if (url == null) {
        if (mounted) {
          setState(() {
            _uploadingAvatar = false;
          });
          _showSnackBar('Failed to upload image');
        }
        return;
      }

      final headers = await authHeaders();
      final response = await http.patch(
        Uri.parse('$apiBase/api/users/me'),
        headers: headers,
        body: jsonEncode({'avatarUrl': url}),
    );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = Map<String, dynamic>.from(data['user'] ?? data);
        setState(() {
          _currentProfile = UserProfile.fromJson(userData);
        });
        await AuthStore.setUser(userData);
        _showSnackBar('Profile picture updated');
      } else {
        _showSnackBar('Failed to update profile picture');
    }
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
      }
    }
  }

  Future<void> _removeAvatar() async {
    if (_currentProfile == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Remove Profile Photo'),
          content: const Text('Are you sure you want to remove your profile photo?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              style: FilledButton.styleFrom(backgroundColor: theme.colorScheme.error),
              child: const Text('Remove'),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    setState(() => _uploadingAvatar = true);

    try {
      final headers = await authHeaders();
      final response = await http.patch(
        Uri.parse('$apiBase/api/users/me'),
        headers: headers,
        body: jsonEncode({'avatarUrl': null}),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = Map<String, dynamic>.from(data['user'] ?? data);
        setState(() {
          _currentProfile = UserProfile.fromJson(userData);
        });
        await AuthStore.setUser(userData);
        _showSnackBar('Profile photo removed');
      } else {
        _showSnackBar('Failed to remove profile photo');
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _uploadingAvatar = false);
    }
  }
  }

  Future<void> _saveProfile() async {
    if (_currentProfile == null) return;

    setState(() => _saving = true);

    try {
      final headers = await authHeaders();
      final fullName = '${_firstNameController.text.trim()} ${_lastNameController.text.trim()}'.trim();
      
      final body = <String, dynamic>{
        'name': fullName,
        if (_phoneController.text.trim().isNotEmpty)
          'phone': _phoneController.text.trim(),
      };

      final response = await http.patch(
        Uri.parse('$apiBase/api/users/me'),
        headers: headers,
        body: jsonEncode(body),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final userData = Map<String, dynamic>.from(data['user'] ?? data);
        await AuthStore.setUser(userData);
        _showSnackBar('Profile updated successfully');
        Navigator.pop(context);
      } else {
        _showSnackBar('Failed to update profile');
      }
    } catch (e) {
      _showSnackBar('Error: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

      return Scaffold(
        appBar: AppBar(
        title: const Text('Edit Profile'),
      ),
      body: SingleChildScrollView(
          child: Column(
            children: [
            const SizedBox(height: 24),
            // Profile Picture
            Stack(
                    children: [
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.grey.shade300, width: 2),
                      ),
                  child: ClipOval(
                    child: _currentProfile!.avatarUrl != null &&
                            _currentProfile!.avatarUrl!.isNotEmpty
                        ? CachedNetworkImage(
                            imageUrl: _currentProfile!.avatarUrl!,
                            fit: BoxFit.cover,
                            errorWidget: (context, url, error) =>
                                _buildAvatarPlaceholder(),
                          )
                        : _buildAvatarPlaceholder(),
              ),
                ),
                // Camera Icon Overlay
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: GestureDetector(
                    onTap: _uploadingAvatar ? null : _showAvatarOptions,
                    child: Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                  ),
                      child: _uploadingAvatar
                          ? const Padding(
                              padding: EdgeInsets.all(6),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.camera_alt,
                              size: 16,
                              color: Colors.white,
                            ),
                    ),
                  ),
                    ),
                ],
              ),
            const SizedBox(height: 32),
            // Your Information Section
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Information',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 20),
                  // First Name
                  TextField(
                    controller: _firstNameController,
                    decoration: InputDecoration(
                      labelText: 'First name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Last Name
                  TextField(
                    controller: _lastNameController,
                    decoration: InputDecoration(
                      labelText: 'Last name',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Phone
                  TextField(
                    controller: _phoneController,
                    decoration: InputDecoration(
                      labelText: 'Phone',
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide(
                          color: Theme.of(context).colorScheme.primary,
                          width: 1.5,
                        ),
                      ),
                      filled: true,
                      fillColor: Colors.white,
                      prefixIcon: Container(
                        padding: const EdgeInsets.all(12),
                        child: const Text('+91 ▼'),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                      isDense: true,
                    ),
                    keyboardType: TextInputType.phone,
                  ),
                  const SizedBox(height: 32),
                ],
                    ),
            ),
            // Cancel and Save Buttons
            SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Cancel Button
                    OutlinedButton(
                      onPressed: _saving ? null : () {
                        Navigator.pop(context);
                      },
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                        minimumSize: const Size(100, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        side: BorderSide(
                          color: Colors.grey.shade300,
                          width: 1,
                        ),
                      ),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Save Button
                    ElevatedButton(
                      onPressed: _saving ? null : _saveProfile,
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 10),
                        minimumSize: const Size(100, 40),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(20),
                        ),
                        backgroundColor: Colors.green,
                        foregroundColor: Colors.white,
                        elevation: 0,
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                              ),
                            )
                          : const Text(
                              'Save',
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarPlaceholder() {
    return Container(
      color: Colors.grey.shade200,
      child: Center(
        child: Text(
          _currentProfile?.getInitials() ?? '?',
          style: TextStyle(
            fontSize: 40,
            fontWeight: FontWeight.bold,
            color: Colors.grey.shade600,
          ),
        ),
      ),
    );
  }
}
