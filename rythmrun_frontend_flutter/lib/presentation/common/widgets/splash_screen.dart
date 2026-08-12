import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:rythmrun_frontend_flutter/theme/app_theme.dart';

/// Simple splash screen shown while checking authentication
///
/// Redesigned to show a blurred mockup of the Track screen shell,
/// giving the perception of instantaneous loading (Option C).
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Track Workouts'),
        automaticallyImplyLeading: false,
        elevation: 0,
        actions: [
          Center(
            child: Container(
              width: 8,
              height: 8,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: spacingMd),
        ],
      ),
      body: Stack(
        children: [
          // Mock background map grid
          Positioned.fill(
            child: Container(
              color: isDark ? Colors.grey[900] : Colors.grey[100],
              child: Center(
                child: Icon(
                  Icons.map,
                  size: 150,
                  color: isDark ? Colors.grey[800] : Colors.grey[300],
                ),
              ),
            ),
          ),
          // Mock Ready to Track Card
          Positioned(
            top: spacingLg,
            left: spacingLg,
            right: spacingLg,
            child: Container(
              padding: const EdgeInsets.all(spacingLg),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                borderRadius: BorderRadius.circular(radiusXl),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(spacingMd),
                    decoration: BoxDecoration(
                      color: Theme.of(
                        context,
                      ).colorScheme.onPrimary.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(radiusMd),
                    ),
                    child: Icon(
                      runningIcon,
                      size: 32,
                      color: Theme.of(context).colorScheme.onPrimary,
                    ),
                  ),
                  const SizedBox(width: spacingLg),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Ready to Track?',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                        const SizedBox(height: spacingXs),
                        Text(
                          'Tap to start your workout',
                          style: TextStyle(
                            fontSize: 14,
                            color: Theme.of(
                              context,
                            ).colorScheme.onPrimary.withValues(alpha: 0.8),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.arrow_forward_ios,
                    size: 20,
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimary.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
          ),
          // Frosted Glass Blur Overlay
          Positioned.fill(
            child: ClipRect(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
                child: Container(
                  color:
                      isDark
                          ? Colors.black.withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.35),
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CupertinoActivityIndicator(radius: 14),
                        const SizedBox(height: 12),
                        Text(
                          'Loading...',
                          style: TextStyle(
                            color: isDark ? Colors.white70 : Colors.black87,
                            fontWeight: FontWeight.w500,
                            fontSize: 15,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: IgnorePointer(
        child: BottomNavigationBar(
          currentIndex: 0,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(trackChangesIcon),
              label: 'Track',
            ),
            BottomNavigationBarItem(
              icon: Icon(listAltIcon),
              label: 'Activities',
            ),
            BottomNavigationBarItem(icon: Icon(fitnessIcon), label: 'Tools'),
            BottomNavigationBarItem(icon: Icon(personIcon), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}
