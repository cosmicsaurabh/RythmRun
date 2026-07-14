import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:rythmrun_frontend_flutter/core/network/auth_failures.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';
import 'package:rythmrun_frontend_flutter/domain/entities/user_entity.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/auth_repository.dart';
import 'package:rythmrun_frontend_flutter/domain/repositories/avatar_repository.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/providers/profile_view_model.dart';

/// IP-2.4 profile name editing: the view model sends the trimmed edit through
/// the repository, commits only a same-owner server-confirmed result, and
/// surfaces the typed offline denial without reaching the network.
void main() {
  const serverUser = UserEntity(
    id: '7',
    firstName: 'Renamed',
    lastName: 'Runner',
    email: 'a@example.com',
  );

  test('a successful edit commits the server-confirmed user once', () async {
    final authRepository = _FakeAuthRepository(result: serverUser);
    final commits = <(String, UserEntity)>[];
    final viewModel = ProfileViewModel(
      _FakeAvatarRepository(),
      authRepository: authRepository,
      pickImage: () async => null,
      currentUserId: () => '7',
      updateProfilePicture: (_, _, _) async {},
      commitProfileUpdate: (ownerUserId, updatedUser) async {
        commits.add((ownerUserId, updatedUser));
      },
    );
    addTearDown(viewModel.dispose);

    final didUpdate = await viewModel.updateProfileName(
      firstName: '  Renamed ',
      lastName: ' Runner ',
    );

    expect(didUpdate, isTrue);
    expect(authRepository.requests, [('Renamed', 'Runner')]);
    expect(commits, [('7', serverUser)]);
    expect(viewModel.state.isLoading, isFalse);
    expect(viewModel.state.errorMessage, isNull);
  });

  test('empty names are rejected before any request', () async {
    final authRepository = _FakeAuthRepository(result: serverUser);
    final viewModel = ProfileViewModel(
      _FakeAvatarRepository(),
      authRepository: authRepository,
      pickImage: () async => null,
      currentUserId: () => '7',
      updateProfilePicture: (_, _, _) async {},
      commitProfileUpdate: (_, _) async {},
    );
    addTearDown(viewModel.dispose);

    final didUpdate = await viewModel.updateProfileName(
      firstName: '   ',
      lastName: 'Runner',
    );

    expect(didUpdate, isFalse);
    expect(authRepository.requests, isEmpty);
    expect(
      viewModel.state.errorMessage,
      'First and last name cannot be empty.',
    );
  });

  test('the typed offline denial surfaces its safe message', () async {
    final authRepository = _FakeAuthRepository(
      error: const AuthSessionUnavailable(
        AuthSessionUnavailableReason.offlineMode,
      ),
    );
    final commits = <(String, UserEntity)>[];
    final viewModel = ProfileViewModel(
      _FakeAvatarRepository(),
      authRepository: authRepository,
      pickImage: () async => null,
      currentUserId: () => '7',
      updateProfilePicture: (_, _, _) async {},
      commitProfileUpdate: (ownerUserId, updatedUser) async {
        commits.add((ownerUserId, updatedUser));
      },
    );
    addTearDown(viewModel.dispose);

    final didUpdate = await viewModel.updateProfileName(
      firstName: 'Renamed',
      lastName: 'Runner',
    );

    expect(didUpdate, isFalse);
    expect(commits, isEmpty);
    expect(
      viewModel.state.errorMessage,
      'This action needs an internet connection.',
    );
    expect(viewModel.state.isLoading, isFalse);
  });

  test('an owner change during the request discards the result', () async {
    var activeUserId = '7';
    final authRepository = _FakeAuthRepository(
      result: serverUser,
      onRequest: () => activeUserId = '8',
    );
    final commits = <(String, UserEntity)>[];
    final viewModel = ProfileViewModel(
      _FakeAvatarRepository(),
      authRepository: authRepository,
      pickImage: () async => null,
      currentUserId: () => activeUserId,
      updateProfilePicture: (_, _, _) async {},
      commitProfileUpdate: (ownerUserId, updatedUser) async {
        commits.add((ownerUserId, updatedUser));
      },
    );
    addTearDown(viewModel.dispose);

    final didUpdate = await viewModel.updateProfileName(
      firstName: 'Renamed',
      lastName: 'Runner',
    );

    expect(didUpdate, isFalse);
    expect(commits, isEmpty);
  });

  test('a suspended user scope pauses profile edits', () async {
    final authRepository = _FakeAuthRepository(result: serverUser);
    final viewModel = ProfileViewModel(
      _FakeAvatarRepository(),
      authRepository: authRepository,
      pickImage: () async => null,
      currentUserId: () => '7',
      updateProfilePicture: (_, _, _) async {},
      commitProfileUpdate: (_, _) async {},
      operationGate: UserScopeOperationGate(),
    );
    addTearDown(viewModel.dispose);

    final didUpdate = await viewModel.updateProfileName(
      firstName: 'Renamed',
      lastName: 'Runner',
    );

    expect(didUpdate, isFalse);
    expect(authRepository.requests, isEmpty);
    expect(
      viewModel.state.errorMessage,
      'Profile updates are paused during account cleanup.',
    );
  });
}

class _FakeAvatarRepository implements AvatarRepository {
  @override
  Future<AvatarUploadResult> uploadAvatar(XFile image) {
    throw UnimplementedError();
  }
}

class _FakeAuthRepository implements AuthRepository {
  _FakeAuthRepository({this.result, this.error, this.onRequest});

  final UserEntity? result;
  final Object? error;
  final void Function()? onRequest;
  final List<(String, String)> requests = <(String, String)>[];

  @override
  Future<UserEntity> updateProfile({
    required String firstName,
    required String lastName,
  }) async {
    requests.add((firstName, lastName));
    onRequest?.call();
    final failure = error;
    if (failure != null) throw failure;
    return result!;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
