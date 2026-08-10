import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../const/custom_app_colors.dart';
import '../../../../theme/app_theme.dart';
import '../models/forgot_password_state.dart';
import '../providers/forgot_password_provider.dart';

class ForgotPasswordScreen extends ConsumerStatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  ConsumerState<ForgotPasswordScreen> createState() =>
      _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends ConsumerState<ForgotPasswordScreen> {
  final _emailController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(forgotPasswordProvider);
    final notifier = ref.read(forgotPasswordProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: CustomAppColors.border,
        leading: IconButton(
          icon: Icon(
            arrowBackIosIcon,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(spacingXl),
          child:
              state.isSent
                  ? _buildSentConfirmation(context)
                  : _buildForm(context, state, notifier),
        ),
      ),
    );
  }

  Widget _buildForm(
    BuildContext context,
    ForgotPasswordState state,
    ForgotPasswordNotifier notifier,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: spacingLg),
        Text(
          'Reset password',
          style: Theme.of(context).textTheme.displayMedium,
        ),
        const SizedBox(height: spacingSm),
        Text(
          "Enter your account email and we'll send you a link to choose a new password.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CustomAppColors.secondaryText,
          ),
        ),
        const SizedBox(height: spacing2xl),
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          enabled: !state.isLoading,
          onChanged: notifier.updateEmail,
          onSubmitted: (_) => notifier.submit(),
          decoration: InputDecoration(
            labelText: 'Email',
            prefixIcon: Icon(emailIcon),
            errorText: state.errorMessage,
          ),
        ),
        const SizedBox(height: spacingXl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: state.isLoading ? null : notifier.submit,
            child:
                state.isLoading
                    ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                    : const Text('Send reset link'),
          ),
        ),
      ],
    );
  }

  Widget _buildSentConfirmation(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: spacing2xl),
        Icon(emailIcon, size: 56, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: spacingLg),
        Text(
          'Check your inbox',
          style: Theme.of(context).textTheme.displaySmall,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: spacingSm),
        Text(
          "If an account exists for that email, we've sent a link to reset your password. The link expires in 30 minutes.",
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: CustomAppColors.secondaryText,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: spacing2xl),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Back to sign in'),
          ),
        ),
      ],
    );
  }
}
