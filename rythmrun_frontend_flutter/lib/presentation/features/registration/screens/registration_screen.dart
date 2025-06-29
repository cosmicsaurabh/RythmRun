import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../../core/utils/validation_helper.dart';
import '../../../widgets/password_strength_indicator.dart';
import '../providers/registration_provider.dart';

class RegistrationScreen extends ConsumerStatefulWidget {
  const RegistrationScreen({super.key});

  @override
  ConsumerState<RegistrationScreen> createState() => _RegistrationScreenState();
}

class _RegistrationScreenState extends ConsumerState<RegistrationScreen> {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController(text: 'Aaa');
  final _lastNameController = TextEditingController(text: 'Bbb');
  final _emailController = TextEditingController(text: 'A@b.com');
  final _passwordController = TextEditingController(text: 'Aa1!Aa1!');
  final _confirmPasswordController = TextEditingController(text: 'Aa1!Aa1!');

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  void _handleSubmit() {
    // First check if form is valid
    //i triggers all vlidarors
    if (!_formKey.currentState!.validate()) {
      return;
    }

    // Then check terms acceptance
    final registrationState = ref.read(registrationProvider);
    if (!registrationState.acceptedTerms) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: CustomAppColors.statusWarning,
          content: Text(
            'Please accept the terms and conditions',
            style: TextStyle(color: CustomAppColors.white),
          ),
        ),
      );
      return;
    }

    // All validations passed, proceed with registration
    ref.read(registrationProvider.notifier).registerUser();
  }

  @override
  Widget build(BuildContext context) {
    final registrationState = ref.watch(registrationProvider);
    final registrationNotifier = ref.read(registrationProvider.notifier);

    // Listen for success and navigate to login
    ref.listen<bool>(registrationProvider.select((state) => state.isSuccess), (
      previous,
      next,
    ) {
      if (next) {
        _showSuccessDialog();
        registrationNotifier.resetForm();
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
                  'Create Account',
                  style: Theme.of(context).textTheme.displayMedium,
                ),
                const SizedBox(height: spacingSm),
                Text(
                  'Join RythmRun and start your fitness journey',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: CustomAppColors.secondaryText,
                  ),
                ),
                const SizedBox(height: spacing2xl),

                // First Name Field
                _buildTextField(
                  controller: _firstNameController,
                  label: 'First Name',
                  onChanged: registrationNotifier.updateFirstName,
                  validator:
                      (value) =>
                          ValidationHelper.validateName(value, 'First name'),
                ),
                const SizedBox(height: spacingLg),

                // Last Name Field
                _buildTextField(
                  controller: _lastNameController,
                  label: 'Last Name',
                  onChanged: registrationNotifier.updateLastName,
                  validator:
                      (value) =>
                          ValidationHelper.validateName(value, 'Last name'),
                ),
                const SizedBox(height: spacingLg),

                // Email Field
                _buildTextField(
                  controller: _emailController,
                  label: 'Email',
                  keyboardType: TextInputType.emailAddress,
                  onChanged: registrationNotifier.updateEmail,
                  validator: (value) => ValidationHelper.validateEmail(value),
                ),
                const SizedBox(height: spacingLg),

                // Password Field
                _buildTextField(
                  controller: _passwordController,
                  label: 'Password',
                  obscureText: registrationState.obscurePassword,
                  onChanged: registrationNotifier.updatePassword,
                  validator:
                      (value) => ValidationHelper.validatePassword(value),
                  suffixIcon: IconButton(
                    icon: Icon(
                      registrationState.obscurePassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    color: Theme.of(context).colorScheme.onSurface,
                    onPressed: registrationNotifier.togglePasswordVisibility,
                  ),
                ),
                const SizedBox(height: spacingSm),

                // Password Strength Indicator
                if (registrationState.password.isNotEmpty)
                  PasswordStrengthIndicator(
                    strength: registrationState.passwordStrength,
                  ),
                const SizedBox(height: spacingLg),

                // Confirm Password Field
                _buildTextField(
                  controller: _confirmPasswordController,
                  label: 'Confirm Password',
                  obscureText: registrationState.obscureConfirmPassword,
                  onChanged: registrationNotifier.updateConfirmPassword,
                  validator:
                      (value) => ValidationHelper.validateConfirmPassword(
                        _passwordController.text,
                        value,
                      ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      registrationState.obscureConfirmPassword
                          ? Icons.visibility_off
                          : Icons.visibility,
                    ),
                    color: Theme.of(context).colorScheme.onSurface,
                    onPressed:
                        registrationNotifier.toggleConfirmPasswordVisibility,
                  ),
                ),
                const SizedBox(height: spacingLg),

                // Terms and Conditions Checkbox
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Checkbox(
                      value: registrationState.acceptedTerms,
                      onChanged:
                          (value) => registrationNotifier.toggleAcceptedTerms(
                            value ?? false,
                          ),
                      activeColor: Theme.of(context).colorScheme.secondary,
                    ),
                    Expanded(
                      child: GestureDetector(
                        onTap:
                            () => registrationNotifier.toggleAcceptedTerms(
                              !registrationState.acceptedTerms,
                            ),
                        child: Padding(
                          padding: const EdgeInsets.only(top: spacingMd),
                          child: RichText(
                            text: TextSpan(
                              style: Theme.of(context).textTheme.bodyMedium,
                              children: [
                                const TextSpan(text: 'I agree to the '),
                                TextSpan(
                                  text: 'Terms of Service',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const TextSpan(text: ' and '),
                                TextSpan(
                                  text: 'Privacy Policy',
                                  style: TextStyle(
                                    color:
                                        Theme.of(context).colorScheme.secondary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: spacing2xl),

                // Error Message
                if (registrationState.errorMessage != null)
                  Container(
                    padding: const EdgeInsets.all(spacingMd),
                    decoration: BoxDecoration(
                      color: CustomAppColors.statusDanger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(radiusSm),
                      border: Border.all(color: CustomAppColors.statusDanger),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.error_outline,
                          color: CustomAppColors.statusDanger,
                          size: iconSizeSm,
                        ),
                        const SizedBox(width: spacingSm),
                        Expanded(
                          child: Text(
                            registrationState.errorMessage!,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(color: CustomAppColors.statusDanger),
                          ),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: spacingLg),

                // Register Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed:
                        registrationState.isLoading ? null : _handleSubmit,
                    child:
                        registrationState.isLoading
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
                            : const Text('Create Account'),
                  ),
                ),
                const SizedBox(height: spacingLg),

                // Login Link
                Center(
                  child: GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: RichText(
                      text: TextSpan(
                        style: Theme.of(context).textTheme.bodyMedium,
                        children: [
                          const TextSpan(text: 'Already have an account? '),
                          TextSpan(
                            text: 'Sign In',
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
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      validator: validator,
      decoration: InputDecoration(labelText: label, suffixIcon: suffixIcon),
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
                  'Account Created!',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: spacingSm),
                Text(
                  'Your account has been created successfully. You can now sign in with your credentials.',
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
                      Navigator.of(context).pop(); // close dialog
                    }
                    if (Navigator.canPop(context)) {
                      Navigator.of(context).pop(); // Go back to login
                    }
                  },
                  child: const Text('Continue to Sign In'),
                ),
              ),
            ],
          ),
    );
  }
}
