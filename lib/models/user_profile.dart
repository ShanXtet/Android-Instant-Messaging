/// User Profile Model
/// Contains all user profile information
class UserProfile {
  final String id;
  final String name;
  final String email;
  final String? phone;
  final String? avatarUrl;
  final String? coverImageUrl;
  final String? bio;
  final UserStatus status;
  final DateTime? lastSeen;
  final DateTime? joinDate;
  final DateTime? birthday;
  final String? gender;
  final String? location;
  final String? timezone;
  final bool emailVerified;
  final bool phoneVerified;
  final bool twoFactorEnabled;

  UserProfile({
    required this.id,
    required this.name,
    required this.email,
    this.phone,
    this.avatarUrl,
    this.coverImageUrl,
    this.bio,
    this.status = UserStatus.offline,
    this.lastSeen,
    this.joinDate,
    this.birthday,
    this.gender,
    this.location,
    this.timezone,
    this.emailVerified = false,
    this.phoneVerified = false,
    this.twoFactorEnabled = false,
  });

  /// Create from JSON map
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      id: json['_id']?.toString() ?? json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '',
      email: json['email']?.toString() ?? '',
      phone: json['phone']?.toString(),
      avatarUrl: json['avatarUrl']?.toString(),
      coverImageUrl: json['coverImageUrl']?.toString(),
      bio: json['bio']?.toString(),
      status: UserStatus.fromString(json['status']?.toString() ?? 'offline'),
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'].toString())
          : null,
      joinDate: json['createdAt'] != null
          ? DateTime.tryParse(json['createdAt'].toString())
          : (json['joinDate'] != null
              ? DateTime.tryParse(json['joinDate'].toString())
              : null),
      birthday: json['birthday'] != null
          ? DateTime.tryParse(json['birthday'].toString())
          : null,
      gender: json['gender']?.toString(),
      location: json['location']?.toString(),
      timezone: json['timezone']?.toString(),
      emailVerified: json['emailVerified'] == true,
      phoneVerified: json['phoneVerified'] == true,
      twoFactorEnabled: json['twoFactorEnabled'] == true,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'email': email,
      'phone': phone,
      'avatarUrl': avatarUrl,
      'coverImageUrl': coverImageUrl,
      'bio': bio,
      'status': status.toString(),
      'lastSeen': lastSeen?.toIso8601String(),
      'joinDate': joinDate?.toIso8601String(),
      'birthday': birthday?.toIso8601String(),
      'gender': gender,
      'location': location,
      'timezone': timezone,
      'emailVerified': emailVerified,
      'phoneVerified': phoneVerified,
      'twoFactorEnabled': twoFactorEnabled,
    };
  }

  /// Create a copy with updated fields
  UserProfile copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? avatarUrl,
    String? coverImageUrl,
    String? bio,
    UserStatus? status,
    DateTime? lastSeen,
    DateTime? joinDate,
    DateTime? birthday,
    String? gender,
    String? location,
    String? timezone,
    bool? emailVerified,
    bool? phoneVerified,
    bool? twoFactorEnabled,
  }) {
    return UserProfile(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      coverImageUrl: coverImageUrl ?? this.coverImageUrl,
      bio: bio ?? this.bio,
      status: status ?? this.status,
      lastSeen: lastSeen ?? this.lastSeen,
      joinDate: joinDate ?? this.joinDate,
      birthday: birthday ?? this.birthday,
      gender: gender ?? this.gender,
      location: location ?? this.location,
      timezone: timezone ?? this.timezone,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      twoFactorEnabled: twoFactorEnabled ?? this.twoFactorEnabled,
    );
  }

  /// Get user initials for avatar fallback
  String getInitials() {
    if (name.isEmpty) {
      if (email.isNotEmpty) {
        return email[0].toUpperCase();
      }
      return '?';
    }
    final parts = name.trim().split(' ').where((p) => p.isNotEmpty).toList();
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    if (parts.isNotEmpty && parts[0].isNotEmpty) {
      return parts[0][0].toUpperCase();
    }
    return '?';
  }
}

/// User Status Enum
enum UserStatus {
  online,
  away,
  busy,
  offline;

  static UserStatus fromString(String value) {
    switch (value.toLowerCase()) {
      case 'online':
        return UserStatus.online;
      case 'away':
        return UserStatus.away;
      case 'busy':
        return UserStatus.busy;
      case 'offline':
      default:
        return UserStatus.offline;
    }
  }

  @override
  String toString() {
    switch (this) {
      case UserStatus.online:
        return 'online';
      case UserStatus.away:
        return 'away';
      case UserStatus.busy:
        return 'busy';
      case UserStatus.offline:
        return 'offline';
    }
  }

  String getDisplayName() {
    switch (this) {
      case UserStatus.online:
        return 'Online';
      case UserStatus.away:
        return 'Away';
      case UserStatus.busy:
        return 'Busy';
      case UserStatus.offline:
        return 'Offline';
    }
  }
}


