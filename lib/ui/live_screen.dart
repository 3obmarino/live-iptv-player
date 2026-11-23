import 'dart:async';

import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'categories_screen.dart';
import 'channel_grid.dart';
import 'common.dart';
import 'epg_grid.dart';
import 'menu_screen.dart';
import 'player_screen.dart';

class LiveScreen extends StatefulWidget {
  const LiveScreen({super.key});
  @override
  State<LiveScreen> createState() => _LiveScreenState();
}

class _LiveScreenState extends State<LiveScreen> {
  /// null = All, kFavourites = favourite channels, otherwise a category id.
  String? _categoryId;
  String _query = '';
  String? _profileId;
  final _search = TextEditingController();
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Keeps "now playing" lines and progress bars current.
    _timer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _search.dispose();
    super.dispose();
  }

  List<Channel> _filtered(AppState s) {
    final q = _query.trim().toLowerCase();
    final fav = s.active?.favorites ?? const <String>{};
    return s.channels.where((c) {
      if (_categoryId == kFavourites) {
        if (!fav.contains(c.id)) return false;
      } else if (_categoryId != null && c.categoryId != _categoryId) {
        return false;
      }
      return q.isEmpty || c.name.toLowerCase().contains(q);
    }).toList();
  }

  String _categoryName(AppState s) {
    if (_categoryId == null) return 'All channels';
    if (_categoryId == kFavourites) return 'Favourite channels';
    for (final c in s.categories) {
      if (c.id == _categoryId) return c.name;
    }
    return 'All channels';
  }

  void _play(List<Channel> list, Channel c) {
    final i = list.indexOf(c);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => PlayerScreen(playlist: i < 0 ? [c] : list, index: i < 0 ? 0 : i),
    ));
  }

  Future<void> _pickCategory() async {
    final picked = await Navigator.of(context).push<String>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => CategoriesScreen(selected: _categoryId),
    ));
    if (picked == null) return;
    setState(() => _categoryId = picked == kAll ? null : picked);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        if (_profileId != s.activeId) {
          _profileId = s.activeId;
          _categoryId = null;
        }
        final list = _filtered(s);
        return Padding(
          padding: isCompact(context) ? const EdgeInsets.fromLTRB(8, 8, 8, 8) : const EdgeInsets.fromLTRB(8, 16, 20, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(context, s),
              const SizedBox(height: 16),
              Expanded(child: _body(context, s, list)),
            ],
          ),
        );
      },
    );
  }

  Widget _header(BuildContext context, AppState s) {
    final t = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final compact = isCompact(context);
    final busy = s.loadingChannels || s.epgLoading;

    final title = InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: _pickCategory,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisSize: MainAxisSize.min, children: [
              Text('Categories',
                  style: (compact ? t.titleLarge : t.headlineSmall)
                      ?.copyWith(fontWeight: FontWeight.w700)),
              const SizedBox(width: 6),
              Icon(Icons.keyboard_arrow_down_rounded, color: cs.onSurfaceVariant),
            ]),
            Text(_categoryName(s),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: t.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          ],
        ),
      ),
    );

    final status = busy
        ? Padding(
            padding: const EdgeInsets.only(right: 12),
            child: Tooltip(
              message: s.loadingChannels ? 'Updating channels…' : 'Updating TV guide…',
              child: Row(children: [
                const SizedBox(
                    width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2)),
                if (!compact) ...[
                  const SizedBox(width: 8),
                  Text(s.loadingChannels ? 'Updating channels…' : 'Updating TV guide…',
                      style: t.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                ],
              ]),
            ),
          )
        : const SizedBox.shrink();

    final search = TextField(
      controller: _search,
      onChanged: (v) => setState(() => _query = v),
      decoration: InputDecoration(
        hintText: 'Search channels',
        prefixIcon: const Icon(Icons.search, size: 20),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: cs.outlineVariant)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: cs.outlineVariant)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(24),
            borderSide: BorderSide(color: accentOf(context), width: 1.5)),
        suffixIcon: _query.isEmpty
            ? null
            : IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: () {
                  _search.clear();
                  setState(() => _query = '');
                },
              ),
      ),
    );

    final buttons = <Widget>[
      IconButton(
        tooltip: 'Recently watched',
        icon: const Icon(Icons.history),
        onPressed: () => _showRecents(context, s),
      ),
      IconButton(
        tooltip: s.settings.epgView ? 'Channel grid' : 'TV guide',
        icon: Icon(s.settings.epgView ? Icons.grid_view_rounded : Icons.view_list_rounded),
        onPressed: () => s.updateSettings((x) => x.epgView = !x.epgView),
      ),
      IconButton(
        tooltip: 'Menu',
        icon: const Icon(Icons.menu_rounded),
        onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const Text('Menu')),
            body: const MenuScreen(),
          ),
        )),
      ),
    ];

    if (compact) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [Expanded(child: Align(alignment: Alignment.centerLeft, child: title)), status, ...buttons]),
          const SizedBox(height: 8),
          search,
        ],
      );
    }
    return Row(
      children: [
        title,
        const Spacer(),
        status,
        SizedBox(width: 340, child: search),
        const SizedBox(width: 8),
        ...buttons,
      ],
    );
  }

  Widget _body(BuildContext context, AppState s, List<Channel> list) {
    final cs = Theme.of(context).colorScheme;
    if (s.channels.isEmpty) {
      if (s.loadingChannels) {
        return const Center(child: CircularProgressIndicator());
      }
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(s.channelsError ?? 'No channels loaded yet',
              textAlign: TextAlign.center,
              style: TextStyle(color: cs.onSurfaceVariant)),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () {
              final p = s.active;
              if (p != null) s.refreshChannels(p);
            },
            icon: const Icon(Icons.refresh),
            label: const Text('Load channels'),
          ),
        ]),
      );
    }
    if (list.isEmpty) {
      return Center(
        child: Text(
          _categoryId == kFavourites
              ? 'No favourite channels yet. Click the star on a channel to add it.'
              : 'No channels match.',
          style: TextStyle(color: cs.onSurfaceVariant),
        ),
      );
    }
    if (s.settings.epgView) {
      return EpgGrid(channels: list, onPlay: (c) => _play(list, c));
    }
    return ChannelGrid(channels: list, onPlay: (c) => _play(list, c));
  }

  void _showRecents(BuildContext context, AppState s) {
    final rec = s.recentChannels;
    final now = DateTime.now().millisecondsSinceEpoch;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recently watched'),
        content: SizedBox(
          width: 440,
          height: 480,
          child: rec.isEmpty
              ? const Center(child: Text('Nothing watched yet'))
              : ListView(children: [
                  for (final c in rec)
                    ListTile(
                      leading: ChannelLogo(c, size: 36),
                      title: Text(c.name),
                      subtitle: Text(currentProgramme(c, now)?.title ?? ''),
                      onTap: () {
                        Navigator.pop(ctx);
                        _play(rec, c);
                      },
                    ),
                ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }
}
