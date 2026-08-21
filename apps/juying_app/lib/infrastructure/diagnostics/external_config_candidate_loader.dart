import 'dart:convert';

import 'package:flutter/services.dart';

import '../../domain/models/external_config_candidate.dart';

abstract final class ExternalConfigCandidateLoader {
  static Future<List<ExternalConfigCandidate>> loadBundled() async {
    final raw = await rootBundle.loadString(
      'assets/config/external_source_candidates.json',
    );
    final decoded = jsonDecode(raw);
    if (decoded is! Map || decoded['candidates'] is! List) return const [];
    return (decoded['candidates'] as List)
        .whereType<Map>()
        .map((value) => _decode(Map<String, Object?>.from(value)))
        .whereType<ExternalConfigCandidate>()
        .toList(growable: false);
  }

  static ExternalConfigCandidate? _decode(Map<String, Object?> value) {
    final id = value['id'];
    final name = value['name'];
    final uri = Uri.tryParse(value['url']?.toString() ?? '');
    final reference = Uri.tryParse(value['referenceUrl']?.toString() ?? '');
    if (id is! String ||
        !RegExp(r'^candidate-[a-z0-9-]+$').hasMatch(id) ||
        name is! String ||
        name.trim().isEmpty ||
        uri == null ||
        !{'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    return ExternalConfigCandidate(
      id: id,
      name: name,
      uri: uri,
      referenceUri: reference?.scheme == 'https' ? reference : null,
    );
  }
}
