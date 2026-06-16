import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:fluxtube/application/application.dart';
import 'package:fluxtube/core/colors.dart';
import 'package:fluxtube/core/enums.dart';
import 'package:fluxtube/core/platform/fullscreen_utils.dart';
import 'package:fluxtube/core/player/global_player_controller.dart';
import 'package:fluxtube/domain/watch/playback/piped_stream_helper.dart';
import 'package:fluxtube/domain/watch/playback/models/generic_quality_info.dart';
import 'package:fluxtube/domain/watch/playback/models/generic_audio_track.dart';
import 'youtube_controls_overlay.dart';
import 'youtube_quality_sheet.dart';

/// Unified video player widget that works with Piped backend.
/// Adapts to portrait (16:9 container) and landscape (fullscreen) modes.
class YouTubePlayerWidget extends StatefulWidget {
  const YouTubePlayerWidget({
    super.key,
    required this.videoId,
    required this.watchState,
    required this.isLandscape,
    required this.isFullscreen,
  });

  final String videoId;
  final WatchState watchState;
  final bool isLandscape;
  final bool isFullscreen;

  @override
  State<YouTubePlayerWidget> createState() => _YouTubePlayerWidgetState();
}

class _YouTubePlayerWidgetState extends State<YouTubePlayerWidget>
    with TickerProviderStateMixin {
  final GlobalPlayerController _globalPlayer = GlobalPlayerController();
  Player get _player => _globalPlayer.player;
  VideoController get _videoController => _globalPlayer.videoController;

  // Quality state
  List<GenericQualityInfo>? _availableQualities;
  String? _currentQualityLabel;
  bool _isInitialized = false;
  bool _isChangingQuality = false;

  // Audio track state
  List<GenericAudioTrackInfo>? _availableAudioTracks;
  String? _currentAudioTrackId;

  // Controls visibility
  bool _controlsVisible = true;
  Timer? _controlsTimer;
  late AnimationController _fadeAnimController;
  late Animation<double> _fadeAnim;

  @override
  void initState() {
    super.initState();
    _fadeAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );
    _fadeAnim = CurvedAnimation(
      parent: _fadeAnimController,
      curve: Curves.easeInOut,
    );
    _fadeAnimController.value = 1.0;

    WidgetsBinding.instance.addPostFrameCallback((_) => _initializePlayback());
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _fadeAnimController.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant YouTubePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _isInitialized = false;
      _player.stop();
      WidgetsBinding.instance.addPostFrameCallback((_) => _initializePlayback());
    }
  }

  Future<void> _initializePlayback() async {
    try {
      if (_globalPlayer.currentVideoId != null &&
          _globalPlayer.currentVideoId != widget.videoId) {
        await _globalPlayer.stopAndClear();
      }

      await _globalPlayer.ensureInitialized();
      _buildQualityOptions();

      // Set default quality
      final streams = widget.watchState.watchResp.videoStreams;
      if (streams != null) {
        final firstMuxed = streams.where((v) => v.videoOnly == false).firstOrNull;
        _currentQualityLabel = firstMuxed?.quality;
      }

      _availableAudioTracks = PipedStreamHelper.getAvailableAudioTracks(
          widget.watchState.watchResp.audioStreams);
      if (_availableAudioTracks!.isNotEmpty) {
        _currentAudioTrackId = _availableAudioTracks!.first.trackId;
      }

      _globalPlayer.setCurrentVideoId(widget.videoId);
      await _setupMediaSource(_currentQualityLabel);

      if (mounted) {
        setState(() => _isInitialized = true);
      }
    } catch (e) {
      debugPrint('[YouTubePlayer] init error: $e');
    }
  }

  void _buildQualityOptions() {
    final watchInfo = widget.watchState.watchResp;
    final streams = watchInfo.videoStreams
        ?.where((v) => v.videoOnly == false && v.quality != null && v.url != null)
        .toList();

    if (streams != null && streams.isNotEmpty) {
      _availableQualities = streams
          .map((v) => GenericQualityInfo(
                label: v.quality!,
                displayLabel: v.quality!,
                resolution: GenericQualityInfo.parseResolution(v.quality!),
                fps: v.fps,
                format: v.format,
                url: v.url,
              ))
          .toList();
      _availableQualities?.sort((a, b) => b.resolution.compareTo(a.resolution));
    } else {
      _availableQualities = [];
    }
  }

  Future<void> _setupMediaSource(String? quality) async {
    final watchInfo = widget.watchState.watchResp;

    String? videoUrl;

    // Try selected quality
    if (quality != null && watchInfo.videoStreams != null) {
      for (final v in watchInfo.videoStreams!) {
        if (v.quality == quality && v.videoOnly == false && v.url != null) {
          videoUrl = v.url;
          break;
        }
      }
    }

    // Fallback: first non-video-only stream
    if (videoUrl == null && watchInfo.videoStreams != null) {
      for (final v in watchInfo.videoStreams!) {
        if (v.videoOnly == false && v.url != null) {
          videoUrl = v.url;
          break;
        }
      }
    }

    // Final fallback
    videoUrl ??= watchInfo.hls;
    if (videoUrl == null && watchInfo.videoStreams != null) {
      for (final v in watchInfo.videoStreams!) {
        if (v.url != null) {
          videoUrl = v.url;
          break;
        }
      }
    }
    videoUrl ??= watchInfo.audioStreams?.firstOrNull?.url;

    if (videoUrl == null) return;

    await _player.open(Media(videoUrl, httpHeaders: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    }));
    await _player.play();
  }

  void _toggleControls() {
    setState(() {
      _controlsVisible = !_controlsVisible;
      if (_controlsVisible) {
        _fadeAnimController.forward();
        _startControlsTimer();
      } else {
        _fadeAnimController.reverse();
        _controlsTimer?.cancel();
      }
    });
  }

  void _startControlsTimer() {
    _controlsTimer?.cancel();
    _controlsTimer = Timer(const Duration(seconds: 4), () {
      if (mounted && _controlsVisible) {
        setState(() {
          _controlsVisible = false;
          _fadeAnimController.reverse();
        });
      }
    });
  }

  void _onTapFullscreen() {
    if (widget.isFullscreen) {
      FullscreenUtils.exitFullscreen();
    } else {
      FullscreenUtils.enterFullscreen();
    }
  }

  void _onQualityChanged(GenericQualityInfo quality) async {
    if (_isChangingQuality) return;
    setState(() => _isChangingQuality = true);

    try {
      if (quality.url != null) {
        await _player.open(Media(quality.url!, httpHeaders: {
          'User-Agent':
              'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
        }));
        await _player.play();
        setState(() => _currentQualityLabel = quality.label);
      }
    } catch (e) {
      debugPrint('[YouTubePlayer] quality switch error: $e');
    } finally {
      if (mounted) setState(() => _isChangingQuality = false);
    }
  }

  void _onSeek(Duration position) {
    _player.seek(position);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Video Renderer ──
          ClipRRect(
            borderRadius: widget.isLandscape
                ? BorderRadius.zero
                : BorderRadius.circular(0),
            child: Video(
              controller: _videoController,
              fit: BoxFit.contain,
            ),
          ),

          // ── Loading Indicator ──
          if (!_isInitialized || _isChangingQuality)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // ── Controls Overlay ──
          if (_isInitialized)
            FadeTransition(
              opacity: _fadeAnim,
              child: YouTubeControlsOverlay(
                player: _player,
                isFullscreen: widget.isFullscreen,
                isLandscape: widget.isLandscape,
                isLive: widget.watchState.watchResp.livestream == true,
                availableQualities: _availableQualities,
                currentQuality: _currentQualityLabel,
                onQualityChanged: _onQualityChanged,
                onToggleFullscreen: _onTapFullscreen,
                onSeek: _onSeek,
                onShowQualitySheet: _showQualitySheet,
              ),
            ),
        ],
      ),
    );
  }

  void _showQualitySheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.grey.shade800,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (_) => YouTubeQualitySheet(
        qualities: _availableQualities ?? [],
        currentQuality: _currentQualityLabel,
        onQualityChanged: (quality) {
          Navigator.pop(context);
          _onQualityChanged(quality);
        },
      ),
    );
  }
}
