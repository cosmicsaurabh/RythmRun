import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/providers/profile_view_model.dart';

void main() {
  test('ProfileState distinguishes omitted error from explicit null', () {
    final original = ProfileState(errorMessage: 'old error');

    expect(original.copyWith().errorMessage, 'old error');
    expect(original.copyWith(errorMessage: null).errorMessage, isNull);
  });

  test('successful upload retry clears the previous profile error', () async {
    final repository = _FakeAvatarRepository(failuresRemaining: 1);
    final updates = <String>[];
    final notifier = ProfileViewModel(
      repository,
      pickImage: () async => XFile('/tmp/profile-test.jpg'),
      currentUserId: () => '7',
      updateProfilePicture: (owner, path, type) async {
        updates.add('$owner:$path:$type');
      },
    );
    addTearDown(notifier.dispose);

    await notifier.pickAndUploadImage();
    expect(notifier.state.errorMessage, isNotNull);

    await notifier.pickAndUploadImage();
    expect(notifier.state.errorMessage, isNull);
    expect(updates, <String>['7:avatars/7/current.jpg:image/jpeg']);
  });

  test(
    'an upload started by A cannot update B after an account change',
    () async {
      final uploadCompleter = Completer<void>();
      final repository = _FakeAvatarRepository(
        uploadCompleter: uploadCompleter,
      );
      var currentUserId = '7';
      final updates = <String>[];
      final notifier = ProfileViewModel(
        repository,
        pickImage: () async => XFile('/tmp/profile-test.jpg'),
        currentUserId: () => currentUserId,
        updateProfilePicture: (owner, path, type) async {
          updates.add('$owner:$path:$type');
        },
      );
      addTearDown(notifier.dispose);

      final pendingUpload = notifier.pickAndUploadImage();
      await Future<void>.delayed(Duration.zero);
      currentUserId = '8';
      uploadCompleter.complete();
      await pendingUpload;

      expect(updates, isEmpty);
    },
  );
}

class _FakeAvatarRepository implements AvatarRepository {
  int failuresRemaining;
  final Completer<void>? uploadCompleter;

  _FakeAvatarRepository({this.failuresRemaining = 0, this.uploadCompleter});

  @override
  Future<AvatarUploadResult> uploadAvatar(XFile image) async {
    await uploadCompleter?.future;
    if (failuresRemaining > 0) {
      failuresRemaining -= 1;
      throw StateError('simulated upload failure');
    }
    return const AvatarUploadResult(
      key: 'avatars/7/current.jpg',
      mimeType: 'image/jpeg',
    );
  }
}
