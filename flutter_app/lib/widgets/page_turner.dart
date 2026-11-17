import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Style d'animation entre deux pages.
enum PageTurnStyle { curl, slide }

/// Feuilleteur de pages façon liseuse : la page tourne autour de la reliure
/// (bord gauche) en révélant la suivante dessous, ou glisse simplement.
///
/// Au plus deux pages sont construites à la fois (celle qui tourne et celle
/// dessous) — indispensable ici, chaque phrase du livre portant une
/// GlobalKey qui ne doit exister qu'une fois dans l'arbre.
class PageTurner extends StatefulWidget {
  final int itemCount;
  final int initialIndex;
  final IndexedWidgetBuilder itemBuilder;
  final ValueChanged<int> onPageChanged;
  final PageTurnStyle style;
  final Color pageColor;

  const PageTurner({
    super.key,
    required this.itemCount,
    required this.initialIndex,
    required this.itemBuilder,
    required this.onPageChanged,
    required this.style,
    required this.pageColor,
  });

  @override
  State<PageTurner> createState() => PageTurnerState();
}

class PageTurnerState extends State<PageTurner> with SingleTickerProviderStateMixin {
  late int _index = widget.initialIndex.clamp(0, math.max(0, widget.itemCount - 1));
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 420),
  );

  /// +1 : on tourne vers la page suivante ; -1 : vers la précédente ; 0 : rien.
  int _dir = 0;
  double _dragDx = 0;

  int get index => _index;

  @override
  void didUpdateWidget(PageTurner old) {
    super.didUpdateWidget(old);
    if (_index >= widget.itemCount) _index = math.max(0, widget.itemCount - 1);
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  bool get _busy => _dir != 0;

  Future<void> next() => _turn(1);
  Future<void> previous() => _turn(-1);

  /// Va à la page [i] : tourne la page si elle est voisine, sinon saute.
  Future<void> goTo(int i, {bool animate = true}) async {
    i = i.clamp(0, math.max(0, widget.itemCount - 1));
    if (i == _index) return;
    if (animate && (i - _index).abs() == 1 && !_busy) {
      await _turn(i - _index);
      return;
    }
    _anim.stop();
    setState(() {
      _dir = 0;
      _index = i;
    });
    widget.onPageChanged(i);
  }

  Future<void> _turn(int dir, {double from = 0}) async {
    if (_busy) return;
    final target = _index + dir;
    if (target < 0 || target >= widget.itemCount) return;
    setState(() => _dir = dir);
    _anim.value = from;
    await _anim.animateTo(1, curve: Curves.easeInOutCubic);
    _finish(true);
  }

  void _finish(bool completed) {
    if (!mounted) return;
    setState(() {
      if (completed) _index += _dir;
      _dir = 0;
      _anim.value = 0;
    });
    if (completed) widget.onPageChanged(_index);
  }

  // ── Glisser du doigt ─────────────────────────────────────────────────────

  void _onDragStart(DragStartDetails d) {
    if (_busy) return;
    _dragDx = 0;
  }

  void _onDragUpdate(DragUpdateDetails d, double width) {
    _dragDx += d.delta.dx;
    if (_dir == 0) {
      final dir = _dragDx < 0 ? 1 : -1;
      final target = _index + dir;
      if (_dragDx.abs() < 4 || target < 0 || target >= widget.itemCount) return;
      setState(() => _dir = dir);
    }
    final t = (-_dragDx * _dir / width).clamp(0.0, 1.0);
    _anim.value = t;
  }

  Future<void> _onDragEnd(DragEndDetails d) async {
    if (_dir == 0) return;
    final v = d.primaryVelocity ?? 0; // px/s, négatif = vers la gauche
    final flung = v.abs() > 300 && (v < 0) == (_dir > 0);
    final complete = flung || _anim.value > 0.4;
    if (complete) {
      await _anim.animateTo(1, curve: Curves.easeOutCubic);
    } else {
      await _anim.animateBack(0, curve: Curves.easeOutCubic);
    }
    _finish(complete);
  }

  // ── Rendu ────────────────────────────────────────────────────────────────

  /// Page qui se décolle comme du papier : le bord libre part de la droite
  /// et balaie l'écran vers la gauche en repliant la page sur elle-même
  /// (on voit son verso), avec une ombre sur la page dessous. En arrière,
  /// le même geste à l'envers : la page revient de la gauche vers la droite.
  Widget _peel(int over, double progress, double w) {
    // Pli vertical en x = fold ; le bord de la page, replié, est en x = edge.
    final fold = w * (1 - progress);
    final edge = w * (1 - 2 * progress);
    final flapLeft = math.max(0.0, edge);
    final flapWidth = math.max(0.0, fold - flapLeft);
    final back = Color.alphaBlend(Colors.black.withValues(alpha: 0.06), widget.pageColor);
    return Stack(children: [
      // Recto encore à plat, à gauche du pli.
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: fold,
        child: ClipRect(
          child: OverflowBox(
            alignment: Alignment.topLeft,
            minWidth: w,
            maxWidth: w,
            child: _page(over),
          ),
        ),
      ),
      // Ombre portée sur la page dessous, juste à droite du pli.
      Positioned(
        left: fold,
        top: 0,
        bottom: 0,
        width: 36,
        child: IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: [
                Colors.black.withValues(alpha: 0.28 * (1 - progress)),
                Colors.black.withValues(alpha: 0.0),
              ]),
            ),
          ),
        ),
      ),
      // Verso replié : couleur du papier, plus sombre près du pli.
      if (flapWidth > 0)
        Positioned(
          left: flapLeft,
          top: 0,
          bottom: 0,
          width: flapWidth,
          child: IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    back,
                    Color.alphaBlend(Colors.black.withValues(alpha: 0.10), back),
                    Color.alphaBlend(Colors.black.withValues(alpha: 0.22), back),
                  ],
                  stops: const [0, 0.7, 1],
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    blurRadius: 12,
                    offset: const Offset(-3, 0),
                  ),
                ],
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _page(int i) => KeyedSubtree(
        key: ValueKey('page_$i'),
        child: ColoredBox(color: widget.pageColor, child: widget.itemBuilder(context, i)),
      );

  @override
  Widget build(BuildContext context) {
    if (widget.itemCount == 0) return const SizedBox.shrink();
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      return GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragStart: _onDragStart,
        onHorizontalDragUpdate: (d) => _onDragUpdate(d, w),
        onHorizontalDragEnd: _onDragEnd,
        child: AnimatedBuilder(
          animation: _anim,
          builder: (context, _) {
            if (_dir == 0) {
              return Stack(children: [Positioned.fill(child: _page(_index))]);
            }
            final t = _anim.value;
            // En avant : la page actuelle part, la suivante est dessous.
            // En arrière : la précédente revient par-dessus la page actuelle.
            final under = _dir > 0 ? _index + 1 : _index;
            final over = _dir > 0 ? _index : _index - 1;
            final progress = _dir > 0 ? t : 1 - t; // 0 = posée, 1 = tournée
            return Stack(children: [
              Positioned.fill(
                child: Stack(children: [
                  Positioned.fill(child: _page(under)),
                  // Glissement : la page dessous sort doucement de l'ombre.
                  if (widget.style == PageTurnStyle.slide)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: ColoredBox(
                        color: Colors.black.withValues(alpha: 0.25 * (1 - progress)),
                      ),
                    ),
                  ),
                ]),
              ),
              Positioned.fill(
                child: widget.style == PageTurnStyle.slide
                    ? Transform.translate(
                        offset: Offset(-w * progress, 0),
                        child: _page(over),
                      )
                    : _peel(over, progress, w),
              ),
            ]);
          },
        ),
      );
    });
  }
}
