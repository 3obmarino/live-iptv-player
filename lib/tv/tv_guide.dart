import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../app_state.dart';
import '../models.dart';
import '../ui/common.dart';

/// Remote-driven TV guide. The parent forwards key presses to [handleKey].
/// ↑/↓ channel, ←/→ programme, OK plays the channel.
class TvGuide extends StatefulWidget {
  const TvGuide({
    super.key,
    required this.channels,
    required this.initialIndex,
    required this.playingId,
    required this.onPlay,
  });
  final List<Channel> channels;
  final int initialIndex;
  final String? playingId;
  final void Function(Channel) onPlay;

  @override
  State<TvGuide> createState() => TvGuideState();
}

class TvGuideState extends State<TvGuide> {
  static const double rowH = 58;
  static const double chW = 190;
  static const int windowMin = 150; // 2½ hours on screen
  static const int halfHour = 30 * 60000;

  late int _row;
  int _first = 0;
  int _visible = 6;
  late int _winStart; // epoch ms
  late int _focusTime; // keeps the "time column" when moving up/down
  int _prog = -1;

  int get _winEnd => _winStart + windowMin * 60000;

  static int _floor30(int ms) => ms - (ms % halfHour);

  List<Programme> _progs(int row) => AppState.I.epg.forChannel(widget.channels[row]);

  @override
  void initState() {
    super.initState();
    final now = DateTime.now().millisecondsSinceEpoch;
    _row = widget.initialIndex.clamp(0, math.max(0, widget.channels.length - 1)).toInt();
    _winStart = _floor30(now);
    _focusTime = now;
    _pickProgAt(_focusTime);
    _first = math.max(0, _row - 2);
  }

  void _pickProgAt(int t) {
    if (widget.channels.isEmpty) {
      _prog = -1;
      return;
    }
    final ps = _progs(_row);
    _prog = -1;
    for (var i = 0; i < ps.length; i++) {
      if (ps[i].start <= t && t < ps[i].stop) {
        _prog = i;
        return;
      }
      if (ps[i].start > t) {
        _prog = i;
        return;
      }
    }
    if (ps.isNotEmpty && ps.last.stop <= t) _prog = ps.length - 1;
  }

  void _ensureRowVisible() {
    if (_row < _first) _first = _row;
    if (_row >= _first + _visible) _first = _row - _visible + 1;
  }

  void _ensureProgVisible({required bool movingRight}) {
    final ps = _progs(_row);
    if (_prog < 0 || _prog >= ps.length) return;
    final p = ps[_prog];
    final tail = _winEnd - halfHour;
    if (p.start >= tail || p.stop <= _winStart + 5 * 60000) {
      _winStart = movingRight ? _floor30(p.start) - halfHour : _floor30(p.start);
    } else if (p.start < _winStart && !movingRight) {
      _winStart = _floor30(p.start);
    }
    _focusTime = math.max(p.start, _winStart);
  }

  /// Returns true if the key was used.
  bool handleKey(LogicalKeyboardKey k) {
    if (widget.channels.isEmpty) return false;
    if (k == LogicalKeyboardKey.arrowDown || k == LogicalKeyboardKey.channelDown) {
      setState(() {
        _row = (_row + 1) % widget.channels.length;
        _pickProgAt(_focusTime);
        _ensureRowVisible();
      });
      return true;
    }
    if (k == LogicalKeyboardKey.arrowUp || k == LogicalKeyboardKey.channelUp) {
      setState(() {
        _row = (_row - 1 + widget.channels.length) % widget.channels.length;
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
          _ensureProgVisible(movingRight: true);
        } else {
          _winStart += halfHour;
          _focusTime = math.max(_focusTime, _winStart);
        }
      });
      return true;
    }
    if (k == LogicalKeyboardKey.arrowLeft) {
      final ps = _progs(_row);
      setState(() {
        if (_prog > 0) {
          _prog--;
          _ensureProgVisible(movingRight: false);
        } else if (ps.isEmpty) {
          _winStart -= halfHour;
          _focusTime = _winStart;
        }
      });
      return true;
    }
    return false;
  }

  void ok() {
    if (widget.channels.isEmpty) return;
    widget.onPlay(widget.channels[_row]);
  }

  Channel? get selectedChannel => widget.channels.isEmpty ? null : widget.channels[_row];

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now().millisecondsSinceEpoch;
    if (widget.channels.isEmpty) {
      return const ColoredBox(
        color: Color(0xF2111114),
        child: Center(
            child: Text('No channels', style: TextStyle(color: Colors.white70, fontSize: 18))),
      );
    }
    final ps = _progs(_row);
    final sel = (_prog >= 0 && _prog < ps.length) ? ps[_prog] : null;
    final ch = widget.channels[_row];

    return ColoredBox(
      color: const Color(0xF2111114),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(40, 28, 40, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ---- details of the selected programme
            SizedBox(
              height: 118,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(ch.name,
                      style: const TextStyle(color: kAccent, fontSize: 15, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(sel?.title ?? 'No TV guide for this channel',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 24, fontWeight: FontWeight.w700)),
                  if (sel != null) ...[
                    const SizedBox(height: 4),
                    Text(
                        '${dayLabel(DateTime.fromMillisecondsSinceEpoch(sel.start))}  '
                        '${fmtMs(sel.start)} – ${fmtMs(sel.stop)}'
                        '${sel.isLiveAt(now) ? '   ·   Live now' : ''}',
                        style: const TextStyle(color: Colors.white70, fontSize: 14)),
                    const SizedBox(height: 6),
                    Text(sel.desc,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white60, fontSize: 13.5, height: 1.35)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(builder: (context, box) {
                _visible = math.max(1, ((box.maxHeight - 30) / rowH).floor());
                _ensureRowVisible();
                final gridW = box.maxWidth - chW;
                final ppm = gridW / windowMin;
                double x(int ms) => (ms - _winStart) / 60000 * ppm;
                final last = math.min(widget.channels.length, _first + _visible);

                return Stack(children: [
                  Column(children: [
                    // time header
                    SizedBox(
                      height: 30,
                      child: Stack(children: [
                        for (var m = 0; m <= windowMin; m += 30)
                          Positioned(
                            left: chW + m * ppm + 6,
                            top: 4,
                            child: Text(
                              fmtMs(_winStart + m * 60000),
                              style: const TextStyle(color: Colors.white60, fontSize: 13),
                            ),
                          ),
                      ]),
                    ),
                    for (var r = _first; r < last; r++)
                      SizedBox(
                        height: rowH,
                        child: Row(children: [
                          SizedBox(
                            width: chW,
                            child: Row(children: [
                              SizedBox(
                                width: 34,
                                child: Text('${r + 1}',
                                    style: const TextStyle(color: Colors.white38, fontSize: 13)),
                              ),
                              ChannelLogo(widget.channels[r], size: 34),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(widget.channels[r].name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                        color: r == _row ? Colors.white : Colors.white70,
                                        fontSize: 14.5,
                                        fontWeight:
                                            r == _row ? FontWeight.w700 : FontWeight.w500)),
                              ),
                              if (widget.channels[r].id == widget.playingId)
                                const Padding(
                                  padding: EdgeInsets.only(right: 8),
                                  child: Icon(Icons.volume_up_rounded, color: kAccent, size: 16),
                                ),
                            ]),
                          ),
                          Expanded(child: _progRow(r, now, x, gridW)),
                        ]),
                      ),
                  ]),
                  // now line
                  if (now > _winStart && now < _winEnd)
                    Positioned(
                      left: chW + x(now),
                      top: 26,
                      bottom: 0,
                      child: Container(width: 2, color: Colors.redAccent),
                    ),
                ]);
              }),
            ),
            const SizedBox(height: 8),
            const Text('OK  watch     ◀ ▶  programmes     ▲ ▼  channels     BACK  close',
                style: TextStyle(color: Colors.white38, fontSize: 12.5)),
          ],
        ),
      ),
    );
  }

  Widget _progRow(int r, int now, double Function(int) x, double gridW) {
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
      final past = p.stop <= now;
      children.add(Positioned(
        left: l + 2,
        top: 3,
        bottom: 3,
        width: w,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: selected
                ? kAccent
                : live
                    ? const Color(0xFF2E2E36)
                    : past
                        ? const Color(0xFF18181C)
                        : const Color(0xFF232329),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(p.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                  color: selected
                      ? kOnAccent
                      : past
                          ? Colors.white38
                          : Colors.white,
                  fontSize: 14,
                  fontWeight: selected || live ? FontWeight.w600 : FontWeight.w500)),
        ),
      ));
    }
    if (children.isEmpty) {
      children.add(Positioned.fill(
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 3, horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10),
          alignment: Alignment.centerLeft,
          decoration: BoxDecoration(
            color: r == _row ? kAccent : const Color(0xFF18181C),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text('No information',
              style: TextStyle(color: r == _row ? kOnAccent : Colors.white54, fontSize: 14)),
        ),
      ));
    }
    return Stack(clipBehavior: Clip.hardEdge, children: children);
  }
}
