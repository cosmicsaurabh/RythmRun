import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/features/ads/core/ads_result.dart';
import 'package:rythmrun_frontend_flutter/features/ads/presentation/start_of_day_offer_prompt.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_providers.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/live_tracking/screens/track_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/tracking_history/screens/tracking_history_screen.dart';
import 'package:rythmrun_frontend_flutter/presentation/features/profile/screens/profile_screen.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

// Provider for managing the current tab index
final tabIndexProvider = StateProvider<int>((ref) => 0);

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  bool _hasPromptedStartOffer = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _maybePromptStartOfDayOffer();
    });
  }

  Future<void> _maybePromptStartOfDayOffer() async {
    if (!mounted || _hasPromptedStartOffer) return;
    final adsService = ref.read(adsServiceProvider);
    await adsService.initialize();

    if (!adsService.canShowStartOfDayOffer) {
      setState(() {
        _hasPromptedStartOffer = true;
      });
      return;
    }

    setState(() {
      _hasPromptedStartOffer = true;
    });

    final action = await showStartOfDayOfferPrompt(context);
    if (!mounted || action != StartOfDayOfferAction.watchNow) return;

    final messenger = ScaffoldMessenger.of(context);
    final result = await adsService.showStartOfDayOffer();

    if (!mounted) return;

    switch (result.status) {
      case AdsResultStatus.completed:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Enjoy an ad-light day!'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case AdsResultStatus.skipped:
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Ad skipped — ads will show after activities today.'),
            duration: Duration(seconds: 2),
          ),
        );
        break;
      case AdsResultStatus.failed:
      case AdsResultStatus.unavailable:
        messenger.showSnackBar(
          SnackBar(
            content: Text(result.errorMessage ?? 'Ad failed to play.'),
            duration: const Duration(seconds: 2),
          ),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
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
