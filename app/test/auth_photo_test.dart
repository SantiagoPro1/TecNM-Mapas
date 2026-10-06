import 'package:flutter_test/flutter_test.dart';
import 'package:navia/data/providers/auth_provider.dart';

void main() {
  group('AuthState photoUrl resolution', () {
    test('returns cachedPhotoUrl when present', () {
      const state = AuthState(
        cachedPhotoUrl: 'https://lh3.googleusercontent.com/photo123',
      );
      expect(state.photoUrl, 'https://lh3.googleusercontent.com/photo123');
    });

    test('returns null when cachedPhotoUrl is empty or null and user is null', () {
      const state = AuthState(cachedPhotoUrl: '   ');
      expect(state.photoUrl, isNull);
    });

    test('copyWith preserves or overrides cachedPhotoUrl properly', () {
      const state = AuthState(
        cachedPhotoUrl: 'https://lh3.googleusercontent.com/original',
      );
      final updated = state.copyWith(
        cachedPhotoUrl: 'https://lh3.googleusercontent.com/new',
      );
      expect(updated.photoUrl, 'https://lh3.googleusercontent.com/new');
    });
  });
}
