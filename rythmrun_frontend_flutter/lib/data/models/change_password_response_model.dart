class ChangePasswordResponseModel {
  final String message;
  final bool success;

  const ChangePasswordResponseModel({
    required this.message,
    required this.success,
  });

  factory ChangePasswordResponseModel.fromJson(Map<String, dynamic> json) {
    return ChangePasswordResponseModel(
      message: json['message'] ?? 'Password changed successfully',
      success: json['status'] == 'success' || json['message'] != null,
    );
  }

  Map<String, dynamic> toJson() {
    return {'message': message, 'success': success};
  }
}
