import 'package:flutter_test/flutter_test.dart';
import 'package:rythmrun_frontend_flutter/core/services/user_scope_operation_gate.dart';

void main() {
  group('UserScopeOperationGate', () {
    test('starts suspended and admits only the activated user', () {
      final gate = UserScopeOperationGate();

      expect(gate.isSuspended, isTrue);
      expect(gate.tryAcquire(1), isNull);

      gate.activate(1);

      expect(gate.isSuspended, isFalse);
      expect(gate.activeUserId, 1);
      expect(gate.tryAcquire(2), isNull);

      final lease = gate.tryAcquire(1);
      expect(lease, isNotNull);
      expect(lease!.userId, 1);
      expect(gate.activeLeaseCount, 1);

      lease.release();
      expect(gate.activeLeaseCount, 0);
    });

    test(
      'suspension rejects new work and waits for every existing lease',
      () async {
        final gate = UserScopeOperationGate()..activate(1);
        final firstLease = gate.tryAcquire(1)!;
        final secondLease = gate.tryAcquire(1)!;
        var didDrain = false;

        final drain = gate.suspendAndDrain().then((_) {
          didDrain = true;
        });
        final repeatedDrain = gate.suspendAndDrain();

        expect(gate.isSuspended, isTrue);
        expect(gate.activeUserId, isNull);
        expect(gate.tryAcquire(1), isNull);
        expect(gate.tryAcquire(2), isNull);

        firstLease.release();
        await _pumpMicrotasks();
        expect(didDrain, isFalse);

        secondLease.release();
        await Future.wait<void>([drain, repeatedDrain]);
        expect(didDrain, isTrue);
        expect(gate.activeLeaseCount, 0);
      },
    );

    test('a different user cannot activate before suspension and drain', () {
      final gate = UserScopeOperationGate()..activate(1);

      expect(() => gate.activate(2), throwsStateError);
      expect(gate.activeUserId, 1);
    });

    test('a draining lease prevents early reactivation', () async {
      final gate = UserScopeOperationGate()..activate(1);
      final lease = gate.tryAcquire(1)!;
      final drain = gate.suspendAndDrain();

      expect(() => gate.activate(2), throwsStateError);

      lease.release();
      await drain;
      gate.activate(2);

      expect(gate.activeUserId, 2);
      expect(gate.tryAcquire(1), isNull);
      gate.tryAcquire(2)!.release();
    });

    test('lease release is idempotent', () {
      final gate = UserScopeOperationGate()..activate(1);
      final lease = gate.tryAcquire(1)!;

      lease.release();
      lease.release();

      expect(lease.isReleased, isTrue);
      expect(gate.activeLeaseCount, 0);
    });
  });
}

Future<void> _pumpMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}
