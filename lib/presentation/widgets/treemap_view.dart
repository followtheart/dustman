import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../core/utils/file_size_formatter.dart';
import '../../domain/entities/disk_node.dart';

/// 一个简易的 squarified treemap。
///
/// - 仅渲染 `root.children`，不会无限递归（点击进入子节点由外部状态控制）。
/// - 面积与 `node.size` 成正比。
/// - 颜色按 hash(name) 在 HSL 环上取，深浅适配明/暗模式。
class TreemapView extends StatefulWidget {
  const TreemapView({
    super.key,
    required this.root,
    required this.onTap,
    required this.onSecondaryTap,
    this.hoverPathChanged,
  });

  final DiskNode root;
  final ValueChanged<DiskNode> onTap;
  final VoidCallback onSecondaryTap;

  /// 鼠标 hover 时的当前 tile（用于状态栏显示）。
  final ValueChanged<DiskNode?>? hoverPathChanged;

  @override
  State<TreemapView> createState() => _TreemapViewState();
}

class _TreemapViewState extends State<TreemapView> {
  DiskNode? _hover;

  @override
  Widget build(BuildContext context) {
    final children =
        (widget.root.children ?? const <DiskNode>[]).where((c) => c.size > 0).toList();

    return LayoutBuilder(
      builder: (context, constraints) {
        if (children.isEmpty || widget.root.size <= 0) {
          return Center(
            child: Text(
              widget.root.isLeaf
                  ? '该目录无子项'
                  : '该目录为空',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
            ),
          );
        }
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final tiles = _squarify(children, Rect.fromLTWH(0, 0, w, h));

        return Listener(
          onPointerDown: (e) {
            if (e.kind == PointerDeviceKind.mouse &&
                e.buttons == kSecondaryMouseButton) {
              widget.onSecondaryTap();
            }
          },
          child: MouseRegion(
            onExit: (_) {
              if (_hover != null) {
                setState(() => _hover = null);
                widget.hoverPathChanged?.call(null);
              }
            },
            child: Stack(
              children: [
                for (final t in tiles)
                  Positioned.fromRect(
                    rect: t.rect,
                    child: _TreemapTile(
                      node: t.node,
                      parentBytes: widget.root.size,
                      highlighted: identical(_hover, t.node),
                      onEnter: () {
                        setState(() => _hover = t.node);
                        widget.hoverPathChanged?.call(t.node);
                      },
                      onTap: () => widget.onTap(t.node),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  List<_PlacedTile> _squarify(List<DiskNode> nodes, Rect area) {
    if (nodes.isEmpty || area.width <= 0 || area.height <= 0) return const [];
    final total = nodes.fold<int>(0, (s, n) => s + n.size);
    if (total <= 0) return const [];

    final out = <_PlacedTile>[];
    _squarifyRecursive(
      List<DiskNode>.from(nodes),
      total,
      area,
      out,
    );
    return out;
  }

  void _squarifyRecursive(
    List<DiskNode> remaining,
    int totalSize,
    Rect area,
    List<_PlacedTile> out,
  ) {
    if (remaining.isEmpty || totalSize <= 0) return;
    if (area.width <= 0.5 || area.height <= 0.5) return;

    final shortSide = math.min(area.width, area.height);
    final row = <DiskNode>[];
    var rowSize = 0;
    double bestRatio = double.infinity;

    var idx = 0;
    while (idx < remaining.length) {
      final candidate = remaining[idx];
      final newRowSize = rowSize + candidate.size;
      final ratio = _worstAspectRatio(
        [...row, candidate],
        shortSide,
        newRowSize,
        totalSize,
        area,
      );
      if (ratio <= bestRatio) {
        row.add(candidate);
        rowSize = newRowSize;
        bestRatio = ratio;
        idx++;
      } else {
        break;
      }
    }

    if (row.isEmpty) {
      // 极端情况下塞一个
      row.add(remaining.first);
      rowSize = remaining.first.size;
      idx = 1;
    }

    // 布局这一行
    final remainingRect = _layoutRow(row, rowSize, totalSize, area, out);

    final next = remaining.sublist(idx);
    final nextTotal = totalSize - rowSize;
    if (next.isNotEmpty && nextTotal > 0) {
      _squarifyRecursive(next, nextTotal, remainingRect, out);
    }
  }

  double _worstAspectRatio(
    List<DiskNode> row,
    double shortSide,
    int rowSize,
    int totalSize,
    Rect area,
  ) {
    if (rowSize <= 0) return double.infinity;
    final areaArea = area.width * area.height;
    if (areaArea <= 0) return double.infinity;
    final rowArea = areaArea * rowSize / totalSize;
    final longSide = rowArea / shortSide;
    double worst = 0;
    for (final n in row) {
      final tileArea = areaArea * n.size / totalSize;
      if (tileArea <= 0 || longSide <= 0) continue;
      final w = tileArea / longSide;
      final r = math.max(longSide / w, w / longSide);
      if (r > worst) worst = r;
    }
    return worst;
  }

  Rect _layoutRow(
    List<DiskNode> row,
    int rowSize,
    int totalSize,
    Rect area,
    List<_PlacedTile> out,
  ) {
    final areaArea = area.width * area.height;
    if (areaArea <= 0 || rowSize <= 0) return area;

    final horizontal = area.width >= area.height;
    final rowFraction = rowSize / totalSize;

    if (horizontal) {
      final rowH = area.height * rowFraction;
      double x = area.left;
      for (final n in row) {
        final w = area.width * (n.size / rowSize);
        out.add(_PlacedTile(
          n,
          Rect.fromLTWH(x, area.top, w, rowH),
        ));
        x += w;
      }
      return Rect.fromLTWH(
        area.left,
        area.top + rowH,
        area.width,
        area.height - rowH,
      );
    } else {
      final rowW = area.width * rowFraction;
      double y = area.top;
      for (final n in row) {
        final h = area.height * (n.size / rowSize);
        out.add(_PlacedTile(
          n,
          Rect.fromLTWH(area.left, y, rowW, h),
        ));
        y += h;
      }
      return Rect.fromLTWH(
        area.left + rowW,
        area.top,
        area.width - rowW,
        area.height,
      );
    }
  }
}

class _PlacedTile {
  _PlacedTile(this.node, this.rect);
  final DiskNode node;
  final Rect rect;
}

class _TreemapTile extends StatelessWidget {
  const _TreemapTile({
    required this.node,
    required this.parentBytes,
    required this.highlighted,
    required this.onEnter,
    required this.onTap,
  });

  final DiskNode node;
  final int parentBytes;
  final bool highlighted;
  final VoidCallback onEnter;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    final color = _colorFor(node.name, brightness);
    final border = highlighted
        ? Theme.of(context).colorScheme.primary
        : Theme.of(context).colorScheme.outline.withOpacity(0.4);

    final percent =
        parentBytes <= 0 ? 0.0 : (node.size / parentBytes) * 100;

    return MouseRegion(
      onEnter: (_) => onEnter(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.all(1),
          decoration: BoxDecoration(
            color: color,
            border: Border.all(color: border, width: highlighted ? 2 : 0.5),
            borderRadius: BorderRadius.circular(3),
          ),
          child: _TileLabel(
            name: node.name,
            sizeText: FileSizeFormatter.format(node.size),
            percent: percent,
            isDirectory: node.isDirectory,
            brightness: brightness,
          ),
        ),
      ),
    );
  }

  static Color _colorFor(String name, Brightness brightness) {
    final hash = name.codeUnits.fold<int>(0, (h, c) => (h * 131 + c) & 0xFFFFFF);
    final hue = (hash % 360).toDouble();
    final hsl = brightness == Brightness.dark
        ? HSLColor.fromAHSL(1.0, hue, 0.55, 0.35)
        : HSLColor.fromAHSL(1.0, hue, 0.45, 0.78);
    return hsl.toColor();
  }
}

class _TileLabel extends StatelessWidget {
  const _TileLabel({
    required this.name,
    required this.sizeText,
    required this.percent,
    required this.isDirectory,
    required this.brightness,
  });

  final String name;
  final String sizeText;
  final double percent;
  final bool isDirectory;
  final Brightness brightness;

  @override
  Widget build(BuildContext context) {
    final fg = brightness == Brightness.dark ? Colors.white : Colors.black87;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 36 || constraints.maxHeight < 22) {
          // 太小就不显示文字
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    isDirectory ? Icons.folder : Icons.insert_drive_file,
                    size: 12,
                    color: fg,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Text(
                      name,
                      style: TextStyle(
                        color: fg,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              if (constraints.maxHeight >= 40)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    '$sizeText  ·  ${percent.toStringAsFixed(1)}%',
                    style: TextStyle(
                      color: fg.withOpacity(0.85),
                      fontSize: 10,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
