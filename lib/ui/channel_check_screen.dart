import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../app_state.dart';
import '../models.dart';
import 'common.dart';

/// PC only: open every channel briefly and list the ones that don't answer.
/// Runs on this machine with your own connection; nothing leaves the PC.
class ChannelCheckScreen extends StatefulWidget {
  const ChannelCheckScreen({super.key});
  @override
  State<ChannelCheckScreen> createState() => _ChannelCheckScreenState();
}

class _Dead {
  _Dead(this.channel, this.url, ProbeResult r)
      : code = r.code,
        reason = r.reason!;
  final Channel channel;
  final String url;
  int? code; // HTTP response code, null when the server never answered
  String reason;

  String get codeText => code == null ? '—' : '$code';

  void update(ProbeResult r) {
    code = r.code;
    reason = r.reason!;
  }
}

class ProbeResult {
  const ProbeResult(this.code, this.reason);
  final int? code;
  final String? reason; // null = working
  bool get ok => reason == null;
}

const _kAll = '__all__';

class _ChannelCheckScreenState extends State<ChannelCheckScreen> {
  String _scope = _kAll;
  int _parallel = 1;
  bool _running = false;
  bool _stop = false;
  bool _finished = false;
  int _done = 0;
  int _total = 0;
  String _phase = '';
  final List<_Dead> _dead = [];
  DateTime? _started;

  List<Channel> _channels() {
    final all = AppState.I.channels;
    if (_scope == _kAll) return List.of(all);
    return [for (final c in all) if (c.categoryId == _scope) c];
  }

  String _categoryName(String id) {
    for (final c in AppState.I.categories) {
      if (c.id == id) return c.name;
    }
    return '';
  }

  Future<void> _start() async {
    final list = _channels();
    if (list.isEmpty) {
      toast(context, 'No channels to check');
      return;
    }
    setState(() {
      _running = true;
      _stop = false;
      _finished = false;
      _dead.clear();
      _done = 0;
      _total = list.length;
      _phase = 'Checking';
      _started = DateTime.now();
    });

    // Pass 1: every channel.
    final failed = <_Dead>[];
    await _runPool(list, _parallel, (c, url, r) {
      if (!r.ok) failed.add(_Dead(c, url, r));
    });

    // Pass 2: try the failures once more, one at a time, so a short hiccup
    // or the provider's connection limit doesn't mark a good channel dead.
    if (!mounted) return;
    if (!_stop && failed.isNotEmpty) {
      setState(() {
        _phase = 'Double-checking ${failed.length} failed';
        _done = 0;
        _total = failed.length;
      });
      await Future<void>.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      final byChannel = {for (final d in failed) d.channel: d};
      await _runPool([for (final d in failed) d.channel], 1, (c, url, r) {
        if (r.ok) {
          byChannel.remove(c);
        } else {
          byChannel[c]!.update(r);
        }
      });
      failed
        ..clear()
        ..addAll(byChannel.values);
    }

    if (!mounted) return;
    setState(() {
      _dead
        ..clear()
        ..addAll(failed);
      _running = false;
      _finished = !_stop;
      _phase = _stop ? 'Stopped' : 'Done';
    });
  }

  Future<void> _runPool(List<Channel> list, int parallel,
      void Function(Channel c, String url, ProbeResult r) onResult) async {
    var next = 0;
    final ua = AppState.I.settings.userAgent;
    Future<void> worker() async {
      while (!_stop && next < list.length) {
        final c = list[next++];
        final url = AppState.I.streamUrlFor(c);
        final r = await probeStream(url, ua);
        if (!mounted) return;
        onResult(c, url, r);
        setState(() {
          _done++;
          if (!r.ok && _phase == 'Checking') _dead.add(_Dead(c, url, r));
        });
      }
    }

    await Future.wait([for (var i = 0; i < parallel; i++) worker()]);
  }

  String _report() {
    final b = StringBuffer()
      ..writeln('Live TV – channels that did not work')
      ..writeln('Profile: ${AppState.I.active?.name ?? ''}')
      ..writeln('Checked: ${_started ?? DateTime.now()}')
      ..writeln('Scope: ${_scope == _kAll ? 'All channels' : _categoryName(_scope)}')
      ..writeln('Dead: ${_dead.length}')
      ..writeln('Note: the addresses below contain your login – do not share this file.')
      ..writeln();
    final sorted = List.of(_dead)
      ..sort((a, b) => _categoryName(a.channel.categoryId)
          .compareTo(_categoryName(b.channel.categoryId)));
    var cat = '\u0000';
    for (final d in sorted) {
      final n = _categoryName(d.channel.categoryId);
      if (n != cat) {
        cat = n;
        b
          ..writeln()
          ..writeln('[${n.isEmpty ? 'No category' : n}]');
      }
      b
        ..writeln('${d.channel.name}')
        ..writeln('  HTTP: ${d.codeText}   ${d.reason}')
        ..writeln('  ${d.url}');
    }
    return b.toString();
  }

  Future<void> _save() async {
    final dir = await getDownloadsDirectory() ?? await getApplicationDocumentsDirectory();
    final stamp = DateTime.now().toIso8601String().substring(0, 16).replaceAll(':', '.');
    final f = File('${dir.path}${Platform.pathSeparator}Dead channels $stamp.txt');
    await f.writeAsString(_report(), encoding: utf8);
    await launchUrl(Uri.file(f.path));
    if (mounted) toast(context, 'Saved to ${f.path}');
  }

  @override
  void dispose() {
    _stop = true;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cats = AppState.I.categories;
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Check channels')),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Opens each channel for a moment to see if it answers. Runs on this PC '
              'with your own connection. Most providers allow only 1–2 streams at a '
              'time, so keep "At a time" at 1 unless your subscription allows more.',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 16,
              runSpacing: 12,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                DropdownMenu<String>(
                  enabled: !_running,
                  initialSelection: _scope,
                  label: const Text('Channels'),
                  width: 320,
                  menuHeight: 400,
                  onSelected: (v) => setState(() => _scope = v ?? _kAll),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                        value: _kAll,
                        label: 'All channels (${AppState.I.channels.length})'),
                    for (final c in cats) DropdownMenuEntry(value: c.id, label: c.name),
                  ],
                ),
                DropdownMenu<int>(
                  enabled: !_running,
                  initialSelection: _parallel,
                  label: const Text('At a time'),
                  width: 140,
                  onSelected: (v) => setState(() => _parallel = v ?? 1),
                  dropdownMenuEntries: const [
                    DropdownMenuEntry(value: 1, label: '1'),
                    DropdownMenuEntry(value: 2, label: '2'),
                    DropdownMenuEntry(value: 4, label: '4'),
                  ],
                ),
                if (_running)
                  OutlinedButton.icon(
                    onPressed: () => setState(() => _stop = true),
                    icon: const Icon(Icons.stop_rounded),
                    label: const Text('Stop'),
                  )
                else
                  FilledButton.icon(
                    onPressed: _start,
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Start check'),
                  ),
              ],
            ),
            const SizedBox(height: 20),
            if (_running || _phase.isNotEmpty) ...[
              Row(children: [
                Text('$_phase  $_done / $_total', style: theme.textTheme.titleSmall),
                const Spacer(),
                Text('${_dead.length} not working',
                    style: theme.textTheme.titleSmall
                        ?.copyWith(color: _dead.isEmpty ? null : theme.colorScheme.error)),
              ]),
              const SizedBox(height: 8),
              LinearProgressIndicator(value: _total == 0 ? null : _done / _total),
              const SizedBox(height: 16),
            ],
            if (_finished && _dead.isEmpty)
              const Text('All checked channels answered.'),
            if (_dead.isNotEmpty && !_running)
              Row(children: [
                FilledButton.tonalIcon(
                  onPressed: _save,
                  icon: const Icon(Icons.save_alt_rounded),
                  label: const Text('Save list'),
                ),
                const SizedBox(width: 12),
                TextButton.icon(
                  onPressed: () {
                    Clipboard.setData(ClipboardData(text: _report()));
                    toast(context, 'List copied');
                  },
                  icon: const Icon(Icons.copy_rounded),
                  label: const Text('Copy'),
                ),
              ]),
            const SizedBox(height: 8),
            Expanded(
              child: Card(
                margin: EdgeInsets.zero,
                child: ListView.separated(
                  itemCount: _dead.length,
                  separatorBuilder: (_, __) => const Divider(height: 1),
                  itemBuilder: (_, i) {
                    final d = _dead[i];
                    return ListTile(
                      dense: true,
                      leading: ChannelLogo(d.channel, size: 32),
                      title: Text(d.channel.name),
                      subtitle: SelectableText(
                          '${_categoryName(d.channel.categoryId)}\n${d.url}',
                          maxLines: 2),
                      isThreeLine: true,
                      trailing: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('HTTP ${d.codeText}',
                              style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  color: theme.colorScheme.error)),
                          Text(d.reason, style: theme.textTheme.bodySmall),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens [url] and waits for the first bytes of video. Returns the HTTP
/// response code (null if the server never answered) and, when it doesn't
/// work, a short reason.
Future<ProbeResult> probeStream(String url, String userAgent) async {
  final client = HttpClient()
    ..connectionTimeout = const Duration(seconds: 8)
    ..userAgent = userAgent.isEmpty ? 'libmpv' : userAgent; // same as the player
  int? code;
  try {
    final req = await client.getUrl(Uri.parse(url)).timeout(const Duration(seconds: 8));
    req.followRedirects = true;
    req.maxRedirects = 5;
    final res = await req.close().timeout(const Duration(seconds: 10));
    code = res.statusCode;
    if (code != 200 && code != 206) {
      return ProbeResult(code, res.reasonPhrase.isEmpty ? 'Refused' : res.reasonPhrase);
    }
    final head = BytesBuilder(copy: false);
    var got = 0;
    await for (final chunk in res.timeout(const Duration(seconds: 10))) {
      got += chunk.length;
      if (head.length < 512) head.add(chunk);
      if (got >= 8192) break;
    }
    if (got == 0) return ProbeResult(code, 'No data');
    final start = latin1.decode(head.takeBytes().take(512).toList(), allowInvalid: true)
        .trimLeft()
        .toLowerCase();
    if (start.startsWith('<!doctype html') || start.startsWith('<html')) {
      return ProbeResult(code, 'Not a stream (web page)');
    }
    return ProbeResult(code, null);
  } on TimeoutException {
    return ProbeResult(code, code == null ? 'No answer' : 'No video data');
  } on SocketException {
    return ProbeResult(code, 'Connection failed');
  } on HandshakeException {
    return ProbeResult(code, 'Secure connection failed');
  } on HttpException {
    return ProbeResult(code, 'Connection failed');
  } catch (_) {
    return ProbeResult(code, 'Error');
  } finally {
    client.close(force: true);
  }
}
