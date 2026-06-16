import 'dart:async';
import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';
import 'package:fluxtube/core/colors.dart';
import 'package:fluxtube/domain/watch/playback/models/generic_quality_info.dart';

/// YouTube-style video player controls overlay.
/// Shows/hides on tap. Auto-hides after 4 seconds.
class YouTubeControlsOverlay extends StatefulWidget {
  const YouTubeControlsOverlay({
    super.key,
    required this.player,
    required this.isFullscreen,
    required this.isLandscape,
    required this.isLive,
    this.availableQualities,
    this.currentQuality,
    this.onQualityChanged,
    required this.onToggleFullscreen,
    required this.onSeek,
    required this.onShowQualitySheet,
  });

  final Player player;
  final bool isFullscreen;
  final bool isLandscape;
  final bool isLive;
  final List<GenericQualityInfo>? availableQualities;
  final String? currentQuality;
  final Function(GenericQualityInfo)? onQualityChanged;
  final VoidCallback onToggleFullscreen;
  final Function(Duration) onSeek;
  final VoidCallback onShowQualitySheet;

  @override
  State<YouTubeControlsOverlay> createState() => _YouTubeControlsOverlayState();
}

class _YouTubeControlsOverlayState extends State<YouTubeControlsOverlay> {
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  bool _isPlaying = false;
  double _brightness = 1.0;
  double _volume = 1.0;
  bool _isDraggingSeek = false;

  StreamSubscription<Duration>? _positionSub;
  StreamSubscription<Duration>? _durationSub;
  StreamSubscription<bool>? _playingSub;

  @override
  void initState() {
    super.initState();
    _positionSub = widget.player.stream.position.listen((p) {
      if (mounted && !_isDraggingSeek) setState(() => _position = p);
    });
    _durationSub = widget.player.stream.duration.listen((d) {
      if (mounted) setState(() => _duration = d);
    });
    _playingSub = widget.player.stream.playing.listen((p) {
      if (mounted) setState(() => _isPlaying = p);
    });
  }

  @override
  void dispose() {
    _positionSub?.cancel();
    _durationSub?.cancel();
    _playingSub?.cancel();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60);
    final seconds = d.inSeconds.remainder(60);
    if (hours > 0) {
      return '${hours.toString().padLeft(2, '0')}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _togglePlayPause() {
    if (_isPlaying) {
      widget.player.pause();
    } else {
      widget.player.play();
    }
  }

  void _onSeekChange(double value) {
    _isDraggingSeek = true;
    setState(() {
      _position = Duration(seconds: value.toInt());
    });
  }

  void _onSeekEnd(double value) {
    _isDraggingSeek = false;
    final target = Duration(seconds: value.toInt());
    widget.onSeek(target);
    widget.player.seek(target);
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          top: MediaQuery.of(context).padding.top + 8,
          left: 8,
          right: 16,
          bottom: 12,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white, size: 24),
              onPressed: widget.onToggleFullscreen,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                widget.player.state.title ?? '',
                style: const TextStyle(color: Colors.white, fontSize: 14),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCenterControls() {
    return Center(
      child: GestureDetector(
        onDoubleTapDown: (details) {
          final width = context.size?.width ?? 1;
          if (details.localPosition.dx < width / 2) {
            // Left side: seek back 10s
            final newPos = _position - const Duration(seconds: 10);
            widget.onSeek(newPos);
            widget.player.seek(newPos);
          } else {
            // Right side: seek forward 10s
            final newPos = _position + const Duration(seconds: 10);
            widget.onSeek(newPos);
            widget.player.seek(newPos);
          }
        },
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Seek back 10s
            _ControlButton(
              icon: Icons.replay_10_rounded,
              onTap: () {
                final newPos = _position - const Duration(seconds: 10);
                widget.onSeek(newPos);
                widget.player.seek(newPos);
              },
            ),
            const SizedBox(width: 24),
            // Play/Pause
            _ControlButton(
              icon: _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: 56,
              iconSize: 40,
              onTap: _togglePlayPause,
            ),
            const SizedBox(width: 24),
            // Seek forward 10s
            _ControlButton(
              icon: Icons.forward_10_rounded,
              onTap: () {
                final newPos = _position + const Duration(seconds: 10);
                widget.onSeek(newPos);
                widget.player.seek(newPos);
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final totalSeconds = _duration.inSeconds > 0
        ? _duration.inSeconds.toDouble()
        : 1.0;
    final positionSeconds = _position.inSeconds.toDouble();

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          bottom: MediaQuery.of(context).padding.bottom + 8,
          top: 8,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [Colors.black.withValues(alpha: 0.8), Colors.transparent],
          ),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Seek Bar ──
            if (!widget.isLive)
              SliderTheme(
                data: SliderThemeData(
                  trackHeight: 3,
                  thumbShape:
                      const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape:
                      const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: Colors.red,
                  inactiveTrackColor: Colors.white38,
                  thumbColor: Colors.red,
                  overlayColor: Colors.red.withValues(alpha: 0.2),
                ),
                child: Slider(
                  value: positionSeconds.clamp(0, totalSeconds),
                  max: totalSeconds,
                  onChanged: _onSeekChange,
                  onChangeEnd: _onSeekEnd,
                ),
              ),

            // ── Time Row ──
            Row(
              children: [
                Text(
                  _formatDuration(_position),
                  style: const TextStyle(color: Colors.white, fontSize: 12),
                ),
                if (!widget.isLive) ...[
                  Text(
                    ' / ${_formatDuration(_duration)}',
                    style: const TextStyle(color: Colors.white54, fontSize: 12),
                  ),
                ],
                const Spacer(),

                // Quality button
                if (_hasQualities)
                  _BottomIconButton(
                    icon: Icons.settings_rounded,
                    label: widget.currentQuality ?? 'Auto',
                    onTap: widget.onShowQualitySheet,
                  ),
                const SizedBox(width: 8),

                // Fullscreen toggle
                IconButton(
                  icon: Icon(
                    widget.isFullscreen
                        ? Icons.fullscreen_exit_rounded
                        : Icons.fullscreen_rounded,
                    color: Colors.white,
                    size: 24,
                  ),
                  onPressed: widget.onToggleFullscreen,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  bool get _hasQualities =>
      widget.availableQualities != null && widget.availableQualities!.length > 1;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        // Semi-transparent background for controls
        GestureDetector(
          onTap: () {},
          child: Container(color: Colors.black12),
        ),

        // Top bar
        if (widget.isLandscape) _buildTopBar(),

        // Center controls
        _buildCenterControls(),

        // Bottom bar
        _buildBottomBar(),
      ],
    );
  }
}

/// Circle button for center controls (replay/play/forward).
class _ControlButton extends StatelessWidget {
  const _ControlButton({
    required this.icon,
    this.size = 40,
    this.iconSize = 24,
    required this.onTap,
  });

  final IconData icon;
  final double size;
  final double iconSize;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white12,
        ),
        child: Icon(icon, color: Colors.white, size: iconSize),
      ),
    );
  }
}

/// Compact bottom bar icon + label button.
class _BottomIconButton extends StatelessWidget {
  const _BottomIconButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, color: Colors.white, size: 18),
          const SizedBox(width: 4),
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
