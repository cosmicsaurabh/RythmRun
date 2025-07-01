import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../../core/models/app_settings.dart';
import '../../../providers/settings_provider.dart';
import '../providers/change_password_provider.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        elevation: 0,
        backgroundColor: Colors.transparent,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(spacingLg),
        child: Column(
          children: [
            // Theme Section
            _buildSection(context, 'Appearance', Icons.palette, [
              _buildTile(
                context,
                'Theme',
                _getThemeModeText(settings.themeMode),
                Icons.brightness_6,
                () => _showThemeSelector(context, ref),
              ),
            ]),
            const SizedBox(height: spacingLg),

            // Units Section
            _buildSection(context, 'Units', Icons.straighten, [
              _buildTile(
                context,
                'Measurement System',
                _getMeasurementUnitText(settings.measurementUnit),
                Icons.speed,
                () => _showUnitsSelector(context, ref),
              ),
            ]),
            // const SizedBox(height: spacingLg),

            // // Notifications Section
            // _buildSection(context, 'Notifications', Icons.notifications, [
            //   _buildTile(
            //     context,
            //     'Push Notifications',
            //     'Receive workout reminders and updates',
            //     Icons.notifications_active,
            //     () => _showNotificationsSelector(context, ref),
            //   ),
            // ]),
            // const SizedBox(height: spacingLg),

            // Privacy Section
            // _buildSection(context, 'Privacy & Data', Icons.security, [
            //   _buildTile(
            //     context,
            //     'Analytics',
            //     'Help improve the app with usage data',
            //     Icons.analytics,
            //     () => _showAnalyticsSelector(context, ref),
            //   ),
            //   _buildTile(
            //     context,
            //     'Auto Backup',
            //     'Automatically backup your data',
            //     Icons.backup,
            //     () => _showAutoBackupSelector(context, ref),
            //   ),
            // ]),
            const SizedBox(height: spacingLg),

            // Account Section
            _buildSection(context, 'Account', Icons.person, [
              _buildTile(
                context,
                'Change Password',
                'Update your account password',
                Icons.lock,
                () => _showChangePasswordDialog(context, ref),
              ),
            ]),
            const SizedBox(height: spacingLg),

            // Danger Zone
            _buildSection(
              context,
              'Danger Zone',
              Icons.warning,
              [
                _buildTile(
                  context,
                  'Delete Account',
                  'Permanently delete your account',
                  Icons.delete_forever,
                  () => _showDeleteAccountDialog(context, ref),
                  isDestructive: true,
                ),
              ],
              iconColor: CustomAppColors.statusError,
            ),
            const SizedBox(height: spacing2xl),

            // Reset Settings
            _buildResetButton(context, ref),
          ],
        ),
      ),
    );
  }

  Widget _buildSection(
    BuildContext context,
    String title,
    IconData icon,
    List<Widget> children, {
    Color? iconColor,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(spacingLg),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(spacingSm),
                  decoration: BoxDecoration(
                    color: (iconColor ?? CustomAppColors.primary).withOpacity(
                      0.1,
                    ),
                    borderRadius: BorderRadius.circular(radiusSm),
                  ),
                  child: Icon(
                    icon,
                    color: iconColor ?? CustomAppColors.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: spacingSm),
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    VoidCallback onTap, {
    bool isDestructive = false,
  }) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: spacingLg,
          vertical: spacingSm,
        ),
        child: Row(
          children: [
            Icon(
              icon,
              color:
                  isDestructive
                      ? CustomAppColors.statusError
                      : Theme.of(context).iconTheme.color,
            ),
            const SizedBox(width: spacingLg),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: isDestructive ? CustomAppColors.statusError : null,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(
                        context,
                      ).textTheme.bodySmall?.color?.withOpacity(0.6),
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: Theme.of(context).iconTheme.color?.withOpacity(0.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResetButton(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: () => _showResetDialog(context, ref),
        icon: const Icon(Icons.refresh),
        label: const Text('Reset All Settings'),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: spacingLg),
          side: BorderSide(color: CustomAppColors.statusWarning),
          foregroundColor: CustomAppColors.statusWarning,
        ),
      ),
    );
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'System';
    }
  }

  String _getMeasurementUnitText(MeasurementUnit unit) {
    switch (unit) {
      case MeasurementUnit.metric:
        return 'Metric (km, kg)';
      case MeasurementUnit.imperial:
        return 'Imperial (mi, lbs)';
    }
  }

  void _showThemeSelector(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
      ),
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Choose Theme',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: spacingLg),
                ...AppThemeMode.values.map((theme) {
                  final current = ref.watch(settingsProvider).themeMode;
                  return ListTile(
                    leading: Icon(_getThemeIcon(theme)),
                    title: Text(_getThemeModeText(theme)),
                    trailing:
                        current == theme
                            ? Icon(Icons.check, color: CustomAppColors.primary)
                            : null,
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .updateThemeMode(theme);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
    );
  }

  void _showUnitsSelector(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(radiusLg)),
      ),
      builder:
          (context) => Container(
            padding: const EdgeInsets.all(spacingLg),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Measurement Units',
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
                const SizedBox(height: spacingLg),
                ...MeasurementUnit.values.map((unit) {
                  final current = ref.watch(settingsProvider).measurementUnit;
                  return ListTile(
                    leading: Icon(_getUnitIcon(unit)),
                    title: Text(_getMeasurementUnitText(unit)),
                    trailing:
                        current == unit
                            ? Icon(Icons.check, color: CustomAppColors.primary)
                            : null,
                    onTap: () {
                      ref
                          .read(settingsProvider.notifier)
                          .updateMeasurementUnit(unit);
                      Navigator.pop(context);
                    },
                  );
                }),
              ],
            ),
          ),
    );
  }

  void _showChangePasswordDialog(BuildContext context, WidgetRef ref) {
    final currentPasswordController = TextEditingController();
    final newPasswordController = TextEditingController();

    // Reset provider state when dialog opens
    ref.read(changePasswordProvider.notifier).reset();

    showDialog(
      context: context,
      barrierDismissible: false, // Prevent dismissing during loading
      builder:
          (context) => Consumer(
            builder: (context, ref, child) {
              final state = ref.watch(changePasswordProvider);

              return AlertDialog(
                title: const Text('Change Password'),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Error display
                    if (state.errorMessage != null)
                      Container(
                        padding: const EdgeInsets.all(spacingSm),
                        margin: const EdgeInsets.only(bottom: spacingLg),
                        decoration: BoxDecoration(
                          color: CustomAppColors.statusError.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(radiusSm),
                          border: Border.all(
                            color: CustomAppColors.statusError,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.error_outline,
                              color: CustomAppColors.statusError,
                            ),
                            const SizedBox(width: spacingSm),
                            Expanded(
                              child: Text(
                                state.errorMessage!,
                                style: TextStyle(
                                  color: CustomAppColors.statusError,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                    // Current Password field
                    TextField(
                      controller: currentPasswordController,
                      decoration: InputDecoration(
                        labelText: 'Current Password',
                        prefixIcon: Icon(
                          Icons.lock_outline,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      obscureText: true,
                      enabled: !state.isLoading,
                    ),
                    const SizedBox(height: spacingLg),

                    // New Password field
                    TextField(
                      controller: newPasswordController,
                      decoration: InputDecoration(
                        labelText: 'New Password',
                        prefixIcon: Icon(
                          Icons.lock,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                      ),
                      obscureText: true,
                      enabled: !state.isLoading,
                    ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed:
                        state.isLoading
                            ? null
                            : () {
                              ref.read(changePasswordProvider.notifier).reset();
                              Navigator.pop(context);
                            },
                    child: const Text('Cancel'),
                  ),
                  ElevatedButton(
                    onPressed:
                        state.isLoading
                            ? null
                            : () async {
                              final currentPassword =
                                  currentPasswordController.text;
                              final newPassword = newPasswordController.text;

                              final successMessage = await ref
                                  .read(changePasswordProvider.notifier)
                                  .changePassword(currentPassword, newPassword);

                              if (successMessage != null) {
                                // Success - close dialog and show success snackbar
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(successMessage),
                                    backgroundColor:
                                        CustomAppColors.statusSuccess,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                                ref
                                    .read(changePasswordProvider.notifier)
                                    .reset();
                              }
                              // Errors are displayed in the dialog automatically
                            },
                    child:
                        state.isLoading
                            ? SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                valueColor: AlwaysStoppedAnimation<Color>(
                                  Theme.of(context).colorScheme.onPrimary,
                                ),
                              ),
                            )
                            : const Text('Change'),
                  ),
                ],
              );
            },
          ),
    );
  }

  void _showDeleteAccountDialog(BuildContext context, WidgetRef ref) {
    final confirmationController = TextEditingController();

    showDialog(
      context: context,
      builder:
          (context) => StatefulBuilder(
            builder:
                (context, setState) => AlertDialog(
                  title: Row(
                    children: [
                      Icon(Icons.warning, color: CustomAppColors.statusError),
                      const SizedBox(width: spacingSm),
                      const Text('Delete Account'),
                    ],
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'This action cannot be undone. All your data will be permanently deleted.',
                        style: TextStyle(color: CustomAppColors.statusError),
                      ),
                      const SizedBox(height: spacingLg),
                      const Text('Type "DELETE" to confirm:'),
                      const SizedBox(height: spacingSm),
                      TextField(
                        controller: confirmationController,
                        decoration: const InputDecoration(
                          hintText: 'DELETE',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ],
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed:
                          confirmationController.text == 'DELETE'
                              ? () {
                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Text(
                                      'Account deletion feature coming soon!',
                                    ),
                                    backgroundColor:
                                        CustomAppColors.statusError,
                                    behavior: SnackBarBehavior.floating,
                                  ),
                                );
                              }
                              : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: CustomAppColors.statusError,
                      ),
                      child: const Text('Delete Account'),
                    ),
                  ],
                ),
          ),
    );
  }

  void _showResetDialog(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Reset Settings'),
            content: const Text(
              'Are you sure you want to reset all settings to default values?',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  ref.read(settingsProvider.notifier).resetSettings();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Text('Settings reset to default'),
                      backgroundColor: CustomAppColors.statusSuccess,
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: CustomAppColors.statusWarning,
                ),
                child: const Text('Reset'),
              ),
            ],
          ),
    );
  }

  IconData _getThemeIcon(AppThemeMode theme) {
    switch (theme) {
      case AppThemeMode.light:
        return Icons.light_mode;
      case AppThemeMode.dark:
        return Icons.dark_mode;
      case AppThemeMode.system:
        return Icons.brightness_auto;
    }
  }

  IconData _getUnitIcon(MeasurementUnit unit) {
    switch (unit) {
      case MeasurementUnit.metric:
        return Icons.public;
      case MeasurementUnit.imperial:
        return Icons.flag;
    }
  }
}
