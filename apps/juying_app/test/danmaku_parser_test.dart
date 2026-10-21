import 'package:flutter_test/flutter_test.dart';
import 'package:juying/core/danmaku/danmaku_models.dart';
import 'package:juying/core/danmaku/danmaku_parser.dart';

void main() {
  group('DanmakuParser Tests', () {
    test('parses Bilibili XML comments correctly', () {
      const xml = '''
<?xml version="1.0" encoding="UTF-8"?>
<i>
  <d p="12.345,1,25,16777215,1620000000,0,user1,0">前方高能预警！</d>
  <d p="5.5,5,18,16711680,1620000000,0,user2,0">顶部固定弹幕测试</d>
  <d p="20.0,4,22,65280,1620000000,0,user3,0">底部固定弹幕测试</d>
</i>
''';

      final list = DanmakuParser.parseBilibiliXml(xml);
      expect(list.length, 3);

      // Verify sorting by timestamp
      expect(list[0].text, '顶部固定弹幕测试');
      expect(list[0].timestampMs, 5500);
      expect(list[0].type, DanmakuType.topFixed);

      expect(list[1].text, '前方高能预警！');
      expect(list[1].timestampMs, 12345);
      expect(list[1].type, DanmakuType.rolling);

      expect(list[2].text, '底部固定弹幕测试');
      expect(list[2].timestampMs, 20000);
      expect(list[2].type, DanmakuType.bottomFixed);
    });

    test('parses DPlayer JSON comments correctly', () {
      const jsonStr = '''
[
  [10.5, 0, 16777215, "author1", "DPlayer 滚动弹幕"],
  [2.1, 1, 16711680, "author2", "DPlayer 顶部弹幕"]
]
''';

      final list = DanmakuParser.parseDplayerJson(jsonStr);
      expect(list.length, 2);

      expect(list[0].text, 'DPlayer 顶部弹幕');
      expect(list[0].timestampMs, 2100);
      expect(list[0].type, DanmakuType.topFixed);

      expect(list[1].text, 'DPlayer 滚动弹幕');
      expect(list[1].timestampMs, 10500);
      expect(list[1].type, DanmakuType.rolling);
    });
  });
}
