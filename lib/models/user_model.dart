import 'package:cloud_firestore/cloud_firestore.dart';
import 'star_model.dart';

class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final int coins;
  final int totalMinutesLogged;
  final int streakCount;
  final DateTime? lastPerfectDay;
  final DateTime? lastCleanSlateCheck;
  final List<String> unlockedBadges;
  final List<String> unlockedThemes;
  final String activeTheme;
  final List<String> unlockedWidgetSkins;
  final String activeWidgetSkin;
  final List<StarModel> constellation;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.coins = 0,
    this.totalMinutesLogged = 0,
    this.streakCount = 0,
    this.lastPerfectDay,
    this.lastCleanSlateCheck,
    this.unlockedBadges = const [],
    this.unlockedThemes = const ['default'],
    this.activeTheme = 'default',
    this.unlockedWidgetSkins = const ['default'],
    this.activeWidgetSkin = 'default',
    this.constellation = const [],
  });

  UserModel copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    int? coins,
    int? totalMinutesLogged,
    int? streakCount,
    DateTime? lastPerfectDay,
    DateTime? lastCleanSlateCheck,
    List<String>? unlockedBadges,
    List<String>? unlockedThemes,
    String? activeTheme,
    List<String>? unlockedWidgetSkins,
    String? activeWidgetSkin,
    List<StarModel>? constellation,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
      totalMinutesLogged: totalMinutesLogged ?? this.totalMinutesLogged,
      streakCount: streakCount ?? this.streakCount,
      lastPerfectDay: lastPerfectDay ?? this.lastPerfectDay,
      lastCleanSlateCheck: lastCleanSlateCheck ?? this.lastCleanSlateCheck,
      unlockedBadges: unlockedBadges ?? this.unlockedBadges,
      unlockedThemes: unlockedThemes ?? this.unlockedThemes,
      activeTheme: activeTheme ?? this.activeTheme,
      unlockedWidgetSkins: unlockedWidgetSkins ?? this.unlockedWidgetSkins,
      activeWidgetSkin: activeWidgetSkin ?? this.activeWidgetSkin,
      constellation: constellation ?? this.constellation,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'coins': coins,
        'totalMinutesLogged': totalMinutesLogged,
        'streakCount': streakCount,
        'lastPerfectDay':
            lastPerfectDay != null ? Timestamp.fromDate(lastPerfectDay!) : null,
        'lastCleanSlateCheck': lastCleanSlateCheck != null
            ? Timestamp.fromDate(lastCleanSlateCheck!)
            : null,
        'unlockedBadges': unlockedBadges,
        'unlockedThemes': unlockedThemes,
        'activeTheme': activeTheme,
        'unlockedWidgetSkins': unlockedWidgetSkins,
        'activeWidgetSkin': activeWidgetSkin,
        'constellation': constellation.map((s) => s.toMap()).toList(),
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] as String,
        displayName: map['displayName'] as String,
        email: map['email'] as String,
        photoUrl: map['photoUrl'] as String?,
        coins: (map['coins'] as int?) ?? 0,
        totalMinutesLogged: (map['totalMinutesLogged'] as int?) ?? 0,
        streakCount: (map['streakCount'] as int?) ?? 0,
        lastPerfectDay: _parseTimestamp(map['lastPerfectDay']),
        lastCleanSlateCheck: _parseTimestamp(map['lastCleanSlateCheck']),
        unlockedBadges: (map['unlockedBadges'] as List<dynamic>? ?? const [])
            .cast<String>(),
        unlockedThemes:
            (map['unlockedThemes'] as List<dynamic>? ?? const ['default'])
                .cast<String>(),
        activeTheme: (map['activeTheme'] as String?) ?? 'default',
        unlockedWidgetSkins:
            (map['unlockedWidgetSkins'] as List<dynamic>? ?? const ['default'])
                .cast<String>(),
        activeWidgetSkin: (map['activeWidgetSkin'] as String?) ?? 'default',
        constellation: (map['constellation'] as List<dynamic>? ?? const [])
            .map((e) => StarModel.fromMap(Map<String, dynamic>.from(e as Map)))
            .toList(),
      );

  static DateTime? _parseTimestamp(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is Timestamp) return value.toDate();
    if (value is String) return DateTime.tryParse(value);
    return null;
  }
}
