class UserEntity {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final DateTime? createdAt;

  const UserEntity({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    this.createdAt,
  });

  String get fullName => '$firstName $lastName';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UserEntity &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          firstName == other.firstName &&
          lastName == other.lastName &&
          email == other.email;

  @override
  int get hashCode =>
      id.hashCode ^ firstName.hashCode ^ lastName.hashCode ^ email.hashCode;

  @override
  String toString() {
    return 'UserEntity{id: $id, firstName: $firstName, lastName: $lastName, email: $email, createdAt: $createdAt}';
  }
}
