import 'dart:developer' as developer;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/di/injection_container.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';

class ProfileState {
  final bool isLoading;
  final String? errorMessage;

  ProfileState({this.isLoading = false, this.errorMessage});

  ProfileState copyWith({bool? isLoading, String? errorMessage}) {
    return ProfileState(
      isLoading: isLoading ?? this.isLoading,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
}

class ProfileViewModel extends StateNotifier<ProfileState> {
  final AvatarRepository _avatarRepository;
  final Ref _ref;

  ProfileViewModel(this._avatarRepository, this._ref) : super(ProfileState());

  Future<void> pickAndUploadImage() async {
    final ImagePicker picker = ImagePicker();
    final XFile? image = await picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      // Start loading state
      state = state.copyWith(isLoading: true, errorMessage: null);

      try {
        developer.log(
          '[pfp] Starting upload process',
          name: 'ProfileViewModel',
        );

        final result = await _avatarRepository.uploadAvatar(image);
        developer.log(
          '[pfp] Upload successful, key: ${result.key}, mimeType: ${result.mimeType}',
          name: 'ProfileViewModel',
        );

        // Update session with new profile picture
        developer.log(
          '[pfp-vm] About to update session with key: ${result.key}, mimeType: ${result.mimeType}',
          name: 'ProfileViewModel',
        );

        _ref
            .read(sessionProvider.notifier)
            .updateProfilePicture(result.key, result.mimeType);

        developer.log(
          '[pfp-vm] Session update call completed',
          name: 'ProfileViewModel',
        );

        // Verify the session was actually updated
        final updatedUser = _ref.read(sessionProvider).user;
        developer.log(
          '[pfp-vm] Verification - Updated user profilePicturePath: ${updatedUser?.profilePicturePath}',
          name: 'ProfileViewModel',
        );

        // If session update didn't work, refresh from server
        if (updatedUser?.profilePicturePath == null) {
          developer.log(
            '[pfp-vm] Session update failed, refreshing from server...',
            name: 'ProfileViewModel',
          );
          await _ref.read(sessionProvider.notifier).refreshSession();

          final refreshedUser = _ref.read(sessionProvider).user;
          developer.log(
            '[pfp-vm] After refresh - user profilePicturePath: ${refreshedUser?.profilePicturePath}',
            name: 'ProfileViewModel',
          );
        }

        // Upload complete - clear loading state
        state = state.copyWith(isLoading: false, errorMessage: null);
        developer.log(
          '[pfp] Profile upload complete',
          name: 'ProfileViewModel',
        );
      } catch (e, stackTrace) {
        developer.log(
          '[pfp] ERROR in pickAndUploadImage: $e\nStackTrace: $stackTrace',
          name: 'ProfileViewModel',
          error: e,
          stackTrace: stackTrace,
        );
        state = state.copyWith(
          isLoading: false,
          errorMessage: 'Failed to upload image.',
        );
      }
    }
  }
}

final profileViewModelProvider =
    StateNotifierProvider<ProfileViewModel, ProfileState>((ref) {
      final avatarRepository = ref.watch(avatarRepositoryProvider);
      return ProfileViewModel(avatarRepository, ref);
    });
