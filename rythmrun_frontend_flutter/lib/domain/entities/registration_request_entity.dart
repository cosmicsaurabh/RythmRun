class RegistrationRequestEntity {
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final bool acceptedTerms;

  const RegistrationRequestEntity({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.acceptedTerms,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is RegistrationRequestEntity &&
          runtimeType == other.runtimeType &&
          firstName == other.firstName &&
          lastName == other.lastName &&
          email == other.email &&
          password == other.password &&
          acceptedTerms == other.acceptedTerms;

  @override
  int get hashCode =>
      firstName.hashCode ^
      lastName.hashCode ^
      email.hashCode ^
      password.hashCode ^
      acceptedTerms.hashCode;

  @override
  String toString() {
    return 'RegistrationRequestEntity{firstName: $firstName, lastName: $lastName, email: $email, acceptedTerms: $acceptedTerms}';
  }
}
