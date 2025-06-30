import '../../domain/entities/user_entity.dart';
import 'user_model.dart';

class AuthResponseModel {
  final UserModel user;
  final String accessToken;
  final String refreshToken;

  const AuthResponseModel({
    required this.user,
    required this.accessToken,
    required this.refreshToken,
  });

  factory AuthResponseModel.fromJson(Map<String, dynamic> json) {
    return AuthResponseModel(
      user: UserModel.fromJson(json), // User data is in the same JSON object
      accessToken: json['accessToken'] as String,
      refreshToken: json['refreshToken'] as String,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      ...user.toJson(),
      'accessToken': accessToken,
      'refreshToken': refreshToken,
    };
  }

  UserEntity toUserEntity() {
    return user.toEntity();
  }
}
