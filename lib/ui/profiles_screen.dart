import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import '../l10n.dart';

class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AppState.I,
      builder: (context, _) {
        final s = AppState.I;
        final cs = Theme.of(context).colorScheme;
        final canPop = Navigator.of(context).canPop();
        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: canPop,
            title: Text(tr('Profiles')),
          ),
          floatingActionButton: FilledButton.icon(
            // Focused on first start, so OK on the remote opens it directly.
            autofocus: s.profiles.isEmpty,
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 20),
              textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w600),
            ),
            onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const EditProfileScreen())),
            icon: const Icon(Icons.add),
            label: Text(tr('Add profile')),
          ),
          body: s.profiles.isEmpty
              ? Center(
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.live_tv_rounded, size: 56, color: cs.onSurfaceVariant),
                    const SizedBox(height: 16),
                    Text(tr('Add your IPTV provider to get started'),
                        style: TextStyle(fontSize: 16)),
                  ]),
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: Wrap(
                    spacing: 16,
                    runSpacing: 16,
                    children: [for (final p in s.profiles) _ProfileCard(p)],
                  ),
                ),
        );
      },
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard(this.p);
  final Profile p;

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    final cs = Theme.of(context).colorScheme;
    final isActive = s.activeId == p.id;
    return SizedBox(
      width: isCompact(context) ? MediaQuery.sizeOf(context).width - 48 : 360,
      child: Card(
        elevation: 0,
        color: cs.surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: isActive ? accentOf(context) : cs.outlineVariant, width: isActive ? 1.5 : 1),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () async {
            await s.setActive(p);
            if (context.mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
          },
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 4, 16),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  backgroundColor: accentOf(context),
                  child: Text(p.name.isEmpty ? '?' : p.name.substring(0, 1).toUpperCase(),
                      style: TextStyle(color: onAccentOf(context), fontWeight: FontWeight.w700)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                      Text('${p.isXtream ? 'Xtream Codes' : 'M3U'} · ${p.host}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                      const SizedBox(height: 6),
                      Row(children: [
                        Icon(Icons.schedule, size: 14, color: cs.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                            p.channelsUpdated == null
                                ? tr('Not loaded yet')
                                : fmtDateTime(p.channelsUpdated!),
                            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
                      ]),
                      if (isActive)
                        Padding(
                          padding: const EdgeInsets.only(top: 6),
                          child: Text(tr('Active'),
                              style: TextStyle(color: accentOf(context), fontWeight: FontWeight.w600, fontSize: 12.5)),
                        ),
                    ],
                  ),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) => _action(context, v),
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'refresh', child: Text(tr('Refresh'))),
                    PopupMenuItem(value: 'edit', child: Text(tr('Edit'))),
                    PopupMenuItem(value: 'delete', child: Text(tr('Delete'))),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _action(BuildContext context, String v) async {
    final s = AppState.I;
    if (v == 'edit') {
      Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => EditProfileScreen(existing: p)));
    } else if (v == 'refresh') {
      var err = await s.refreshChannels(p);
      if (err == null && s.activeId == p.id) err = await s.refreshEpg();
      if (context.mounted) toast(context, err ?? tr('Profile refreshed'));
    } else if (v == 'delete') {
      final ok = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr('Delete "{name}"?', {'name': p.name})),
          content: Text(tr('Its channel list, TV guide and favourites are removed from this PC.')),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: Text(tr('Cancel'))),
            FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(tr('Delete'))),
          ],
        ),
      );
      if (ok == true) await s.deleteProfile(p);
    }
  }
}

class EditProfileScreen extends StatefulWidget {
  const EditProfileScreen({super.key, this.existing});
  final Profile? existing;
  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late ProfileType _type = widget.existing?.type ?? ProfileType.xtream;
  late final _name = TextEditingController(text: widget.existing?.name ?? '');
  late final _server = TextEditingController(text: widget.existing?.server ?? '');
  late final _user = TextEditingController(text: widget.existing?.username ?? '');
  late final _pass = TextEditingController(text: widget.existing?.password ?? '');
  late final _m3u = TextEditingController(text: widget.existing?.m3uUrl ?? '');
  bool _busy = false;
  bool _hidePass = true;
  String? _err;

  @override
  void dispose() {
    for (final c in [_name, _server, _user, _pass, _m3u]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final xt = _type == ProfileType.xtream;
    if (xt && (_server.text.trim().isEmpty || _user.text.trim().isEmpty || _pass.text.trim().isEmpty)) {
      setState(() => _err = tr('Server, username and password are required.'));
      return;
    }
    if (!xt && _m3u.text.trim().isEmpty) {
      setState(() => _err = tr('The playlist URL is required.'));
      return;
    }
    setState(() {
      _err = null;
      _busy = true;
    });
    final e = widget.existing;
    final p = Profile(
      id: e?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      name: '',
      type: _type,
      server: normalizeServerInput(_server.text),
      username: _user.text.trim(),
      password: _pass.text.trim(),
      m3uUrl: _m3u.text.trim(),
      customEpgUrl: e?.customEpgUrl ?? '',
      playlistEpgUrl: e?.playlistEpgUrl ?? '',
      expDate: e?.expDate,
      channelsUpdated: e?.channelsUpdated,
      epgUpdated: e?.epgUpdated,
      favorites: e?.favorites,
      favoriteCategories: e?.favoriteCategories,
      recents: e?.recents,
    );
    p.name = _name.text.trim().isEmpty ? p.host : _name.text.trim();

    final s = AppState.I;
    // Only saved when the channel list actually loads.
    final err = await s.refreshChannels(p, addIfValid: true);
    if (!mounted) return;
    if (err != null) {
      setState(() {
        _busy = false;
        _err = 'Could not load the channel list, so the profile was not '
            '${e == null ? 'added' : 'changed'}. Check the details and try again.\n$err';
      });
      return;
    }
    if (s.activeId == p.id) {
      p.epgUpdated = null; // credentials may have changed: fetch a fresh guide
      s.refreshEpg();
    }
    // As the very first screen there is nothing to go back to: the app
    // switches to the channels by itself once the profile is active.
    if (Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final xt = _type == ProfileType.xtream;
    final cs = Theme.of(context).colorScheme;
    InputDecoration dec(String label, [String? hint]) =>
        InputDecoration(labelText: label, hintText: hint);
    return Scaffold(
      appBar: AppBar(title: Text(widget.existing == null ? 'Add profile' : 'Edit profile')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<ProfileType>(
                  showSelectedIcon: false,
                  segments: [
                    ButtonSegment(value: ProfileType.xtream, label: Text('Xtream Codes')),
                    ButtonSegment(value: ProfileType.m3u, label: Text(tr('M3U / M3U8 playlist'))),
                  ],
                  selected: {_type},
                  onSelectionChanged: (v) => setState(() => _type = v.first),
                ),
                const SizedBox(height: 24),
                AppTextField(
                    controller: _name,
                    textInputAction: TextInputAction.next,
                    decoration: dec(tr('Name'), tr('e.g. Home'))),
                const SizedBox(height: 14),
                if (xt) ...[
                  AppTextField(
                      controller: _server,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.next,
                      decoration: dec(tr('Server URL'), 'http://example.com:8080')),
                  const SizedBox(height: 14),
                  AppTextField(
                      controller: _user,
                      textInputAction: TextInputAction.next,
                      decoration: dec(tr('Username'))),
                  const SizedBox(height: 14),
                  AppTextField(
                    controller: _pass,
                    obscureText: _hidePass,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _busy ? null : _save(),
                    decoration: dec(tr('Password')).copyWith(
                      suffixIcon: IconButton(
                        icon: Icon(_hidePass ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _hidePass = !_hidePass),
                      ),
                    ),
                  ),
                ] else
                  AppTextField(
                      controller: _m3u,
                      keyboardType: TextInputType.url,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _busy ? null : _save(),
                      decoration: dec(tr('M3U / M3U8 URL'))),
                if (_err != null) ...[
                  const SizedBox(height: 16),
                  Text(_err!, style: TextStyle(color: cs.error)),
                ],
                const SizedBox(height: 28),
                FilledButton(
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                  onPressed: _busy ? null : _save,
                  child: _busy
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : Text(widget.existing == null ? 'Add profile' : 'Save'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Re-exported here so the UI does not import api.dart just for this.
String normalizeServerInput(String s) {
  var v = s.trim();
  if (v.isEmpty) return v;
  if (!v.contains('://')) v = 'http://$v';
  final u = Uri.tryParse(v);
  if (u == null || u.host.isEmpty) return v;
  return Uri(scheme: u.scheme, host: u.host, port: u.hasPort ? u.port : null).toString();
}
