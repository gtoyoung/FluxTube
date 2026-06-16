import 'package:fluxtube/core/enums.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:fluxtube/application/application.dart';
import 'package:fluxtube/core/platform/fullscreen_utils.dart';
import 'package:fluxtube/core/player/global_player_controller.dart';
import 'package:fluxtube/domain/watch/playback/models/generic_quality_info.dart';
import 'youtube_controls_overlay.dart';
import 'package:fluxtube/domain/watch/models/piped/video/video_stream.dart';
import 'package:fluxtube/domain/watch/playback/piped_stream_helper.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
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
  int _initSeq = 0;

  // Separate stream lists for merging support
  List<VideoStream> _muxedStreams = [];
  List<VideoStream> _videoOnlyStreams = [];

  // Explode fallback streams (when Piped has limited quality)
  List<VideoStream> _explodeMuxedStreams = [];

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
    _scheduleInitialization();
  }

  @override
  void dispose() {
    _controlsTimer?.cancel();
    _fadeAnimController.dispose();
    super.dispose();
  }

  bool get _isWatchDataReady =>
      widget.watchState.fetchWatchInfoStatus == ApiStatus.loaded &&
      widget.watchState.oldId == widget.videoId &&
      (widget.watchState.watchResp.videoStreams.isNotEmpty ||
          widget.watchState.watchResp.hls != null);

  void _scheduleInitialization() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initializePlayback();
      }
    });
  }

  @override
  void didUpdateWidget(covariant YouTubePlayerWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoId != widget.videoId) {
      _initSeq += 1;
      if (mounted) {
        setState(() => _isInitialized = false);
      }
      unawaited(_globalPlayer.stopAndClear());
      _scheduleInitialization();
    } else if (!_isInitialized && _isWatchDataReady) {
      _scheduleInitialization();
    }
  }

  Future<void> _initializePlayback() async {
    final int seq = ++_initSeq;
    try {
      if (!mounted || !_isWatchDataReady || seq != _initSeq) return;

      if (_globalPlayer.currentVideoId != null &&
          _globalPlayer.currentVideoId != widget.videoId) {
        await _globalPlayer.stopAndClear();
      }

      await _globalPlayer.ensureInitialized();
      if (!mounted || !_isWatchDataReady || seq != _initSeq) return;

      // Build quality options from Piped (separates muxed / video-only / HLS)
      _buildQualityOptions();

      // If Piped returned limited quality (< 720p), try Explode fallback
      if (await _tryExplodeFallback()) {
        // Rebuild quality options with Explode streams merged
        _buildQualityOptions();
      }

      // Pick best initial quality: best muxed > best video-only > HLS Auto
      _currentQualityLabel = _pickBestQuality();

      _globalPlayer.setCurrentVideoId(widget.videoId);
      final bool initialized = await _setupMediaSource(_currentQualityLabel);

      if (!mounted || seq != _initSeq) return;
      if (mounted) {
        setState(() => _isInitialized = initialized);
      }
    } catch (e) {
      debugPrint('[YouTubePlayer] init error: $e');
      if (mounted && seq == _initSeq) {
        setState(() => _isInitialized = false);
      }
    }
  }

  /// Try fetching muxed streams directly from YouTube via Explode
  /// when Piped provides limited quality (e.g. only 360p).
  Future<bool> _tryExplodeFallback() async {
    // If Piped already has quality >= 720p, no fallback needed
    final hasHighQuality = _availableQualities?.any((q) => q.resolution >= 720) ?? false;
    if (hasHighQuality) return false;
    await _fetchExplodeMuxedStreams();
    return _explodeMuxedStreams.isNotEmpty;
  }

  Future<void> _fetchExplodeMuxedStreams() async {
    try {
      final yt = YoutubeExplode();
      try {
        final manifest = await yt.videos.streamsClient.getManifest(widget.videoId);
        _explodeMuxedStreams = manifest.muxed.map((s) => VideoStream(
          url: s.url.toString(),
          quality: s.qualityLabel,
          videoOnly: false,
          format: s.container.name,
          fps: _fpsValue(s.framerate),
          width: s.videoResolution.width,
          height: s.videoResolution.height,
        )).toList();
        debugPrint('[YouTubePlayer] Explode fallback: ${_explodeMuxedStreams.length} muxed streams');
      } finally {
        yt.close();
      }
    } catch (e) {
      debugPrint('[YouTubePlayer] Explode fallback error: $e');
    }
  }

  static int? _fpsValue(Framerate framerate) {
    switch (framerate) {
      case Framerate.fps24: return 24;
      case Framerate.fps30: return 30;
      case Framerate.fps48: return 48;
      case Framerate.fps60: return 60;
      default: return null;
    }
  }

  String? _pickBestQuality() {
    final watchInfo = widget.watchState.watchResp;
    // Best muxed stream (highest resolution)
    if (_muxedStreams.isNotEmpty) {
      final best = _muxedStreams
          .reduce((a, b) {
            final ra = GenericQualityInfo.parseResolution(a.quality ?? '');
            final rb = GenericQualityInfo.parseResolution(b.quality ?? '');
            return ra >= rb ? a : b;
          });
      return best.quality;
    }
    // Best video-only stream (needs audio merging)
    if (_videoOnlyStreams.isNotEmpty) {
      final best = _videoOnlyStreams
          .reduce((a, b) {
            final ra = GenericQualityInfo.parseResolution(a.quality ?? '');
            final rb = GenericQualityInfo.parseResolution(b.quality ?? '');
            return ra >= rb ? a : b;
          });
      return best.quality;
    }
    // HLS fallback
    if (watchInfo.hls != null) return 'Auto';
    return null;
  }

  void _buildQualityOptions() {
    final watchInfo = widget.watchState.watchResp;
    final streams = watchInfo.videoStreams;

    // Separate muxed and video-only streams from Piped
    _muxedStreams = streams
        .where((v) => v.videoOnly != true && v.quality != null && v.url != null)
        .toList();
    _videoOnlyStreams = streams
        .where((v) => v.videoOnly == true && v.quality != null && v.url != null)
        .toList();

    // Merge Explode fallback muxed streams (dedup by quality, prefer Piped)
    for (final e in _explodeMuxedStreams) {
      if (e.quality != null && !_muxedStreams.any((m) => m.quality == e.quality)) {
        _muxedStreams.add(e);
      }
    }

    // Build merged quality list: video-only first (higher quality), then muxed
    final combined = <GenericQualityInfo>[];
    final seenLabels = <String>{};

    // Dedup: if both muxed and video-only have same quality label, prefer video-only
    for (final v in [..._videoOnlyStreams, ..._muxedStreams]) {
      if (v.quality != null && seenLabels.add(v.quality!)) {
        combined.add(GenericQualityInfo(
          label: v.quality!,
          displayLabel: v.quality!,
          resolution: GenericQualityInfo.parseResolution(v.quality!),
          fps: v.fps,
          format: v.format,
          url: v.url,
        ));
      }
    }

    // Add HLS / Auto option at top
    if (watchInfo.hls != null) {
      combined.insert(0, GenericQualityInfo(
        label: 'Auto',
        displayLabel: 'Auto (HLS)',
        resolution: 99999,
        format: 'hls',
        url: watchInfo.hls,
      ));
    }

    combined.sort((a, b) => b.resolution.compareTo(a.resolution));
    _availableQualities = combined;
  }

  Future<bool> _setupMediaSource(String? quality) async {
    final watchInfo = widget.watchState.watchResp;
    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };

    try {
      // 1. Auto / HLS
      if (quality == 'Auto' && watchInfo.hls != null) {
        await _player.open(Media(watchInfo.hls!, httpHeaders: headers));
        await _player.play();
        return true;
      }

      // 2. Video-only stream — needs audio merging
      if (quality != null) {
        final videoOnly = _videoOnlyStreams.where((v) => v.quality == quality).firstOrNull;
        if (videoOnly != null && videoOnly.url != null) {
          final audioStream = PipedStreamHelper.getBestAudioStream(watchInfo.audioStreams);
          await _player.open(Media(videoOnly.url!, httpHeaders: headers));
          if (audioStream?.url != null) {
            try {
              await _player.setAudioTrack(AudioTrack.uri(audioStream!.url!));
              debugPrint('[YouTubePlayer] Set audio track for video-only stream');
            } catch (e) {
              debugPrint('[YouTubePlayer] Audio track error: $e');
            }
          }
          await _player.play();
          return true;
        }
      }

      // 3. Muxed stream (preferred quality or fallback)
      String? videoUrl;
      if (quality != null && _muxedStreams.isNotEmpty) {
        final match = _muxedStreams.where((v) => v.quality == quality).firstOrNull;
        videoUrl = match?.url;
      }
      videoUrl ??= _muxedStreams.firstOrNull?.url;
      videoUrl ??= watchInfo.hls;
      videoUrl ??= watchInfo.videoStreams.firstOrNull?.url;
      videoUrl ??= watchInfo.audioStreams?.firstOrNull?.url;

      if (videoUrl == null) {
        debugPrint('[YouTubePlayer] No playable stream found for ${widget.videoId}');
        return false;
      }

      await _player.open(Media(videoUrl, httpHeaders: headers));
      await _player.play();
      return true;
    } catch (e) {
      debugPrint('[YouTubePlayer] setup media source error: $e');
      return false;
    }
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
  void _onTapBack() {
    if (!mounted) return;
    FullscreenUtils.exitFullscreen();
    // Direct pop — canPop is still false until next rebuild after exitFullscreen.
    // ignore: use_of_void_result
    Navigator.of(context).pop();
  }

  void _onQualityChanged(GenericQualityInfo quality) async {
    if (_isChangingQuality) return;
    setState(() => _isChangingQuality = true);

    const headers = {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
    };

    try {
      if (quality.url == null) return;

      if (quality.label == 'Auto') {
        // HLS / Auto — quality.url is the HLS manifest URL
        await _player.open(Media(quality.url!, httpHeaders: headers));
      } else if (_videoOnlyStreams.any((v) => v.quality == quality.label)) {
        // Video-only → open video + add audio track
        final audioStream = PipedStreamHelper.getBestAudioStream(
            widget.watchState.watchResp.audioStreams);
        await _player.open(Media(quality.url!, httpHeaders: headers));
        if (audioStream?.url != null) {
          try {
            await _player.setAudioTrack(AudioTrack.uri(audioStream!.url!));
          } catch (e) {
            debugPrint('[YouTubePlayer] quality audio track error: $e');
          }
        }
      } else {
        // Muxed
        await _player.open(Media(quality.url!, httpHeaders: headers));
      }

      await _player.play();
      setState(() => _currentQualityLabel = quality.label);
    } catch (e) {
      debugPrint('[YouTubePlayer] quality switch error: $e');
    } finally {
      if (mounted) setState(() => _isChangingQuality = false);
    }
  }

  void _onSeek(Duration position) {
    _player.seek(position);
  }

  String? get _thumbnailUrl => widget.watchState.watchResp.thumbnailUrl;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _toggleControls,
      child: Stack(
        fit: StackFit.expand,
        children: [
          // ── Thumbnail (shown before video starts) ──
          if (!_isInitialized && _thumbnailUrl != null)
            Positioned.fill(
              child: Image.network(
                _thumbnailUrl!,
                fit: BoxFit.contain,
                loadingBuilder: (_, child, progress) {
                  if (progress == null) return child;
                  return const Center(child: CircularProgressIndicator(color: Colors.white));
                },
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),

          // ── Video Renderer ──
          ClipRRect(
            borderRadius: widget.isLandscape
                ? BorderRadius.zero
                : BorderRadius.zero,
            child: Video(
              controller: _videoController,
              fit: BoxFit.contain,
            ),
          ),

          // ── Dark overlay + big play button when not initialized ──
          if (!_isInitialized)
            Container(
              color: Colors.black26,
              child: Center(
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.black87,
                    size: 40,
                  ),
                ),
              ),
            ),

          // ── Loading Indicator ──
          if (_isChangingQuality)
            Container(
              color: Colors.black26,
              child: const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
            ),

          // ── Gradient Overlay (always on top of video, under controls) ──
          if (_isInitialized)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.15),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.15),
                      ],
                      stops: const [0.0, 0.2, 0.8, 1.0],
                    ),
                  ),
                ),
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
                onBack: _onTapBack,
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
