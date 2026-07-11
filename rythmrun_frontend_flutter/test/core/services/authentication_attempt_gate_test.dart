import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/authentication_attempt_gate.dart';

void main() {
  test(
    'authentication mutations serialize and account exit drains them',
    () async {
      final gate = AuthenticationAttemptGate();
      final lease = gate.tryAcquire();

      expect(lease, isNotNull);
      expect(gate.tryAcquire(), isNull);

      var didDrain = false;
      final drain = gate.suspendAndDrain().then((_) => didDrain = true);
      await Future<void>.delayed(Duration.zero);
      expect(didDrain, isFalse);
      expect(gate.tryAcquire(), isNull);

      lease!.release();
      await drain;
      expect(didDrain, isTrue);
      expect(gate.tryAcquire(), isNull);

      gate.resume();
      final nextLease = gate.tryAcquire();
      expect(nextLease, isNotNull);
      nextLease!.release();
    },
  );
}
