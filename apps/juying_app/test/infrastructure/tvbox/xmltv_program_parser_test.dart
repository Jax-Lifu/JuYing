import 'package:flutter_test/flutter_test.dart';
import 'package:juying/infrastructure/tvbox/xmltv_program_parser.dart';

void main() {
  test('XMLTV 仅返回指定频道的有效节目并按开始时间排序', () {
    final programs = XmltvProgramParser.parse(
      '''
<tv>
  <programme channel="other" start="20260820100000 +0800" stop="20260820110000 +0800"><title>忽略</title></programme>
  <programme channel="CCTV1" start="20260820120000 +0800" stop="20260820130000 +0800"><title>午间新闻</title><desc>新闻 &amp; 资讯</desc></programme>
  <programme channel="CCTV1" start="20260820100000 +0800" stop="20260820110000 +0800"><title>早间新闻</title></programme>
</tv>
''',
      sourceId: 'tvbox-test',
      sourceItemId: 'channel-1',
      channelId: 'CCTV1',
    );

    expect(programs.map((item) => item.title), ['早间新闻', '午间新闻']);
    expect(programs.last.description, '新闻 & 资讯');
    expect(programs.singleWhere((item) => item.title == '早间新闻').sourceId,
        'tvbox-test');
  });
}
