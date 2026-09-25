import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/domain/enum_by_name.dart';
import 'package:subtitle_studio/domain/task.dart';

void main() {
  // 存档里的名字可能是旧版本写的或被手改过，认不出来要给 null 由调用方回落，
  // 不能像 SDK 的 values.byName 那样抛出来拖垮整份存档。
  test('认得的名字返回枚举，认不出来或不是字符串返回 null', () {
    expect(TaskStatus.values.tryByName('done'), TaskStatus.done);
    expect(TaskStatus.values.tryByName('乱写'), isNull);
    expect(TaskStatus.values.tryByName(null), isNull);
    expect(TaskStatus.values.tryByName(3), isNull);
  });
}
