import 'package:flutter/material.dart';
import 'package:fluxtube/application/application.dart';
import 'package:fluxtube/generated/l10n.dart';
import 'package:fluxtube/presentation/watch/widgets/sections/like_section.dart';
import 'package:fluxtube/presentation/watch/widgets/sections/subscribe_section.dart';

/// YouTube-style video info section below the player.
/// Shows: title, views/date, channel info, like/share/save actions.
class YouTubeVideoInfoSection extends StatelessWidget {
  const YouTubeVideoInfoSection({
    super.key,
    required this.watchState,
    required this.isLoading,
    required this.videoId,
  });

  final WatchState watchState;
  final bool isLoading;
  final String videoId;

  @override
  Widget build(BuildContext context) {
    final watchInfo = watchState.watchResp;
    if (isLoading || watchInfo.title == null) {
      return _buildShimmer();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Title ──
        Text(
          watchInfo.title ?? '',
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w600,
            color: Colors.white,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 6),

        // ── Views & Date ──
        Text(
          _formatViews(watchInfo.views ?? 0, watchInfo.uploadDate),
          style: const TextStyle(fontSize: 13, color: Colors.white54),
        ),
        const SizedBox(height: 12),

        // ── Channel Row + Subscribe ──
        ChannelInfoSection(
          state: watchState,
          watchInfo: watchInfo,
          locals: S.of(context),
        ),
        const SizedBox(height: 8),

        // ── Action Row (Like / Dislike / Save / Share / Download / PiP) ──
        LikeSection(
          id: videoId,
          state: watchState,
          watchInfo: watchInfo,
          pipClicked: () {},
        ),
        const SizedBox(height: 4),
      ],
    );
  }

  String _formatViews(int views, String? uploadDate) {
    String viewsStr;
    if (views >= 10000000) {
      viewsStr = '${(views / 10000000).toStringAsFixed(1)}M views';
    } else if (views >= 1000) {
      viewsStr = '${(views / 1000).toStringAsFixed(1)}K views';
    } else {
      viewsStr = '$views views';
    }

    if (uploadDate != null && uploadDate.isNotEmpty) {
      return '$viewsStr • $uploadDate';
    }
    return viewsStr;
  }

  Widget _buildShimmer() {
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 16),
      ],
    );
  }
}
