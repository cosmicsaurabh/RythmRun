import 'package:email_validator/email_validator.dart';

class ValidationHelper {
  static String? validateEmail(String? email) {
   
    if (email == null || email.isEmpty || !EmailValidator.validate(email)) {
      return 'Please enter a valid email address';
    }
    return null;
  }

  static String? validatePassword(String? password) {
    if (password == null || password.isEmpty) {
      return 'Password is required';
    }
    if (password.length < 8) {
      return 'Password must be at least 8 characters long';
    }
    if (!password.contains(RegExp(r'[A-Z]'))) {
      return 'Password must contain at least one uppercase letter';
    }
    if (!password.contains(RegExp(r'[a-z]'))) {
      return 'Password must contain at least one lowercase letter';
    }
    if (!password.contains(RegExp(r'[0-9]'))) {
      return 'Password must contain at least one number';
    }
    if (!password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) {
      return 'Password must contain at least one special character';
    }
    return null;
  }

  static String? validateConfirmPassword(
    String? password,
    String? confirmPassword,
  ) {
   
    if (confirmPassword == null || confirmPassword.isEmpty || password != confirmPassword) {
      return 'Passwords do not match';
    }
    return null;
  }

  static String? validateName(String? name, String fieldName) {
    if (name == null || name.isEmpty) {
      return '$fieldName is required';
    }
    if (name.length < 3) {
      return '$fieldName must be at least 3 characters long';
    }
    if (!RegExp(r'^[a-zA-Z\s]+$').hasMatch(name)) {
      return '$fieldName can only contain letters and spaces';
    }
    return null;
  }

  static PasswordStrength getPasswordStrength(String password) {
    int score = 0;

    if (password.length >= 8) score++;
    if (password.contains(RegExp(r'[A-Z]'))) score++;
    if (password.contains(RegExp(r'[a-z]'))) score++;
    if (password.contains(RegExp(r'[0-9]'))) score++;
    if (password.contains(RegExp(r'[!@#$%^&*(),.?":{}|<>]'))) score++;
    if (password.length >= 12) score++;

    switch (score) {
      case 0:
      case 1:
      case 2:
        return PasswordStrength.weak;
      case 3:
      case 4:
        return PasswordStrength.medium;
      case 5:
      case 6:
        return PasswordStrength.strong;
      default:
        return PasswordStrength.weak;
    }
  }

  /// Validates all registration form fields at once
  /// Returns a map of field names to error messages
  static Map<String, String> validateRegistrationForm({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String confirmPassword,
    required bool acceptedTerms,
  }) {
    final errors = <String, String>{};

    final firstNameError = validateName(firstName, 'First name');
    if (firstNameError != null) errors['firstName'] = firstNameError;

    final lastNameError = validateName(lastName, 'Last name');
    if (lastNameError != null) errors['lastName'] = lastNameError;

    final emailError = validateEmail(email);
    if (emailError != null) errors['email'] = emailError;

    final passwordError = validatePassword(password);
    if (passwordError != null) errors['password'] = passwordError;

    final confirmPasswordError = validateConfirmPassword(
      password,
      confirmPassword,
    );
    if (confirmPasswordError != null) {
      errors['confirmPassword'] = confirmPasswordError;
    }

    if (!acceptedTerms) {
      errors['terms'] = 'Please accept the terms and conditions';
    }

    return errors;
  }

  /// Checks if all registration form fields are valid
  static bool isRegistrationFormValid({
    required String firstName,
    required String lastName,
    required String email,
    required String password,
    required String confirmPassword,
    required bool acceptedTerms,
  }) {
    return validateRegistrationForm(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
      confirmPassword: confirmPassword,
      acceptedTerms: acceptedTerms,
    ).isEmpty;
  }
}

enum PasswordStrength { weak, medium, strong }
