// Cloudflare on Gill(OS): Flutter has no web view on Linux, so the app borrows the system's
// Chromium browser (Brave on Gill(OS)) with a private profile of its own:
//  - Verify: the site opens in a small Brave window; once the check is passed (the page title
//    stops being Cloudflare's), the window closes by itself and Brave saves the pass.
//  - Searching: pages from verified sites are loaded by the same browser, hidden (headless),
//    so Cloudflare sees the same browser, cookies and identity it already trusted.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

class LinuxBrowser {
  LinuxBrowser._();
  static final instance = LinuxBrowser._();

  static const _candidates = ['brave-browser', 'brave', 'chromium-browser', 'chromium', 'google-chrome'];
  String? _binary;
  String? _ua;
  bool _probed = false;
  Future<void> _queue = Future.value();

  String get _profile => '${Platform.environment['HOME'] ?? '/tmp'}/.local/share/torrent-search-engine/browser';

  /// The browser, if one is installed.
  String? get binary {
    if (!_probed) {
      _probed = true;
      for (final name in _candidates) {
        for (final dir in (Platform.environment['PATH'] ?? '/usr/bin:/bin').split(':')) {
          final f = File('$dir/$name');
          if (f.existsSync()) {
            _binary = f.path;
            break;
          }
        }
        if (_binary != null) break;
      }
    }
    return _binary;
  }

  bool get available => binary != null;

  /// One identity for the window and the hidden loads: Chrome's own (reduced) user agent for the
  /// installed version, so the pass Cloudflare gave the window is valid for searches too.
  Future<String> userAgent() async {
    if (_ua != null) return _ua!;
    var major = 140;
    try {
      final r = await Process.run(binary!, ['--version']).timeout(const Duration(seconds: 10));
      final m = RegExp(r'(\d{2,3})\.').allMatches('${r.stdout}');
      for (final x in m) {
        final v = int.parse(x.group(1)!);
        if (v >= 90 && v < 400) {
          major = v;
          break;
        }
      }
    } catch (_) {}
    return _ua = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) '
        'Chrome/$major.0.0.0 Safari/537.36';
  }

  // Chromium refuses to run as root without this (only happens in build/test containers)
  static bool get _root => Platform.environment['USER'] == 'root' || Platform.environment['HOME'] == '/root';

  List<String> _common(String ua) => [
        if (_root) '--no-sandbox',
        '--user-data-dir=$_profile',
        '--user-agent=$ua',
        '--password-store=basic',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-sync',
      ];

  /// Runs [job] after any earlier browser job (one profile can't be opened twice at once).
  Future<T> _serial<T>(Future<T> Function() job) {
    final c = Completer<T>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await job());
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  /// Opens [site] in a small browser window for the user to pass the check. Returns the
  /// browser's user agent once the page is the real site, or null if the window was closed first.
  Future<String?> verify(Uri site, {Duration timeout = const Duration(minutes: 4)}) => _serial(() async {
        final ua = await userAgent();
        final port = 9300 + Random().nextInt(500);
        final p = await Process.start(binary!, [
          ..._common(ua),
          '--remote-debugging-port=$port',
          '--remote-allow-origins=http://127.0.0.1:$port',
          '--window-size=1000,760',
          '--app=$site',
        ]);
        p.stdout.drain<void>();
        p.stderr.drain<void>();
        var exited = false;
        unawaited(p.exitCode.then((_) => exited = true));
        final until = DateTime.now().add(timeout);
        var passedSince = DateTime(3000);
        final client = HttpClient()..connectionTimeout = const Duration(seconds: 2);
        try {
          while (!exited && DateTime.now().isBefore(until)) {
            await Future<void>.delayed(const Duration(milliseconds: 1200));
            final tab = await _tab(client, port, site.host);
            if (tab == null) continue;
            final title = '${tab['title'] ?? ''}';
            final loading = title.isEmpty || title == site.host || title.startsWith('http');
            final challenged = looksLikeChallengeTitle(title);
            if (!loading && !challenged) {
              // stay a moment on the real page so the pass is stored, then close the window
              if (passedSince.year == 3000) passedSince = DateTime.now();
              if (DateTime.now().difference(passedSince) > const Duration(seconds: 2)) {
                await _get(client, 'http://127.0.0.1:$port/json/close/${tab['id']}');
                await p.exitCode.timeout(const Duration(seconds: 8), onTimeout: () {
                  p.kill();
                  return 0;
                });
                return ua;
              }
            } else {
              passedSince = DateTime(3000);
            }
          }
          return null;
        } finally {
          client.close(force: true);
          if (!exited) p.kill();
        }
      });

  /// Loads [url] in a hidden browser and returns the page, after scripts have run. Each load gets
  /// a throwaway copy of the profile's cookies, so several sources load at once.
  Future<String> fetch(Uri url) async {
    final ua = await userAgent();
    final tmp = Directory.systemTemp.createTempSync('tse-browser-');
    try {
      final def = Directory('${tmp.path}/Default')..createSync();
      for (final name in ['Cookies', 'Cookies-journal']) {
        final f = File('$_profile/Default/$name');
        if (f.existsSync()) f.copySync('${def.path}/$name');
      }
      final r = await Process.run(binary!, [
          ..._common(ua).map((a) => a.startsWith('--user-data-dir=') ? '--user-data-dir=${tmp.path}' : a),
          '--headless=new',
          '--disable-gpu',
          '--virtual-time-budget=9000',
          '--dump-dom',
          '$url',
        ]).timeout(const Duration(seconds: 30));
        var html = '${r.stdout}';
        // JSON APIs come back wrapped in a page: unwrap them
        final pre = RegExp(r'^\s*<html><head>.*?</head><body><pre[^>]*>(.*)</pre>', dotAll: true).firstMatch(html);
        if (pre != null) html = _unescape(pre.group(1)!);
        return html;
    } finally {
      try {
        tmp.deleteSync(recursive: true);
      } catch (_) {}
    }
  }

  Future<Map<String, dynamic>?> _tab(HttpClient client, int port, String host) async {
    final body = await _get(client, 'http://127.0.0.1:$port/json/list');
    if (body == null) return null;
    try {
      final list = jsonDecode(body) as List;
      for (final t in list) {
        if (t is Map<String, dynamic> && t['type'] == 'page') return t;
      }
    } catch (_) {}
    return null;
  }

  Future<String?> _get(HttpClient client, String url) async {
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close().timeout(const Duration(seconds: 3));
      return await res.transform(utf8.decoder).join();
    } catch (_) {
      return null;
    }
  }

  static String _unescape(String s) => s
      .replaceAll('&quot;', '"')
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&#39;', "'")
      .replaceAll('&amp;', '&');
}

/// Cloudflare's check page titles.
bool looksLikeChallengeTitle(String title) {
  final t = title.toLowerCase();
  return t.contains('just a moment') || t.contains('attention required') || t.contains('checking your browser') ||
      t.contains('verify you are human') || t.contains('one more step') || t.contains('security check');
}
