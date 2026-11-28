import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/common.dart';
import '../l10n.dart';
import '../reminders.dart';

/// Full-screen TV guide (TiviMate style). The live video is drawn by the
/// parent inside [preview]; this widget paints everything around it:
/// programme details to the right of the preview, then date/time, a time
/// ruler and the channel × programme grid.
///
/// The parent forwards remote keys to [TvGuideState.handleKey].
class TvGuide extends StatefulWidget {
  const TvGuide({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.playingId,
    required this.categoryName,
    required this.preview,
    this.emptyText,
  });
  final List<Channel> channels;
  final int initialIndex;
  final String? playingId;
  final String categoryName;

  /// Area (in this widget's coordinates) left free for the video preview.
  final Rect preview;

  /// Shown instead of the grid when [channels] is empty.
  final String? emptyText;

  @override
  State<TvGuide> createState() => TvGuideState();
}

class TvGuideState extends State<TvGuide> {
  static const double rowH = 40;
  double chW = 300; // narrower when the sidebar is open
  int windowMin = 150; // 2½ h across the grid (1½ h when narrow)
  static const int halfHour = 30 * 60000;

  late int _row;
  int _first = 0;
  int _visible = 8;
  late int _winStart;
  late int _focusTime;
  int _prog = -1;

  int get _winEnd => _winStart + windowMin * 60000;
  static int _floor30(int ms) => ms - (ms % halfHour);
  int get _minStart => _floor30(DateTime.now().millisecondsSinceEpoch);

  List<Programme> _progs(int row) => AppState.I.epg.forChannel(widget.channels[row]);

  Channel? get selected => widget.channels.isEmpty ? null : widget.channels[_row];

  /// The highlighted programme (null on a channel without guide).
  Programme? get selectedProgramme {
    if (widget.channels.isEmpty) return null;
    final ps = _progs(_row);
    return (_prog >= 0 && _prog < ps.length) ? ps[_prog] : null;
  }

  @override
  void initState() {
    super.initState();
    _reset();
  }

  void _reset() {
    final now = DateTime.now().millisecondsSinceEpoch;
    _row = widget.initialIndex.clamp(0, math.max(0, widget.channels.length - 1)).toInt();
    _first = math.max(0, _row - 3);
    _winStart = _floor30(now);
    _focusTime = now;
    _pickProgAt(_focusTime);
  }

  @override
  void didUpdateWidget(TvGuide old) {
    super.didUpdateWidget(old);
    if (!_sameChannels(old.channels, widget.channels)) _reset();
  }

  static bool _sameChannels(List<Channel> a, List<Channel> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id) return false;
    }
    return true;
  }

  void _pickProgAt(int t) {
    _prog = -1;
    if (widget.channels.isEmpty) return;
    final ps = _progs(_row);
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].stop > t) {
        _prog = i;
        return;
      }
    }
  }

  void _ensureRowVisible() {
    if (_row < _first) _first = _row;
    if (_row >= _first + _visible) _first = _row - _visible + 1;
  }

  void _followProg({required bool right}) {
    final ps = _progs(_row);
    if (_prog < 0 || _prog >= ps.length) return;
    final p = ps[_prog];
    if (right && p.start >= _winEnd - halfHour) {
      _winStart = _floor30(p.start) - halfHour;
    } else if (!right && p.start < _winStart) {
      _winStart = math.max(_minStart, _floor30(p.start));
    }
    _focusTime = math.max(p.start, _winStart);
  }

  /// True when ◀ should leave the guide (selection is at "now").
  bool get atLeftEdge {
    if (widget.channels.isEmpty) return true;
    if (_winStart > _minStart) return false;
    final ps = _progs(_row);
    if (_prog <= 0 || _prog >= ps.length) return true;
    return ps[_prog - 1].stop <= DateTime.now().millisecondsSinceEpoch;
  }

  bool handleKey(LogicalKeyboardKey k) {
    if (widget.channels.isEmpty) return false;
    final n = widget.channels.length;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      setState(() {
        _row = (_row + 1) % n;
        _pickProgAt(_focusTime);
        _ensureRowVisible();
      });
      return true;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      setState(() {
        _row = (_row - 1 + n) % n;
        _pickProgAt(_focusTime);
        _ensureRowVisible();
      });
      return true;
    }
    if (k == LogicalKeyboardKey.arrowRight) {
      final ps = _progs(_row);
      setState(() {
        if (_prog >= 0 && _prog < ps.length - 1) {
          _prog++;
          _followProg(right: true);
        } else {
          _winStart += halfHour;
          _focusTime = math.max(_focusTime, _winStart);
        }
      });
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      if (atLeftEdge) return false;
      setState(() {
        if (_prog > 0) {
          _prog--;
          _followProg(right: false);
        } else {
          _winStart = math.max(_minStart, _winStart - halfHour);
          _focusTime = _winStart;
        }
      });
      return true;
    }
    return false;
  }

  static String dateTimeLabel(DateTime d) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${days[d.weekday - 1]} ${d.day} ${months[d.month - 1]}  ${fmtTime(d)}';
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (widget.channels.isEmpty) {
      return ColoredBox(
        color: Color(0xFF101114),
        child: Center(
            child: Text(widget.emptyText ?? tr('No channels in this category'),
                style: TextStyle(color: Colors.white70, fontSize: 18))),
      );
    }
    if (_winStart < _minStart) _winStart = _minStart;
    final ch = widget.channels[_row];
    final ps = _progs(_row);
    final sel = (_prog >= 0 && _prog < ps.length) ? ps[_prog] : null;
    final fav = AppState.I.isFavorite(ch);
    final pv = widget.preview;

    return ColoredBox(
      color: const Color(0xFF101114),
      child: LayoutBuilder(builder: (context, box) {
        final gridTop = pv.bottom + 14;
        final rowsH = box.maxHeight - gridTop - 34 - 6;
        _visible = math.max(1, (rowsH / rowH).floor());
        _ensureRowVisible();
        chW = math.min(300.0, box.maxWidth * 0.32);
        final gridW = box.maxWidth - 32 - chW;
        windowMin = gridW < 520 ? 90 : 150;
        final ppm = gridW / windowMin;
        double x(int ms) => (ms - _winStart) / 60000 * ppm;
        final last = math.min(widget.channels.length, _first + _visible);

        return Stack(children: [
          // ---------------------------------------------------- details
          Positioned(
            left: pv.right + 28,
            right: 28,
            top: pv.top,
            height: pv.height,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Expanded(
                    child: Text(sel?.title ?? ch.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white, fontSize: 26, fontWeight: FontWeight.w700)),
                  ),
                  Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                      color: fav ? kAccent : Colors.white54, size: 28),
                ]),
                const SizedBox(height: 8),
                Row(children: [
                  if (sel != null) ...[
                    Text('${fmtMs(sel.start)} – ${fmtMs(sel.stop)}',
                        style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    const SizedBox(width: 14),
                    if (sel.isLiveAt(now)) ...[
                      SizedBox(
                        width: 70,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: LinearProgressIndicator(
                            value: sel.progressAt(now),
                            minHeight: 3,
                            color: kAccent,
                            backgroundColor: Colors.white24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      Text('${((sel.stop - now) / 60000).ceil()} min',
                          style: const TextStyle(color: Colors.white70, fontSize: 16)),
                    ] else
                      Text('${((sel.stop - sel.start) / 60000).round()} min',
                          style: const TextStyle(color: Colors.white70, fontSize: 16)),
                  ],
                  const Spacer(),
                  Text(widget.categoryName,
                      style: const TextStyle(color: Colors.white70, fontSize: 16)),
                ]),
                const SizedBox(height: 10),
                Expanded(
                  child: Text(
                    sel == null ? 'No TV guide for this channel' : sel.desc,
                    overflow: TextOverflow.fade,
                    style: const TextStyle(color: Colors.white70, fontSize: 15, height: 1.35),
                  ),
                ),
              ],
            ),
          ),

          // ---------------------------------------------- header + ruler
          Positioned(
            left: 16,
            right: 16,
            top: gridTop,
            height: 34,
            child: Row(children: [
              SizedBox(
                width: chW,
                child: Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: Text(dateTimeLabel(DateTime.now()),
                      style: const TextStyle(
                          color: kAccent, fontSize: 18, fontWeight: FontWeight.w600)),
                ),
              ),
              Expanded(
                child: Stack(clipBehavior: Clip.none, children: [
                  for (var m = 0; m < windowMin; m += 30)
                    Positioned(
                      left: m * ppm,
                      top: 4,
                      child: Text(fmtMs(_winStart + m * 60000),
                          style: const TextStyle(color: Colors.white70, fontSize: 15)),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(height: 1, color: Colors.white24),
                  ),
                  if (now > _winStart && now < _winEnd)
                    Positioned(
                      left: x(now) - 4,
                      bottom: -4,
                      child: Container(
                        width: 9,
                        height: 9,
                        decoration: const BoxDecoration(color: kAccent, shape: BoxShape.circle),
                      ),
                    ),
                ]),
              ),
            ]),
          ),

          // ------------------------------------------------------ rows
          Positioned(
            left: 16,
            right: 16,
            top: gridTop + 34 + 6,
            bottom: 0,
            child: Stack(children: [
              Column(children: [
                for (var r = _first; r < last; r++) _rowWidget(r, now, x),
              ]),
              if (now > _winStart && now < _winEnd)
                Positioned(
                  left: chW + x(now),
                  top: 0,
                  bottom: 0,
                  child: IgnorePointer(
                      child: Container(width: 2, color: kAccent.withOpacity(0.85))),
                ),
            ]),
          ),
        ]);
      }),
    );
  }

  Widget _rowWidget(int r, int now, double Function(int) x) {
    final c = widget.channels[r];
    final isSelRow = r == _row;
    final playing = c.id == widget.playingId;
    return SizedBox(
      height: rowH,
      child: Row(children: [
        SizedBox(
          width: chW,
          child: Row(children: [
            SizedBox(
              width: 44,
              child: Text('${r + 1}',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: isSelRow ? kAccent : Colors.white70,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            const SizedBox(width: 8),
            ChannelLogo(c, size: 32),
            const SizedBox(width: 12),
            Expanded(
              child: Text(c.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: isSelRow ? kAccent : Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ),
            if (playing)
              const Padding(
                padding: EdgeInsets.only(left: 6, right: 10),
                child: Icon(Icons.play_arrow_rounded, color: kAccent, size: 24),
              )
            else
              const SizedBox(width: 10),
          ]),
        ),
        Expanded(child: _progRow(r, now, x)),
      ]),
    );
  }

  Widget _progRow(int r, int now, double Function(int) x) {
    final ps = _progs(r);
    final children = <Widget>[];
    for (var i = 0; i < ps.length; i++) {
      final p = ps[i];
      if (p.stop <= _winStart) continue;
      if (p.start >= _winEnd) break;
      final l = x(math.max(p.start, _winStart));
      final w = x(math.min(p.stop, _winEnd)) - l - 4;
      if (w < 3) continue;
      final selected = r == _row && i == _prog;
      final live = p.isLiveAt(now);
      children.add(Positioned(
        left: l + 2,
        top: 3,
        bottom: 3,
        width: w,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected
                ? kAccent
                : live
                    ? const Color(0xFF30333D)
                    : const Color(0xFF24262E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(children: [
            if (Reminders.I.has(widget.channels[r], p))
              Padding(
                padding: const EdgeInsets.only(right: 6),
                child: Icon(Icons.notifications_active_rounded,
                    size: 16, color: selected ? kOnAccent : kAccent),
              ),
            Expanded(
              child: Text(p.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      color: selected ? kOnAccent : Colors.white,
                      fontSize: 15,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500)),
            ),
          ]),
        ),
      ));
    }
    if (children.isEmpty) {
      final selected = r == _row;
      children.add(Positioned.fill(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected ? kAccent : const Color(0xFF24262E),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(tr('No TV guide for this channel'),
              style: TextStyle(color: selected ? kOnAccent : Colors.white60, fontSize: 16)),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}
