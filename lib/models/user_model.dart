class UserModel {
  final String uid;
  final String displayName;
  final String email;
  final String? photoUrl;
  final int coins;

  const UserModel({
    required this.uid,
    required this.displayName,
    required this.email,
    this.photoUrl,
    this.coins = 0,
  });

  UserModel copyWith({
    String? uid,
    String? displayName,
    String? email,
    String? photoUrl,
    int? coins,
  }) {
    return UserModel(
      uid: uid ?? this.uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      coins: coins ?? this.coins,
    );
  }

  Map<String, dynamic> toMap() => {
        'uid': uid,
        'displayName': displayName,
        'email': email,
        'photoUrl': photoUrl,
        'coins': coins,
      };

  factory UserModel.fromMap(Map<String, dynamic> map) => UserModel(
        uid: map['uid'] as String,
        displayName: map['displayName'] as String,
        email: map['email'] as String,
        photoUrl: map['photoUrl'] as String?,
        coins: (map['coins'] as int?) ?? 0,
      );
}