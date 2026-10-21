import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:juying/features/tvbox/services/tvbox_config_service.dart';

void main() {
  test('preserves commas and closing delimiters inside quoted rules', () {
    const rules = {
      'regex': r'\d{1,}',
      'bracket': 'value,]',
      'spaces': 'value,   }',
      'escaped': 'quote: " and slash: \\ then ,}',
      'url': 'https://example.test/path,]//not-a-comment',
    };

    final cleaned = TvBoxConfigService.sanitizeJson(jsonEncode(rules));

    expect(jsonDecode(cleaned), rules);
  });

  test('removes actual trailing commas through comments without changing rules',
      () {
    const document = r'''
    {
      // A rule can contain the same delimiters as relaxed JSON syntax.
      "rules": ["{1,}", "value,]", /* trailing item */ ],
      "nested": {"escaped": "quote: \" then ,}", // trailing field
      }, /* trailing object */
    }
    ''';

    final cleaned = TvBoxConfigService.sanitizeJson(document);

    expect(jsonDecode(cleaned), {
      'rules': ['{1,}', 'value,]'],
      'nested': {'escaped': 'quote: " then ,}'},
    });
  });
}
