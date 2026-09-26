import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/bars.dart';
import '../core/fmt.dart';
import '../core/indicators.dart' as ind;
import '../core/rule.dart' as rule;
import 'palette.dart';

enum ChartType { candle, volume, stoch, rsi, cci }

/// Bars on screen by default: about three months of trading days.
const int chartWindow = 63, minBars = 20;

/// Zoom, scroll and the selected day, shared by every panel of one stock so they move together.
class ChartGroup extends ChangeNotifier {
  int visible = chartWindow; // bars on screen
  int end = 1 << 30; // one past the last bar on screen; huge = pinned to the latest
  int selected = -1;

  void redraw() => notifyListeners();

  void reset() {
    visible = chartWindow;
    end = 1 << 30;
    selected = -1;
    notifyListeners();
  }
}

/// Per bar marks from running the rule over every day, so the chart shows exactly what the
/// alerts would have said.
class _Marks {
  _Marks(Bars bars, rule.RuleConfig cfg) {
    final n = bars.size;
    goldLevel = List.filled(n, 0);
    deadLevel = List.filled(n, 0);
    goldStart = List.filled(n, 0);
    deadStart = List.filled(n, 0);
    goldPart = List.generate(n, (_) => List.filled(3, false));
    deadPart = List.generate(n, (_) => List.filled(3, false));
    goldCross = List.generate(n, (_) => List.filled(3, false));
    deadCross = List.generate(n, (_) => List.filled(3, false));
    final plain = cfg.plain();
    final s = bars.series;
    maBreak = ind.maBreakouts(s.ma, bars.close, bars.volume,
        up60: cfg.maUp60, up120: cfg.maUp120, spread: cfg.maSpread / 100);
    for (var i = 1; i < n; i++) {
      goldPart[i] = rule.golden(s.snap(i - 1), s.snap(i), cfg);
      deadPart[i] = rule.dead(s.snap(i - 1), s.snap(i), cfg);
      goldCross[i] = rule.golden(s.snap(i - 1), s.snap(i), plain);
      deadCross[i] = rule.dead(s.snap(i - 1), s.snap(i), plain);
    }
    for (var i = 1; i < n; i++) {
      final from = math.max(0, i - rule.history + 1);
      final seq = [for (var j = from; j <= i; j++) s.snap(j)];
      final m = rule.match(seq, cfg);
      goldLevel[i] = _level(m[0], cfg.need);
      deadLevel[i] = _level(m[1], cfg.need);
      goldStart[i] = _spanStart(i, m[0], goldPart, cfg.window);
      deadStart[i] = _spanStart(i, m[1], deadPart, cfg.window);
    }
  }

  late List<int> goldLevel, deadLevel, goldStart, deadStart;
  late List<List<bool>> goldPart, deadPart, goldCross, deadCross;

  /// Moving-average breakout days.
  late List<bool> maBreak;

  static int _level(List<bool> m, int need) {
    final c = rule.count(m);
    return c >= need ? c : 0;
  }

  /// First day inside the window on which one of the matched indicators crossed.
  static int _spanStart(int i, List<bool> matched, List<List<bool>> parts, int window) {
    var start = i;
    for (var j = math.max(1, i - window); j <= i; j++) {
      for (var p = 0; p < 3; p++) {
        if (matched[p] && parts[j][p]) start = math.min(start, j);
      }
    }
    return start;
  }
}

final Expando<Map<String, _Marks>> _marksCache = Expando();

_Marks _marksFor(Bars bars, rule.RuleConfig cfg) {
  final key = '${cfg.slow}${cfg.stochBand}${cfg.rsiBand}${cfg.cciBand}${cfg.stochLo}${cfg.stochHi}'
      '${cfg.rsiLo}${cfg.rsiHi}${cfg.cciLevel}${cfg.window}${cfg.pairs}${cfg.maUp60}${cfg.maUp120}${cfg.maSpread}';
  final map = _marksCache[bars] ??= {};
  return map[key] ??= _Marks(bars, cfg);
}

/// One panel of the stock detail: candles with moving averages, volume, or one oscillator.
/// Two fingers (or Ctrl + the mouse wheel) zoom; a sideways drag scrolls through time; a tap, a long
/// press then drag, or hovering the mouse shows a day's values; a double tap resets. A vertical
/// drag is left to the list, so the page still scrolls when the finger starts on a chart.
class ChartPanel extends StatefulWidget {
  const ChartPanel({
    super.key,
    required this.type,
    required this.bars,
    required this.cfg,
    required this.group,
    this.showMa = true,
    this.showSignals = true,
    this.compact = false,
  });

  final ChartType type;
  final Bars? bars;
  final rule.RuleConfig cfg;
  final ChartGroup group;
  final bool showMa, showSignals, compact;

  @override
  State<ChartPanel> createState() => _ChartPanelState();
}

class _ChartPanelState extends State<ChartPanel> {
  bool _crosshair = false;
  double _width = 1;
  int _pointers = 0;

  _Geometry? _geo() {
    final b = widget.bars;
    if (b == null || b.size < 2) return null;
    return _Geometry(b, widget.group, _width, widget.type, _gutter, MediaQuery.textScalerOf(context));
  }

  double get _gutter {
    final b = widget.bars;
    final scaler = MediaQuery.textScalerOf(context);
    double w = _textWidth('-100', scaler);
    if (b != null) {
      var max = 0.0;
      for (final h in b.high) {
        if (!h.isNaN && h > max) max = h;
      }
      w = math.max(w, _textWidth(axis(max * 1.1), scaler));
    }
    return w + 8;
  }

  double _textWidth(String s, TextScaler scaler) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: TextStyle(fontFamily: 'NotoSansKR', fontSize: scaler.scale(11))),
        textDirection: TextDirection.ltr)
      ..layout();
    return tp.width;
  }

  void _selectAt(double px) {
    final g = _geo();
    if (g == null) return;
    var i = g.from + ((px - g.left) / g.step).floor();
    i = i.clamp(g.from, g.to - 1);
    widget.group.selected = i;
    widget.group.redraw();
  }

  /// Keeps the day under the fingers in place while the number of bars on screen changes.
  void _zoom(double factor, double focusX) {
    final g = _geo();
    if (g == null) return;
    final b = widget.bars!;
    final before = g.shown;
    final after = math.max(math.min(minBars, b.size), math.min(b.size, (before / factor).round()));
    if (after == before) return;
    final ratio = ((focusX - g.left) / (g.right - g.left)).clamp(0.0, 1.0);
    final focus = g.from + ratio * before;
    widget.group.visible = after;
    widget.group.end = _clampEnd((focus - ratio * after).round() + after, after);
    widget.group.redraw();
  }

  /// Past the latest bar means "follow the latest".
  int _clampEnd(int end, int shown) {
    if (end >= widget.bars!.size) return 1 << 30;
    return math.max(shown, end);
  }

  double _panX = 0;
  int _panEnd = 0;

  /// Pinch: bars on screen and the scale when the fingers came down, and the bar (fractional)
  /// that was under them. Sizes come from the whole gesture's scale, so small moves add up
  /// instead of each rounding away to no change — which made the zoom stutter.
  bool _pinching = false;
  int _pinchShown = 0;
  double _pinchScale = 1, _pinchBar = 0;

  void _pinch(ScaleUpdateDetails d, _Geometry g) {
    if (!_pinching) {
      _pinching = true;
      _pinchShown = g.shown;
      _pinchScale = d.scale;
      _pinchBar = g.from + (d.localFocalPoint.dx - g.left) / g.step;
    }
    final size = widget.bars!.size;
    final shown = (_pinchShown * _pinchScale / d.scale).round().clamp(math.min(minBars, size), size).toInt();
    final ratio = ((d.localFocalPoint.dx - g.left) / (g.right - g.left)).clamp(0.0, 1.0);
    final end = _clampEnd((_pinchBar - ratio * shown).round() + shown, shown);
    if (shown == widget.group.visible && end == widget.group.end) return;
    widget.group.visible = shown;
    widget.group.end = end;
    widget.group.redraw();
  }

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final body = widget.type == ChartType.candle
        ? (widget.compact ? 150.0 : 230.0)
        : widget.type == ChartType.volume
            ? 70.0
            : 110.0;
    final height = body + scaler.scale(widget.type == ChartType.candle ? 46 : 16);
    final theme = Theme.of(context);
    final colors = _Colors(
      Palette.of(context),
      theme.colorScheme.onSurface,
      theme.colorScheme.onSurfaceVariant,
    );
    return LayoutBuilder(builder: (context, box) {
      _width = box.maxWidth;
      final chart = AnimatedBuilder(
        animation: widget.group,
        builder: (context, _) => CustomPaint(
          size: Size(box.maxWidth, height),
          painter: _ChartPainter(
            type: widget.type,
            bars: widget.bars,
            cfg: widget.cfg,
            group: widget.group,
            showMa: widget.showMa,
            showSignals: widget.showSignals,
            gutter: _gutter,
            scaler: scaler,
            colors: colors,
            marks: widget.bars != null && widget.showSignals && widget.bars!.size >= 2
                ? _marksFor(widget.bars!, widget.cfg)
                : null,
          ),
        ),
      );
      if (widget.bars == null || widget.bars!.size < 2) return SizedBox(height: height, child: chart);
      // Fingers on the screen, for pinch zoom. Only touches count: a mouse drag always pans.
      bool touch(PointerEvent e) => e.kind == PointerDeviceKind.touch;
      return Listener(
        onPointerDown: (e) => touch(e) ? _pointers++ : null,
        onPointerUp: (e) => touch(e) ? _pointers = math.max(0, _pointers - 1) : null,
        onPointerCancel: (e) => touch(e) ? _pointers = math.max(0, _pointers - 1) : null,
        onPointerSignal: (e) {
          // The wheel scrolls the page; Ctrl + wheel zooms the chart.
          if (e is PointerScrollEvent && HardwareKeyboard.instance.isControlPressed) {
            GestureBinding.instance.pointerSignalResolver.register(e, (event) {
              final s = event as PointerScrollEvent;
              _zoom(s.scrollDelta.dy < 0 ? 1.15 : 1 / 1.15, s.localPosition.dx);
            });
          }
        },
        child: MouseRegion(
          onHover: (e) => _selectAt(e.localPosition.dx),
          onExit: (_) {
            widget.group.selected = -1;
            widget.group.redraw();
          },
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => _selectAt(d.localPosition.dx),
            onDoubleTap: widget.group.reset,
            onLongPressStart: (d) {
              _crosshair = true;
              _selectAt(d.localPosition.dx);
            },
            onLongPressMoveUpdate: (d) => _selectAt(d.localPosition.dx),
            onLongPressEnd: (_) => _crosshair = false,
            onScaleStart: (d) {
              final g = _geo();
              _panX = d.localFocalPoint.dx;
              _panEnd = g?.to ?? 0;
              _pinching = false;
            },
            onScaleEnd: (_) => _pinching = false,
            onScaleUpdate: (d) {
              if (_crosshair) return;
              final g = _geo();
              if (g == null) return;
              if (d.pointerCount >= 2 || _pointers >= 2) {
                _pinch(d, g);
                _panX = d.localFocalPoint.dx;
                _panEnd = _geo()!.to;
              } else {
                // Back to one finger: carry on panning from here.
                _pinching = false;
                final end = _clampEnd(_panEnd + ((_panX - d.localFocalPoint.dx) / g.step).round(), g.shown);
                if (end == widget.group.end) return;
                widget.group.end = end;
                widget.group.redraw();
              }
            },
            child: SizedBox(height: height, child: chart),
          ),
        ),
      );
    });
  }
}

class _Colors {
  _Colors(this.p, this.onSurface, this.muted);

  final Palette p;
  final Color onSurface, muted;
}

class _Geometry {
  _Geometry(this.bars, this.group, this.width, this.type, this.gutter, this.scaler);

  final Bars bars;
  final ChartGroup group;
  final double width, gutter;
  final ChartType type;
  final TextScaler scaler;

  int get shown => math.max(2, math.min(group.visible, bars.size));

  /// One past the last bar on screen.
  int get to => math.max(shown, math.min(bars.size, group.end));

  int get from => to - shown;

  double get left => 4;

  /// Axis labels sit in a gutter to the right of the plot, never on top of it. The gutter is as
  /// wide as this stock's largest price label, so the days line up across panels.
  double get right => width - gutter;

  double get step => (right - left) / math.max(1, to - from);

  double x(int i) => left + (i - from + 0.5) * step;
}

class _ChartPainter extends CustomPainter {
  _ChartPainter({
    required this.type,
    required this.bars,
    required this.cfg,
    required this.group,
    required this.showMa,
    required this.showSignals,
    required this.gutter,
    required this.scaler,
    required this.colors,
    required this.marks,
  });

  final ChartType type;
  final Bars? bars;
  final rule.RuleConfig cfg;
  final ChartGroup group;
  final bool showMa, showSignals;
  final double gutter;
  final TextScaler scaler;
  final _Colors colors;
  final _Marks? marks;

  late Canvas c;
  late Size size;
  late _Geometry g;

  double sp(double v) => scaler.scale(v);

  double get top => type == ChartType.candle ? sp(34) : sp(18);

  double get bottom => size.height - (type == ChartType.candle ? sp(16) : 4);

  double y(double v, double lo, double hi) => bottom - (v - lo) / (hi - lo) * (bottom - top);

  int get at => group.selected >= g.from && group.selected < g.to ? group.selected : g.to - 1;

  Paint stroke(Color color, double width) => Paint()
    ..color = color
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..isAntiAlias = true;

  Paint fill(Color color) => Paint()
    ..color = color
    ..style = PaintingStyle.fill
    ..isAntiAlias = true;

  TextPainter _tp(String s, Color color, {bool bold = false}) => TextPainter(
        text: TextSpan(
            text: s,
            style: TextStyle(
                fontFamily: 'NotoSansKR',
                fontSize: sp(11),
                color: color,
                height: 1.0,
                fontWeight: bold ? FontWeight.w700 : FontWeight.w400)),
        textDirection: TextDirection.ltr,
      )..layout();

  /// Draws text with its baseline at `base`, like Canvas.drawText.
  double text(String s, double x, double base, Color color, {bool bold = false}) {
    final tp = _tp(s, color, bold: bold);
    tp.paint(c, Offset(x, base - tp.computeDistanceToActualBaseline(TextBaseline.alphabetic)));
    return tp.width;
  }

  double measure(String s, {bool bold = false}) => _tp(s, colors.muted, bold: bold).width;

  @override
  void paint(Canvas canvas, Size size) {
    c = canvas;
    this.size = size;
    final b = bars;
    if (b == null || b.size < 2) {
      text('차트를 불러오는 중…', 8, size.height / 2, colors.muted);
      return;
    }
    g = _Geometry(b, group, size.width, type, gutter, scaler);
    switch (type) {
      case ChartType.candle:
        _candles(b);
      case ChartType.volume:
        _volume(b);
      case ChartType.stoch:
        _stoch(b);
      case ChartType.rsi:
        _rsi(b);
      case ChartType.cci:
        _cci(b);
    }
    if (group.selected >= g.from && group.selected < g.to) {
      c.drawLine(Offset(g.x(at), top), Offset(g.x(at), bottom), stroke(colors.muted, 1));
    }
  }

  void _candles(Bars b) {
    final a = g.from, n = g.to;
    var lo = double.maxFinite, hi = -double.maxFinite;
    for (var i = a; i < n; i++) {
      lo = math.min(lo, b.low[i]);
      hi = math.max(hi, b.high[i]);
      if (showMa) {
        for (final m in b.series.ma) {
          if (!m[i].isNaN) {
            lo = math.min(lo, m[i]);
            hi = math.max(hi, m[i]);
          }
        }
      }
    }
    final pad = (hi - lo) * 0.08 + 1e-9;
    lo -= pad;
    hi += pad;
    _frame();
    _priceTicks(lo, hi);
    _spans();
    _breakLines();

    final w = math.max(1.0, g.step * 0.62);
    final p = colors.p;
    for (var i = a; i < n; i++) {
      final rising = b.close[i] >= b.open[i];
      final color = b.close[i] == b.open[i] ? p.flat : rising ? p.up : p.down;
      c.drawLine(Offset(g.x(i), y(b.high[i], lo, hi)), Offset(g.x(i), y(b.low[i], lo, hi)), stroke(color, 1));
      final y1 = y(math.max(b.open[i], b.close[i]), lo, hi);
      final y2 = y(math.min(b.open[i], b.close[i]), lo, hi);
      c.drawRect(Rect.fromLTRB(g.x(i) - w / 2, y1, g.x(i) + w / 2, math.max(y2, y1 + 1)), fill(color));
    }
    if (showMa) {
      for (var m = 0; m < b.series.ma.length; m++) {
        _polyline(b.series.ma[m], lo, hi, Palette.ma[m], 1.3);
      }
    }
    if (showSignals) _markers(b, lo, hi);

    // Header: selected day, then moving-average legend.
    final i = at;
    final d = b.date[i];
    text('${d.substring(0, 4)}.${d.substring(4, 6)}.${d.substring(6)}  시 ${grouped(b.open[i])}  '
        '고 ${grouped(b.high[i])}  저 ${grouped(b.low[i])}  종 ${grouped(b.close[i])}', g.left, sp(13), colors.onSurface);
    if (showMa) {
      var xx = g.left;
      for (var m = 0; m < ind.maPeriods.length; m++) {
        final label = 'MA${ind.maPeriods[m]} ';
        xx += text(label, xx, sp(28), Palette.ma[m]) + 4;
      }
    }
    // Dates under the axis.
    final base = size.height - 3;
    text(_label(b, a), g.left, base, colors.muted);
    final last = _label(b, n - 1);
    text(last, g.right - measure(last), base, colors.muted);
  }

  String _label(Bars b, int i) {
    final d = b.date[i];
    return '${d.substring(2, 4)}.${d.substring(4, 6)}.${d.substring(6)}';
  }

  /// ▲ under golden matches and ▼ over dead ones: solid for 3 indicators, hollow for 2. A small
  /// "돌파" at the top of each moving-average breakout's dashed line.
  void _markers(Bars b, double lo, double hi) {
    final m = marks;
    if (m == null) return;
    const size = 5.0;
    for (var i = math.max(1, g.from); i < g.to; i++) {
      if (m.goldLevel[i] >= 2) _triangle(g.x(i), y(b.low[i], lo, hi) + 3, size, true, colors.p.up, m.goldLevel[i] == 3);
      if (m.deadLevel[i] >= 2) _triangle(g.x(i), y(b.high[i], lo, hi) - 3, size, false, colors.p.down, m.deadLevel[i] == 3);
      if (m.maBreak[i]) {
        const label = '돌파';
        final w = measure(label, bold: true);
        final xx = g.x(i) + 3 + w > g.right ? g.x(i) - 3 - w : g.x(i) + 3;
        text(label, xx, top + sp(12), Palette.maBreak, bold: true);
      }
    }
  }

  /// Dashed violet lines, behind the candles, on moving-average breakout days.
  void _breakLines() {
    final m = marks;
    if (!showSignals || m == null) return;
    final paint = stroke(Palette.maBreak, 1.2);
    final dash = sp(4), gap = sp(3);
    for (var i = math.max(1, g.from); i < g.to; i++) {
      if (!m.maBreak[i]) continue;
      final xx = g.x(i);
      for (var yy = top; yy < bottom; yy += dash + gap) {
        c.drawLine(Offset(xx, yy), Offset(xx, math.min(yy + dash, bottom)), paint);
      }
    }
  }

  /// Shaded columns from the first matching crossing to the signal day; darker for 3 indicators.
  void _spans() {
    final m = marks;
    if (!showSignals || m == null) return;
    final half = g.step / 2;
    for (var i = math.max(1, g.from); i < g.to; i++) {
      if (m.goldLevel[i] >= 2) {
        c.drawRect(Rect.fromLTRB(g.x(math.max(g.from, m.goldStart[i])) - half, top, g.x(i) + half, bottom),
            fill(colors.p.up.withAlpha(m.goldLevel[i] == 3 ? 0x40 : 0x1C)));
      }
      if (m.deadLevel[i] >= 2) {
        c.drawRect(Rect.fromLTRB(g.x(math.max(g.from, m.deadStart[i])) - half, top, g.x(i) + half, bottom),
            fill(colors.p.down.withAlpha(m.deadLevel[i] == 3 ? 0x40 : 0x1C)));
      }
    }
  }

  /// Dots on the oscillator's line: red for golden crosses and blue for dead ones — large when
  /// the cross meets the band condition (counts toward signals), small otherwise — and hollow
  /// rings where the line crosses a band level: red for oversold, blue for overbought.
  void _crossings(int part, List<double> v, double lo, double hi, double low, double high) {
    final m = marks;
    if (!showSignals || m == null) return;
    const r = 3.5;
    final p = colors.p;
    for (var i = math.max(1, g.from); i < g.to; i++) {
      if (v[i].isNaN || v[i - 1].isNaN) continue;
      final xx = g.x(i), yy = y(v[i], lo, hi).clamp(top, bottom);
      final crossLow = (v[i - 1] < low) != (v[i] < low);
      final crossHigh = (v[i - 1] > high) != (v[i] > high);
      if (crossLow) c.drawCircle(Offset(xx, y(low, lo, hi)), r - 1, stroke(p.up, 1));
      if (crossHigh) c.drawCircle(Offset(xx, y(high, lo, hi)), r - 1, stroke(p.down, 1));
      // Crossings that meet the band condition count toward signals: large dots.
      // Other crossings of the two lines: small, faint dots. (CCI's crossing is the band itself.)
      if (m.goldPart[i][part]) {
        c.drawCircle(Offset(xx, yy), r, fill(p.up));
      } else if (part != rule.cciPart && m.goldCross[i][part]) {
        c.drawCircle(Offset(xx, yy), r * 0.55, fill(p.up.withAlpha(0xA0)));
      }
      if (m.deadPart[i][part]) {
        c.drawCircle(Offset(xx, yy), r, fill(p.down));
      } else if (part != rule.cciPart && m.deadCross[i][part]) {
        c.drawCircle(Offset(xx, yy), r * 0.55, fill(p.down.withAlpha(0xA0)));
      }
    }
  }

  void _triangle(double cx, double tipY, double size, bool pointUp, Color color, bool solid) {
    final dir = pointUp ? 1 : -1;
    final path = Path()
      ..moveTo(cx, tipY)
      ..lineTo(cx - size, tipY + dir * size * 1.6)
      ..lineTo(cx + size, tipY + dir * size * 1.6)
      ..close();
    c.drawPath(path, solid ? fill(color) : stroke(color, 1.2));
  }

  /// Volume bars coloured like the candles, with the 20-day average volume as a line.
  void _volume(Bars b) {
    final volumeMa = ind.sma(b.volume, 20);
    var max = 1.0;
    for (var i = g.from; i < g.to; i++) {
      if (!b.volume[i].isNaN) max = math.max(max, b.volume[i]);
      if (!volumeMa[i].isNaN) max = math.max(max, volumeMa[i]);
    }
    max *= 1.08;
    _spans();
    _frame();
    c.drawLine(Offset(g.left, y(max / 2, 0, max)), Offset(g.right, y(max / 2, 0, max)), stroke(Palette.grid, 1));
    _axisLabel(compactNumber(max / 2), y(max / 2, 0, max));
    final w = math.max(1.0, g.step * 0.62);
    final p = colors.p;
    for (var i = g.from; i < g.to; i++) {
      if (b.volume[i].isNaN) continue;
      final color = b.close[i] == b.open[i] ? p.flat : b.close[i] > b.open[i] ? p.up : p.down;
      c.drawRect(Rect.fromLTRB(g.x(i) - w / 2, y(b.volume[i], 0, max), g.x(i) + w / 2, bottom), fill(color.withAlpha(0xB0)));
    }
    _polyline(volumeMa, 0, max, Palette.lineSignal, 1.2);
    final i = at;
    _header('거래량', compactNumber(b.volume[i]), colors.onSurface, '20일 평균 ${compactNumber(volumeMa[i])}', Palette.lineSignal);
  }

  void _stoch(Bars b) {
    final k = cfg.slow ? b.series.kSlow : b.series.kFast;
    final d = cfg.slow ? b.series.dSlow : b.series.dFast;
    _bands(0, 100, cfg.stochLo, cfg.stochHi, cfg.stochBand);
    _spans();
    _frame();
    _polyline(k, 0, 100, colors.p.lineMain, 1.5);
    _polyline(d, 0, 100, Palette.lineSignal, 1.2);
    _crossings(rule.stoch, k, 0, 100, cfg.stochLo, cfg.stochHi);
    final i = at;
    _header('${cfg.slow ? 'Slow' : 'Fast'} 스토캐스틱 5-3-3', '%K ${fixed1(k[i])}', colors.p.lineMain, '%D ${fixed1(d[i])}',
        Palette.lineSignal);
  }

  void _rsi(Bars b) {
    _bands(0, 100, cfg.rsiLo, cfg.rsiHi, cfg.rsiBand);
    _spans();
    _frame();
    _polyline(b.series.rsi, 0, 100, colors.p.lineMain, 1.5);
    _polyline(b.series.rsiSig, 0, 100, Palette.lineSignal, 1.2);
    _crossings(rule.rsiPart, b.series.rsi, 0, 100, cfg.rsiLo, cfg.rsiHi);
    final i = at;
    _header('RSI 14 · 시그널 9', 'RSI ${fixed1(b.series.rsi[i])}', colors.p.lineMain, '시그널 ${fixed1(b.series.rsiSig[i])}',
        Palette.lineSignal);
  }

  void _cci(Bars b) {
    final v = b.series.cci;
    final level = cfg.cciLevel;
    var m = level * 1.3;
    for (var i = g.from; i < g.to; i++) {
      if (!v[i].isNaN) m = math.max(m, v[i].abs() * 1.05);
    }
    _bands(-m, m, -level, level, true);
    _spans();
    _dashed(y(0, -m, m), Palette.grid);
    _frame();
    _polyline(v, -m, m, colors.p.lineMain, 1.5);
    _crossings(rule.cciPart, v, -m, m, -level, level);
    _header('CCI ${ind.cciN}', 'CCI ${fixed1(v[at])}', colors.p.lineMain, null, null);
  }

  /// Shaded zones beyond the two levels, with dashed lines and their labels on the axis.
  void _bands(double lo, double hi, double low, double high, bool active) {
    c.drawRect(Rect.fromLTRB(g.left, y(hi, lo, hi), g.right, y(high, lo, hi)), fill(Palette.band));
    c.drawRect(Rect.fromLTRB(g.left, y(low, lo, hi), g.right, y(lo, lo, hi)), fill(Palette.band));
    final color = active ? colors.muted : Palette.grid;
    _dashed(y(high, lo, hi), color);
    _dashed(y(low, lo, hi), color);
    _axisLabel(axis(high), y(high, lo, hi));
    _axisLabel(axis(low), y(low, lo, hi));
  }

  void _dashed(double yy, Color color) {
    final p = stroke(color, 1);
    for (var x = g.left; x < g.right; x += 7) {
      c.drawLine(Offset(x, yy), Offset(math.min(x + 4, g.right), yy), p);
    }
  }

  void _frame() => c.drawRect(Rect.fromLTRB(g.left, top, g.right, bottom), stroke(Palette.grid, 1));

  /// Grid lines at round prices (1, 2 or 5 × 10ⁿ apart), about four of them.
  void _priceTicks(double lo, double hi) {
    final raw = (hi - lo) / 4;
    final mag = math.pow(10, (math.log(raw) / math.ln10).floor()).toDouble();
    final f = raw / mag;
    final step = (f < 1.5 ? 1 : f < 3 ? 2 : f < 7 ? 5 : 10) * mag;
    for (var v = (lo / step).ceil() * step; v < hi; v += step) {
      final yy = y(v, lo, hi);
      c.drawLine(Offset(g.left, yy), Offset(g.right, yy), stroke(Palette.grid, 1));
      _axisLabel(axis(v), yy);
    }
  }

  /// In the gutter, vertically centred on its line and kept inside the panel.
  void _axisLabel(String s, double yy) {
    final base = math.max(top + sp(8), math.min(bottom, yy + sp(4)));
    text(s, g.right + 4, base, colors.muted);
  }

  void _polyline(List<double> v, double lo, double hi, Color color, double width) {
    final path = Path();
    var pen = false;
    for (var i = g.from; i < g.to; i++) {
      if (v[i].isNaN) {
        pen = false;
        continue;
      }
      final yy = y(v[i], lo, hi).clamp(top, bottom);
      if (pen) {
        path.lineTo(g.x(i), yy);
      } else {
        path.moveTo(g.x(i), yy);
      }
      pen = true;
    }
    c.drawPath(path, stroke(color, width));
  }

  void _header(String title, String a, Color ca, String? b, Color? cb) {
    final yy = sp(13);
    var xx = g.left;
    xx += text(title, xx, yy, colors.onSurface, bold: true) + 10;
    xx += text(a, xx, yy, ca);
    if (b != null) text(b, xx + 8, yy, cb!);
  }

  @override
  bool shouldRepaint(covariant _ChartPainter old) => true;
}
