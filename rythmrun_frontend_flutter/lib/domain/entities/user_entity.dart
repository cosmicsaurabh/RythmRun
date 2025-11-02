class UserEntity {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String? profilePicturePath; // Keep for backward compatibility
  final String? profilePictureType;
  final DateTime? createdAt;

  const UserEntity({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.profilePicturePath,
    this.profilePictureType,
    this.createdAt,
  });

  UserEntity copyWith({
    String? id,
    String? firstName,
    String? lastName,
    String? email,
    String? profilePicturePath,
    String? profilePictureType,
    DateTime? createdAt,
  }) {
    return UserEntity(
      id: id ?? this.id,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      email: email ?? this.email,
      profilePicturePath: profilePicturePath ?? this.profilePicturePath,
      profilePictureType: profilePictureType ?? this.profilePictureType,
      createdAt: createdAt ?? this.createdAt,
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
          profilePicturePath == other.profilePicturePath &&
          profilePictureType == other.profilePictureType;

  @override
  int get hashCode =>
      id.hashCode ^
      firstName.hashCode ^
      lastName.hashCode ^
      email.hashCode ^
      profilePicturePath.hashCode ^
      profilePictureType.hashCode;

  @override
  String toString() {
    return 'UserEntity{id: $id, firstName: $firstName, lastName: $lastName, email: $email, profilePicturePath: $profilePicturePath, profilePictureType: $profilePictureType, createdAt: $createdAt}';
  }
}
