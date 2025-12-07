enum AdsResultStatus { completed, skipped, failed, unavailable }

class AdsResult {
  const AdsResult({required this.status, this.errorMessage});

  const AdsResult.completed() : this(status: AdsResultStatus.completed);
  const AdsResult.skipped() : this(status: AdsResultStatus.skipped);
  const AdsResult.failed([String? message])
    : this(status: AdsResultStatus.failed, errorMessage: message);
  const AdsResult.unavailable([String? message])
    : this(status: AdsResultStatus.unavailable, errorMessage: message);

  final AdsResultStatus status;
  final String? errorMessage;

  bool get isSuccess => status == AdsResultStatus.completed;
}
