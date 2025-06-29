import '../../domain/entities/registration_request_entity.dart';

class RegistrationRequestModel {
  final String firstName;
  final String lastName;
  final String email;
  final String password;
  final bool acceptedTerms;

  const RegistrationRequestModel({
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.password,
    required this.acceptedTerms,
  });

  factory RegistrationRequestModel.fromJson(Map<String, dynamic> json) {
    return RegistrationRequestModel(
      firstName: json['firstName'] as String,
      lastName: json['lastName'] as String,
      email: json['email'] as String,
      password: json['password'] as String,
      acceptedTerms: json['acceptedTerms'] as bool,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'username': email, // Backend expects email as username
      'firstname': firstName, // Backend expects lowercase 'firstname'
      'lastname': lastName, // Backend expects lowercase 'lastname'
      'password': password,
      // acceptedTerms is not needed by backend
    };
  }

  factory RegistrationRequestModel.fromEntity(
    RegistrationRequestEntity entity,
  ) {
    return RegistrationRequestModel(
      firstName: entity.firstName,
      lastName: entity.lastName,
      email: entity.email,
      password: entity.password,
      acceptedTerms: entity.acceptedTerms,
    );
  }

  RegistrationRequestEntity toEntity() {
    return RegistrationRequestEntity(
      firstName: firstName,
      lastName: lastName,
      email: email,
      password: password,
      acceptedTerms: acceptedTerms,
    );
  }
}
