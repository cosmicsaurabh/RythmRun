import 'dart:developer';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/const/custom_app_colors.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/providers/session_provider.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/profile_menu_item.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/profile_stat_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/common/widgets/quick_action_card.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/settings/screens/settings_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/providers/tracking_history_provider.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';
import 'package:url_launcher/url_launcher.dart';

class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen>
    with TickerProviderStateMixin {
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.2, 1.0, curve: Curves.elasticOut),
      ),
    );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final sessionData = ref.watch(sessionProvider);
    final user = sessionData.user;

    return Scaffold(
      body:
          user == null
              ? const Center(child: CupertinoActivityIndicator())
              : AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return SafeArea(
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: SlideTransition(
                        position: _slideAnimation,
                        child: CustomScrollView(
                          physics: const BouncingScrollPhysics(),
                          slivers: [
                            // Custom App Bar
                            SliverAppBar(
                              expandedHeight: 284,
                              floating: false,
                              pinned: false,
                              backgroundColor: Colors.transparent,
                              elevation: 0,
                              flexibleSpace: FlexibleSpaceBar(
                                background: _buildProfileHeader(context, user),
                              ),
                            ),

                            // Content
                            SliverPadding(
                              padding: const EdgeInsets.fromLTRB(
                                spacingLg,
                                0,
                                spacingLg,
                                spacingLg,
                              ),
                              sliver: SliverList(
                                delegate: SliverChildListDelegate([
                                  const SizedBox(height: spacingLg),

                                  // Achievement Banner
                                  _buildAchievementBanner(context),
                                  const SizedBox(height: spacing2xl),

                                  // Statistics Cards
                                  _buildStatsSection(context),
                                  const SizedBox(height: spacing2xl),

                                  // Quick Actions
                                  _buildQuickActions(context),
                                  const SizedBox(height: spacing2xl),

                                  // Menu Section
                                  _buildMenuSection(context, ref),
                                  const SizedBox(height: spacingLg),

                                  // Logout Button
                                  _buildLogoutSection(context, ref),
                                  const SizedBox(height: spacing2xl),
                                ]),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
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
            CustomAppColors.colorA,
            CustomAppColors.colorB,
            CustomAppColors.colorC.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(radiusXl * 2),
          bottomRight: Radius.circular(radiusXl * 2),
        ),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Profile Picture with Glow Effect
          Hero(
            tag: 'profile-avatar',
            child: Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: CustomAppColors.white, width: 4),
                boxShadow: [
                  BoxShadow(
                    color: CustomAppColors.white.withOpacity(0.3),
                    blurRadius: 20,
                    spreadRadius: 5,
                  ),
                ],
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    CustomAppColors.white.withOpacity(0.3),
                    CustomAppColors.white.withOpacity(0.1),
                  ],
                ),
              ),
              child: const Icon(
                personIcon,
                size: 60,
                color: CustomAppColors.white,
              ),
            ),
          ),
          const SizedBox(height: spacingLg),

          // User Name with Shadow
          Text(
            (user.firstName == null && user.lastName == null) ||
                    (user.firstName.trim().isEmpty &&
                        user.lastName.trim().isEmpty)
                ? 'User'
                : '${user.firstName} ${user.lastName}',
            style: Theme.of(context).textTheme.headlineLarge?.copyWith(
              color: CustomAppColors.white,
              fontWeight: FontWeight.bold,
              shadows: [
                Shadow(
                  color: CustomAppColors.black.withOpacity(0.26),
                  offset: Offset(0, 2),
                  blurRadius: 4,
                ),
              ],
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: spacingSm),

          // Email with Icon
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(emailIcon, color: CustomAppColors.white, size: 16),
              const SizedBox(width: spacingSm),
              Text(
                user.email,
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: CustomAppColors.white.withOpacity(0.9),
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
          const SizedBox(height: spacingSm),

          // Member Since with Badge
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: spacingLg,
              vertical: spacingSm,
            ),
            decoration: BoxDecoration(
              color: CustomAppColors.white.withOpacity(0.2),
              borderRadius: BorderRadius.circular(radiusXl),
              border: Border.all(
                color: CustomAppColors.white.withOpacity(0.3),
                width: 1,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  calendarTodayIcon,
                  color: CustomAppColors.white,
                  size: 14,
                ),
                const SizedBox(width: spacingSm),
                Text(
                  'Member since ${_formatDate(user.createdAt)}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: CustomAppColors.white.withOpacity(0.9),
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAchievementBanner(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(spacingLg),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            CustomAppColors.statusSuccess.withOpacity(0.1),
            CustomAppColors.statusInfo.withOpacity(0.1),
          ],
        ),
        borderRadius: BorderRadius.circular(radiusLg),
        border: Border.all(
          color: CustomAppColors.statusSuccess.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(spacingSm),
            decoration: BoxDecoration(
              color: CustomAppColors.statusSuccess.withOpacity(0.2),
              borderRadius: BorderRadius.circular(radiusSm),
            ),
            child: const Icon(
              emojiEventsIcon,
              color: CustomAppColors.statusSuccess,
              size: 24,
            ),
          ),
          const SizedBox(width: spacingLg),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Weekly Goal Achieved! 🎉',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: CustomAppColors.statusSuccess,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'You\'ve completed 5 workouts this week',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(
                      context,
                    ).textTheme.bodySmall?.color?.withOpacity(0.7),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsSection(BuildContext context) {
    final state = ref.watch(trackingHistoryProvider);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [CustomAppColors.colorA, CustomAppColors.colorB],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: spacingSm),
            Text(
              'Your Stats',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: spacingLg),
        GridView.count(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          crossAxisCount: 2,
          crossAxisSpacing: spacingLg,
          mainAxisSpacing: spacingLg,
          childAspectRatio: 1.27,
          children: [
            ProfileStatCard(
              title: 'Activities',
              value: '${state.overallStatistics?.totalWorkouts}',
              icon: runningIcon,
              color: CustomAppColors.colorB,
            ),
            ProfileStatCard(
              title: 'Distance',
              value: '${state.overallStatistics?.formattedTotalDistance}',
              icon: distanceIcon,
              color: CustomAppColors.distance,
            ),
            ProfileStatCard(
              title: 'Time',
              value: '${state.overallStatistics?.formattedTotalDuration}',
              icon: timeIcon,
              color: CustomAppColors.time,
            ),
            ProfileStatCard(
              title: 'Friends',
              value: '-',
              icon: friendsIcon,
              color: CustomAppColors.colorA,
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [CustomAppColors.colorC, CustomAppColors.colorA],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: spacingSm),
            Text(
              'Quick Actions',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: spacingLg),
        Row(
          children: [
            Expanded(
              child: buildQuickActionCard(
                context: context,
                title: 'Share Profile',
                icon: shareIcon,
                color: CustomAppColors.statusInfo,
                onTap: () => _shareProfile(context),
              ),
            ),
            const SizedBox(width: spacingLg),
            Expanded(
              child: buildQuickActionCard(
                context: context,
                title: 'Export Data',
                icon: downloadIcon,
                color: CustomAppColors.colorB,
                onTap: () => _exportData(context),
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
        Row(
          children: [
            Container(
              width: 4,
              height: 24,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [CustomAppColors.colorB, CustomAppColors.colorC],
                ),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: spacingSm),
            Text(
              'Settings',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        const SizedBox(height: spacingLg),
        Container(
          decoration: BoxDecoration(
            color: Theme.of(context).cardColor,
            borderRadius: BorderRadius.circular(radiusLg),
            boxShadow: [
              BoxShadow(
                color: CustomAppColors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            children: [
              ProfileMenuItem(
                icon: personOutlineIcon,
                title: 'Edit Profile',
                subtitle: 'Update your personal information',
                onTap: () => _editProfile(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: settingsIcon,
                title: 'Settings',
                subtitle: 'Theme, units, and app preferences',
                onTap: () => _openSettings(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: notificationsIcon,
                title: 'Notifications',
                subtitle: 'Manage your notification preferences',
                onTap: () => _openNotifications(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: securityIcon,
                title: 'Privacy & Security',
                subtitle: 'Control your privacy settings',
                onTap: () => _openPrivacySettings(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: helpOutlineIcon,
                title: 'Help & Support',
                subtitle: 'Get help and contact support',
                onTap: () => _openHelp(context),
              ),
              const Divider(height: 1),
              ProfileMenuItem(
                icon: infoOutlineIcon,
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
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: [
            CustomAppColors.statusError,
            CustomAppColors.statusError.withOpacity(0.8),
          ],
        ),
        borderRadius: BorderRadius.circular(radiusLg),
        boxShadow: [
          BoxShadow(
            color: CustomAppColors.statusError.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _logout(context, ref),
          borderRadius: BorderRadius.circular(radiusLg),
          child: const Padding(
            padding: EdgeInsets.symmetric(vertical: spacingLg),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(logoutIcon, color: CustomAppColors.white),
                SizedBox(width: spacingSm),
                Text(
                  'Logout',
                  style: TextStyle(
                    color: CustomAppColors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
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

  void _shareProfile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Profile sharing - Coming Soon!'),
        backgroundColor: CustomAppColors.statusInfo,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _exportData(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: const Text('Data export - Coming Soon!'),
        backgroundColor: CustomAppColors.colorB,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _editProfile(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Edit Profile - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openSettings(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const SettingsScreen()),
    );
  }

  void _openNotifications(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Notifications Settings - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openPrivacySettings(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Privacy Settings - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  void _openHelp(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Help & Support - Coming Soon!'),
        backgroundColor: CustomAppColors.statusError,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _launchUrl(String url) async {
    final Uri uri = Uri.parse(url);
    if (!await launchUrl(uri)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to launch URL'),
            backgroundColor: CustomAppColors.statusError,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        log('Failed to launch URL');
      }
    }
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: 'RythmRun',
      applicationVersion: '1.0.0',
      applicationIcon: Container(
        padding: const EdgeInsets.all(spacingSm),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [CustomAppColors.colorA, CustomAppColors.colorB],
          ),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: const Icon(fitnessIcon, size: 40, color: CustomAppColors.white),
      ),
      children: [
        const Text(
          'Your fitness companion for tracking workouts and connecting with friends.',
        ),
        const SizedBox(height: spacingMd),
        GestureDetector(
          onTap: () {
            _launchUrl(
              'https://cosmicsaurabh.github.io/RythmRun/privacy-policy',
            );
          },
          child: const Text(
            'Privacy Policy',
            style: TextStyle(
              color: CustomAppColors.colorB,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
        const SizedBox(height: spacingSm),
        GestureDetector(
          onTap: () {
            _launchUrl('https://cosmicsaurabh.github.io/RythmRun/terms');
          },
          child: const Text(
            'Terms of Service',
            style: TextStyle(
              color: CustomAppColors.colorB,
              decoration: TextDecoration.underline,
            ),
          ),
        ),
      ],
    );
  }

  void _logout(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder:
          (context) => AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusLg),
            ),
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
