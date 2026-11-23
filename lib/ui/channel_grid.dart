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
          maxCrossAxisExtent: 460,
          mainAxisExtent: 76,
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
                    Text(channel.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w600)),
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
                          color: kAccent,
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
                    color: fav ? kAccent : cs.onSurfaceVariant),
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
