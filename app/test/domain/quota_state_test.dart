import 'package:flutter_test/flutter_test.dart';
import 'package:playzy/domain/quota_state.dart';

void main() {
  group('QuotaState', () {
    test('parses JSON from the backend', () {
      final q = QuotaState.fromJson({
        'freeUsed': 2,
        'freeLimit': 3,
        'credits': 10,
        'canGenerate': true,
      });
      expect(q.freeUsed, 2);
      expect(q.freeLimit, 3);
      expect(q.credits, 10);
      expect(q.canGenerate, isTrue);
      expect(q.freeRemaining, 1);
    });

    test('freeRemaining never goes negative', () {
      const q = QuotaState(freeUsed: 5, freeLimit: 3, credits: 0, canGenerate: false);
      expect(q.freeRemaining, 0);
    });

    test('tolerates missing fields (defensive defaults)', () {
      final q = QuotaState.fromJson({});
      expect(q.canGenerate, isFalse);
      expect(q.freeLimit, 0);
    });
  });
}
