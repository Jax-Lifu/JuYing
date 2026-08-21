enum ExternalConfigProbeStatus {
  notChecked,
  reachable,
  redirected,
  httpError,
  invalidResponse,
  unreachable,
}

enum ExternalConfigRisk {
  insecureTransport,
  executableExtension,
  thirdPartyParser,
  embeddedCredentialMarker,
  nestedRemoteConfig,
  unknownAuthorization,
}

class ExternalConfigCandidate {
  const ExternalConfigCandidate({
    required this.id,
    required this.name,
    required this.uri,
    required this.referenceUri,
  });

  final String id;
  final String name;
  final Uri uri;
  final Uri? referenceUri;
}

class ExternalConfigProbeResult {
  const ExternalConfigProbeResult({
    required this.status,
    required this.checkedAt,
    this.httpStatus,
    this.contentType,
    this.risks = const {},
  });

  final ExternalConfigProbeStatus status;
  final DateTime checkedAt;
  final int? httpStatus;
  final String? contentType;
  final Set<ExternalConfigRisk> risks;

  bool get allowedForPlayback => false;
}
