import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';

const Object _unsetProfileValue = Object();

typedef PickProfileImage = Future<XFile?> Function();
typedef CurrentProfileUserId = String? Function();
typedef UpdateProfilePicture =
    Future<void> Function(String ownerUserId, String path, String type);
typedef CommitProfileUpdate =
    Future<void> Function(String ownerUserId, UserEntity updatedUser);

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
  final AuthRepository? _authRepository;
  final PickProfileImage _pickImage;
  final CurrentProfileUserId _currentUserId;
  final UpdateProfilePicture _updateProfilePicture;
  final CommitProfileUpdate? _commitProfileUpdate;
  final UserScopeOperationGate? _operationGate;
  bool _isDisposed = false;

  ProfileViewModel(
    this._avatarRepository, {
    AuthRepository? authRepository,
    required PickProfileImage pickImage,
    required CurrentProfileUserId currentUserId,
    required UpdateProfilePicture updateProfilePicture,
    CommitProfileUpdate? commitProfileUpdate,
    UserScopeOperationGate? operationGate,
  }) : _authRepository = authRepository,
       _pickImage = pickImage,
       _currentUserId = currentUserId,
       _updateProfilePicture = updateProfilePicture,
       _commitProfileUpdate = commitProfileUpdate,
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

  /// Updates first/last name through the server and commits the confirmed
  /// result into session state. Returns whether the edit was applied.
  Future<bool> updateProfileName({
    required String firstName,
    required String lastName,
  }) async {
    final authRepository = _authRepository;
    final commitProfileUpdate = _commitProfileUpdate;
    if (authRepository == null || commitProfileUpdate == null) return false;

    final trimmedFirstName = firstName.trim();
    final trimmedLastName = lastName.trim();
    if (trimmedFirstName.isEmpty || trimmedLastName.isEmpty) {
      state = state.copyWith(
        errorMessage: 'First and last name cannot be empty.',
      );
      return false;
    }

    final ownerUserId = _currentUserId();
    if (ownerUserId == null) {
      state = state.copyWith(errorMessage: 'Sign in to update your profile.');
      return false;
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
      return false;
    }

    state = state.copyWith(isLoading: true, errorMessage: null);
    try {
      final updatedUser = await authRepository.updateProfile(
        firstName: trimmedFirstName,
        lastName: trimmedLastName,
      );
      if (_isDisposed || _currentUserId() != ownerUserId) return false;

      await commitProfileUpdate(ownerUserId, updatedUser);
      if (_isDisposed || _currentUserId() != ownerUserId) return false;

      state = state.copyWith(isLoading: false, errorMessage: null);
      return true;
    } on AuthSessionFailure catch (failure) {
      if (_isDisposed || _currentUserId() != ownerUserId) return false;
      // Typed session failures carry a safe, user-appropriate message —
      // notably the offline-mode denial from the IP-2.3 guard.
      state = state.copyWith(isLoading: false, errorMessage: failure.message);
      return false;
    } catch (_) {
      if (_isDisposed || _currentUserId() != ownerUserId) return false;
      state = state.copyWith(
        isLoading: false,
        errorMessage: 'Failed to update profile. Please try again.',
      );
      return false;
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
        authRepository: ref.watch(authRepositoryProvider),
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
        commitProfileUpdate:
            (ownerUserId, updatedUser) => ref
                .read(sessionProvider.notifier)
                .applyProfileUpdate(
                  ownerUserId: ownerUserId,
                  updatedUser: updatedUser,
                ),
        operationGate: ref.watch(userScopeOperationGateProvider),
      );
    });

/// The storage key is only a cache identity. The backend remains authoritative
/// and returns a short-lived signed URL for the authenticated user's avatar.
final profileAvatarUrlProvider = FutureProvider.autoDispose.family<Uri, String>(
  (ref, _) {
    return ref.watch(avatarRepositoryProvider).getAvatarReadUrl();
  },
);
