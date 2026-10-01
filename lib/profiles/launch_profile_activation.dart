import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../services/launch_profile_service.dart';
import '../utils/app_logger.dart';
import 'active_profile_provider.dart';
import 'profile_activation.dart';

/// Switches to the profile a `plezy://profile` link names, through the same
/// path as the profile picker (PIN prompt, binding, rollback on failure).
///
/// Returns true when that profile is active afterwards. An unknown profile
/// returns false so the caller falls back to its normal flow.
Future<bool> activateLaunchProfile(BuildContext context, LaunchProfileRequest request) async {
  final activeProfile = context.read<ActiveProfileProvider>();
  final profile = request.resolve(activeProfile.profiles);
  if (profile == null) {
    appLogger.w('Launch profile link matched no profile: $request');
    return false;
  }
  if (activeProfile.activeId == profile.id) return true;
  appLogger.i('Launch profile link: switching to ${profile.displayName}');
  return switchProfileFromUi(context, profile);
}
