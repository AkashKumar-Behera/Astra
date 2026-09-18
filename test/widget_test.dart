import 'package:flutter_test/flutter_test.dart';
import 'package:astra/core/theme/astra_theme.dart';

void main() {
  test('AstraTheme initialization smoke test', () {
    final theme = AstraTheme.darkTheme;
    expect(theme, isNotNull);
    expect(theme.scaffoldBackgroundColor, isNotNull);
  });
}
