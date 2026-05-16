// Placeholder smoke test. Real UI tests live in their own files.
import 'package:dustman/core/i18n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('AppLocalizations falls back to zh when key missing', () {
    final loc = AppLocalizations('en');
    expect(loc.t('nav.junk'), 'Junk Cleaner');
    expect(loc.t('does.not.exist'), 'does.not.exist');
  });
}
