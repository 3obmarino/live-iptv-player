import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

class ChannelGrid extends StatelessWidget {
  const ChannelGrid({super.key, required this.channels, required this.onPlay});
  final List<Channel> channels;
  final void Function(Channel) onPlay;

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
      child: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          // Wider tiles (5 instead of 6 columns on a big screen) and room for
          // a time line + two lines of title, so event names aren't cut off.
          maxCrossAxisExtent: 540,
          mainAxisExtent: 92,
          crossAxisSpacing: 4,
          mainAxisSpacing: 2,
        ),
        itemCount: channels.length,
        itemBuilder: (ctx, i) => ChannelTile(
          channel: channels[i],
          now: now,
          onTap: () => onPlay(channels[i]),
        ),
      ),
    );
  }
}

class ChannelTile extends StatelessWidget {
  const ChannelTile(
      {super.key, required this.channel, required this.now, required this.onTap});
  final Channel channel;
  final int now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final cs = Theme.of(context).colorScheme;
    final cur = currentProgramme(channel, now);
    final fav = s.isFavorite(channel);
    final split = splitEventName(channel.name);
    return Material(
      color: Colors.transparent,
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
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(value: 'guide', child: Text('TV guide for this channel')),
                  PopupMenuItem(
                      value: 'fav',
                      child: Text(fav ? 'Remove from favourites' : 'Add to favourites')),
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
