/// The user's story allowance. In backend mode this is the authoritative value
/// from `GET /v1/quota` (ADR 0002); in fake/offline mode it's built from local
/// mirrors. Either way the UI reads this one shape.
class QuotaState {
  const QuotaState({
    required this.freeUsed,
    required this.freeLimit,
    required this.credits,
    required this.canGenerate,
  });

  final int freeUsed;
  final int freeLimit;
  final int credits;
  final bool canGenerate;

  /// Free stories left (never negative).
  int get freeRemaining => (freeLimit - freeUsed).clamp(0, freeLimit);

  factory QuotaState.fromJson(Map<String, dynamic> json) {
    return QuotaState(
      freeUsed: (json['freeUsed'] as num?)?.toInt() ?? 0,
      freeLimit: (json['freeLimit'] as num?)?.toInt() ?? 0,
      credits: (json['credits'] as num?)?.toInt() ?? 0,
      canGenerate: json['canGenerate'] as bool? ?? false,
    );
  }
}
