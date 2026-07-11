import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/di/injection_container.dart';
import '../../../common/providers/session_provider.dart';
import '../models/login_state.dart';
import 'login_notifier.dart';

export 'login_notifier.dart' show LoginNotifier;

final loginProvider = StateNotifierProvider<LoginNotifier, LoginState>((ref) {
  final loginUserUsecase = ref.watch(loginUserUsecaseProvider);
  return LoginNotifier(
    loginUserUsecase,
    beginAuthentication:
        () => ref.read(sessionProvider.notifier).beginAuthenticationAttempt(),
    completeAuthentication:
        (user, admission) => ref
            .read(sessionProvider.notifier)
            .completeAuthenticationAttempt(user, admission),
  );
});
