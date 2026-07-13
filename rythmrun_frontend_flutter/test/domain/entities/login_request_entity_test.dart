import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/login_request_entity.dart';

void main() {
  test('string representation never contains the password', () {
    const password = 'unique-sensitive-password';
    final request = LoginRequestEntity(
      email: 'runner@example.com',
      password: password,
    );

    expect(request.toString(), contains('runner@example.com'));
    expect(request.toString(), isNot(contains(password)));
  });
}
