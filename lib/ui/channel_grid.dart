import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class ChannelGrid extends StatefulWidget {
  const ChannelGrid(
      {super.key,
      required this.channels,
      required this.onPlay,
      this.onGoToCategory,
      this.focusId});
  final List<Channel> channels;
  final void Function(Channel) onPlay;

  /// Search results: menu entry "Go to category".
  final void Function(Channel)? onGoToCategory;

  /// Scroll to and mark this channel (after "Go to category").
  final String? focusId;

  static const _maxExtent = 540.0, _rowH = 92.0, _spacing = 4.0, _pad = 8.0;

  @override
  State<ChannelGrid> createState() => _ChannelGridState();
}

class _ChannelGridState extends State<ChannelGrid> {
  static const _maxExtent = ChannelGrid._maxExtent,
      _rowH = ChannelGrid._rowH,
      _spacing = ChannelGrid._spacing,
      _pad = ChannelGrid._pad;

  // One controller per "focus" so normal rebuilds never move the list.
  ScrollController? _ctrl;
  String? _ctrlFor;

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final now = DateTime.now().millisecondsSinceEpoch;
    return Container(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        // Same column count as the grid below, to scroll to [focusId].
        final cols = ((box.maxWidth - 2 * _pad) / (_maxExtent + _spacing)).ceil().clamp(1, 99);
        if (_ctrl == null || _ctrlFor != widget.focusId) {
          final idx = widget.focusId == null ? -1 : widget.channels.indexWhere((c) => c.id == widget.focusId);
          final rowsAbove = idx <= 0 ? 0 : (idx ~/ cols) - 1; // one row of context above
          final offset = rowsAbove <= 0 ? 0.0 : rowsAbove * (_rowH + 2);
          final old = _ctrl;
          if (old != null) WidgetsBinding.instance.addPostFrameCallback((_) => old.dispose());
          _ctrl = ScrollController(initialScrollOffset: offset);
          _ctrlFor = widget.focusId;
        }
        return GridView.builder(
        key: ValueKey(widget.focusId),
        controller: _ctrl,
        padding: const EdgeInsets.all(_pad),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          // Wider tiles (5 instead of 6 columns on a big screen) and room for
          // a time line + two lines of title, so event names aren't cut off.
          maxCrossAxisExtent: _maxExtent,
          mainAxisExtent: _rowH,
          crossAxisSpacing: _spacing,
          mainAxisSpacing: 2,
        ),
        itemCount: widget.channels.length,
        itemBuilder: (ctx, i) => ChannelTile(
          channel: widget.channels[i],
          now: now,
          onTap: () => widget.onPlay(widget.channels[i]),
          onGoToCategory:
              widget.onGoToCategory == null ? null : () => widget.onGoToCategory!(widget.channels[i]),
          marked: widget.channels[i].id == widget.focusId,
        ),
      );
      }),
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile(
      {super.key,
      required this.channel,
      required this.now,
      required this.onTap,
      this.onGoToCategory,
      this.marked = false});
  final Channel channel;
  final int now;
  final VoidCallback onTap;
  final VoidCallback? onGoToCategory;
  final bool marked;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final cs = Theme.of(context).colorScheme;
    final cur = currentProgramme(channel, now);
    final fav = s.isFavorite(channel);
    final split = splitEventName(channel.name);
    String? catName;
    if (onGoToCategory != null) {
      for (final c in s.categories) {
        if (c.id == channel.categoryId) catName = c.name;
      }
    }
    return Material(
      color: marked ? accentOf(context).withOpacity(0.14) : Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              ChannelLogo(channel, size: 44),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (split.when != null)
                      Text(split.when!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: accentOf(context))),
                    Tooltip(
                      message: channel.name,
                      waitDuration: const Duration(milliseconds: 600),
                      child: Text(split.title,
                          // Event channels rarely have a guide: give the name two lines.
                          maxLines: cur == null ? 2 : 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 14.5, fontWeight: FontWeight.w600, height: 1.25)),
                    ),
                    if (cur != null) ...[
                      const SizedBox(height: 2),
                      Text(cur.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          value: cur.progressAt(now),
                          minHeight: 3,
                          color: accentOf(context),
                          backgroundColor: cs.surfaceContainerHighest,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                tooltip: fav ? 'Remove from favourites' : 'Add to favourites',
                icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                    color: fav ? accentOf(context) : cs.onSurfaceVariant),
                onPressed: () => s.toggleFavorite(channel),
              ),
              PopupMenuButton<String>(
                tooltip: 'More',
                icon: Icon(Icons.more_vert, color: cs.onSurfaceVariant),
                onSelected: (v) {
                  if (v == 'guide') {
                    showChannelGuide(context, channel, onWatch: onTap);
                  } else if (v == 'fav') {
                    s.toggleFavorite(channel);
                  } else if (v == 'cat') {
                    onGoToCategory?.call();
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'guide', child: Text('TV guide for this channel')),
                  PopupMenuItem(
                      value: 'fav',
                      child: Text(fav ? 'Remove from favourites' : 'Add to favourites')),
                  if (catName != null)
                    PopupMenuItem(value: 'cat', child: Text('Go to category: $catName')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Event channels are often named like "[DS] (27/11) 19:25 Herning - Esbjerg"
/// or "16:20 Kairat Almaty - Mjällby 11/26 [Disney+ DK]". Show the date and
/// time on their own small line above the name, so the match itself has room.
({String? when, String title}) splitEventName(String name) {
  final m = _eventRe.firstMatch(name);
  if (m == null) return (when: null, title: name);
  final title = m.group(4)!.trim();
  if (title.isEmpty) return (when: null, title: name);
  final tag = m.group(1)?.replaceAll(RegExp(r'[\[\]]'), '').trim();
  final date = m.group(2)?.replaceAll(RegExp(r'[()]'), '').trim();
  final when = [
    if (tag != null && tag.isNotEmpty) tag,
    if (date != null && date.isNotEmpty) date,
    m.group(3)!,
  ].join('  ·  ');
  return (when: when, title: title);
}

final _eventRe = RegExp(
    r'^\s*(\[[^\]]{1,10}\]\s*)?(\(?\d{1,2}[/.]\d{1,2}\)?\s+)?(\d{1,2}[:.]\d{2})\s*[-–|:]?\s+(.+)$');
