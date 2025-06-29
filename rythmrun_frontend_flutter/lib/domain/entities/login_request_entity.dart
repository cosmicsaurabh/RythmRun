class LoginRequestEntity{
  final String email;
  final String password;

  LoginRequestEntity({required this.email, required this.password});

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is LoginRequestEntity &&
          runtimeType == other.runtimeType &&
          email == other.email &&
          password == other.password;

  @override
  int get hashCode => email.hashCode ^ password.hashCode;

  @override
  String toString() {
    return 'LoginRequestEntity{email: $email, password: $password}';
  }
}