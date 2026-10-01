import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../profiles/profile.dart';
import '../utils/app_logger.dart';

/// A request to open the app as a specific profile, from a
/// `plezy://profile?id=...` or `plezy://profile?name=...` link.
@immutable
class LaunchProfileRequest {
  const LaunchProfileRequest({this.id, this.name});

  /// Exact profile id, as carried by pinned launcher shortcuts.
  final String? id;

  /// Profile display name, matched case-insensitively. Meant for automation,
  /// where profile ids are not known up front.
  final String? name;

  static LaunchProfileRequest? fromChannel(Object? args) {
    if (args is! Map) return null;
    final id = args['id'];
    final name = args['name'];
    final request = LaunchProfileRequest(
      id: id is String && id.isNotEmpty ? id : null,
      name: name is String && name.trim().isNotEmpty ? name.trim() : null,
    );
    return request.id == null && request.name == null ? null : request;
  }

  /// The profile this request names, or null when none (or, by name, more
  /// than one) matches.
  Profile? resolve(List<Profile> profiles) {
    final id = this.id;
    if (id != null) {
      for (final profile in profiles) {
        if (profile.id == id) return profile;
      }
    }
    final name = this.name?.toLowerCase();
    if (name != null) {
      final matches = profiles.where((p) => p.displayName.trim().toLowerCase() == name).toList();
      if (matches.length == 1) return matches.single;
      if (matches.length > 1) appLogger.w('Launch profile link: ${matches.length} profiles share the requested name');
    }
    return null;
  }

  @override
  String toString() => 'LaunchProfileRequest(id: $id, name: $name)';
}

/// Bridges Android `plezy://profile` links and pinned profile shortcuts.
///
/// Cold-start links are pulled with [takeInitialRequest]; links that arrive
/// while the app is running go to [onProfileLink]. A link nobody accepts stays
/// pending natively until the next [takeInitialRequest].
class LaunchProfileService {
  static const MethodChannel _channel = MethodChannel('com.plezy/launch_profile');

  static final LaunchProfileService _instance = LaunchProfileService._internal();
  factory LaunchProfileService() => _instance;

  LaunchProfileService._internal() {
    if (Platform.isAndroid) _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Warm-start handler. Returns true once it has taken the request.
  Future<bool> Function(LaunchProfileRequest request)? onProfileLink;

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method != 'onProfileLink') return null;
    final request = LaunchProfileRequest.fromChannel(call.arguments);
    final handler = onProfileLink;
    if (request == null || handler == null) return false;
    return handler(request);
  }

  /// The pending profile link, consumed on read.
  Future<LaunchProfileRequest?> takeInitialRequest() async {
    if (!Platform.isAndroid) return null;
    try {
      return LaunchProfileRequest.fromChannel(await _channel.invokeMethod<Object?>('getInitialProfileLink'));
    } on MissingPluginException {
      return null;
    } on PlatformException catch (e) {
      appLogger.w('Failed to read launch profile link', error: e);
      return null;
    }
  }

  /// Whether the launcher accepts pinned shortcuts.
  Future<bool> isPinShortcutSupported() async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('isPinShortcutSupported') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException catch (e) {
      appLogger.w('Failed to query pinned shortcut support', error: e);
      return false;
    }
  }

  /// Asks the launcher to pin a shortcut that opens the app as [profile].
  /// Returns whether the request was handed to the launcher; the user still
  /// confirms it there.
  Future<bool> requestPinShortcut(Profile profile, {required String label, Uint8List? icon}) async {
    if (!Platform.isAndroid) return false;
    try {
      return await _channel.invokeMethod<bool>('requestPinShortcut', {
            'profileId': profile.id,
            'label': label,
            'icon': icon,
          }) ??
          false;
    } on PlatformException catch (e) {
      appLogger.w('Failed to request pinned profile shortcut', error: e);
      return false;
    }
  }
}
