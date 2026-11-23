enum ProfileType { xtream, m3u }

DateTime? _dt(Object? v) =>
    v is num ? DateTime.fromMillisecondsSinceEpoch(v.toInt()) : null;

class Profile {
  Profile({
    required this.id,
    required this.name,
    required this.type,
    this.server = '',
    this.username = '',
    this.password = '',
    this.m3uUrl = '',
    this.customEpgUrl = '',
    this.playlistEpgUrl = '',
    this.expDate,
    this.channelsUpdated,
    this.epgUpdated,
    Set<String>? favorites,
    Set<String>? favoriteCategories,
    List<String>? recents,
  })  : favorites = favorites ?? <String>{},
        favoriteCategories = favoriteCategories ?? <String>{},
        recents = recents ?? <String>[];

  final String id;
  String name;
  ProfileType type;
  String server;
  String username;
  String password;
  String m3uUrl;

  /// User override of the EPG (XMLTV) URL. Empty = use [defaultEpgUrl].
  String customEpgUrl;

  /// EPG URL announced in the M3U header (url-tvg / x-tvg-url).
  String playlistEpgUrl;
  DateTime? expDate;
  DateTime? channelsUpdated;
  DateTime? epgUpdated;
  final Set<String> favorites;
  final Set<String> favoriteCategories;
  final List<String> recents;

  bool get isXtream => type == ProfileType.xtream;

  String get host {
    final raw = isXtream ? server : m3uUrl;
    final u = Uri.tryParse(raw);
    return (u == null || u.host.isEmpty) ? raw : u.host;
  }

  String get defaultEpgUrl {
    if (isXtream) {
      if (server.isEmpty) return '';
      return '$server/xmltv.php?username=${Uri.encodeQueryComponent(username)}'
          '&password=${Uri.encodeQueryComponent(password)}';
    }
    return playlistEpgUrl;
  }

  String get effectiveEpgUrl =>
      customEpgUrl.trim().isNotEmpty ? customEpgUrl.trim() : defaultEpgUrl;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type.name,
        'server': server,
        'username': username,
        'password': password,
        'm3uUrl': m3uUrl,
        'customEpgUrl': customEpgUrl,
        'playlistEpgUrl': playlistEpgUrl,
        'expDate': expDate?.millisecondsSinceEpoch,
        'channelsUpdated': channelsUpdated?.millisecondsSinceEpoch,
        'epgUpdated': epgUpdated?.millisecondsSinceEpoch,
        'favorites': favorites.toList(),
        'favoriteCategories': favoriteCategories.toList(),
        'recents': recents,
      };

  factory Profile.fromJson(Map<String, dynamic> j) => Profile(
        id: j['id'] as String,
        name: j['name'] as String? ?? '',
        type: j['type'] == 'm3u' ? ProfileType.m3u : ProfileType.xtream,
        server: j['server'] as String? ?? '',
        username: j['username'] as String? ?? '',
        password: j['password'] as String? ?? '',
        m3uUrl: j['m3uUrl'] as String? ?? '',
        customEpgUrl: j['customEpgUrl'] as String? ?? '',
        playlistEpgUrl: j['playlistEpgUrl'] as String? ?? '',
        expDate: _dt(j['expDate']),
        channelsUpdated: _dt(j['channelsUpdated']),
        epgUpdated: _dt(j['epgUpdated']),
        favorites: <String>{
          for (final f in (j['favorites'] as List? ?? const [])) f as String
        },
        favoriteCategories: <String>{
          for (final f in (j['favoriteCategories'] as List? ?? const []))
            f as String
        },
        recents: <String>[
          for (final r in (j['recents'] as List? ?? const [])) r as String
        ],
      );
}

class Category {
  const Category(this.id, this.name);
  final String id;
  final String name;

  Map<String, dynamic> toJson() => {'i': id, 'n': name};
  factory Category.fromJson(Map<String, dynamic> j) =>
      Category(j['i'] as String, j['n'] as String? ?? '');
}

class Channel {
  const Channel({
    required this.id,
    required this.name,
    this.logo = '',
    this.epgId = '',
    this.categoryId = '',
    this.added = 0,
    this.number = 0,
    this.url = '',
  });

  /// Xtream stream_id, or the stream URL for M3U playlists.
  final String id;
  final String name;
  final String logo;
  final String epgId;
  final String categoryId;
  final int added;
  final int number;

  /// Direct URL (M3U only). Xtream URLs are built at play time.
  final String url;

  Map<String, dynamic> toJson() => {
        'i': id,
        'n': name,
        'l': logo,
        'e': epgId,
        'c': categoryId,
        'a': added,
        'o': number,
        'u': url,
      };

  factory Channel.fromJson(Map<String, dynamic> j) => Channel(
        id: j['i'] as String,
        name: j['n'] as String? ?? '',
        logo: j['l'] as String? ?? '',
        epgId: j['e'] as String? ?? '',
        categoryId: j['c'] as String? ?? '',
        added: (j['a'] as num?)?.toInt() ?? 0,
        number: (j['o'] as num?)?.toInt() ?? 0,
        url: j['u'] as String? ?? '',
      );
}

class Programme {
  const Programme(this.start, this.stop, this.title, this.desc);

  /// Epoch milliseconds (UTC instant).
  final int start;
  final int stop;
  final String title;
  final String desc;

  bool isLiveAt(int t) => start <= t && t < stop;
  double progressAt(int t) =>
      stop <= start ? 0 : ((t - start) / (stop - start)).clamp(0.0, 1.0).toDouble();
  Programme shifted(int ms) => Programme(start + ms, stop + ms, title, desc);
}

const epgFrequencies = <int, String>{
  0: 'Disabled',
  1: 'Every hour',
  4: 'Every 4 hours',
  12: 'Every 12 hours',
  24: 'Every day',
  48: 'Every 2 days',
  72: 'Every 3 days',
  168: 'Every 7 days',
};

class Settings {
  Settings();

  bool epgEnabled = true;
  int epgRefreshHours = 24;
  int epgTimeShiftHours = 0;
  String themeMode = 'system'; // system | light | dark
  String streamFormat = 'ts'; // ts | m3u8
  bool hwdec = true;
  String userAgent = '';
  bool epgView = false;

  Map<String, dynamic> toJson() => {
        'epgEnabled': epgEnabled,
        'epgRefreshHours': epgRefreshHours,
        'epgTimeShiftHours': epgTimeShiftHours,
        'themeMode': themeMode,
        'streamFormat': streamFormat,
        'hwdec': hwdec,
        'userAgent': userAgent,
        'epgView': epgView,
      };

  factory Settings.fromJson(Map<String, dynamic> j) => Settings()
    ..epgEnabled = j['epgEnabled'] as bool? ?? true
    ..epgRefreshHours = (j['epgRefreshHours'] as num?)?.toInt() ?? 24
    ..epgTimeShiftHours = (j['epgTimeShiftHours'] as num?)?.toInt() ?? 0
    ..themeMode = j['themeMode'] as String? ?? 'system'
    ..streamFormat = j['streamFormat'] as String? ?? 'ts'
    ..hwdec = j['hwdec'] as bool? ?? true
    ..userAgent = j['userAgent'] as String? ?? ''
    ..epgView = j['epgView'] as bool? ?? false;
}
