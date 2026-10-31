import 'package:flutter_test/flutter_test.dart';
import 'package:subtitle_studio/services/reveal.dart';

void main() {
  test('Windows 定位文件：路径独立于选择开关，统一混用的分隔符', () {
    expect(
      Reveal.windowsArguments(
        r'C:\Users\用户\My Videos/合并结果, 01.mp4',
        select: true,
      ),
      ['/select,', r'C:\Users\用户\My Videos\合并结果, 01.mp4'],
    );
  });

  test('Windows 网络共享路径保留 UNC 前缀和特殊字符', () {
    expect(
      Reveal.windowsArguments('//server/share/资料 & 备份/a.mp4', select: true),
      ['/select,', r'\\server\share\资料 & 备份\a.mp4'],
    );
  });

  test('Windows 打开目录（含产物缺失的回退）不传选择开关', () {
    expect(
      Reveal.windowsArguments('D:/My Videos/输出'),
      [r'D:\My Videos\输出'],
    );
    expect(Reveal.windowsArguments('D:/'), [r'D:\']);
  });
}
