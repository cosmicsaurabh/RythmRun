import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/error_handler.dart';
import '../../../common/providers/session_provider.dart';

/// Non-blocking prompt shown when the signed-in account has not yet confirmed
/// its email address.
///
/// Only password accounts ever see this: an account created through Google is
/// already verified by Google, so nagging it would be both wrong and
/// unactionable (it has no password flow to fall back on).
class EmailVerificationBanner extends ConsumerStatefulWidget {
  const EmailVerificationBanner({super.key});

  @override
  ConsumerState<EmailVerificationBanner> createState() =>
      _EmailVerificationBannerState();
}

class _EmailVerificationBannerState
    extends ConsumerState<EmailVerificationBanner> {
  bool _dismissed = false;
  bool _busy = false;
  String? _message;

  Future<void> _resend() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    String message;
    try {
      await ref.read(sessionProvider.notifier).resendVerificationEmail();
      message = 'Verification email sent. Check your inbox.';
    } catch (error) {
      // Covers the server-side cooldown (429) and offline errors.
      message = ErrorHandler.getErrorMessage(error);
    }

    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = message;
    });
  }

  Future<void> _refresh() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });

    await ref.read(sessionProvider.notifier).refreshVerificationState();
    if (!mounted) return;

    // If it worked, this widget stops rendering on the next build.
    final stillUnverified =
        ref.read(currentUserProvider)?.emailVerified == false;
    setState(() {
      _busy = false;
      _message =
          stillUnverified
              ? 'Not confirmed yet. Open the link in your email, then try again.'
              : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (_dismissed || user == null || user.emailVerified || !user.hasPassword) {
      return const SizedBox.shrink();
    }

    // The home Scaffold has no AppBar, so keep clear of the status bar.
    return SafeArea(
      bottom: false,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        decoration: BoxDecoration(
          color: Colors.amber.shade100,
          border: Border(
            bottom: BorderSide(color: Colors.amber.shade300, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.mark_email_unread_outlined,
                  size: 18,
                  color: Colors.amber.shade900,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Confirm your email to secure your account.',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber.shade900,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  color: Colors.amber.shade900,
                  tooltip: 'Dismiss',
                  visualDensity: VisualDensity.compact,
                  onPressed: () => setState(() => _dismissed = true),
                ),
              ],
            ),
            if (_message != null)
              Padding(
                padding: const EdgeInsets.only(left: 26, right: 8, top: 2),
                child: Text(
                  _message!,
                  style: TextStyle(fontSize: 12, color: Colors.amber.shade900),
                ),
              ),
            Padding(
              padding: const EdgeInsets.only(left: 18),
              child: Row(
                children: [
                  TextButton(
                    onPressed: _busy ? null : _resend,
                    child: const Text('Resend email'),
                  ),
                  TextButton(
                    onPressed: _busy ? null : _refresh,
                    child: const Text("I've confirmed"),
                  ),
                  if (_busy)
                    const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
