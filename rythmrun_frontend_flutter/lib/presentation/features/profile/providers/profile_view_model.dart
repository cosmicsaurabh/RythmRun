import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';

const Object _unsetProfileValue = Object();

typedef PickProfileImage = Future<XFile?> Function();
typedef CurrentProfileUserId = String? Function();
typedef UpdateProfilePicture =
    Future<void> Function(String ownerUserId, String path, String type);

class ProfileState {
  final bool isLoading;
  final String? errorMessage;

  ProfileState({this.isLoading = false, this.errorMessage});

  ProfileState copyWith({
    bool? isLoading,
    Object? errorMessage = _unsetProfileValue,
  }) {
    return ProfileState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage:
          identical(errorMessage, _unsetProfileValue)
              ? this.errorMessage
              : errorMessage as String?,
    );
  }
}

class ProfileViewModel extends StateNotifier<ProfileState> {
  final AvatarRepository _avatarRepository;
  final PickProfileImage _pickImage;
  final CurrentProfileUserId _currentUserId;
  final UpdateProfilePicture _updateProfilePicture;
  final UserScopeOperationGate? _operationGate;
  bool _isDisposed = false;

  ProfileViewModel(
    this._avatarRepository, {
    required PickProfileImage pickImage,
    required CurrentProfileUserId currentUserId,
    required UpdateProfilePicture updateProfilePicture,
    UserScopeOperationGate? operationGate,
  }) : _pickImage = pickImage,
       _currentUserId = currentUserId,
       _updateProfilePicture = updateProfilePicture,
       _operationGate = operationGate,
       super(ProfileState());

  Future<void> pickAndUploadImage() async {
    final ownerUserId = _currentUserId();
    if (ownerUserId == null) {
      state = state.copyWith(errorMessage: 'Sign in to update your profile.');
      return;
    }
    final numericUserId = int.tryParse(ownerUserId);
    final operationLease =
        numericUserId == null
            ? null
            : _operationGate?.tryAcquire(numericUserId);
    if (_operationGate != null && operationLease == null) {
      state = state.copyWith(
        errorMessage: 'Profile updates are paused during account cleanup.',
      );
      return;
    }

    try {
      final image = await _pickImage();
      if (_isDisposed || _currentUserId() != ownerUserId) return;

      if (image == null) return;
      // Start loading state
      state = state.copyWith(isLoading: true, errorMessage: null);

      try {
        developer.log(
          '[pfp] Starting upload process',
          name: 'ProfileViewModel',
        );

        final result = await _avatarRepository.uploadAvatar(image);
        if (_isDisposed || _currentUserId() != ownerUserId) return;
        // Update session with new profile picture
        await _updateProfilePicture(ownerUserId, result.key, result.mimeType);

        developer.log(
          '[pfp-vm] Session update call completed',
          name: 'ProfileViewModel',
        );

        if (_isDisposed || _currentUserId() != ownerUserId) return;

        // Upload complete - clear loading state
        state = state.copyWith(isLoading: false, errorMessage: null);
        developer.log(
          '[pfp] Profile upload complete',
          name: 'ProfileViewModel',
        );
      } catch (_) {
        if (_isDisposed || _currentUserId() != ownerUserId) return;
        developer.log('[pfp] Avatar upload failed', name: 'ProfileViewModel');
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to upload image.',
        );
      }
    } finally {
      operationLease?.release();
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }
}

final profileViewModelProvider =
    StateNotifierProvider<ProfileViewModel, ProfileState>((ref) {
      final avatarRepository = ref.watch(avatarRepositoryProvider);
      final picker = ImagePicker();
      return ProfileViewModel(
        avatarRepository,
        pickImage: () => picker.pickImage(source: ImageSource.gallery),
        currentUserId: () => ref.read(sessionProvider).user?.id,
        updateProfilePicture:
            (ownerUserId, path, type) => ref
                .read(sessionProvider.notifier)
                .updateProfilePicture(
                  ownerUserId: ownerUserId,
                  path: path,
                  type: type,
                ),
        operationGate: ref.watch(userScopeOperationGateProvider),
      );
    });
