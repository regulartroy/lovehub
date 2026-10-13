import 'package:flutter_test/flutter_test.dart';
import 'package:lovehub/services/app_check_setup.dart';

void main() {
  test('App Check activates only on web with a site key', () {
    expect(shouldActivateAppCheck(isWeb: true, siteKey: 'abc'), isTrue);
    expect(shouldActivateAppCheck(isWeb: true, siteKey: '  '), isFalse);
    expect(shouldActivateAppCheck(isWeb: false, siteKey: 'abc'), isFalse);
  });
}
