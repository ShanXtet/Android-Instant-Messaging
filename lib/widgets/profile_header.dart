import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/user_profile.dart';

/// Profile Header Widget
/// Displays user avatar, cover image, name, status, bio, and quick actions
class ProfileHeader extends StatelessWidget {
  final UserProfile profile;
  final VoidCallback? onAvatarTap;
  final VoidCallback? onCoverTap;
  final VoidCallback? onMessageTap;
  final VoidCallback? onCallTap;
  final VoidCallback? onVideoCallTap;
  final bool isLoading;

  const ProfileHeader({
    super.key,
    required this.profile,
    this.onAvatarTap,
    this.onCoverTap,
    this.onMessageTap,
    this.onCallTap,
    this.onVideoCallTap,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            colorScheme.primaryContainer,
            colorScheme.surfaceContainerLowest,
          ],
        ),
      ),
      child: Column(
        children: [
          // Cover Image Section
          Stack(
            children: [
              GestureDetector(
                onTap: onCoverTap,
                child: Container(
                  height: 200,
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        colorScheme.primary,
                        colorScheme.secondary,
                      ],
                    ),
                  ),
                  child: profile.coverImageUrl != null &&
                          profile.coverImageUrl!.isNotEmpty
                      ? Stack(
                          fit: StackFit.expand,
                          children: [
                            CachedNetworkImage(
                              imageUrl: profile.coverImageUrl!,
                              fit: BoxFit.cover,
                              errorWidget: (context, url, error) =>
                                  _buildDefaultCover(colorScheme),
                            ),
                            // Gradient overlay
                            Container(
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topCenter,
                                  end: Alignment.bottomCenter,
                                  colors: [
                                    Colors.transparent,
                                    Colors.black.withOpacity(0.3),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : _buildDefaultCover(colorScheme),
                ),
              ),
              // Edit cover button
              if (onCoverTap != null)
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    icon: const Icon(Icons.camera_alt, color: Colors.white),
                    onPressed: onCoverTap,
                    style: IconButton.styleFrom(
                      backgroundColor: Colors.black.withOpacity(0.5),
                    ),
                  ),
                ),
            ],
          ),

          // Avatar and User Info Section
          Transform.translate(
            offset: const Offset(0, -60),
            child: Column(
              children: [
                // Avatar with edit badge
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    GestureDetector(
                      onTap: onAvatarTap,
                      child: Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: colorScheme.surface,
                            width: 4,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: ClipOval(
                          child: profile.avatarUrl != null &&
                                  profile.avatarUrl!.isNotEmpty
                              ? CachedNetworkImage(
                                  imageUrl: profile.avatarUrl!,
                                  fit: BoxFit.cover,
                                  errorWidget: (context, url, error) =>
                                      _buildAvatarFallback(colorScheme),
                                )
                              : _buildAvatarFallback(colorScheme),
                        ),
                      ),
                    ),
                    // Edit avatar badge
                    if (onAvatarTap != null)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          decoration: BoxDecoration(
                            color: colorScheme.primary,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: colorScheme.surface,
                              width: 3,
                            ),
                          ),
                          child: IconButton(
                            icon: const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                            onPressed: isLoading ? null : onAvatarTap,
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(
                              minWidth: 36,
                              minHeight: 36,
                            ),
                          ),
                        ),
                      ),
                    // Loading overlay
                    if (isLoading)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.5),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: CircularProgressIndicator(
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 16),

                // User Name
                Text(
                  profile.name.isNotEmpty ? profile.name : 'No name',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),

                const SizedBox(height: 8),

                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(profile.status, colorScheme),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: _getStatusDotColor(profile.status),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        profile.status.getDisplayName(),
                        style: TextStyle(
                          color: _getStatusTextColor(profile.status),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

                // Bio
                if (profile.bio != null && profile.bio!.isNotEmpty) ...[
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Text(
                      profile.bio!,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                      textAlign: TextAlign.center,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],

                // Join Date and Last Seen
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (profile.joinDate != null) ...[
                        Icon(
                          Icons.calendar_today,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Joined ${_formatDate(profile.joinDate!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                      if (profile.joinDate != null &&
                          profile.lastSeen != null) ...[
                        const SizedBox(width: 16),
                        Container(
                          width: 4,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.onSurfaceVariant,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 16),
                      ],
                      if (profile.lastSeen != null) ...[
                        Icon(
                          Icons.access_time,
                          size: 14,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Last seen ${_formatLastSeen(profile.lastSeen!)}',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),

                // Quick Action Buttons
                const SizedBox(height: 24),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (onMessageTap != null)
                        _ActionButton(
                          icon: Icons.message,
                          label: 'Message',
                          onTap: onMessageTap!,
                          colorScheme: colorScheme,
                        ),
                      if (onCallTap != null) ...[
                        const SizedBox(width: 12),
                        _ActionButton(
                          icon: Icons.call,
                          label: 'Call',
                          onTap: onCallTap!,
                          colorScheme: colorScheme,
                        ),
                      ],
                      if (onVideoCallTap != null) ...[
                        const SizedBox(width: 12),
                        _ActionButton(
                          icon: Icons.videocam,
                          label: 'Video',
                          onTap: onVideoCallTap!,
                          colorScheme: colorScheme,
                        ),
                      ],
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefaultCover(ColorScheme colorScheme) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colorScheme.primary,
            colorScheme.secondary,
          ],
        ),
      ),
    );
  }

  Widget _buildAvatarFallback(ColorScheme colorScheme) {
    return Container(
      color: colorScheme.primaryContainer,
      child: Center(
        child: Text(
          profile.getInitials(),
          style: TextStyle(
            fontSize: 48,
            fontWeight: FontWeight.bold,
            color: colorScheme.onPrimaryContainer,
          ),
        ),
      ),
    );
  }

  Color _getStatusColor(UserStatus status, ColorScheme colorScheme) {
    switch (status) {
      case UserStatus.online:
        return Colors.green.withOpacity(0.1);
      case UserStatus.away:
        return Colors.orange.withOpacity(0.1);
      case UserStatus.busy:
        return Colors.red.withOpacity(0.1);
      case UserStatus.offline:
        return colorScheme.surfaceContainerHighest;
    }
  }

  Color _getStatusDotColor(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return Colors.green;
      case UserStatus.away:
        return Colors.orange;
      case UserStatus.busy:
        return Colors.red;
      case UserStatus.offline:
        return Colors.grey;
    }
  }

  Color _getStatusTextColor(UserStatus status) {
    switch (status) {
      case UserStatus.online:
        return Colors.green.shade700;
      case UserStatus.away:
        return Colors.orange.shade700;
      case UserStatus.busy:
        return Colors.red.shade700;
      case UserStatus.offline:
        return Colors.grey.shade700;
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays < 30) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 365) {
      final months = (difference.inDays / 30).floor();
      return '$months ${months == 1 ? 'month' : 'months'} ago';
    } else {
      final years = (difference.inDays / 365).floor();
      return '$years ${years == 1 ? 'year' : 'years'} ago';
    }
  }

  String _formatLastSeen(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'just now';
    } else if (difference.inMinutes < 60) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inHours < 24) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return '${(difference.inDays / 7).floor()}w ago';
    }
  }
}

/// Quick Action Button Widget
class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final ColorScheme colorScheme;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.colorScheme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        label: Text(label),
        style: FilledButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }
}

