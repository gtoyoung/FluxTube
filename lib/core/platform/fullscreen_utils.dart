import 'package:flutter/services.dart';

/// YouTube-style fullscreen manager.
/// Enters/exits immersive mode and locks/unlocks orientation.
class FullscreenUtils {
  FullscreenUtils._();

  static bool _isFullscreen = false;

  static bool get isFullscreen => _isFullscreen;

  /// Enter fullscreen: immersive sticky + landscape lock.
  static Future<void> enterFullscreen() async {
    if (_isFullscreen) return;
    _isFullscreen = true;

    await Future.wait([
      SystemChrome.setEnabledSystemUIMode(
        SystemUiMode.immersiveSticky,
        overlays: [],
      ),
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.landscapeLeft,
        DeviceOrientation.landscapeRight,
      ]),
    ]);
  }

  /// Exit fullscreen: restore system UI + portrait lock.
  static Future<void> exitFullscreen() async {
    if (!_isFullscreen) return;
    _isFullscreen = false;

    await Future.wait([
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    ]);
  }

  /// Toggle fullscreen state.
  static Future<void> toggleFullscreen() async {
    if (_isFullscreen) {
      await exitFullscreen();
    } else {
      await enterFullscreen();
    }
  }

  /// Reset all system UI overrides (call on screen dispose).
  static Future<void> reset() async {
    _isFullscreen = false;
    await Future.wait([
      SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge),
      SystemChrome.setPreferredOrientations([
        DeviceOrientation.portraitUp,
        DeviceOrientation.portraitDown,
      ]),
    ]);
  }
}
