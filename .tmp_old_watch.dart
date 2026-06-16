import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluxtube/application/application.dart';
import 'package:fluxtube/core/colors.dart';
import 'package:fluxtube/core/enums.dart';
import 'package:fluxtube/core/platform/fullscreen_utils.dart';
import 'package:fluxtube/core/player/global_player_controller.dart';
import 'package:fluxtube/domain/watch/models/basic_info.dart';
import 'package:fluxtube/core/player/playback_queue_controller.dart';
import 'package:fluxtube/generated/l10n.dart';
import 'package:fluxtube/presentation/watch/widgets/sections/sections.dart';
import 'package:fluxtube/presentation/watch/widgets/widgets.dart';
import 'package:fluxtube/widgets/widgets.dart';

import 'widgets/youtube_player_widget.dart';
import 'widgets/youtube_video_info_section.dart';

/// Unified YouTube-style watch screen for all backends.
/// Portrait: player (16:9) + video info + scrollable content.
/// Landscape: fullscreen player with overlay controls.
class YouTubeWatchScreen extends StatefulWidget {
  const YouTubeWatchScreen({
    super.key,
    required this.id,
    required this.channelId,
  });

  final String id;
  final String channelId;

  @override
  State<YouTubeWatchScreen> createState() => _YouTubeWatchScreenState();
}

class _YouTubeWatchScreenState extends State<YouTubeWatchScreen>
    with WidgetsBindingObserver {
  final GlobalPlayerController _playerController = GlobalPlayerController();

  bool _showPlayer = false;
  String? _playerVideoId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _initializeVideo());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    FullscreenUtils.reset();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.detached) {
      _playerController.disposePlayer();
    }
  }

  @override
  void didUpdateWidget(covariant YouTubeWatchScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.id != widget.id) {
      _showPlayer = false;
      WidgetsBinding.instance.addPostFrameCallback((_) => _initializeVideo());
    }
  }

  void _initializeVideo() {
    final bloc = BlocProvider.of<WatchBloc>(context);
    if (bloc.state.fetchWatchInfoStatus != ApiStatus.loaded ||
        bloc.state.watchResp.title == null) {
      bloc.add(WatchEvent.getWatchInfo(id: widget.id));
    }
  }

  String _videoIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return '';
    final uri = Uri.tryParse(url);
    if (uri == null) return '';
    // Handle youtu.be/VIDEO_ID
    if (uri.host == 'youtu.be') return uri.pathSegments.first;
    // Handle youtube.com/watch?v=VIDEO_ID
    return uri.queryParameters['v'] ?? '';
  }

  String? _channelIdFromUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    final segments = Uri.tryParse(url)?.pathSegments;
    if (segments != null && segments.length >= 2) return segments[1];
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final locals = S.of(context);
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return BlocListener<WatchBloc, WatchState>(
      listenWhen: (previous, current) =>
          previous.fetchWatchInfoStatus != current.fetchWatchInfoStatus &&
          current.fetchWatchInfoStatus == ApiStatus.loaded,
      listener: (context, state) {
        final watchInfo = state.watchResp;
        if (watchInfo.title != null && watchInfo.title!.isNotEmpty) {
          BlocProvider.of<WatchBloc>(context).add(
            WatchEvent.setSelectedVideoBasicDetails(
              details: VideoBasicInfo(
                id: widget.id,
                title: watchInfo.title,
                thumbnailUrl: watchInfo.thumbnailUrl,
                channelName: watchInfo.uploader,
                channelId: watchInfo.uploaderUrl?.split('/').last,
                uploaderVerified: watchInfo.uploaderVerified,
              ),
            ),
          );
          PlaybackQueueController.instance.setQueue(
            currentVideoId: widget.id,
            videos: (watchInfo.relatedStreams ?? []).map((related) {
              return VideoBasicInfo(
                id: _videoIdFromUrl(related.url),
                title: related.title,
                thumbnailUrl: related.thumbnail,
                channelName: related.uploaderName,
                channelId: _channelIdFromUrl(related.uploaderUrl),
                channelThumbnailUrl: related.uploaderAvatar,
                uploaderVerified: related.uploaderVerified,
              );
            }).toList(),
          );
        }
      },
      child: PopScope(
        canPop: !isLandscape,
        onPopInvokedWithResult: (didPop, _) {
          if (isLandscape) {
            FullscreenUtils.exitFullscreen();
          } else if (!didPop) {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            }
          }
        },
        child: Scaffold(
          backgroundColor: isLandscape ? kBlackColor : null,
          body: _buildBody(locals, isLandscape),
        ),
      ),
    );
  }

  Widget _buildBody(S locals, bool isLandscape) {
    if (isLandscape) {
      return _buildLandscapeLayout(locals);
    }
    return _buildPortraitLayout(locals);
  }

  Widget _buildLandscapeLayout(S locals) {
    return BlocBuilder<WatchBloc, WatchState>(
      buildWhen: (previous, current) =>
          previous.fetchWatchInfoStatus != current.fetchWatchInfoStatus ||
          previous.watchResp != current.watchResp,
      builder: (context, state) {
        final isLoading = state.fetchWatchInfoStatus == ApiStatus.initial ||
            state.fetchWatchInfoStatus == ApiStatus.loading;

        return YouTubePlayerWidget(
          key: ValueKey('player_${widget.id}'),
          videoId: widget.id,
          watchState: state,
          isLandscape: true,
          isFullscreen: true,
        );
      },
    );
  }

  Widget _buildPortraitLayout(S locals) {
    return BlocBuilder<WatchBloc, WatchState>(
      buildWhen: (previous, current) =>
          previous.fetchWatchInfoStatus != current.fetchWatchInfoStatus ||
          previous.watchResp != current.watchResp ||
          previous.isDescriptionTapped != current.isDescriptionTapped ||
          previous.isTapComments != current.isTapComments ||
          previous.subtitles != current.subtitles ||
          previous.sponsorSegments != current.sponsorSegments,
      builder: (context, state) {
        final watchInfo = state.watchResp;
        final isLoading = state.fetchWatchInfoStatus == ApiStatus.initial ||
            state.fetchWatchInfoStatus == ApiStatus.loading;
        final hasError = state.fetchWatchInfoStatus == ApiStatus.error;

        if (hasError) {
          return SafeArea(
            child: SingleChildScrollView(
              child: InstanceAutoCheckWidget(
                videoId: widget.id,
                lottie: 'assets/cat-404.zip',
                onRetry: () => BlocProvider.of<WatchBloc>(context)
                    .add(WatchEvent.getWatchInfo(id: widget.id)),
              ),
            ),
          );
        }

        return SafeArea(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Player (16:9) ──
                AspectRatio(
                  aspectRatio: 16 / 9,
                  child: YouTubePlayerWidget(
                    key: ValueKey('player_${widget.id}'),
                    videoId: widget.id,
                    watchState: state,
                    isLandscape: false,
                    isFullscreen: false,
                  ),
                ),

                // ── Video Info ──
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: YouTubeVideoInfoSection(
                    watchState: state,
                    isLoading: isLoading,
                    videoId: widget.id,
                  ),
                ),

                const Divider(height: 1),

                // ── Description or Comments / Related ──
                state.isDescriptionTapped
                    ? _buildDescription(state, watchInfo, locals)
                    : _buildRelatedOrComments(state, watchInfo, locals),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildDescription(
      WatchState state, dynamic watchInfo, S locals) {
    // Reuse existing DescriptionSection from current codebase
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: DescriptionSection(
        height: MediaQuery.of(context).size.height,
        watchInfo: watchInfo,
        locals: locals,
      ),
    );
  }

  Widget _buildRelatedOrComments(
      WatchState state, dynamic watchInfo, S locals) {
    if (state.isTapComments) {
      return CommentSection(
        videoId: widget.id,
        state: state,
        height: MediaQuery.of(context).size.height,
        locals: locals,
      );
    }

    // Show related videos by default
    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
      child: RelatedVideoSection(
        locals: locals,
        watchInfo: watchInfo,
      ),
    );
  }
}

// Minimal stubs for sections that exist elsewhere but may not be
// imported from the barrel file. We import from sections.dart above.

// The actual implementations are in:
// - lib/presentation/watch/widgets/sections/description_section.dart
// - lib/presentation/watch/widgets/sections/comment_section.dart
// - lib/presentation/watch/widgets/sections/related_video_section.dart
