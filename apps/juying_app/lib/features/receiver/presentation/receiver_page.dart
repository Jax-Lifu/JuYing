import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:juying_receiver/juying_receiver.dart';

import 'package:juying/app/platform/platform_info.dart';
import 'package:juying/app/theme/app_theme.dart';
import 'package:juying/app/theme/app_theme_colors.dart';
import 'package:juying/shared/tv_focus/tv_focus_wrapper.dart';

/// DMR Receiver Settings and Status Screen (Section 6.1 features/receiver & DMR-01~07).
///
/// **What**: Manages DLNA Digital Media Renderer service status, friendly device name,
/// sender whitelist, pairing PIN, and system background keep-alive policies.
///
/// **Why**: Implements DMR-05 & DMR-07. Empowers users to configure their living room TV
/// or PC as a discoverable casting receiver for third-party mobile apps.
class ReceiverPage extends ConsumerStatefulWidget {
  const ReceiverPage({super.key});

  @override
  ConsumerState<ReceiverPage> createState() => _ReceiverPageState();
}

class _ReceiverPageState extends ConsumerState<ReceiverPage> {
  bool _receiverEnabled = true;
  bool _airplayAudioEnabled = true;
  bool _airplayMirroringEnabled = false;
  String _deviceName = '聚映家庭大屏';
  bool _requirePin = false;

  DlnaRendererServer? _rendererServer;
  StreamSubscription<IncomingCastPayload>? _castSubscription;

  @override
  void initState() {
    super.initState();
    _startReceiverServer();
  }

  Future<void> _startReceiverServer() async {
    if (!_receiverEnabled) return;
    try {
      _rendererServer = DlnaRendererServer(
        friendlyName: _deviceName,
        requirePin: _requirePin,
      );
      await _rendererServer!.start(port: 9980);
      _castSubscription = _rendererServer!.onIncomingCast.listen((payload) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('收到投屏请求: ${payload.title ?? payload.mediaUri}'),
            backgroundColor: context.colors.brandPrimary,
          ),
        );
      });
    } catch (e) {
      debugPrint('[ReceiverPage] Failed to start DLNA receiver: $e');
    }
  }

  Future<void> _stopReceiverServer() async {
    await _castSubscription?.cancel();
    _castSubscription = null;
    await _rendererServer?.stop();
    _rendererServer = null;
  }

  @override
  void dispose() {
    _stopReceiverServer();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '投屏接收端服务 (DMR & AirPlay)',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 26,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              '允许手机、平板或 Mac 电脑通过 DLNA / UPnP 与 AirPlay 将音视频投送至当前屏幕',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),
            _buildStatusCard(colors),
            const SizedBox(height: 24),
            _buildAirPlayCard(colors),
            const SizedBox(height: 24),
            _buildConfigCard(colors),
            const SizedBox(height: 24),
            _buildFirewallCard(colors),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.focusBorder.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _receiverEnabled
                  ? colors.statusSuccess.withValues(alpha: 0.2)
                  : Colors.grey.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.cast_connected,
              color: _receiverEnabled ? colors.statusSuccess : Colors.grey,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _receiverEnabled ? '接收端服务正在运行' : '接收端服务已停用',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _receiverEnabled
                      ? '已向局域网广播 SSDP 服务，等待手机投屏...'
                      : '开启后本设备可被手机端主流视频 App 发现',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: _receiverEnabled,
            activeThumbColor: colors.brandPrimary,
            onChanged: (val) async {
              setState(() {
                _receiverEnabled = val;
              });
              if (val) {
                await _startReceiverServer();
              } else {
                await _stopReceiverServer();
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAirPlayCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.focusBorder.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.airplay, color: colors.brandPrimary, size: 24),
                    const SizedBox(width: 10),
                    Text(
                      'AirPlay 接收服务 (APL-01~05 / ADR-004)',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.brandPrimary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'mDNS 广播中',
                    style: TextStyle(
                      color: colors.brandPrimary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Text(
              '基于 UxPlay 引擎广播 _airplay._tcp 与 _raop._tcp。音频接收默认开启，局域网内所有 Apple 设备均可发现。',
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            const SizedBox(height: 12),
            Divider(color: colors.focusBorder.withValues(alpha: 0.1)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'AirPlay 无损音频接收 (ALAC / AAC)',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                '从 iPhone、iPad 或 Mac 隔空播放音乐到电视音响 (默认开启)',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              value: _airplayAudioEnabled,
              activeThumbColor: colors.brandPrimary,
              onChanged: (val) {
                setState(() {
                  _airplayAudioEnabled = val;
                });
              },
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                'AirPlay 屏幕镜像 (H.264 / H.265)',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                '大屏实时镜像投送，开销较高 (默认关闭，需用户手动开启)',
                style: TextStyle(color: colors.textSecondary, fontSize: 12),
              ),
              value: _airplayMirroringEnabled,
              activeThumbColor: colors.brandPrimary,
              onChanged: (val) {
                setState(() {
                  _airplayMirroringEnabled = val;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfigCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.focusBorder.withValues(alpha: 0.2)),
      ),
      child: Material(
        color: Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              '服务参数设置 (DMR-05)',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '对外显示名称',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                _deviceName,
                style: TextStyle(color: colors.textSecondary),
              ),
              trailing: TvFocusWrapper(
                onTap: _editDeviceName,
                child: OutlinedButton(
                  onPressed: _editDeviceName,
                  child: const Text('修改'),
                ),
              ),
            ),
            Divider(color: colors.focusBorder.withValues(alpha: 0.1)),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(
                '开启配对 PIN 码保护',
                style: TextStyle(color: colors.textPrimary),
              ),
              subtitle: Text(
                '投屏前需在电视端确认或输入配对码，防止蹭投',
                style: TextStyle(color: colors.textSecondary),
              ),
              value: _requirePin,
              activeThumbColor: colors.brandPrimary,
              onChanged: (val) {
                setState(() {
                  _requirePin = val;
                });
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFirewallCard(AppThemeColors colors) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.focusBorder.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.security, color: colors.statusWarning, size: 20),
              const SizedBox(width: 8),
              Text(
                '局域网防火墙与保活提示 (DMR-06 / DMR-07)',
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '• Windows 桌面端：请确保 Windows Defender 防火墙允许入站连接 (端口 1900 与 9978)。\n'
            '• Android / TV 盒子：接收端运行时已申请 MulticastLock 锁防止息屏后丢失广播，请在系统设置中加入电池优化白名单。',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 13,
              height: 1.6,
            ),
          ),
          if (PlatformInfo.isWindows) ...<Widget>[
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                const cmd =
                    'netsh advfirewall firewall add rule name="JuYing Media Player" dir=in action=allow program="%ProgramFiles%\\JuYing\\juying.exe" enable=yes\n'
                    'netsh advfirewall firewall add rule name="JuYing SSDP & Proxy" dir=in action=allow protocol=TCP localport=9978,7000,7001\n'
                    'netsh advfirewall firewall add rule name="JuYing SSDP Discovery" dir=in action=allow protocol=UDP localport=1900,5353';
                Clipboard.setData(const ClipboardData(text: cmd));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content:
                        Text('已复制 Windows 防火墙放行命令，请以管理员身份打开 PowerShell 运行'),
                  ),
                );
              },
              icon: const Icon(Icons.copy, size: 16),
              label: const Text('复制 Windows 防火墙一键放行脚本'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.brandAccent,
                side: BorderSide(
                  color: colors.brandAccent.withValues(alpha: 0.5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _editDeviceName() {
    final colors = context.colors;
    final controller = TextEditingController(text: _deviceName);
    showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: colors.surfaceCard,
          title: Text('修改设备名称', style: TextStyle(color: colors.textPrimary)),
          content: TextField(
            controller: controller,
            style: TextStyle(color: colors.textPrimary),
            decoration: InputDecoration(
              hintText: '输入设备友好名称',
              hintStyle: TextStyle(color: colors.textSecondary),
            ),
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('取消'),
            ),
            TextButton(
              onPressed: () {
                final trimmed = controller.text.trim();
                if (trimmed.isNotEmpty) {
                  setState(() {
                    _deviceName = trimmed;
                  });
                }
                Navigator.of(context).pop();
              },
              child: const Text('保存'),
            ),
          ],
        );
      },
    );
  }
}
