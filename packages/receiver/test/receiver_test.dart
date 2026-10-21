import 'dart:convert';
import 'dart:io';

import 'package:juying_receiver/juying_receiver.dart';
import 'package:test/test.dart';

void main() {
  group('DLNA MediaRenderer Receiver Model Tests (Section 5.8 & DMR-04)', () {
    test('IncomingCastPayload model parses DIDL metadata fields safely', () {
      const payload = IncomingCastPayload(
        mediaUri: 'http://192.168.1.100:9978/p/token-cast-1',
        title: '新闻联播 (投屏)',
        coverUrl: 'http://192.168.1.100:9978/cover.jpg',
        senderIp: '192.168.1.5',
      );

      expect(payload.mediaUri, contains('/p/token-cast-1'));
      expect(payload.title, equals('新闻联播 (投屏)'));
      expect(payload.senderIp, equals('192.168.1.5'));
    });
  });

  group('DLNA MediaRenderer Server Protocol & SOAP Tests (DMR-01~05)', () {
    late DlnaRendererServer server;
    late HttpClient client;

    setUp(() async {
      server = DlnaRendererServer(
        friendlyName: '聚映客厅电视测试机',
        udn: 'uuid:test-renderer-001',
      );
      await server.start(port: 0);
      client = HttpClient();
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    test('serves UPnP MediaRenderer device description XML (DMR-01)', () async {
      final req = await client
          .getUrl(Uri.parse('http://127.0.0.1:${server.port}/description.xml'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(resp.headers.contentType?.mimeType, equals('text/xml'));

      final body = await utf8.decodeStream(resp);
      expect(
          body,
          contains(
              '<deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>'));
      expect(body, contains('<friendlyName>聚映客厅电视测试机</friendlyName>'));
      expect(
          body,
          contains(
              '<serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>'));
      expect(
          body,
          contains(
              '<serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>'));
      expect(body, contains('<UDN>uuid:test-renderer-001</UDN>'));
    });

    test(
        'handles SetAVTransportURI and parses DIDL metadata title and cover (DMR-02 & DMR-04)',
        () async {
      final castFuture = server.onIncomingCast.first;

      final req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set('SOAPACTION',
          '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
      req.headers.contentType = ContentType('text', 'xml', charset: 'utf-8');

      const didlMeta =
          '&lt;DIDL-Lite xmlns=&quot;urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/&quot;&gt;&lt;item id=&quot;0&quot;&gt;&lt;dc:title xmlns:dc=&quot;http://purl.org/dc/elements/1.1/&quot;&gt;流浪地球2 (4K HDR)&lt;/dc:title&gt;&lt;upnp:albumArtURI xmlns:upnp=&quot;urn:schemas-upnp-org:metadata-1-0/upnp/&quot;&gt;http://example.com/poster.jpg&lt;/upnp:albumArtURI&gt;&lt;/item&gt;&lt;/DIDL-Lite&gt;';
      const soapBody = '''<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <InstanceID>0</InstanceID>
      <CurrentURI>http://192.168.1.88:9978/p/stream-token-42</CurrentURI>
      <CurrentURIMetaData>$didlMeta</CurrentURIMetaData>
    </u:SetAVTransportURI>
  </s:Body>
</s:Envelope>''';

      req.write(soapBody);
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));

      final payload = await castFuture.timeout(const Duration(seconds: 3));
      expect(payload.mediaUri,
          equals('http://192.168.1.88:9978/p/stream-token-42'));
      expect(payload.title, equals('流浪地球2 (4K HDR)'));
      expect(payload.coverUrl, equals('http://example.com/poster.jpg'));
    });

    test('handles Play, Pause, Stop, and Seek transport commands (DMR-02)',
        () async {
      final playFuture = server.onPlay.first;
      final pauseFuture = server.onPause.first;
      final stopFuture = server.onStop.first;
      final seekFuture = server.onSeek.first;

      // 1. Play
      var req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set(
          'SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#Play"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Play xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><Speed>1</Speed></u:Play></s:Body></s:Envelope>');
      var resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      await playFuture;

      // 2. Pause
      req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set(
          'SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#Pause"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Pause xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body></s:Envelope>');
      resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      await pauseFuture;

      // 3. Seek
      req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set(
          'SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#Seek"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Seek xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><Target>01:15:30</Target></u:Seek></s:Body></s:Envelope>');
      resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      final seekTarget = await seekFuture;
      expect(seekTarget,
          equals(const Duration(hours: 1, minutes: 15, seconds: 30)));

      // 4. Stop
      req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set(
          'SOAPACTION', '"urn:schemas-upnp-org:service:AVTransport:1#Stop"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:Stop xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"/></s:Body></s:Envelope>');
      resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      await stopFuture;
    });

    test('enforces Pairing PIN authentication when enabled (DMR-05)', () async {
      server.requirePin = true;
      server.pairingPin = '654321';

      // 1. Without PIN -> rejected with 500 SOAP Fault
      var req = await client.postUrl(
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/control'));
      req.headers.set('SOAPACTION',
          '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><CurrentURI>http://example.com/test.mp4</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>');
      var resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.internalServerError));
      var body = await utf8.decodeStream(resp);
      expect(body, contains('Invalid Pairing PIN'));

      // 2. With valid PIN -> accepted
      req = await client.postUrl(Uri.parse(
          'http://127.0.0.1:${server.port}/AVTransport/control?pin=654321'));
      req.headers.set('SOAPACTION',
          '"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI"');
      req.write(
          '<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/"><s:Body><u:SetAVTransportURI xmlns:u="urn:schemas-upnp-org:service:AVTransport:1"><CurrentURI>http://example.com/test.mp4</CurrentURI></u:SetAVTransportURI></s:Body></s:Envelope>');
      resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
    });

    test('supports GENA event subscription lifecycle (DMR-03)', () async {
      final req = await client.openUrl('SUBSCRIBE',
          Uri.parse('http://127.0.0.1:${server.port}/AVTransport/events'));
      final resp = await req.close();
      expect(resp.statusCode, equals(HttpStatus.ok));
      expect(resp.headers.value('SID'), startsWith('uuid:juying-sub-'));
      expect(resp.headers.value('TIMEOUT'), equals('Second-1800'));
    });
  });
}
