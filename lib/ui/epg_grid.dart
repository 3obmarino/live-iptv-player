import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

/// Timeline TV guide: channel column on the left, programmes on a
/// horizontally scrollable time axis, red line at "now".
class EpgGrid extends StatefulWidget {
  const EpgGrid({super.key, required this.channels, required this.onPlay});
  final List<Channel> channels;
  final void Function(Channel) onPlay;
  @override
  State<EpgGrid> createState() => _EpgGridState();
}

class _EpgGridState extends State<EpgGrid> {
  static const double rowH = 60;
  static const double chW = 128;
  static const double headerH = 40;
  static const double ppm = 5; // pixels per minute (300 px per hour)
  static const int hours = 30;

  late DateTime _start;
  late final ScrollController _h;
  final _vLeft = ScrollController();
  final _vRight = ScrollController();
  Timer? _timer;

  int get _startMs => _start.millisecondsSinceEpoch;
  int get _endMs => _startMs + hours * 3600000;
  double _xFor(int ms) => (ms - _startMs) / 60000 * ppm;
  double get _width => hours * 60 * ppm;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _start = DateTime(now.year, now.month, now.day, now.hour)
        .subtract(const Duration(hours: 2));
    _h = ScrollController(
        initialScrollOffset: math.max(0, _xFor(now.millisecondsSinceEpoch) - 30 * ppm));
    _vRight.addListener(() {
      if (_vLeft.hasClients && _vLeft.offset != _vRight.offset) {
        _vLeft.jumpTo(_vRight.offset);
      }
    });
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _h.dispose();
    _vLeft.dispose();
    _vRight.dispose();
    super.dispose();
  }

  void _jumpToNow() {
    final x = _xFor(DateTime.now().millisecondsSinceEpoch) - 30 * ppm;
    _h.animateTo(math.max(0, x),
        duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now().millisecondsSinceEpoch;
    final nowX = _xFor(now);
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        children: [
          // ---- channel column (scroll synced from the right side)
          SizedBox(
            width: isCompact(context) ? 92 : chW,
            child: Column(children: [
              SizedBox(
                height: headerH,
                child: Center(
                  child: ActionChip(
                    tooltip: 'Jump to now',
                    label: Text(fmtDate(DateTime.now()), style: const TextStyle(fontSize: 12)),
                    onPressed: _jumpToNow,
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ),
              Expanded(
                child: Listener(
                  onPointerSignal: (e) {
                    if (e is PointerScrollEvent && _vRight.hasClients) {
                      final p = _vRight.position;
                      _vRight.jumpTo((p.pixels + e.scrollDelta.dy)
                          .clamp(p.minScrollExtent, p.maxScrollExtent)
                          .toDouble());
                    }
                  },
                  child: ScrollConfiguration(
                    behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
                    child: ListView.builder(
                      controller: _vLeft,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: widget.channels.length,
                      itemExtent: rowH,
                      itemBuilder: (_, i) => _channelCell(widget.channels[i], cs),
                    ),
                  ),
                ),
              ),
            ]),
          ),
          VerticalDivider(width: 1, color: cs.outlineVariant),
          // ---- timeline
          Expanded(
            child: Scrollbar(
              controller: _h,
              child: SingleChildScrollView(
                controller: _h,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: _width,
                  child: Column(children: [
                    SizedBox(height: headerH, child: _timeHeader(cs)),
                    Expanded(
                      child: Stack(children: [
                        ListView.builder(
                          controller: _vRight,
                          itemCount: widget.channels.length,
                          itemExtent: rowH,
                          itemBuilder: (_, i) => _row(widget.channels[i], now, cs),
                        ),
                        if (nowX >= 0 && nowX <= _width)
                          Positioned(
                            left: nowX,
                            top: 0,
                            bottom: 0,
                            child: IgnorePointer(
                              child: Container(width: 2, color: Colors.redAccent),
                            ),
                          ),
                      ]),
                    ),
                  ]),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _timeHeader(ColorScheme cs) {
    return Stack(children: [
      for (var h = 0; h <= hours; h++)
        Positioned(
          left: h * 60 * ppm + 6,
          top: 12,
          child: Builder(builder: (_) {
            final t = _start.add(Duration(hours: h));
            final label = t.hour == 0 ? '${two(t.day)}/${two(t.month)}' : '${two(t.hour)}:00';
            return Text(label,
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: t.hour == 0 ? FontWeight.w700 : FontWeight.w500,
                    color: cs.onSurfaceVariant));
          }),
        ),
      for (var h = 0; h <= hours; h++)
        Positioned(
          left: h * 60 * ppm,
          top: 10,
          bottom: 8,
          child: Container(width: 1, color: cs.outlineVariant),
        ),
    ]);
  }

  Widget _channelCell(Channel c, ColorScheme cs) {
    return InkWell(
      onTap: () => widget.onPlay(c),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ChannelLogo(c, size: 28),
            const SizedBox(height: 3),
            Text(c.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  Widget _row(Channel c, int now, ColorScheme cs) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final progs = AppState.I.epg.forChannel(c);
    final s = _startMs, e = _endMs;
    final children = <Widget>[];
    for (final p in progs) {
      if (p.stop <= s) continue;
      if (p.start >= e) break;
      final left = _xFor(math.max(p.start, s));
      final right = _xFor(math.min(p.stop, e));
      final w = right - left - 4;
      if (w < 2) continue;
      final past = p.stop <= now;
      final live = p.isLiveAt(now);
      final bg = live
          ? kAccent.withOpacity(dark ? 0.28 : 0.12)
          : past
              ? (dark ? const Color(0xFF1F1F24) : const Color(0xFFF3F3F5))
              : cs.surfaceContainerHighest;
      final fg = past ? cs.onSurfaceVariant : cs.onSurface;
      children.add(Positioned(
        left: left + 2,
        top: 4,
        bottom: 4,
        width: w,
        child: Tooltip(
          message: '${fmtMs(p.start)}–${fmtMs(p.stop)}  ${p.title}',
          child: Material(
            color: bg,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => widget.onPlay(c),
              onSecondaryTap: () =>
                  showProgrammeDetails(context, c, p, onWatch: () => widget.onPlay(c)),
              onLongPress: () =>
                  showProgrammeDetails(context, c, p, onWatch: () => widget.onPlay(c)),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(p.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13,
                            color: fg,
                            fontWeight: live ? FontWeight.w600 : FontWeight.w500)),
                    if (w > 90)
                      Text('${fmtMs(p.start)}–${fmtMs(p.stop)}',
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                  ],
                ),
              ),
            ),
          ),
        ),
      ));
    }
    if (children.isEmpty) {
      children.add(Positioned(
        left: 2,
        right: 2,
        top: 4,
        bottom: 4,
        child: Container(
          decoration: BoxDecoration(
              color: cs.surfaceContainerLow, borderRadius: BorderRadius.circular(6)),
          padding: EdgeInsets.only(left: math.max(8, _xFor(now) - 120)),
          alignment: Alignment.centerLeft,
          child: Text('No TV guide',
              style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
        ),
      ));
    }
    return DecoratedBox(
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: cs.outlineVariant))),
      child: Stack(children: children),
    );
  }
}
