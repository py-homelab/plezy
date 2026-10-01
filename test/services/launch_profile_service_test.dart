import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/profiles/profile.dart';
import 'package:plezy/services/launch_profile_service.dart';

Profile _local(String id, String name) => Profile.local(id: id, displayName: name, createdAt: DateTime(2024));

Profile _plexHome(String id, String name) => Profile.plexHome(id: id, displayName: name, createdAt: DateTime(2024));

void main() {
  final adults = _plexHome('plex-home-conn-1-uuid-a', 'Adults');
  final kids = _plexHome('plex-home-conn-1-uuid-k', 'Kids');
  final guest = _local('local-guest', 'Guest');
  final profiles = [adults, kids, guest];

  group('LaunchProfileRequest.fromChannel', () {
    test('reads id and name', () {
      final request = LaunchProfileRequest.fromChannel({'id': 'abc', 'name': ' Kids '});
      expect(request?.id, 'abc');
      expect(request?.name, 'Kids');
    });

    test('rejects payloads without a usable id or name', () {
      expect(LaunchProfileRequest.fromChannel(null), isNull);
      expect(LaunchProfileRequest.fromChannel('plezy://profile'), isNull);
      expect(LaunchProfileRequest.fromChannel({'id': '', 'name': '  '}), isNull);
    });
  });

  group('LaunchProfileRequest.resolve', () {
    test('matches an exact id', () {
      expect(const LaunchProfileRequest(id: 'plex-home-conn-1-uuid-k').resolve(profiles), kids);
    });

    test('matches a name case-insensitively', () {
      expect(const LaunchProfileRequest(name: 'kids').resolve(profiles), kids);
      expect(const LaunchProfileRequest(name: 'GUEST').resolve(profiles), guest);
    });

    test('prefers the id over the name', () {
      expect(const LaunchProfileRequest(id: 'plex-home-conn-1-uuid-a', name: 'Kids').resolve(profiles), adults);
    });

    test('falls back to the name when the id is unknown', () {
      expect(const LaunchProfileRequest(id: 'plex-home-gone', name: 'Kids').resolve(profiles), kids);
    });

    test('returns null for no match or an ambiguous name', () {
      expect(const LaunchProfileRequest(name: 'Nobody').resolve(profiles), isNull);
      final duplicate = [...profiles, _local('local-kids', 'Kids')];
      expect(const LaunchProfileRequest(name: 'Kids').resolve(duplicate), isNull);
    });
  });
}
