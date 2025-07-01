import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../providers/session_provider.dart';
import '../../../widgets/profile_stat_card.dart';
import '../../../widgets/profile_menu_item.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sessionData = ref.watch(sessionProvider);
    final user = sessionData.user;

    return Scaffold(
      body: SafeArea(
        child:
            user == null
                ? const Center(child: CircularProgressIndicator())
                : SingleChildScrollView(
                  padding: const EdgeInsets.all(spacingLg),
                  child: Column(
                    children: [
                      // Profile Header
                      _buildProfileHeader(context, user),
                      const SizedBox(height: spacing2xl),

                      // Statistics Cards
                      _buildStatsSection(context),
                      const SizedBox(height: spacing2xl),

                      // Menu Section
                      _buildMenuSection(context, ref),
                      const SizedBox(height: spacingLg),

                      // Logout Button
                      _buildLogoutSection(context, ref),
                    ],
                  ),
                ),
      ),
    );
  }

  Widget _buildProfileHeader(BuildContext context, user) {
    return Container(
      padding: const EdgeInsets.all(spacingXl),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Theme.of(context).colorScheme.primary,
            Theme.of(context).colorScheme.secondary,
          ],
        ),
        borderRadius: BorderRadius.circular(radiusXl),
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          // Profile Picture
          Container(
            width: 100,
            height: 100,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: CustomAppColors.white, width: 4),
              color: CustomAppColors.white.withOpacity(0.2),
            ),
            child: Icon(Icons.person, size: 50, color: CustomAppColors.white),
          ),
          const SizedBox(height: spacingLg),

          // User Name
          Text(
            '${user.firstName} ${user.lastName}',
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
              color: CustomAppColors.white,
              fontWeight: FontWeight.bold,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: spacingSm),

          // Email
          Text(
            user.email,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: CustomAppColors.white.withOpacity(0.9),
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: spacingSm),

          // Member Since
          Text(
            'Member since ${_formatDate(user.createdAt)}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: CustomAppColors.white.withOpacity(0.8),
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Your Stats',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: spacingLg),
        Row(
          children: [
            Expanded(
              child: ProfileStatCard(
                title: 'Activities',
                value: '12',
                icon: Icons.directions_run,
                color: CustomAppColors.statusSuccess,
              ),
            ),
            const SizedBox(width: spacingLg),
            Expanded(
              child: ProfileStatCard(
                title: 'Distance',
                value: '45.2 km',
                icon: Icons.route,
                color: CustomAppColors.primary,
              ),
            ),
          ],
        ),
        const SizedBox(height: spacingLg),
        Row(
          children: [
            Expanded(
              child: ProfileStatCard(
                title: 'Time',
                value: '8h 23m',
                icon: Icons.timer,
                color: CustomAppColors.secondary,
              ),
            ),
            const SizedBox(width: spacingLg),
            Expanded(
              child: ProfileStatCard(
                title: 'Friends',
                value: '24',
                icon: Icons.people,
                color: CustomAppColors.accent,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildMenuSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Settings',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: spacingLg),
        Container(
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
              ProfileMenuItem(
                icon: Icons.person_outline,
                title: 'Edit Profile',
                subtitle: 'Update your personal information',
                onTap: () => _editProfile(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: Icons.notifications,
                title: 'Notifications',
                subtitle: 'Manage your notification preferences',
                onTap: () => _openNotifications(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: Icons.security,
                title: 'Privacy & Security',
                subtitle: 'Control your privacy settings',
                onTap: () => _openPrivacySettings(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: Icons.help_outline,
                title: 'Help & Support',
                subtitle: 'Get help and contact support',
                onTap: () => _openHelp(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: Icons.info_outline,
                title: 'About',
                subtitle: 'App version and information',
                onTap: () => _showAbout(context),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLogoutSection(BuildContext context, WidgetRef ref) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        onPressed: () => _logout(context, ref),
        icon: const Icon(Icons.logout),
        label: const Text('Logout'),
        style: ElevatedButton.styleFrom(
          backgroundColor: CustomAppColors.statusError,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: spacingLg),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusLg),
          ),
        ),
      ),
    );
  }

  String _formatDate(DateTime? date) {
    if (date == null) {
      return '-';
    }
    final months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${months[date.month - 1]} ${date.year}';
  }

  void _editProfile(BuildContext context) {
    // TODO: Navigate to edit profile screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit Profile - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
      ),
    );
  }

  void _openNotifications(BuildContext context) {
    // TODO: Navigate to notifications settings
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifications Settings - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
      ),
    );
  }

  void _openPrivacySettings(BuildContext context) {
    // TODO: Navigate to privacy settings
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Privacy Settings - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
      ),
    );
  }

  void _openHelp(BuildContext context) {
    // TODO: Navigate to help screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Help & Support - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'RythmRun',
      applicationVersion: '1.0.0',
      applicationIcon: const Icon(Icons.fitness_center, size: 40),
      children: [
        const Text(
          'Your fitness companion for tracking workouts and connecting with friends.',
        ),
      ],
      barrierDismissible: true,
      barrierColor: CustomAppColors.black.withOpacity(0.5),
    );
  }

  void _logout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder:
          (context) => AlertDialog(
            title: const Text('Logout'),
            content: const Text('Are you sure you want to logout?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  ref.read(sessionProvider.notifier).logout();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: CustomAppColors.statusError,
                  foregroundColor: CustomAppColors.white,
                ),
                child: const Text('Logout'),
              ),
            ],
          ),
    );
  }
}
