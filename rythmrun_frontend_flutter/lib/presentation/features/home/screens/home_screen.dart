import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/track/screens/track_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/screens/tracking_history_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/screens/profile_screen.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

// Provider for managing the current tab index
final tabIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentIndex = ref.watch(tabIndexProvider);

    final List<Widget> screens = [
      const TrackScreen(),
      const ActivitiesScreen(),
      const ProfileScreen(),
    ];

    return Scaffold(
      body: IndexedStack(index: currentIndex, children: screens),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: currentIndex,
        onTap: (index) {
          ref.read(tabIndexProvider.notifier).state = index;
        },
        type: BottomNavigationBarType.fixed,
        items: const [
          BottomNavigationBarItem(icon: Icon(trackChangesIcon), label: 'Track'),
          BottomNavigationBarItem(icon: Icon(listAltIcon), label: 'Activities'),
          BottomNavigationBarItem(icon: Icon(personIcon), label: 'Profile'),
        ],
      ),
    );
  }
}
