import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

import 'package:juying/core/models/device_profile.dart';
import 'package:juying/features/cast/services/dlna_cast_service.dart';

void main() {
  group('DlnaCastService Tests', () {
    test('casts query-string URLs as XML text without altering the URL',
        () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
                Response<void>(requestOptions: options, statusCode: 200));
          },
        ),
      );
      final service = DlnaCastService(dio: dio);
      const mediaUrl = 'https://media.test/video?token=abc&quality=hd';
      expect(
        await service.castVideo(
          device: const DlnaDevice(
            id: 'test-tv',
            name: 'Test TV',
            controlUrl: 'http://tv.test/control',
            location: 'http://tv.test/description.xml',
          ),
          mediaUrl: mediaUrl,
          title: 'Test video',
        ),
        isTrue,
      );
      expect(requests, hasLength(2));
      expect(requests.first.data, contains('token=abc&amp;quality=hd'));
      final setUri = XmlDocument.parse(requests.first.data as String);
      expect(setUri.findAllElements('CurrentURI').single.innerText, mediaUrl);
      expect(
          XmlDocument.parse(requests.last.data as String)
              .rootElement
              .name
              .local,
          'Envelope');
    });

    test(
        'pause, stop, seek, and setVolume send valid UPnP SOAP requests (CAST-02)',
        () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));
      final requests = <RequestOptions>[];
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            requests.add(options);
            handler.resolve(
              Response<void>(requestOptions: options, statusCode: 200),
            );
          },
        ),
      );

      final service = DlnaCastService(dio: dio);
      const testDevice = DlnaDevice(
        id: 'test-tv',
        name: 'Living Room TV',
        controlUrl: 'http://192.168.1.50:8080/avt_control',
        renderingControlUrl: 'http://192.168.1.50:8080/rc_control',
        location: 'http://192.168.1.50:8080/desc.xml',
      );

      // Pause
      expect(await service.pauseVideo(testDevice), isTrue);
      expect(requests.last.headers['SOAPAction'],
          '"urn:schemas-upnp-org:service:AVTransport:1#Pause"');

      // Stop
      expect(await service.stopVideo(testDevice), isTrue);
      expect(requests.last.headers['SOAPAction'],
          '"urn:schemas-upnp-org:service:AVTransport:1#Stop"');

      // Seek to 01:23:45
      expect(
        await service.seekVideo(
          testDevice,
          const Duration(hours: 1, minutes: 23, seconds: 45),
        ),
        isTrue,
      );
      expect(requests.last.headers['SOAPAction'],
          '"urn:schemas-upnp-org:service:AVTransport:1#Seek"');
      expect(requests.last.data, contains('<Target>01:23:45</Target>'));

      // Set volume (clamped to 0-100)
      expect(await service.setVolume(testDevice, 75), isTrue);
      expect(requests.last.path, 'http://192.168.1.50:8080/rc_control');
      expect(requests.last.headers['SOAPAction'],
          '"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume"');
      expect(requests.last.data, contains('<DesiredVolume>75</DesiredVolume>'));
    });

    test(
        'getPositionInfo correctly parses track duration and rel time (CAST-02)',
        () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));

      const mockResponseXml = '''
<?xml version="1.0" encoding="utf-8"?>
<s:Envelope xmlns:s="http://schemas.xmlsoap.org/soap/envelope/">
  <s:Body>
    <u:GetPositionInfoResponse xmlns:u="urn:schemas-upnp-org:service:AVTransport:1">
      <TrackDuration>01:45:30</TrackDuration>
      <RelTime>00:15:20</RelTime>
    </u:GetPositionInfoResponse>
  </s:Body>
</s:Envelope>
''';

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: mockResponseXml,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      final service = DlnaCastService(dio: dio);
      const testDevice = DlnaDevice(
        id: 'test-tv',
        name: 'Living Room TV',
        controlUrl: 'http://192.168.1.50:8080/avt_control',
        location: 'http://192.168.1.50:8080/desc.xml',
      );

      final pos = await service.getPositionInfo(testDevice);
      expect(pos, isNotNull);
      expect(pos!.trackDuration,
          const Duration(hours: 1, minutes: 45, seconds: 30));
      expect(pos.relTime, const Duration(minutes: 15, seconds: 20));
    });

    test(
        'fetches device from manual IP and matches DeviceProfile (CAST-01 & CAST-04)',
        () async {
      final dio = Dio();
      addTearDown(() => dio.close(force: true));

      const mockDescXml = '''
<?xml version="1.0"?>
<root xmlns="urn:schemas-upnp-org:device-1-0">
  <device>
    <deviceType>urn:schemas-upnp-org:device:MediaRenderer:1</deviceType>
    <friendlyName>Mi TV 4A 65</friendlyName>
    <manufacturer>Xiaomi</manufacturer>
    <modelName>L65M5-AZ</modelName>
    <serviceList>
      <service>
        <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
        <controlURL>/upnp/control/AVTransport</controlURL>
      </service>
      <service>
        <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
        <controlURL>/upnp/control/RenderingControl</controlURL>
      </service>
    </serviceList>
  </device>
</root>
''';

      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (options, handler) {
            handler.resolve(
              Response<String>(
                requestOptions: options,
                data: mockDescXml,
                statusCode: 200,
              ),
            );
          },
        ),
      );

      const xiaomiProfile = DeviceProfile(
        id: 'xiaomi-tv',
        manufacturer: 'Xiaomi',
        quirks: DeviceQuirks(
          supportsRange: true,
          supportsMkv: false,
          supportsHevc: true,
        ),
      );

      final service = DlnaCastService(
        dio: dio,
        profiles: [xiaomiProfile],
      );

      final dev = await service.fetchDeviceFromIp('192.168.1.88', port: 8080);
      expect(dev, isNotNull);
      expect(dev!.name, 'Mi TV 4A 65');
      expect(
          dev.controlUrl, 'http://192.168.1.88:8080/upnp/control/AVTransport');
      expect(dev.renderingControlUrl,
          'http://192.168.1.88:8080/upnp/control/RenderingControl');
      expect(dev.profile, isNotNull);
      expect(dev.profile!.id, 'xiaomi-tv');
      expect(dev.profile!.quirks.supportsMkv, isFalse);
    });
  });
}
