import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../../core/utils/validation_helper.dart';
import '../../../widgets/error_display_widget.dart';
import '../providers/login_provider.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    // First check if form is valid
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // All validations passed, proceed with login
    ref.read(loginProvider.notifier).loginUser();
  }

  @override
  Widget build(BuildContext context) {
    final loginState = ref.watch(loginProvider);
    final loginNotifier = ref.read(loginProvider.notifier);

    // Listen for success and navigate
    ref.listen<bool>(loginProvider.select((state) => state.isSuccess), (
      previous,
      next,
    ) {
      if (next) {
        _showSuccessDialog();
        loginNotifier.resetForm();
      }
    });

    return Scaffold(
      appBar: AppBar(
        elevation: 0,
        backgroundColor: CustomAppColors.border,
        leading: IconButton(
          icon: Icon(
            Icons.arrow_back_ios,
            color: Theme.of(context).colorScheme.onSurface,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(spacingXl),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: spacingLg),

                // Header
                Text(
                  'Welcome Back',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: spacingSm),
                Text(
                  'Sign in to continue your fitness journey',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CustomAppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: spacing2xl),

                // Email Field
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: loginNotifier.updateEmail,
                  validator: (value) => ValidationHelper.validateEmail(value),
                  prefixIcon: Icons.email_outlined,
                ),
                const SizedBox(height: spacingLg),

                // Password Field
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  obscureText: loginState.obscurePassword,
                  onChanged: loginNotifier.updatePassword,
                  validator: (value) {
                    if (value == null || value.isEmpty) {
                      return 'Password is required';
                    }
                    return null;
                  },
                  prefixIcon: Icons.lock_outline,
                  suffixIcon: IconButton(
                    icon: Icon(
                      loginState.obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                    onPressed: loginNotifier.togglePasswordVisibility,
                  ),
                ),
                const SizedBox(height: spacingMd),

                // Remember Me and Forgot Password Row
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Remember Me Checkbox
                    Row(
                      children: [
                        Checkbox(
                          value: loginState.rememberMe,
                          onChanged:
                              (value) => loginNotifier.toggleRememberMe(
                                value ?? false,
                              ),
                          activeColor: Theme.of(context).colorScheme.secondary,
                        ),
                        GestureDetector(
                          onTap:
                              () => loginNotifier.toggleRememberMe(
                                !loginState.rememberMe,
                              ),
                          child: Text(
                            'Remember me',
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        ),
                      ],
                    ),

                    // Forgot Password Link
                    GestureDetector(
                      onTap: () {
                        // TODO: Navigate to forgot password screen
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Forgot password feature coming soon!',
                            ),
                          ),
                        );
                      },
                      child: Text(
                        'Forgot Password?',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: Theme.of(context).colorScheme.secondary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: spacing2xl),

                // Error Message
                if (loginState.errorMessage != null)
                  ErrorDisplayWidget(
                    errorMessage: loginState.errorMessage!,
                    onRetry: () {
                      // Clear the error first
                      ref.read(loginProvider.notifier).clearError();
                      // Then retry the login
                      _handleSubmit();
                    },
                    isRetryEnabled: !loginState.isLoading,
                  ),
                const SizedBox(height: spacingLg),

                // Login Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: loginState.isLoading ? null : _handleSubmit,
                    child:
                        loginState.isLoading
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.secondary,
                                ),
                              ),
                            )
                            : const Text('Sign In'),
                  ),
                ),
                const SizedBox(height: spacingLg),

                // Register Link
                Center(
                  child: GestureDetector(
                    onTap: () {
                      // Navigate to registration screen
                      try {
                        Navigator.of(
                          context,
                        ).pushReplacementNamed('/registration');
                      } catch (e) {
                        print(e);
                      }
                    },
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: "Don't have an account? "),
                          TextSpan(
                            text: 'Sign Up',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.secondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required Function(String) onChanged,
    required String? Function(String?) validator,
    TextInputType? keyboardType,
    bool obscureText = false,
    Widget? suffixIcon,
    IconData? prefixIcon,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon:
            prefixIcon != null
                ? Icon(
                  prefixIcon,
                  color: Theme.of(
                    context,
                  ).colorScheme.onSurface.withOpacity(0.7),
                )
                : null,
        suffixIcon: suffixIcon,
      ),
      style: Theme.of(context).textTheme.bodyMedium,
    );
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusLg),
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(spacingLg),
                  decoration: BoxDecoration(
                    color: CustomAppColors.statusSuccess.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.check_circle,
                    color: CustomAppColors.statusSuccess,
                    size: 48,
                  ),
                ),
                const SizedBox(height: spacingLg),
                Text(
                  'Welcome Back!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: spacingSm),
                Text(
                  'You have successfully signed in to RythmRun.',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CustomAppColors.secondaryText,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    if (Navigator.canPop(context)) {
                      Navigator.of(context).pop(); // Close dialog
                    }
                    // Navigation will happen automatically via session provider
                  },
                  child: const Text('Continue'),
                ),
              ),
            ],
          ),
    );
  }
}
