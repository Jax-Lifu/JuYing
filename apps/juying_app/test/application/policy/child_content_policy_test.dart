import 'package:flutter_test/flutter_test.dart';
import 'package:juying/application/policy/child_content_policy.dart';
import 'package:juying/domain/models/unified_media.dart';

void main() {
  test('儿童档案仅允许保守的动画片和少儿分类', () {
    expect(
      ChildContentPolicy.allowsCategory(
        MediaCategory.animation,
        isChildProfile: true,
      ),
      isTrue,
    );
    expect(
      ChildContentPolicy.allowsCategory(
        MediaCategory.drama,
        isChildProfile: true,
      ),
      isFalse,
    );
    expect(
      ChildContentPolicy.allowsCategory(
        MediaCategory.drama,
        isChildProfile: false,
      ),
      isTrue,
    );
  });
}
