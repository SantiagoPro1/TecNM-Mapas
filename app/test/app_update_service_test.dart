import 'package:flutter_test/flutter_test.dart';
import 'package:navia/services/update/app_update_service.dart';

void main() {
  AppUpdateInfo update(int installed, int remote) => AppUpdateInfo(
        latestVersion: '1.1.3',
        latestBuildNumber: remote,
        installedBuildNumber: installed,
        apkUrl: 'https://example.com/app.apk',
        releaseNotes: '',
      );

  test('Compares the installed APK build, even with the same version name', () {
    expect(update(17, 20).hasUpdate, isTrue);
    expect(update(20, 20).hasUpdate, isFalse);
    expect(update(21, 20).hasUpdate, isFalse);
  });
}
