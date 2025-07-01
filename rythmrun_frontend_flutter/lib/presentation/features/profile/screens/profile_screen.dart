import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../theme/app_theme.dart';
import '../../../../const/custom_app_colors.dart';
import '../../../providers/session_provider.dart';
import '../../../widgets/profile_stat_card.dart';
import '../../../widgets/profile_menu_item.dart';
import '../../settings/screens/settings_screen.dart';

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
              ? const Center(child: CircularProgressIndicator())
              : AnimatedBuilder(
                animation: _animationController,
                builder: (context, child) {
                  return Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          CustomAppColors.primary.withOpacity(0.1),
                          CustomAppColors.secondary.withOpacity(0.05),
                          Theme.of(context).scaffoldBackgroundColor,
                        ],
                        stops: const [0.0, 0.3, 1.0],
                      ),
                    ),
                    child: SafeArea(
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
                                  background: _buildProfileHeader(
                                    context,
                                    user,
                                  ),
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
            CustomAppColors.primary,
            CustomAppColors.secondary,
            CustomAppColors.accent.withOpacity(0.8),
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
                Icons.person,
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
                const Shadow(
                  color: Colors.black26,
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
              const Icon(
                Icons.email_outlined,
                color: CustomAppColors.white,
                size: 16,
              ),
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
                  Icons.calendar_today,
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
              Icons.emoji_events,
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
                  colors: [CustomAppColors.primary, CustomAppColors.secondary],
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
          childAspectRatio: 1.28,
          children: [
            ProfileStatCard(
              title: 'Activities',
              value: '12',
              icon: Icons.directions_run,
              color: CustomAppColors.statusSuccess,
            ),
            ProfileStatCard(
              title: 'Distance',
              value: '45.2 km',
              icon: Icons.route,
              color: CustomAppColors.primary,
            ),
            ProfileStatCard(
              title: 'Time',
              value: '8h 23m',
              icon: Icons.timer,
              color: CustomAppColors.secondary,
            ),
            ProfileStatCard(
              title: 'Friends',
              value: '24',
              icon: Icons.people,
              color: CustomAppColors.accent,
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
                  colors: [CustomAppColors.accent, CustomAppColors.primary],
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
              child: _buildQuickActionCard(
                context,
                'Share Profile',
                Icons.share,
                CustomAppColors.statusInfo,
                () => _shareProfile(context),
              ),
            ),
            const SizedBox(width: spacingLg),
            Expanded(
              child: _buildQuickActionCard(
                context,
                'Export Data',
                Icons.download,
                CustomAppColors.secondary,
                () => _exportData(context),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQuickActionCard(
    BuildContext context,
    String title,
    IconData icon,
    Color color,
    VoidCallback onTap,
  ) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(radiusLg),
        child: Container(
          padding: const EdgeInsets.all(spacingLg),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(radiusLg),
            border: Border.all(color: color.withOpacity(0.3), width: 1),
          ),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(spacingSm),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(radiusSm),
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: spacingSm),
              Text(
                title,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                  color: color,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
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
                  colors: [CustomAppColors.secondary, CustomAppColors.accent],
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
                color: Colors.black.withOpacity(0.05),
                blurRadius: 20,
                offset: const Offset(0, 4),
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
                icon: Icons.settings,
                title: 'Settings',
                subtitle: 'Theme, units, and app preferences',
                onTap: () => _openSettings(context),
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
                Icon(Icons.logout, color: CustomAppColors.white),
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
        backgroundColor: CustomAppColors.secondary,
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
            colors: [CustomAppColors.primary, CustomAppColors.secondary],
          ),
          borderRadius: BorderRadius.circular(radiusSm),
        ),
        child: const Icon(
          Icons.fitness_center,
          size: 40,
          color: CustomAppColors.white,
        ),
      ),
      children: [
        const Text(
          'Your fitness companion for tracking workouts and connecting with friends.',
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
