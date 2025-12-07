import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:rythmrun_frontend_flutter/features/ads/service/ads_providers.dart';

class ActivityBannerAdSlot extends ConsumerWidget {
  const ActivityBannerAdSlot({
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    this.backgroundColor,
  });

  final EdgeInsetsGeometry padding;
  final Color? backgroundColor;

  bool _isEmptyWidget(Widget widget) {
    return widget is SizedBox &&
        (widget.width == null || widget.width == 0) &&
        (widget.height == null || widget.height == 0);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adsService = ref.watch(adsServiceProvider);
    final banner = adsService.activityBanner();

    if (_isEmptyWidget(banner)) {
      return const SizedBox.shrink();
    }

    return Container(
      color: backgroundColor ?? Theme.of(context).colorScheme.surface,
      padding: padding,
      alignment: Alignment.center,
      child: banner,
    );
  }
}
