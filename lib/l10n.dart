import 'dart:io';

/// App language. 'auto' follows the device (Danish on a Danish PC, phone or
/// TV, otherwise English); Settings > Language can force one.
class L10n {
  static String setting = 'auto'; // auto | da | en

  static bool get isDanish {
    if (setting == 'da') return true;
    if (setting == 'en') return false;
    // e.g. da_DK, da-DK, en_US
    return Platform.localeName.toLowerCase().startsWith('da');
  }
}

/// Translate an English UI text. `{name}` placeholders are filled from [args].
String tr(String en, [Map<String, Object?> args = const {}]) {
  var s = (L10n.isDanish ? _da[en] : null) ?? en;
  args.forEach((k, v) => s = s.replaceAll('{$k}', '$v'));
  return s;
}

const _da = <String, String>{
  // ---------------------------------------------------------------- general
  'Save': 'Gem',
  'Saved': 'Gemt',
  'Cancel': 'Annuller',
  'Close': 'Luk',
  'Copy': 'Kopiér',
  'Clear': 'Ryd',
  'Delete': 'Slet',
  'Edit': 'Rediger',
  'Refresh': 'Opdater',
  'Stop': 'Stop',
  'Later': 'Senere',
  'Install': 'Installer',
  'Watch': 'Se',
  'Watch channel': 'Se kanalen',
  'Settings': 'Indstillinger',
  'Menu': 'Menu',
  'More': 'Mere',
  'Active': 'Aktiv',
  'Enabled': 'Slået til',
  'Try again': 'Prøv igen',
  'Today': 'I dag',
  'Tomorrow': 'I morgen',
  'Yesterday': 'I går',
  'No description.': 'Ingen beskrivelse.',
  'Language': 'Sprog',
  'Automatic': 'Automatisk',
  'Automatic (device language)': 'Automatisk (enhedens sprog)',

  // -------------------------------------------------------------- channels
  'Categories': 'Kategorier',
  'All channels': 'Alle kanaler',
  'All channels ({n})': 'Alle kanaler ({n})',
  'Favourite channels': 'Favoritkanaler',
  'Favourites': 'Favoritter',
  'Search channels': 'Søg kanaler',
  'Search categories': 'Søg kategorier',
  'Favourite categories only': 'Kun favoritkategorier',
  'Favourite category': 'Favoritkategori',
  'Remove favourite category': 'Fjern favoritkategori',
  'No favourite categories yet. Click a star to add one.':
      'Ingen favoritkategorier endnu. Klik på en stjerne for at tilføje en.',
  'No favourite channels yet. Click the star on a channel to add it.':
      'Ingen favoritkanaler endnu. Klik på stjernen ved en kanal for at tilføje den.',
  'Add to favourites': 'Tilføj til favoritter',
  'Remove from favourites': 'Fjern fra favoritter',
  'TV guide for this channel': 'Tv-guide for denne kanal',
  'Go to category: {name}': 'Gå til kategori: {name}',
  'Recently watched': 'Senest set',
  'Nothing watched yet': 'Intet set endnu',
  'No channels loaded yet': 'Ingen kanaler indlæst endnu',
  'No channels loaded': 'Ingen kanaler indlæst',
  'Load channels': 'Indlæs kanaler',
  'No channels match.': 'Ingen kanaler matcher.',
  'No channels in this category': 'Ingen kanaler i denne kategori',
  'Loading channels…': 'Indlæser kanaler…',
  'Updating channels…': 'Opdaterer kanaler…',
  'Updating TV guide…': 'Opdaterer tv-guide…',
  'Channel grid': 'Kanalgitter',
  'TV guide': 'Tv-guide',
  'Jump to now': 'Gå til nu',
  'No TV guide': 'Ingen tv-guide',
  'No TV guide for this channel': 'Ingen tv-guide for denne kanal',
  'Press BACK twice, then ◀ and OK for Settings':
      'Tryk TILBAGE to gange, derefter ◀ og OK for Indstillinger',
  'Settings  ·  update available': 'Indstillinger  ·  opdatering klar',
  '{n} min': '{n} min',

  // ---------------------------------------------------------------- player
  'Could not play this channel': 'Kanalen kunne ikke afspilles',
  "This channel isn't responding right now. Try again in a moment, or pick another channel.":
      'Kanalen svarer ikke lige nu. Prøv igen om lidt, eller vælg en anden kanal.',
  'Audio': 'Lyd',
  'Audio track': 'Lydspor',
  'Audio {n}': 'Lyd {n}',
  'Back (Esc)': 'Tilbage (Esc)',
  'Fullscreen (F)': 'Fuld skærm (F)',
  'Channel list (L)': 'Kanalliste (L)',
  'Mute (M)': 'Lyd fra (M)',
  'Pause (Space)': 'Pause (mellemrum)',
  'Play (Space)': 'Afspil (mellemrum)',
  'Previous channel (↑)': 'Forrige kanal (↑)',
  'Next channel (↓)': 'Næste kanal (↓)',

  // ------------------------------------------------------------------ menu
  'Playlist': 'Playliste',
  '{n} channels': '{n} kanaler',
  'updated {t}': 'opdateret {t}',
  'last {t}': 'senest {t}',
  'Last update failed: {e}': 'Sidste opdatering fejlede: {e}',
  'Updating channel list…': 'Opdaterer kanallisten…',
  'Channel list updated': 'Kanallisten er opdateret',
  'Video player settings': 'Afspillerindstillinger',
  'EPG': 'EPG',
  'Theme': 'Tema',
  'Follow system': 'Følg systemet',
  'Light': 'Lyst',
  'Dark': 'Mørkt',
  'Check channels': 'Tjek kanaler',
  "Find channels that don't work": 'Find kanaler, der ikke virker',
  'Check for updates': 'Søg efter opdateringer',
  'Version {v}': 'Version {v}',
  'Start on boot': 'Start ved opstart',
  'Off – open LiveTV Player when the device starts':
      'Fra – åbn LiveTV Player, når enheden starter',
  'On': 'Til',
  'On – allow "Display over other apps" for LiveTV Player to finish':
      'Til – tillad "Vis oven på andre apps" for LiveTV Player for at gøre det færdigt',
  'Open Android Settings > Apps > LiveTV Player and allow "Display over other apps"':
      'Åbn Android-indstillinger > Apps > LiveTV Player og tillad "Vis oven på andre apps"',
  'Start on boot is off': 'Start ved opstart er slået fra',
  'LiveTV Player will open when the device starts': 'LiveTV Player åbner, når enheden starter',
  'Share player log': 'Del afspillerlog',
  'Open the log of what the player does': 'Åbn loggen over, hvad afspilleren gør',
  'Save it to the Download folder, to help find playback problems':
      'Gem den i Download-mappen, så afspilningsfejl kan findes',
  'Send it to help find playback problems': 'Send den, så afspilningsfejl kan findes',
  'This is a local development build': 'Dette er en lokal udviklingsversion',
  'You have the latest version ({v})': 'Du har den nyeste version ({v})',
  'Manage profiles': 'Administrer profiler',
  'No profile': 'Ingen profil',
  'Expires {d}': 'Udløber {d}',

  // --------------------------------------------------------------- updates
  'Up to date': 'Opdateret',
  'Version {v} is available': 'Version {v} er klar',
  'Version {v} is available (you have {c}).': 'Version {v} er klar (du har {c}).',
  'You have {v}.': 'Du har {v}.',
  'Downloading… {p}%': 'Henter… {p}%',
  'Downloading version {v}… {p}%': 'Henter version {v}… {p}%',
  'Update failed: {e}': 'Opdatering fejlede: {e}',
  'Android may ask you to allow LiveTV Player to install apps the first time.':
      'Android spørger måske første gang, om LiveTV Player må installere apps.',
  'Could not verify the update (no checksum published)':
      'Opdateringen kunne ikke kontrolleres (ingen kontrolsum offentliggjort)',
  'The downloaded update failed verification and was deleted':
      'Den hentede opdatering bestod ikke kontrollen og blev slettet',
  'Download failed (HTTP {c})': 'Download fejlede (HTTP {c})',

  // -------------------------------------------------------------- profiles
  'Profiles': 'Profiler',
  'Add profile': 'Tilføj profil',
  'Edit profile': 'Rediger profil',
  'Add your IPTV provider to get started': 'Tilføj din IPTV-udbyder for at komme i gang',
  'Xtream Codes': 'Xtream Codes',
  'M3U / M3U8 playlist': 'M3U / M3U8-playliste',
  'Name': 'Navn',
  'e.g. Home': 'fx Hjemme',
  'Server URL': 'Serveradresse',
  'Username': 'Brugernavn',
  'Password': 'Adgangskode',
  'M3U / M3U8 URL': 'M3U / M3U8-adresse',
  'Server, username and password are required.': 'Server, brugernavn og adgangskode skal udfyldes.',
  'The playlist URL is required.': 'Playlistens adresse skal udfyldes.',
  'Could not load the channel list, so the profile was not added. Check the details and try again.':
      'Kanallisten kunne ikke hentes, så profilen blev ikke tilføjet. Tjek oplysningerne og prøv igen.',
  'Could not load the channel list, so the profile was not changed. Check the details and try again.':
      'Kanallisten kunne ikke hentes, så profilen blev ikke ændret. Tjek oplysningerne og prøv igen.',
  'Not loaded yet': 'Ikke indlæst endnu',
  'Profile refreshed': 'Profilen er opdateret',
  'Delete "{name}"?': 'Slet "{name}"?',
  'Its channel list, TV guide and favourites are removed from this PC.':
      'Dens kanalliste, tv-guide og favoritter fjernes fra denne enhed.',
  'Press →| on the keyboard when done. Back also saves.':
      'Tryk →| på tastaturet, når du er færdig. Tilbage gemmer også.',

  // ------------------------------------------------------------------- EPG
  'TV guide updated': 'Tv-guiden er opdateret',
  "Using the provider's default EPG": 'Bruger udbyderens egen EPG',
  'Last updated {t}': 'Senest opdateret {t}',
  'Never updated': 'Aldrig opdateret',
  'Refresh now': 'Opdater nu',
  'Updating…': 'Opdaterer…',
  'Refresh frequency': 'Opdateringsfrekvens',
  'Time shift': 'Tidsforskydning',
  'Custom URL': 'Egen adresse',
  'XMLTV address (.xml or .xml.gz).': 'XMLTV-adresse (.xml eller .xml.gz).',
  "Leave as is to use the provider's own guide. Clear resets it.":
      'Lad den stå for at bruge udbyderens egen guide. Ryd nulstiller den.',
  'Disabled': 'Slået fra',
  'Every hour': 'Hver time',
  'Every 4 hours': 'Hver 4. time',
  'Every 12 hours': 'Hver 12. time',
  'Every day': 'Hver dag',
  'Every 2 days': 'Hver 2. dag',
  'Every 3 days': 'Hver 3. dag',
  'Every 7 days': 'Hver 7. dag',

  // ------------------------------------------------------- player settings
  'Stream format': 'Streamformat',
  'Used for Xtream Codes profiles. Try HLS if a channel stutters.':
      'Bruges til Xtream Codes-profiler. Prøv HLS, hvis en kanal hakker.',
  'Hardware decoding': 'Hardwareafkodning',
  'Lower CPU use. Turn off if you see a black picture.':
      'Mindre CPU-forbrug. Slå fra, hvis billedet er sort.',
  'User agent': 'User agent',
  'Only needed if your provider requires a specific one. Empty = default.':
      'Kun nødvendig, hvis din udbyder kræver en bestemt. Tom = standard.',
  'Changes apply to the next channel you open.': 'Ændringer gælder fra næste kanal, du åbner.',
  'Keyboard in the player': 'Tastatur i afspilleren',
  'Space   pause         F   fullscreen (or double-click)\n':
      'Mellemrum   pause         F   fuld skærm (eller dobbeltklik)\n',
  '↑ / ↓  or  PgUp / PgDn   change channel\n': '↑ / ↓  eller  PgUp / PgDn   skift kanal\n',
  'L   channel list      I   programme info      Esc   back':
      'L   kanalliste      I   programinfo      Esc   tilbage',

  // --------------------------------------------------------- channel check
  'Opens each channel for a moment to see if it answers. Runs on this PC with your own connection. Most providers allow only 1–2 streams at a time, so keep "At a time" at 1 unless your subscription allows more.':
      'Åbner hver kanal et øjeblik for at se, om den svarer. Kører på denne pc med din egen forbindelse. De fleste udbydere tillader kun 1–2 streams ad gangen, så lad "Ad gangen" stå på 1, medmindre dit abonnement tillader flere.',
  'Channels': 'Kanaler',
  'At a time': 'Ad gangen',
  'Start check': 'Start tjek',
  'Checking': 'Tjekker',
  'Done': 'Færdig',
  'Stopped': 'Stoppet',
  'Double-checking {n} failed': 'Tjekker {n} fejlede igen',
  '{n} not working': '{n} virker ikke',
  'All checked channels answered.': 'Alle tjekkede kanaler svarede.',
  'Save list': 'Gem liste',
  'List copied': 'Listen er kopieret',
  'No channels to check': 'Ingen kanaler at tjekke',
  'Saved to {p}': 'Gemt i {p}',

  // ------------------------------------------------------------ player log
  'The log is empty – play a channel first': 'Loggen er tom – afspil en kanal først',
  'Opened {p}': 'Åbnede {p}',
  'Choose where to send the log': 'Vælg, hvor loggen skal sendes hen',
  'Could not share or save the log': 'Loggen kunne ikke deles eller gemmes',

  // ---------------------------------------------------------------- errors
  'The server did not respond in time': 'Serveren svarede ikke i tide',
  'Network error: {e}': 'Netværksfejl: {e}',
  'Invalid data: {e}': 'Ugyldige data: {e}',
  'The server responded with HTTP {c}': 'Serveren svarede med HTTP {c}',
  'The server returned an invalid response': 'Serveren sendte et ugyldigt svar',
  'Login was rejected by the server': 'Serveren afviste login',
  'No live channels were returned': 'Der kom ingen live-kanaler tilbage',
  'No live channels found in the playlist': 'Ingen live-kanaler fundet i playlisten',
  'No profile selected': 'Ingen profil valgt',
  'This profile has no EPG URL': 'Profilen har ingen EPG-adresse',
  'Load the channel list first': 'Indlæs kanallisten først',
  'The EPG contained no programmes for your channels': 'EPG’en indeholdt ingen programmer for dine kanaler',
  'The EPG server responded with HTTP {c}': 'EPG-serveren svarede med HTTP {c}',
};
