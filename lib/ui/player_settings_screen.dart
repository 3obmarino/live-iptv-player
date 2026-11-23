import 'package:flutter/material.dart';

import '../app_state.dart';
import 'common.dart';

class PlayerSettingsScreen extends StatefulWidget {
  const PlayerSettingsScreen({super.key});
  @override
  State<PlayerSettingsScreen> createState() => _PlayerSettingsScreenState();
}

class _PlayerSettingsScreenState extends State<PlayerSettingsScreen> {
  late final TextEditingController _ua =
      TextEditingController(text: AppState.I.settings.userAgent);

  @override
  void dispose() {
    _ua.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Video player settings')),
      body: ListenableBuilder(
        listenable: AppState.I,
        builder: (context, _) {
          final s = AppState.I;
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            children: [
              const SizedBox(height: 8),
              const Text('Stream format', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Used for Xtream Codes profiles. Try HLS if a channel stutters.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 12),
              SegmentedButton<String>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: 'ts', label: Text('MPEG-TS (.ts)')),
                  ButtonSegment(value: 'm3u8', label: Text('HLS (.m3u8)')),
                ],
                selected: {s.settings.streamFormat},
                onSelectionChanged: (v) => s.updateSettings((x) => x.streamFormat = v.first),
              ),
              const SizedBox(height: 16),
              const Divider(),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Hardware decoding'),
                subtitle: const Text('Lower CPU use. Turn off if you see a black picture.'),
                value: s.settings.hwdec,
                onChanged: (v) => s.updateSettings((x) => x.hwdec = v),
              ),
              const Divider(),
              const SizedBox(height: 16),
              const Text('User agent', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 4),
              Text('Only needed if your provider requires a specific one. Empty = default.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
              const SizedBox(height: 12),
              TextField(controller: _ua),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: () async {
                    await s.updateSettings((x) => x.userAgent = _ua.text.trim());
                    if (context.mounted) toast(context, 'Saved');
                  },
                  child: const Text('Save'),
                ),
              ),
              const SizedBox(height: 24),
              Text('Changes apply to the next channel you open.',
                  style: TextStyle(color: cs.onSurfaceVariant, fontSize: 12.5)),
              const SizedBox(height: 24),
              const Text('Keyboard in the player', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(
                '↑ / ↓  or  PgUp / PgDn   change channel\n'
                '← / →   volume        M   mute\n'
                'Space   pause         F   fullscreen (or double-click)\n'
                'L   channel list      I   programme info      Esc   back',
                style: TextStyle(color: cs.onSurfaceVariant, height: 1.6),
              ),
            ],
          );
        },
      ),
    );
  }
}
