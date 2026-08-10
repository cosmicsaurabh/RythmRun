import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/di/injection_container.dart';
import '../models/forgot_password_state.dart';
import 'forgot_password_notifier.dart';

export 'forgot_password_notifier.dart' show ForgotPasswordNotifier;

final forgotPasswordProvider = StateNotifierProvider.autoDispose<
  ForgotPasswordNotifier,
  ForgotPasswordState
>((ref) {
  return ForgotPasswordNotifier(ref.watch(requestPasswordResetUsecaseProvider));
});
