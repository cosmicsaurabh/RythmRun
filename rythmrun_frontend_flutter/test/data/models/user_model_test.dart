import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/data/models/user_model.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';

void main() {
  test('parses and preserves a passwordless backend user capability', () {
    final model = UserModel.fromJson(<String, Object?>{
      'id': 7,
      'firstname': 'Google',
      'lastname': 'Runner',
      'username': 'runner@example.test',
      'hasPassword': false,
    });

    expect(model.hasPassword, isFalse);
    expect(model.toEntity().hasPassword, isFalse);
    expect(model.toJson()['hasPassword'], isFalse);
    expect(UserModel.fromEntity(model).hasPassword, isFalse);
  });

  test('older responses default to password-capable', () {
    final model = UserModel.fromJson(<String, Object?>{
      'id': 7,
      'firstname': 'Legacy',
      'lastname': 'Runner',
      'username': 'runner@example.test',
    });

    expect(model.hasPassword, isTrue);
  });

  test('copy and equality include the password capability', () {
    const passwordUser = UserEntity(
      id: '7',
      firstName: 'A',
      lastName: 'Runner',
      email: 'runner@example.test',
    );
    final googleUser = passwordUser.copyWith(hasPassword: false);

    expect(googleUser.hasPassword, isFalse);
    expect(googleUser, isNot(passwordUser));
    expect(googleUser.hashCode, isNot(passwordUser.hashCode));
    expect(googleUser.copyWith(), googleUser);
  });

  test('parses and round-trips an unverified email', () {
    final model = UserModel.fromJson(<String, Object?>{
      'id': 7,
      'firstname': 'Ada',
      'lastname': 'Runner',
      'username': 'runner@example.test',
      'emailVerified': false,
    });

    expect(model.emailVerified, isFalse);
    expect(model.toEntity().emailVerified, isFalse);
    expect(model.toJson()['emailVerified'], isFalse);
    expect(UserModel.fromEntity(model).emailVerified, isFalse);
  });

  test('responses omitting emailVerified default to verified', () {
    final model = UserModel.fromJson(<String, Object?>{
      'id': 7,
      'firstname': 'Legacy',
      'lastname': 'Runner',
      'username': 'runner@example.test',
    });

    // Defaulting to true keeps an older API (or a pre-upgrade cached blob)
    // from flagging every existing account as unverified.
    expect(model.emailVerified, isTrue);
  });

  test('equality and copyWith track the verified flag so the UI rebuilds', () {
    const verified = UserEntity(
      id: '7',
      firstName: 'A',
      lastName: 'Runner',
      email: 'runner@example.test',
    );
    final unverified = verified.copyWith(emailVerified: false);

    expect(unverified.emailVerified, isFalse);
    expect(unverified, isNot(verified));
    expect(unverified.hashCode, isNot(verified.hashCode));
    expect(unverified.copyWith(emailVerified: true), verified);
  });
}
