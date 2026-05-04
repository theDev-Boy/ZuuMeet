import 'package:equatable/equatable.dart';

/// Represents a Zuumeet user stored in Firebase Realtime Database.
class UserModel extends Equatable {
  final String uid;
  final String name;
  final String email;
  final String? photoUrl;
  final String gender;
  final String age;
  final String country;
  final String countryCode;
  final bool isOnline;
  final bool isSearching;
  final int createdAt;
  final int lastActive;
  final List<String> blockedUsers;
  final List<String> friends;
  final List<String> friendRequests;
  final String avatarUrl;
  final String frameId;
  final bool isVip;
  final String displayId; // 6-digit numeric ID

  const UserModel({
    required this.uid,
    required this.name,
    required this.email,
    this.photoUrl,
    this.gender = '',
    this.age = '',
    this.country = '',
    this.countryCode = '',
    this.isOnline = false,
    this.isSearching = false,
    required this.createdAt,
    required this.lastActive,
    this.blockedUsers = const [],
    this.friends = const [],
    this.friendRequests = const [],
    this.avatarUrl = '',
    this.frameId = 'free_border',
    this.isVip = false,
    this.displayId = '',
  });

  factory UserModel.fromJson(Map<dynamic, dynamic> json, String uid) {
    return UserModel(
      uid: uid,
      name: json['name'] as String? ?? '',
      email: json['email'] as String? ?? '',
      photoUrl: json['photoUrl'] as String?,
      gender: json['gender'] as String? ?? '',
      age: json['age'] as String? ?? '',
      country: json['country'] as String? ?? '',
      countryCode: json['countryCode'] as String? ?? '',
      isOnline: json['isOnline'] as bool? ?? false,
      isSearching: json['isSearching'] as bool? ?? false,
      createdAt: json['createdAt'] as int? ?? 0,
      lastActive: json['lastActive'] as int? ?? 0,
      blockedUsers: (json['blockedUsers'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      friends: (json['friends'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      friendRequests: (json['friendRequests'] as List<dynamic>?)
              ?.map((e) => e.toString())
              .toList() ??
          [],
      avatarUrl: json['avatarUrl'] as String? ?? '',
      frameId: json['frameId'] as String? ?? 'free_border',
      isVip: json['isVip'] as bool? ?? false,
      displayId: json['displayId'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'email': email,
      'photoUrl': photoUrl,
      'gender': gender,
      'age': age,
      'country': country,
      'countryCode': countryCode,
      'isOnline': isOnline,
      'isSearching': isSearching,
      'createdAt': createdAt,
      'lastActive': lastActive,
      'blockedUsers': blockedUsers,
      'friends': friends,
      'friendRequests': friendRequests,
      'avatarUrl': avatarUrl,
      'frameId': frameId,
      'isVip': isVip,
      'displayId': displayId,
    };
  }

  UserModel copyWith({
    String? name,
    String? email,
    String? photoUrl,
    String? gender,
    String? age,
    String? country,
    String? countryCode,
    bool? isOnline,
    bool? isSearching,
    int? lastActive,
    List<String>? blockedUsers,
    List<String>? friends,
    List<String>? friendRequests,
    String? avatarUrl,
    String? frameId,
    bool? isVip,
    String? displayId,
  }) {
    return UserModel(
      uid: uid,
      name: name ?? this.name,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      gender: gender ?? this.gender,
      age: age ?? this.age,
      country: country ?? this.country,
      countryCode: countryCode ?? this.countryCode,
      isOnline: isOnline ?? this.isOnline,
      isSearching: isSearching ?? this.isSearching,
      createdAt: createdAt,
      lastActive: lastActive ?? this.lastActive,
      blockedUsers: blockedUsers ?? this.blockedUsers,
      friends: friends ?? this.friends,
      friendRequests: friendRequests ?? this.friendRequests,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      frameId: frameId ?? this.frameId,
      isVip: isVip ?? this.isVip,
      displayId: displayId ?? this.displayId,
    );
  }

  /// Converts a country code to a flag emoji.
  String get flagEmoji {
    if (countryCode.isEmpty || countryCode.length != 2) return '🌍';
    final code = countryCode.toUpperCase();
    return String.fromCharCodes([
      code.codeUnitAt(0) + 0x1F1A5,
      code.codeUnitAt(1) + 0x1F1A5,
    ]);
  }

  /// Returns initials for avatar placeholder.
  String get initials {
    if (name.isEmpty) return '?';
    final parts = name.trim().split(' ');
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }

  @override
  List<Object?> get props => [uid, name, email, gender, age, country];
}
