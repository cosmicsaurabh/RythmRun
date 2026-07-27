import 'package:image_picker/image_picker.dart';

class AvatarUploadResult {
  final String key;
  final String mimeType;

  const AvatarUploadResult({required this.key, required this.mimeType});
}

abstract class AvatarRepository {
  Future<AvatarUploadResult> uploadAvatar(XFile image);

  /// Returns a short-lived URL for the authenticated user's current avatar.
  Future<Uri> getAvatarReadUrl();
}
