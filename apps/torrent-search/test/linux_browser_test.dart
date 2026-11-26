// Gill(OS) Cloudflare helper: page titles, and (when a Chromium browser is installed) a real
// hidden page load.
import 'package:flutter_test/flutter_test.dart';
import 'package:seedfinder/desktop/linux_browser.dart';

void main() {
  test('Cloudflare check titles are recognised', () {
    expect(looksLikeChallengeTitle('Just a moment...'), isTrue);
    expect(looksLikeChallengeTitle('Attention Required! | Cloudflare'), isTrue);
    expect(looksLikeChallengeTitle('1337x | Free Movies, TV Series, Music, Games and Software'), isFalse);
  });

  test('the hidden browser loads a page', () async {
    final b = LinuxBrowser.instance;
    if (!b.available) {
      markTestSkipped('no Chromium browser here');
      return;
    }
    final ua = await b.userAgent();
    expect(ua, contains('Chrome/'));
    final html = await b.fetch(Uri.parse('https://example.com/'));
    expect(html, contains('Example Domain'));
  }, timeout: const Timeout(Duration(seconds: 60)));
}
