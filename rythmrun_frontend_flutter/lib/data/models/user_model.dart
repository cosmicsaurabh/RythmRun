import '../../domain/entities/user_entity.dart';

class UserModel extends UserEntity {
  const UserModel({
    required super.id,
    required super.firstName,
    required super.lastName,
    required super.email,
    super.profilePicturePath,
    super.profilePictureType,
    super.createdAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'].toString(), // Backend returns int, convert to string
      firstName: json['firstname'] ?? '', // Backend uses lowercase
      lastName: json['lastname'] ?? '', // Backend uses lowercase
      email: json['username'] ?? '', // Backend uses username field for email
      profilePicturePath:
          json['profilePicturePath'] as String?, // Profile picture S3 key
      profilePictureType:
          json['profilePictureType'] as String?, // Profile picture MIME type
      createdAt: null, // Not provided by backend in registration response
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'firstName': firstName,
      'lastName': lastName,
      'email': email,
      'profilePicturePath': profilePicturePath,
      'profilePictureType': profilePictureType,
      'createdAt': createdAt?.toIso8601String(),
    };
  }

  factory UserModel.fromEntity(UserEntity entity) {
    return UserModel(
      id: entity.id,
      firstName: entity.firstName,
      lastName: entity.lastName,
      email: entity.email,
      profilePicturePath: entity.profilePicturePath,
      profilePictureType: entity.profilePictureType,
      createdAt: entity.createdAt,
    );
  }

  UserEntity toEntity() {
    return UserEntity(
      id: id,
      firstName: firstName,
      lastName: lastName,
      email: email,
      profilePicturePath: profilePicturePath,
      profilePictureType: profilePictureType,
      createdAt: createdAt,
    );
  }
}
