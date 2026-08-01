import 'package:cloud_firestore/cloud_firestore.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final int coins;
  final int streakCount;
  final DateTime? lastPerfectDay;
  final List<String> unlockedBadges;
  final List<String> unlockedThemes;
  final String activeTheme;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.coins = 0,
    this.streakCount = 0,
    this.lastPerfectDay,
    this.unlockedBadges = const [],
    this.unlockedThemes = const ['default'],
    this.activeTheme = 'default',
  });

  UserModel copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    int? coins,
    int? streakCount,
    DateTime? lastPerfectDay,
    List<String>? unlockedBadges,
    List<String>? unlockedThemes,
    String? activeTheme,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
      streakCount: streakCount ?? this.streakCount,
      lastPerfectDay: lastPerfectDay ?? this.lastPerfectDay,
      unlockedBadges: unlockedBadges ?? this.unlockedBadges,
      unlockedThemes: unlockedThemes ?? this.unlockedThemes,
      activeTheme: activeTheme ?? this.activeTheme,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'coins': coins,
        'streakCount': streakCount,
        'lastPerfectDay':
            lastPerfectDay != null ? Timestamp.fromDate(lastPerfectDay!) : null,
        'unlockedBadges': unlockedBadges,
        'unlockedThemes': unlockedThemes,
        'activeTheme': activeTheme,
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] as String,
        displayName: map['displayName'] as String,
        email: map['email'] as String,
        photoUrl: map['photoUrl'] as String?,
        coins: (map['coins'] as int?) ?? 0,
        streakCount: (map['streakCount'] as int?) ?? 0,
        lastPerfectDay: _parsePerfectDay(map['lastPerfectDay']),
        unlockedBadges: (map['unlockedBadges'] as List<dynamic>? ?? const [])
            .cast<String>(),
        unlockedThemes:
            (map['unlockedThemes'] as List<dynamic>? ?? const ['default'])
                .cast<String>(),
        activeTheme: (map['activeTheme'] as String?) ?? 'default',
      );

  static DateTime? _parsePerfectDay(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
