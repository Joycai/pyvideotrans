/// 把升序的行号合并成区间：`001–004、009、015–021`。超过 [maxRuns] 段
/// 后面写「等」—— 面板只有一行，列全了也看不完。
String selectionRanges(List<int> numbers, {int maxRuns = 6}) {
  String n(int v) => v.toString().padLeft(3, '0');
  final runs = <String>[];
  var i = 0;
  while (i < numbers.length) {
    var j = i;
    while (j + 1 < numbers.length && numbers[j + 1] == numbers[j] + 1) {
      j++;
    }
    runs.add(i == j ? n(numbers[i]) : '${n(numbers[i])}–${n(numbers[j])}');
    i = j + 1;
  }
  if (runs.length <= maxRuns) return runs.join('、');
  return '${runs.take(maxRuns).join('、')} 等';
}
