import 'package:flutter/material.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';
import '../updater.dart' show kTvBuild;
import '../l10n.dart';

class EpgSettingsScreen extends StatefulWidget {
  const EpgSettingsScreen({super.key});
  @override
  State<EpgSettingsScreen> createState() => _EpgSettingsScreenState();
}

class _EpgSettingsScreenState extends State<EpgSettingsScreen> {
  late final TextEditingController _url =
      TextEditingController(text: AppState.I.active?.effectiveEpgUrl ?? '');

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _refreshNow() async {
    final err = await AppState.I.refreshEpg();
    if (mounted) toast(context, err ?? tr('TV guide updated'));
  }

  Future<void> _saveUrl() async {
    final s = AppState.I;
    final p = s.active;
    if (p == null) return;
    final v = _url.text.trim();
    final before = p.effectiveEpgUrl;
    p.customEpgUrl = v == p.defaultEpgUrl ? '' : v;
    await s.profileChanged(p);
    if (!mounted) return;
    toast(context, tr('Saved'));
    if (p.effectiveEpgUrl != before) _refreshNow();
  }

  Future<void> _clearUrl() async {
    final s = AppState.I;
    final p = s.active;
    if (p == null) return;
    p.customEpgUrl = '';
    _url.text = p.defaultEpgUrl;
    await s.profileChanged(p);
    if (mounted) toast(context, tr('Using the provider\'s default EPG'));
  }

  Future<void> _pickShift() async {
    final s = AppState.I;
    final v = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr('Time shift')),
        children: [
          SizedBox(
            width: 280,
            height: 420,
            child: ListView(children: [
              for (var h = -12; h <= 12; h++)
                ListTile(
                  dense: true,
                  selected: s.settings.epgTimeShiftHours == h,
                  selectedColor: accentOf(ctx),
                  title: Text(h == 0 ? '0h (no shift)' : '${h > 0 ? '+' : ''}${h}h'),
                  onTap: () => Navigator.pop(ctx, h),
                ),
            ]),
          ),
        ],
      ),
    );
    if (v != null) await s.updateSettings((x) => x.epgTimeShiftHours = v);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('EPG')),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final s = AppState.I;
          final p = s.active;
          final last = p?.epgUpdated;
          final next = s.nextEpgRefresh;
          var refreshSub = last == null ? tr('Never updated') : tr('Last updated {t}', {'t': fmtDateTime(last)});
          if (!s.epgLoading && s.epgError != null) {
            refreshSub += '\nLast attempt failed: ${s.epgError}';
          }
          final freqSub = tr(epgFrequencies[s.settings.epgRefreshHours] ?? '') +
              (next != null && s.settings.epgEnabled
                  ? '  ·  next update ${fmtDateTime(next.isBefore(DateTime.now()) ? DateTime.now() : next)}'
                  : '');
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            children: [
              SwitchListTile(
                autofocus: kTvBuild,
                title: Text(tr('Enabled')),
                value: s.settings.epgEnabled,
                onChanged: (v) => s.updateSettings((x) => x.epgEnabled = v),
              ),
              const Divider(),
              ListTile(
                enabled: !s.epgLoading && p != null && s.settings.epgEnabled,
                leading: s.epgLoading
                    ? const SizedBox(
                        width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.refresh),
                title: Text(s.epgLoading ? 'Updating…' : 'Refresh now'),
                subtitle: Text(refreshSub),
                onTap: _refreshNow,
              ),
              const Divider(),
              ListTile(
                enabled: s.settings.epgEnabled,
                leading: const Icon(Icons.update),
                title: Text(tr('Refresh frequency')),
                subtitle: Text(freqSub),
                onTap: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(builder: (_) => const _FrequencyScreen())),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.more_time),
                title: Text(tr('Time shift')),
                subtitle: Text('${s.settings.epgTimeShiftHours}h'),
                onTap: _pickShift,
              ),
              const Divider(),
              const SizedBox(height: 16),
              Text(tr('Custom URL'), style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text(
                p == null || p.defaultEpgUrl.isEmpty
                    ? tr('XMLTV address (.xml or .xml.gz).')
                    : tr('Leave as is to use the provider\'s own guide. Clear resets it.'),
                style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
              ),
              const SizedBox(height: 12),
              AppTextField(controller: _url, enabled: p != null),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: p == null ? null : _clearUrl,
                    child: Text(tr('Clear')),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(46)),
                    onPressed: p == null ? null : _saveUrl,
                    child: Text(tr('Save')),
                  ),
                ),
              ]),
            ],
          );
        },
      ),
    );
  }
}

class _FrequencyScreen extends StatelessWidget {
  const _FrequencyScreen();

  @override
  Widget build(BuildContext context) {
    final s = AppState.I;
    return Scaffold(
      appBar: AppBar(title: Text(tr('Refresh frequency'))),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          for (final e in epgFrequencies.entries)
            ListTile(
              leading: Icon(
                s.settings.epgRefreshHours == e.key
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: s.settings.epgRefreshHours == e.key ? accentOf(context) : null,
              ),
              title: Text(tr(e.value)),
              onTap: () async {
                await s.updateSettings((x) => x.epgRefreshHours = e.key);
                if (context.mounted) Navigator.pop(context);
              },
            ),
        ],
      ),
    );
  }
}
