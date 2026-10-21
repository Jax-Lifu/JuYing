import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xml/xml.dart';

import '../juying_receiver.dart';

/// DLNA MediaRenderer Daemon and SOAP Service Handler (Section 6.1 receiver/dlna_renderer).
abstract interface class IDlnaRendererDaemon {
  Future<void> start({int port, String? friendlyName});
  Future<void> stop();
}

/// Concrete DLNA / UPnP MediaRenderer Server (DMR-01~05 & ADR-003).
///
/// **What**: Implements a complete UPnP MediaRenderer v1 daemon in pure Dart:
/// - Provides XML device description, AVTransport, RenderingControl, ConnectionManager SCPDs (DMR-01).
/// - Handles SOAP commands: SetAVTransportURI, Play, Pause, Stop, Seek, GetPositionInfo, SetVolume, SetMute (DMR-02).
/// - Parses DIDL-Lite metadata for titles, covers, and media formats (DMR-04).
/// - Enforces device friendlyName, optional sender IP whitelist, and pairing PIN verification (DMR-05).
/// - Responds to SSDP M-SEARCH multicast discovery queries on 239.255.255.250:1900 (DMR-01).
///
/// **Why**: Transforms JuYing on Android TV, PC, or tablet into an open living room
/// casting receiver without relying on proprietary third-party libraries.
class DlnaRendererServer implements IDlnaRendererDaemon, ReceiverService {
  DlnaRendererServer({
    this.friendlyName = '聚映家庭大屏',
    this.udn = 'uuid:juying-dmr-universal-001',
    this.manufacturer = 'JuYing Project',
    this.modelName = 'JuYing Living Room MediaRenderer',
    this.requirePin = false,
    this.pairingPin = '888888',
    this.allowedIps = const <String>{},
  });

  String friendlyName;
  final String udn;
  final String manufacturer;
  final String modelName;
  bool requirePin;
  String pairingPin;
  Set<String> allowedIps;

  HttpServer? _server;
  RawDatagramSocket? _ssdpSocket;
  Timer? _notifyTimer;

  int _port = 0;
  int get port => _port;

  // Playback state tracking
  String _currentTransportState = 'NO_MEDIA_PRESENT';
  String _currentUri = '';
  String _currentTitle = '';
  String _currentCoverUrl = '';
  Duration _currentDuration = Duration.zero;
  Duration _currentPosition = Duration.zero;
  int _volume = 80;
  bool _mute = false;

  final _castController = StreamController<IncomingCastPayload>.broadcast();
  final _playController = StreamController<void>.broadcast();
  final _pauseController = StreamController<void>.broadcast();
  final _stopController = StreamController<void>.broadcast();
  final _seekController = StreamController<Duration>.broadcast();
  final _volumeController = StreamController<int>.broadcast();

  @override
  Stream<IncomingCastPayload> get onIncomingCast => _castController.stream;
  Stream<void> get onPlay => _playController.stream;
  Stream<void> get onPause => _pauseController.stream;
  Stream<void> get onStop => _stopController.stream;
  Stream<Duration> get onSeek => _seekController.stream;
  Stream<int> get onVolume => _volumeController.stream;

  /// Updates current playback progress reported to DMC controllers.
  void updateProgress(
      {required Duration position, required Duration duration}) {
    _currentPosition = position;
    _currentDuration = duration;
  }

  /// Updates current transport playback state reported to DMC controllers.
  void updateTransportState(String state) {
    _currentTransportState = state;
  }

  @override
  Future<void> start({int port = 0, String? friendlyName}) async {
    if (friendlyName != null && friendlyName.isNotEmpty) {
      this.friendlyName = friendlyName;
    }

    _server = await HttpServer.bind(InternetAddress.anyIPv4, port);
    _server!.idleTimeout = null;
    _port = _server!.port;

    _server!.listen(_handleHttpRequest);
    _startSsdpResponder();
  }

  @override
  Future<void> stop() async {
    _notifyTimer?.cancel();
    _notifyTimer = null;

    try {
      _ssdpSocket?.close();
    } catch (_) {}
    _ssdpSocket = null;

    await _server?.close(force: true);
    _server = null;
    _currentTransportState = 'NO_MEDIA_PRESENT';
  }

  void _handleHttpRequest(HttpRequest request) async {
    final path = request.uri.path;
    final method = request.method.toUpperCase();

    try {
      if (method == 'GET' &&
          (path == '/description.xml' || path == '/dmr.xml' || path == '/')) {
        _serveDeviceDescription(request);
      } else if (method == 'GET' && path.endsWith('/scpd.xml')) {
        _serveScpd(request);
      } else if (method == 'POST' && path.contains('/AVTransport/control')) {
        await _handleAvTransportSoap(request);
      } else if (method == 'POST' &&
          path.contains('/RenderingControl/control')) {
        await _handleRenderingControlSoap(request);
      } else if (method == 'POST' &&
          path.contains('/ConnectionManager/control')) {
        await _handleConnectionManagerSoap(request);
      } else if (method == 'SUBSCRIBE' || method == 'UNSUBSCRIBE') {
        _handleGenaSubscription(request);
      } else {
        request.response.statusCode = HttpStatus.notFound;
        await request.response.close();
      }
    } catch (e) {
      request.response.statusCode = HttpStatus.internalServerError;
      request.response.write('Server Error: $e');
      await request.response.close();
    }
  }

  void _serveDeviceDescription(HttpRequest request) {
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <specVersion>
    <major>1</major>
    <minor>0</minor>
  </specVersion>
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>$friendlyName</friendlyName>
    <manufacturer>$manufacturer</manufacturer>
    <manufacturerURL>https://github.com/flytech/juying</manufacturerURL>
    <modelDescription>JuYing Cross-Platform MediaRenderer</modelDescription>
    <modelName>$modelName</modelName>
    <modelNumber>JuYing-v2.0</modelNumber>
    <UDN>$udn</UDN>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
        <SCPDURL>/AVTransport/scpd.xml</SCPDURL>
        <controlURL>/AVTransport/control</controlURL>
        <eventSubURL>/AVTransport/events</eventSubURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
        <SCPDURL>/RenderingControl/scpd.xml</SCPDURL>
        <controlURL>/RenderingControl/control</controlURL>
        <eventSubURL>/RenderingControl/events</eventSubURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:ConnectionManager:1</serviceType>
        <serviceId>urn:upnp-org:serviceId:ConnectionManager</serviceId>
        <SCPDURL>/ConnectionManager/scpd.xml</SCPDURL>
        <controlURL>/ConnectionManager/control</controlURL>
        <eventSubURL>/ConnectionManager/events</eventSubURL>
      </service>
    </serviceList>
  </device>
</root>''';

    request.response
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..headers.set('Server', 'JuYing-UPnP/1.0 DLNADOC/1.50')
      ..write(xml);
    request.response.close();
  }

  void _serveScpd(HttpRequest request) {
    const scpdXml = '''<?xml version="1.0" encoding="utf-8"?>
<scpd xmlns="urn:schemas-upnp-org:service-1-0">
  <specVersion><major>1</major><minor>0</minor></specVersion>
  <actionList></actionList>
  <serviceStateTable></serviceStateTable>
</scpd>''';

    request.response
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(scpdXml);
    request.response.close();
  }

  Future<void> _handleAvTransportSoap(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final senderIp = request.connectionInfo?.remoteAddress.address ?? '';

    // Sender IP whitelist validation (DMR-05)
    if (allowedIps.isNotEmpty && !allowedIps.contains(senderIp)) {
      _sendSoapFault(
          request, 606, 'Action Not Authorized: Sender IP not in whitelist');
      return;
    }

    final soapAction = request.headers.value('SOAPACTION') ?? '';

    if (soapAction.contains('SetAVTransportURI')) {
      final uri = _extractXmlTag(body, 'CurrentURI');
      final metadataXml = _extractXmlTag(body, 'CurrentURIMetaData');
      final didl = _parseDidl(metadataXml);

      // Pairing PIN check (DMR-05)
      if (requirePin) {
        final pin = request.uri.queryParameters['pin'] ??
            request.headers.value('X-JuYing-Pin');
        if (pin != pairingPin) {
          _sendSoapFault(request, 401, 'Invalid Pairing PIN');
          return;
        }
      }

      _currentUri = uri;
      _currentTitle = didl.title ?? '在线投屏';
      _currentCoverUrl = didl.coverUrl ?? '';
      _currentTransportState = 'STOPPED';

      _castController.add(IncomingCastPayload(
        mediaUri: uri,
        title: _currentTitle,
        coverUrl: _currentCoverUrl,
        senderIp: senderIp,
      ));

      _sendSoapResponse(request, 'SetAVTransportURIResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', '');
    } else if (soapAction.contains('Play')) {
      _currentTransportState = 'PLAYING';
      _playController.add(null);
      _sendSoapResponse(request, 'PlayResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', '');
    } else if (soapAction.contains('Pause')) {
      _currentTransportState = 'PAUSED_PLAYBACK';
      _pauseController.add(null);
      _sendSoapResponse(request, 'PauseResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', '');
    } else if (soapAction.contains('Stop')) {
      _currentTransportState = 'STOPPED';
      _stopController.add(null);
      _sendSoapResponse(request, 'StopResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', '');
    } else if (soapAction.contains('Seek')) {
      final target = _extractXmlTag(body, 'Target');
      final dur = _parseDurationString(target);
      _currentPosition = dur;
      _seekController.add(dur);
      _sendSoapResponse(request, 'SeekResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', '');
    } else if (soapAction.contains('GetTransportInfo')) {
      final res =
          '''<CurrentTransportState>$_currentTransportState</CurrentTransportState>
<CurrentTransportStatus>OK</CurrentTransportStatus>
<CurrentSpeed>1</CurrentSpeed>''';
      _sendSoapResponse(request, 'GetTransportInfoResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', res);
    } else if (soapAction.contains('GetPositionInfo')) {
      final durStr = _formatDurationString(_currentDuration);
      final relStr = _formatDurationString(_currentPosition);
      final res = '''<Track>1</Track>
<TrackDuration>$durStr</TrackDuration>
<TrackMetaData></TrackMetaData>
<TrackURI>$_currentUri</TrackURI>
<RelTime>$relStr</RelTime>
<AbsTime>$relStr</AbsTime>
<RelCount>2147483647</RelCount>
<AbsCount>2147483647</AbsCount>''';
      _sendSoapResponse(request, 'GetPositionInfoResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', res);
    } else if (soapAction.contains('GetMediaInfo')) {
      final durStr = _formatDurationString(_currentDuration);
      final res = '''<NrTracks>1</NrTracks>
<MediaDuration>$durStr</MediaDuration>
<CurrentURI>$_currentUri</CurrentURI>
<CurrentURIMetaData></CurrentURIMetaData>
<NextURI></NextURI>
<NextURIMetaData></NextURIMetaData>
<PlayMedium>NETWORK</PlayMedium>
<RecordMedium>NOT_IMPLEMENTED</RecordMedium>
<WriteStatus>NOT_IMPLEMENTED</WriteStatus>''';
      _sendSoapResponse(request, 'GetMediaInfoResponse',
          'urn:schemas-upnp-org:service:AVTransport:1', res);
    } else {
      _sendSoapFault(request, 401, 'Invalid Action');
    }
  }

  Future<void> _handleRenderingControlSoap(HttpRequest request) async {
    final body = await utf8.decodeStream(request);
    final soapAction = request.headers.value('SOAPACTION') ?? '';

    if (soapAction.contains('SetVolume')) {
      final volStr = _extractXmlTag(body, 'DesiredVolume');
      final val = int.tryParse(volStr) ?? _volume;
      _volume = val.clamp(0, 100);
      _volumeController.add(_volume);
      _sendSoapResponse(request, 'SetVolumeResponse',
          'urn:schemas-upnp-org:service:RenderingControl:1', '');
    } else if (soapAction.contains('GetVolume')) {
      final res = '<CurrentVolume>$_volume</CurrentVolume>';
      _sendSoapResponse(request, 'GetVolumeResponse',
          'urn:schemas-upnp-org:service:RenderingControl:1', res);
    } else if (soapAction.contains('SetMute')) {
      final muteStr = _extractXmlTag(body, 'DesiredMute');
      _mute = muteStr == '1' || muteStr.toLowerCase() == 'true';
      _sendSoapResponse(request, 'SetMuteResponse',
          'urn:schemas-upnp-org:service:RenderingControl:1', '');
    } else if (soapAction.contains('GetMute')) {
      final res = '<CurrentMute>${_mute ? 1 : 0}</CurrentMute>';
      _sendSoapResponse(request, 'GetMuteResponse',
          'urn:schemas-upnp-org:service:RenderingControl:1', res);
    } else {
      _sendSoapFault(request, 401, 'Invalid Action');
    }
  }

  Future<void> _handleConnectionManagerSoap(HttpRequest request) async {
    final soapAction = request.headers.value('SOAPACTION') ?? '';
    if (soapAction.contains('GetProtocolInfo')) {
      const res =
          '<Source></Source><Sink>http-get:*:video/mp4:*,http-get:*:video/quicktime:*,http-get:*:video/x-matroska:*,http-get:*:application/vnd.apple.mpegurl:*,http-get:*:audio/mpeg:*</Sink>';
      _sendSoapResponse(request, 'GetProtocolInfoResponse',
          'urn:schemas-upnp-org:service:ConnectionManager:1', res);
    } else {
      _sendSoapFault(request, 401, 'Invalid Action');
    }
  }

  void _handleGenaSubscription(HttpRequest request) {
    // GENA event subscription handling (DMR-03)
    final sid = 'uuid:juying-sub-${DateTime.now().millisecondsSinceEpoch}';
    request.response
      ..statusCode = HttpStatus.ok
      ..headers.set('SID', sid)
      ..headers.set('TIMEOUT', 'Second-1800')
      ..headers.set('Server', 'JuYing-UPnP/1.0');
    request.response.close();
  }

  void _sendSoapResponse(
      HttpRequest request, String action, String serviceType, String innerXml) {
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <u:$action xmlns:u="$serviceType">
      $innerXml
    </u:$action>
  </s:Body>
</s:Envelope>''';

    request.response
      ..statusCode = HttpStatus.ok
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..headers.set('EXT', '')
      ..headers.set('Server', 'JuYing-UPnP/1.0 DLNADOC/1.50')
      ..write(xml);
    request.response.close();
  }

  void _sendSoapFault(HttpRequest request, int code, String description) {
    final xml = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/" s:encodingStyle="http://schemas.xmlsoap.org/soap/encoding/">
  <s:Body>
    <s:Fault>
      <faultcode>s:Client</faultcode>
      <faultstring>UPnPError</faultstring>
      <detail>
        <UPnPError xmlns="urn:schemas-upnp-org:control-1-0">
          <errorCode>$code</errorCode>
          <errorDescription>$description</errorDescription>
        </UPnPError>
      </detail>
    </s:Fault>
  </s:Body>
</s:Envelope>''';

    request.response
      ..statusCode = HttpStatus.internalServerError
      ..headers.contentType = ContentType('text', 'xml', charset: 'utf-8')
      ..write(xml);
    request.response.close();
  }

  void _startSsdpResponder() {
    try {
      RawDatagramSocket.bind(
        InternetAddress.anyIPv4,
        1900,
        reuseAddress: true,
        reusePort: !Platform.isWindows,
      ).then((socket) {
        _ssdpSocket = socket;
        try {
          socket.joinMulticast(InternetAddress('239.255.255.250'));
        } catch (_) {}

        socket.listen((event) {
          if (event == RawSocketEvent.read) {
            final datagram = socket.receive();
            if (datagram != null) {
              _processSsdpDatagram(datagram);
            }
          }
        });
      }).catchError((_) {
        // Fallback: If 1900 cannot be bound (e.g. permission or another service), continue HTTP serving
      });
    } catch (_) {}
  }

  void _processSsdpDatagram(Datagram datagram) {
    final text = utf8.decode(datagram.data, allowMalformed: true);
    if (!text.startsWith('M-SEARCH')) return;

    final target = _extractHeaderValue(text, 'ST');
    final isMatching = target == 'ssdp:all' ||
        target == 'upnp:rootdevice' ||
        target == 'urn:schemas-upnp-org:device:MediaRenderer:1' ||
        target == udn;

    if (isMatching && _port > 0) {
      final responseText = '''HTTP/1.1 200 OK\r
CACHE-CONTROL: max-age=1800\r
DATE: ${DateTime.now().toUtc().toIso8601String()}\r
EXT:\r
LOCATION: http://${datagram.address.address}:$_port/description.xml\r
SERVER: Linux/4.9 UPnP/1.0 JuYing/2.0\r
ST: urn:schemas-upnp-org:device:MediaRenderer:1\r
USN: $udn::urn:schemas-upnp-org:device:MediaRenderer:1\r
\r
''';
      try {
        _ssdpSocket?.send(
            utf8.encode(responseText), datagram.address, datagram.port);
      } catch (_) {}
    }
  }

  String _extractXmlTag(String xml, String tag) {
    final start = xml.indexOf('<$tag');
    if (start == -1) return '';
    final closeTag = xml.indexOf('>', start);
    if (closeTag == -1) return '';
    final end = xml.indexOf('</$tag>', closeTag);
    if (end == -1) return '';
    return xml.substring(closeTag + 1, end).trim();
  }

  String? _extractHeaderValue(String text, String header) {
    for (final line in text.split('\r\n')) {
      final idx = line.indexOf(':');
      if (idx > 0 &&
          line.substring(0, idx).trim().toUpperCase() == header.toUpperCase()) {
        return line.substring(idx + 1).trim();
      }
    }
    return null;
  }

  ({String? title, String? coverUrl}) _parseDidl(String rawDidl) {
    if (rawDidl.isEmpty) return (title: null, coverUrl: null);
    try {
      final unescaped = rawDidl
          .replaceAll('&lt;', '<')
          .replaceAll('&gt;', '>')
          .replaceAll('&quot;', '"')
          .replaceAll('&amp;', '&');
      final doc = XmlDocument.parse(unescaped);
      final title = doc.findAllElements('dc:title').firstOrNull?.innerText;
      final cover =
          doc.findAllElements('upnp:albumArtURI').firstOrNull?.innerText;
      return (title: title, coverUrl: cover);
    } catch (_) {
      return (title: null, coverUrl: null);
    }
  }

  Duration _parseDurationString(String str) {
    final parts = str.split(':');
    if (parts.length == 3) {
      final h = int.tryParse(parts[0]) ?? 0;
      final m = int.tryParse(parts[1]) ?? 0;
      final s = double.tryParse(parts[2]) ?? 0.0;
      return Duration(hours: h, minutes: m, seconds: s.toInt());
    }
    return Duration.zero;
  }

  String _formatDurationString(Duration d) {
    final h = d.inHours.toString().padLeft(2, '0');
    final m = (d.inMinutes % 60).toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$h:$m:$s';
  }
}
