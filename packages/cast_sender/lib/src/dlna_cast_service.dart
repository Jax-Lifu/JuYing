import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:juying_core/juying_core.dart';
import 'package:xml/xml.dart';

/// Position and duration feedback from a remote DLNA playback device.
class DlnaPositionInfo {
  const DlnaPositionInfo({
    required this.trackDuration,
    required this.relTime,
  });

  /// Total duration of current media track.
  final Duration trackDuration;

  /// Current playback position on remote display.
  final Duration relTime;
}

/// Represents a discovered UPnP / DLNA Digital Media Renderer (DMR).
class DlnaDevice {
  const DlnaDevice({
    required this.id,
    required this.name,
    required this.controlUrl,
    required this.location,
    this.renderingControlUrl,
    this.modelName,
    this.manufacturer,
    this.profile,
  });

  /// Unique identifier (usually the device description URL or UDN).
  final String id;

  /// Human-readable friendly device name.
  final String name;

  /// AVTransport service control endpoint.
  final String controlUrl;

  /// RenderingControl service control endpoint (for volume / mute).
  final String? renderingControlUrl;

  /// Full URL to the device description XML.
  final String location;

  /// Hardware model name.
  final String? modelName;

  /// Hardware manufacturer.
  final String? manufacturer;

  /// Matched hardware compatibility profile.
  final DeviceProfile? profile;
}

/// DLNA / UPnP Media Casting controller (DMC) (CAST-01~05 & ADR-003).
///
/// **What**: Discovers living room smart TVs via SSDP multicast (`239.255.255.250:1900`)
/// or manual IP address, sends SOAP XML commands to control playback, volume, and seeking.
///
/// **Why**: Implements CAST-01 and CAST-02 requirements from the JuYing guidance document.
/// Enables cross-screen casting from mobile/desktop to living room displays with
/// full transport controls.
class DlnaCastService {
  DlnaCastService({
    Dio? dio,
    List<DeviceProfile>? profiles,
  })  : _dio = dio ??
            Dio(
              BaseOptions(
                connectTimeout: const Duration(seconds: 4),
                receiveTimeout: const Duration(seconds: 4),
              ),
            ),
        _profiles = profiles ?? const <DeviceProfile>[];

  final Dio _dio;
  final List<DeviceProfile> _profiles;

  /// Discovers DLNA MediaRenderer devices on the local Wi-Fi network via SSDP.
  Future<List<DlnaDevice>> discoverDevices({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    final devices = <DlnaDevice>[];
    RawDatagramSocket? socket;

    try {
      socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;

      const ssdpSearch = 'M-SEARCH * HTTP/1.1\r\n'
          'HOST: 239.255.255.250:1900\r\n'
          'MAN: "ssdp:discover"\r\n'
          'MX: 3\r\n'
          'ST: urn:schemas-upnp-org:service:AVTransport:1\r\n\r\n';

      final data = utf8.encode(ssdpSearch);
      socket.send(
        data,
        InternetAddress('239.255.255.250'),
        1900,
      );

      final locations = <String>{};
      final completer = Completer<void>();

      socket.listen((event) {
        if (event == RawSocketEvent.read) {
          final dg = socket?.receive();
          if (dg != null) {
            final text = utf8.decode(dg.data, allowMalformed: true);
            final locMatch =
                RegExp(r'LOCATION:\s*(http://[^\r\n]+)', caseSensitive: false)
                    .firstMatch(text);
            if (locMatch != null) {
              final loc = locMatch.group(1)!.trim();
              locations.add(loc);
            }
          }
        }
      });

      Timer(timeout, () {
        if (!completer.isCompleted) completer.complete();
      });

      await completer.future;

      // Ingest device descriptions
      for (final loc in locations) {
        final dev = await fetchDeviceDescription(loc);
        if (dev != null) devices.add(dev);
      }
    } catch (_) {
    } finally {
      socket?.close();
    }

    return devices;
  }

  /// Manually queries a device by IP address as fallback when SSDP multicast is blocked.
  Future<DlnaDevice?> fetchDeviceFromIp(
    String ip, {
    int? port,
    String? path,
  }) async {
    final ports = port != null
        ? [port]
        : const [1900, 8080, 1400, 49152, 49153, 49154, 52235];
    final defaultPath = path ?? '/description.xml';

    for (final p in ports) {
      final targetUrl = 'http://$ip:$p$defaultPath';
      final dev = await fetchDeviceDescription(targetUrl);
      if (dev != null) return dev;
    }
    return null;
  }

  /// Fetches and parses UPnP device description XML from [locationUrl].
  Future<DlnaDevice?> fetchDeviceDescription(String locationUrl) async {
    try {
      final res = await _dio.get<String>(locationUrl);
      final xmlStr = res.data;
      if (xmlStr == null) return null;

      final doc = XmlDocument.parse(xmlStr);
      final friendlyName =
          doc.findAllElements('friendlyName').firstOrNull?.innerText.trim() ??
              'DLNA TV';
      final modelName =
          doc.findAllElements('modelName').firstOrNull?.innerText.trim();
      final manufacturer =
          doc.findAllElements('manufacturer').firstOrNull?.innerText.trim();

      // Find AVTransport and RenderingControl control URLs
      String? avTransportUrl;
      String? renderingControlUrl;
      final services = doc.findAllElements('service');
      for (final s in services) {
        final serviceType =
            s.findAllElements('serviceType').firstOrNull?.innerText.trim() ??
                '';
        if (serviceType.contains('AVTransport')) {
          avTransportUrl ??=
              s.findAllElements('controlURL').firstOrNull?.innerText.trim();
        } else if (serviceType.contains('RenderingControl')) {
          renderingControlUrl ??=
              s.findAllElements('controlURL').firstOrNull?.innerText.trim();
        }
      }

      if (avTransportUrl != null) {
        final uri = Uri.parse(locationUrl);
        final fullControlUrl = avTransportUrl.startsWith('http')
            ? avTransportUrl
            : uri.resolve(avTransportUrl).toString();

        String? fullRenderingUrl;
        if (renderingControlUrl != null) {
          fullRenderingUrl = renderingControlUrl.startsWith('http')
              ? renderingControlUrl
              : uri.resolve(renderingControlUrl).toString();
        }

        // Match hardware profile if available
        DeviceProfile? matchedProfile;
        for (final p in _profiles) {
          if (p.matches(
            deviceManufacturer: manufacturer,
            deviceModel: modelName,
          )) {
            matchedProfile = p;
            break;
          }
        }

        return DlnaDevice(
          id: locationUrl,
          name: friendlyName,
          controlUrl: fullControlUrl,
          renderingControlUrl: fullRenderingUrl,
          location: locationUrl,
          modelName: modelName,
          manufacturer: manufacturer,
          profile: matchedProfile,
        );
      }
    } catch (_) {}
    return null;
  }

  /// Sends `SetAVTransportURI` and `Play` commands to initiate remote casting (CAST-02).
  Future<bool> castVideo({
    required DlnaDevice device,
    required String mediaUrl,
    required String title,
  }) async {
    try {
      final setUriBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>${XmlText(mediaUrl).toXmlString()}</CurrentURI>
      <CurrentURIMetaData></CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>
''';

      await _dio.post<dynamic>(
        device.controlUrl,
        data: setUriBody,
        options: Options(
          headers: <String, dynamic>{
            'SOAPAction':
                '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );

      final playBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <Speed>1</Speed>
    </u:Play>
  </s:Body>
</s:Envelope>
''';

      await _dio.post<dynamic>(
        device.controlUrl,
        data: playBody,
        options: Options(
          headers: <String, dynamic>{
            'SOAPAction': '"urn:schemas-upnp-org:service:AVTransport:1#Play"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );

      return true;
    } catch (_) {
      return false;
    }
  }

  /// Sends remote `Pause` command to the rendering device (CAST-02).
  Future<bool> pauseVideo(DlnaDevice device) async {
    return _sendSoapAction(
      endpoint: device.controlUrl,
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      action: 'Pause',
      body: '<InstanceID>0</InstanceID>',
    );
  }

  /// Sends remote `Stop` command to the rendering device (CAST-02).
  Future<bool> stopVideo(DlnaDevice device) async {
    return _sendSoapAction(
      endpoint: device.controlUrl,
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      action: 'Stop',
      body: '<InstanceID>0</InstanceID>',
    );
  }

  /// Sends remote `Seek` command to a specific playback timestamp (CAST-02).
  Future<bool> seekVideo(DlnaDevice device, Duration target) async {
    final relTime = _formatDuration(target);
    return _sendSoapAction(
      endpoint: device.controlUrl,
      serviceType: 'urn:schemas-upnp-org:service:AVTransport:1',
      action: 'Seek',
      body: '<InstanceID>0</InstanceID>'
          '<Unit>REL_TIME</Unit>'
          '<Target>$relTime</Target>',
    );
  }

  /// Queries the current playback position and duration (CAST-02).
  Future<DlnaPositionInfo?> getPositionInfo(DlnaDevice device) async {
    try {
      const action = 'GetPositionInfo';
      const serviceType = 'urn:schemas-upnp-org:service:AVTransport:1';
      final soapBody = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:$action xmlns:u="$serviceType">
      <InstanceID>0</InstanceID>
    </u:$action>
  </s:Body>
</s:Envelope>
''';

      final res = await _dio.post<String>(
        device.controlUrl,
        data: soapBody,
        options: Options(
          headers: <String, dynamic>{
            'SOAPAction': '"$serviceType#$action"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );

      final xmlStr = res.data;
      if (xmlStr == null) return null;

      final doc = XmlDocument.parse(xmlStr);
      final trackDurationStr =
          doc.findAllElements('TrackDuration').firstOrNull?.innerText.trim();
      final relTimeStr =
          doc.findAllElements('RelTime').firstOrNull?.innerText.trim();

      return DlnaPositionInfo(
        trackDuration: _parseDuration(trackDurationStr),
        relTime: _parseDuration(relTimeStr),
      );
    } catch (_) {
      return null;
    }
  }

  /// Adjusts master volume level on TV screen via RenderingControl service (CAST-02).
  Future<bool> setVolume(DlnaDevice device, int volume) async {
    final rcUrl = device.renderingControlUrl;
    if (rcUrl == null) return false;

    final clampedVolume = volume.clamp(0, 100);
    return _sendSoapAction(
      endpoint: rcUrl,
      serviceType: 'urn:schemas-upnp-org:service:RenderingControl:1',
      action: 'SetVolume',
      body: '<InstanceID>0</InstanceID>'
          '<Channel>Master</Channel>'
          '<DesiredVolume>$clampedVolume</DesiredVolume>',
    );
  }

  Future<bool> _sendSoapAction({
    required String endpoint,
    required String serviceType,
    required String action,
    required String body,
  }) async {
    try {
      final envelope = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/" xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:$action xmlns:u="$serviceType">
      $body
    </u:$action>
  </s:Body>
</s:Envelope>
''';

      await _dio.post<dynamic>(
        endpoint,
        data: envelope,
        options: Options(
          headers: <String, dynamic>{
            'SOAPAction': '"$serviceType#$action"',
            'Content-Type': 'text/xml; charset="utf-8"',
          },
        ),
      );
      return true;
    } catch (_) {
      return false;
    }
  }

  String _formatDuration(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  Duration _parseDuration(String? str) {
    if (str == null || str.isEmpty || str == 'NOT_IMPLEMENTED') {
      return Duration.zero;
    }
    final parts = str.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = int.tryParse(parts[2].split('.').first) ?? 0;
      return Duration(hours: h, minutes: m, seconds: s);
    }
    return Duration.zero;
  }
}
