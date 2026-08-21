import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../../../domain/models/external_config_candidate.dart';
import '../../../infrastructure/diagnostics/external_config_candidate_loader.dart';
import '../../../infrastructure/diagnostics/external_config_probe_service.dart';

class ExternalSourceDiagnosticsPage extends StatefulWidget {
  const ExternalSourceDiagnosticsPage({super.key});

  @override
  State<ExternalSourceDiagnosticsPage> createState() =>
      _ExternalSourceDiagnosticsPageState();
}

class _ExternalSourceDiagnosticsPageState
    extends State<ExternalSourceDiagnosticsPage> {
  late final http.Client _client = http.Client();
  late final ExternalConfigProbeService _probe =
      ExternalConfigProbeService(client: _client);
  late final Future<List<ExternalConfigCandidate>> _candidates =
      ExternalConfigCandidateLoader.loadBundled();
  final Map<String, ExternalConfigProbeResult> _results = {};
  var _checking = false;

  @override
  void dispose() {
    _client.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('外部配置安全检测'),
          actions: [
            IconButton(
              onPressed: _checking ? null : _checkAll,
              tooltip: '检测全部',
              icon: _checking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.health_and_safety_outlined),
            ),
          ],
        ),
        body: FutureBuilder<List<ExternalConfigCandidate>>(
          future: _candidates,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            if (snapshot.hasError) {
              return const Center(child: Text('无法加载候选配置清单'));
            }
            final candidates = snapshot.data ?? const [];
            return ListView(
              padding: const EdgeInsets.all(20),
              children: [
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '此页面只做有界、无重定向、无执行的可达性与结构检测。'
                      '检测成功不代表内容已授权；这些配置不会进入目录、搜索或播放器。',
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                ...candidates.map((candidate) {
                  final result = _results[candidate.id];
                  return Card(
                    child: ListTile(
                      leading: Icon(
                        _statusIcon(result?.status),
                        color: _statusColor(context, result?.status),
                      ),
                      title: Text(candidate.name),
                      subtitle: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(candidate.uri.host),
                          const SizedBox(height: 4),
                          Text(_summary(result)),
                          if (result != null && result.risks.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: result.risks
                                    .map((risk) => Chip(
                                          visualDensity: VisualDensity.compact,
                                          label: Text(_riskLabel(risk)),
                                        ))
                                    .toList(growable: false),
                              ),
                            ),
                        ],
                      ),
                      trailing: IconButton(
                        tooltip: '检测',
                        onPressed:
                            _checking ? null : () => _checkCandidate(candidate),
                        icon: const Icon(Icons.refresh_rounded),
                      ),
                    ),
                  );
                }),
              ],
            );
          },
        ),
      );

  Future<void> _checkAll() async {
    final candidates = await _candidates;
    if (!mounted) return;
    setState(() => _checking = true);
    try {
      // 顺序探测，避免对第三方站点造成并发压力。
      for (final candidate in candidates) {
        final result = await _probe.probe(candidate);
        if (!mounted) return;
        setState(() => _results[candidate.id] = result);
      }
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _checkCandidate(ExternalConfigCandidate candidate) async {
    setState(() => _checking = true);
    try {
      final result = await _probe.probe(candidate);
      if (mounted) setState(() => _results[candidate.id] = result);
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  String _summary(ExternalConfigProbeResult? result) {
    if (result == null) return '未检测 · 隔离候选';
    final status = switch (result.status) {
      ExternalConfigProbeStatus.notChecked => '未检测',
      ExternalConfigProbeStatus.reachable => '配置结构可识别',
      ExternalConfigProbeStatus.redirected => '发生重定向（未跟随）',
      ExternalConfigProbeStatus.httpError => 'HTTP 错误',
      ExternalConfigProbeStatus.invalidResponse => '响应不是受支持配置',
      ExternalConfigProbeStatus.unreachable => '无法访问',
    };
    return '$status${result.httpStatus == null ? '' : ' · HTTP ${result.httpStatus}'} · 禁止播放';
  }

  String _riskLabel(ExternalConfigRisk risk) => switch (risk) {
        ExternalConfigRisk.insecureTransport => 'HTTP 明文',
        ExternalConfigRisk.executableExtension => '可执行扩展',
        ExternalConfigRisk.thirdPartyParser => '第三方解析',
        ExternalConfigRisk.embeddedCredentialMarker => '疑似凭据字段',
        ExternalConfigRisk.nestedRemoteConfig => '嵌套远程配置',
        ExternalConfigRisk.unknownAuthorization => '授权未知',
      };

  IconData _statusIcon(ExternalConfigProbeStatus? status) => switch (status) {
        ExternalConfigProbeStatus.reachable => Icons.warning_amber_rounded,
        ExternalConfigProbeStatus.redirected => Icons.redo_rounded,
        ExternalConfigProbeStatus.httpError ||
        ExternalConfigProbeStatus.invalidResponse ||
        ExternalConfigProbeStatus.unreachable =>
          Icons.error_outline_rounded,
        _ => Icons.help_outline_rounded,
      };

  Color _statusColor(
    BuildContext context,
    ExternalConfigProbeStatus? status,
  ) =>
      switch (status) {
        ExternalConfigProbeStatus.reachable => Colors.orange,
        ExternalConfigProbeStatus.redirected => Colors.amber,
        ExternalConfigProbeStatus.httpError ||
        ExternalConfigProbeStatus.invalidResponse ||
        ExternalConfigProbeStatus.unreachable =>
          Theme.of(context).colorScheme.error,
        _ => Theme.of(context).colorScheme.outline,
      };
}
