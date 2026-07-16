class UserEntity {
  static const Object _unset = Object();

  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final bool hasPassword;
  final String? profilePicturePath; // Keep for backward compatibility
  final String? profilePictureType;
  final DateTime? createdAt;

  const UserEntity({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.hasPassword = true,
    this.profilePicturePath,
    this.profilePictureType,
    this.createdAt,
  });

  UserEntity copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? email,
    bool? hasPassword,
    Object? profilePicturePath = _unset,
    Object? profilePictureType = _unset,
    Object? createdAt = _unset,
  }) {
    return UserEntity(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      hasPassword: hasPassword ?? this.hasPassword,
      profilePicturePath:
          identical(profilePicturePath, _unset)
              ? this.profilePicturePath
              : profilePicturePath as String?,
      profilePictureType:
          identical(profilePictureType, _unset)
              ? this.profilePictureType
              : profilePictureType as String?,
      createdAt:
          identical(createdAt, _unset)
              ? this.createdAt
              : createdAt as DateTime?,
    );
  }

  String get fullName => '$firstName $lastName';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          firstName == other.firstName &&
          lastName == other.lastName &&
          email == other.email &&
          hasPassword == other.hasPassword &&
          profilePicturePath == other.profilePicturePath &&
          profilePictureType == other.profilePictureType;

  @override
  int get hashCode =>
      id.hashCode ^
      firstName.hashCode ^
      lastName.hashCode ^
      email.hashCode ^
      hasPassword.hashCode ^
      profilePicturePath.hashCode ^
      profilePictureType.hashCode;

  @override
  String toString() {
    return 'UserEntity{id: $id, hasPassword: $hasPassword, hasProfilePicture: ${profilePicturePath != null}, createdAt: $createdAt}';
  }
}
