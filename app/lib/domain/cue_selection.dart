/// 字幕表的选区：焦点行、选中集合与 Shift 锚点，位置都是文档下标。
///
/// 三者放在一个不可变对象里，由编辑器控制器独占：分开存的话，每处改
/// 焦点的地方都得记着同步集合，漏一处就会出现「焦点不在选区里」。
///
/// 不变量：[positions] 非空，[focus] 恒在其中。选区不能被取消到空 ——
/// 检视面板永远要有一条可看。
///
/// [toggle] 与 [extendTo] 的目标行应当在 `order`（可见行）里 —— 点击只会
/// 落在看得见的行上。万一不在，扩选退回单选，切换照常进行。
class CueSelection {
  const CueSelection.single(int position)
    : focus = position,
      anchor = position,
      _positions = null;

  CueSelection._(this.focus, this.anchor, Set<int> positions)
    : _positions = Set.unmodifiable(positions);

  /// 检视面板与播放跟随的那一条。
  final int focus;

  /// Shift+点击的起点：最近一次普通点击或 ⌘/Ctrl+点击的行。
  final int anchor;

  /// 单选时为 null，省得每次单选都分配一个集合。
  final Set<int>? _positions;

  Set<int> get positions => _positions ?? {focus};

  int get length => _positions?.length ?? 1;

  bool get isMultiple => length > 1;

  bool contains(int position) =>
      _positions?.contains(position) ?? position == focus;

  /// ⌘/Ctrl+点击：切换 [position] 的选中。[order] 是可见行按显示顺序的
  /// 文档下标，用来在取消焦点行时挑下一个焦点。
  CueSelection toggle(int position, List<int> order) {
    final current = positions;
    if (!current.contains(position)) {
      return CueSelection._(position, position, {...current, position});
    }
    if (current.length == 1) return this;
    final rest = {...current}..remove(position);
    var focus = this.focus;
    if (focus == position) focus = _nearest(position, rest, order);
    // 锚点落在刚取消的行上，与 Finder、资源管理器一致。
    return CueSelection._(focus, position, rest);
  }

  /// Shift+点击：选区换成锚点到 [position] 之间的可见行（含两端）。
  /// 锚点被筛掉了就没有「之间」可言，退回单选。
  CueSelection extendTo(int position, List<int> order) {
    final from = order.indexOf(anchor);
    final to = order.indexOf(position);
    if (from < 0 || to < 0) return CueSelection.single(position);
    final lo = from < to ? from : to;
    final hi = from < to ? to : from;
    return CueSelection._(position, anchor, {...order.sublist(lo, hi + 1)});
  }

  /// 只保留 [keep] 里的行，比如当前看得见的行。焦点不在 [keep] 里时
  /// 退回只选焦点这一条 —— 焦点是检视面板正在看的那条，不能凭空换掉。
  /// 锚点不在 [keep] 里时换成焦点，否则 Shift+点击找不到起点，会把还
  /// 看得见的选中行一起丢掉。单选时也一样：⌘ 取消掉另一条后锚点落在
  /// 被取消的行上，那一行随后可能被筛掉。
  CueSelection restrictTo(Set<int> keep) {
    if (!isMultiple) {
      return keep.contains(this.anchor) ? this : CueSelection.single(focus);
    }
    if (!keep.contains(focus)) return CueSelection.single(focus);
    final rest = positions.where(keep.contains).toSet();
    final anchor = keep.contains(this.anchor) ? this.anchor : focus;
    if (rest.length == positions.length && anchor == this.anchor) return this;
    if (rest.length == 1) return CueSelection.single(focus);
    return CueSelection._(focus, anchor, rest);
  }

  /// 取消焦点行后的新焦点：可见顺序里往后最近的选中行，没有就往前找；
  /// 都不可见就取文档里最靠前的一条。
  static int _nearest(int removed, Set<int> rest, List<int> order) {
    final at = order.indexOf(removed);
    if (at >= 0) {
      for (var i = at + 1; i < order.length; i++) {
        if (rest.contains(order[i])) return order[i];
      }
      for (var i = at - 1; i >= 0; i--) {
        if (rest.contains(order[i])) return order[i];
      }
    }
    return rest.reduce((a, b) => a < b ? a : b);
  }

  @override
  bool operator ==(Object other) =>
      other is CueSelection &&
      other.focus == focus &&
      other.anchor == anchor &&
      other.length == length &&
      other.positions.containsAll(positions);

  @override
  int get hashCode =>
      Object.hash(focus, anchor, Object.hashAllUnordered(positions));

  @override
  String toString() =>
      'CueSelection(focus: $focus, anchor: $anchor, '
      'positions: ${positions.toList()..sort()})';
}
