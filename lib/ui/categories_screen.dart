import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';

const kAll = '__all__';
const kFavourites = '__fav__';

/// Full-page category picker. Pops with the chosen id (kAll, kFavourites
/// or a category id). Star = favourite category; the switch top-right shows
/// favourite categories only.
class CategoriesScreen extends StatefulWidget {
  const CategoriesScreen({super.key, this.selected});
  final String? selected;
  @override
  State<CategoriesScreen> createState() => _CategoriesScreenState();
}

class _CategoriesScreenState extends State<CategoriesScreen> {
  String _q = '';
  bool _favOnly = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        final counts = <String, int>{};
        for (final c in s.channels) {
          counts[c.categoryId] = (counts[c.categoryId] ?? 0) + 1;
        }
        final favCount = s.active?.favorites.length ?? 0;
        final q = _q.trim().toLowerCase();
        final cats = s.categories.where((c) {
          if ((counts[c.id] ?? 0) == 0) return false;
          if (_favOnly && !s.isFavoriteCategory(c.id)) return false;
          return q.isEmpty || c.name.toLowerCase().contains(q);
        }).toList()
          // favourite categories first, otherwise provider order
          ..sort((a, b) {
            final fa = s.isFavoriteCategory(a.id) ? 0 : 1;
            final fb = s.isFavoriteCategory(b.id) ? 0 : 1;
            return fa.compareTo(fb);
          });

        Widget row(String id, String name, int count, {bool star = true, IconData? icon}) {
          final sel = (widget.selected ?? kAll) == id;
          final fav = s.isFavoriteCategory(id);
          return Column(children: [
            ListTile(
              selected: sel,
              selectedColor: kAccent,
              contentPadding: const EdgeInsets.symmetric(horizontal: 20),
              leading: icon == null ? null : Icon(icon, size: 20),
              title: Text(name,
                  style: TextStyle(fontWeight: sel ? FontWeight.w600 : FontWeight.w400)),
              trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                Text('$count', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                const SizedBox(width: 8),
                if (star)
                  IconButton(
                    tooltip: fav ? 'Remove favourite category' : 'Favourite category',
                    icon: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded,
                        color: fav ? kAccent : cs.onSurfaceVariant),
                    onPressed: () => s.toggleFavoriteCategory(id),
                  )
                else
                  const SizedBox(width: 48),
              ]),
              onTap: () => Navigator.pop(context, id),
            ),
            const Divider(indent: 20, endIndent: 20),
          ]);
        }

        final compact = isCompact(context);
        final searchField = TextField(
          autofocus: !compact,
          onChanged: (v) => setState(() => _q = v),
          decoration: const InputDecoration(
              hintText: 'Search categories',
              prefixIcon: Icon(Icons.search, size: 20)),
        );
        return Scaffold(
          appBar: AppBar(
            leading: IconButton(
                icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
            title: const Text('Categories'),
            actions: [
              if (!compact) SizedBox(width: 340, child: searchField),
              const SizedBox(width: 16),
              Tooltip(
                message: 'Favourite categories only',
                child: Row(children: [
                  Icon(Icons.star_rounded, size: 20, color: cs.onSurfaceVariant),
                  Switch(
                    value: _favOnly,
                    onChanged: (v) => setState(() => _favOnly = v),
                  ),
                ]),
              ),
              const SizedBox(width: 16),
            ],
            bottom: compact
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(60),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                      child: searchField,
                    ),
                  )
                : null,
          ),
          body: ListView(children: [
            if (!_favOnly && q.isEmpty) ...[
              row(kAll, 'All channels', s.channels.length,
                  star: false, icon: Icons.apps_rounded),
              row(kFavourites, 'Favourite channels', favCount,
                  star: false, icon: Icons.star_rounded),
            ],
            for (final c in cats) row(c.id, c.name, counts[c.id] ?? 0),
            if (cats.isEmpty && _favOnly)
              Padding(
                padding: const EdgeInsets.all(32),
                child: Text('No favourite categories yet. Click a star to add one.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: cs.onSurfaceVariant)),
              ),
          ]),
        );
      },
    );
  }
}
