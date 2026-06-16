import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:fluxtube/application/application.dart';
import 'package:fluxtube/domain/subscribes/models/subscribe.dart';
import 'package:fluxtube/domain/watch/models/piped/video/watch_resp.dart';
import 'package:fluxtube/presentation/watch/widgets/sections/like_section.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:go_router/go_router.dart';
/// YouTube-style video info section below the player.
/// Shows: title, views/date, channel info, action buttons, expandable description.
class YouTubeVideoInfoSection extends StatefulWidget {
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
  State<YouTubeVideoInfoSection> createState() => _YouTubeVideoInfoSectionState();
}

class _YouTubeVideoInfoSectionState extends State<YouTubeVideoInfoSection> {
  bool _showFullDescription = false;

  @override
  Widget build(BuildContext context) {
    final watchInfo = widget.watchState.watchResp;
    if (widget.isLoading || watchInfo.title == null) {
      return _buildShimmer();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Padding wrapper for top section ──
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title ──
              Text(
                watchInfo.title ?? '',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                  height: 1.3,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),

              // ── Views & Date (YouTube style: compact, subtle) ──
              Text(
                _formatMeta(watchInfo.views, watchInfo.uploadDate),
                style: const TextStyle(fontSize: 13, color: Colors.white54),
              ),
              const SizedBox(height: 12),

              // ── Channel Row + Subscribe ──
              _buildChannelRow(watchInfo),
              const SizedBox(height: 8),

              // ── Action Row (Like / Dislike / Save / Share / Download) ──
              SizedBox(
                height: 40,
                child: LikeSection(
                  id: widget.videoId,
                  state: widget.watchState,
                  watchInfo: watchInfo,
                  pipClicked: () {},
                ),
              ),
            ],
          ),
        ),

        // ── Separator before description ──
        const Divider(color: Colors.white12, height: 1, thickness: 0.5),

        // ── Expandable Description ──
        _buildDescription(watchInfo),

        const Divider(color: Colors.white12, height: 1, thickness: 0.5),
      ],
    );
  }

  Widget _buildChannelRow(WatchResp watchInfo) {
    return Row(
      children: [
        // Channel avatar
        GestureDetector(
          onTap: () => _navigateToChannel(watchInfo),
          child: Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white12,
              image: watchInfo.uploaderAvatar != null
                  ? DecorationImage(
                      image: NetworkImage(watchInfo.uploaderAvatar!),
                      fit: BoxFit.cover,
                    )
                  : null,
            ),
            child: watchInfo.uploaderAvatar == null
                ? const Icon(Icons.person, color: Colors.white54, size: 22)
                : null,
          ),
        ),
        const SizedBox(width: 12),
        // Channel name + subscriber count
        Expanded(
          child: GestureDetector(
            onTap: () => _navigateToChannel(watchInfo),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  watchInfo.uploader ?? 'Unknown',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (watchInfo.uploaderSubscriberCount != null)
                  Text(
                    '${_formatCount(watchInfo.uploaderSubscriberCount!)} subscribers',
                    style: const TextStyle(fontSize: 12, color: Colors.white54),
                  ),
              ],
            ),
          ),
        ),
        // Subscribe button
        BlocBuilder<SubscribeBloc, SubscribeState>(
          builder: (context, subState) {
            final channelId = watchInfo.uploaderUrl?.split('/').last;
            final isSubscribed = channelId != null && subState.channelInfo?.id == channelId;
            return TextButton(
              style: TextButton.styleFrom(
                backgroundColor: isSubscribed ? Colors.white12 : Colors.red,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              onPressed: () {
                if (channelId == null) return;
                if (isSubscribed) {
                  context.read<SubscribeBloc>().add(
                    SubscribeEvent.deleteSubscribeInfo(id: channelId),
                  );
                } else {
                  context.read<SubscribeBloc>().add(
                    SubscribeEvent.addSubscribe(
                      channelInfo: Subscribe(
                        id: channelId,
                        channelName: watchInfo.uploader ?? 'Unknown',
                        isVerified: watchInfo.uploaderVerified ?? false,
                        avatarUrl: watchInfo.uploaderAvatar,
                      ),
                    ),
                  );
                }
              },
              child: Text(
                isSubscribed ? 'Subscribed' : 'Subscribe',
                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
              ),
            );
          },
        ),
      ],
    );
  }


  void _navigateToChannel(WatchResp watchInfo) {
    if (watchInfo.uploaderUrl == null) return;
    try {
      context.pushNamed('channel', pathParameters: {
        'channelId': watchInfo.uploaderUrl!.split('/').last,
      }, queryParameters: {
        'avatarUrl': watchInfo.uploaderAvatar,
      });
    } catch (_) {}
  }
  Widget _buildDescription(WatchResp watchInfo) {
    final desc = watchInfo.description;
    if (desc == null || desc.isEmpty || desc == 'fetching...') {
      return const SizedBox.shrink();
    }

    final isLong = desc.length > 200;
    final displayText = _showFullDescription || !isLong ? desc : '${desc.substring(0, 200)}...';

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SelectableText.rich(
            _buildDescriptionSpans(context, displayText),
            style: const TextStyle(fontSize: 13, color: Colors.white70, height: 1.4),
          ),
          if (isLong)
            GestureDetector(
              onTap: () => setState(() => _showFullDescription = !_showFullDescription),
              child: Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  _showFullDescription ? 'Show less' : 'Show more',
                  style: const TextStyle(fontSize: 13, color: Colors.white70, fontWeight: FontWeight.w600),
                ),
              ),
            ),
        ],
      ),
    );
  }

  TextSpan _buildDescriptionSpans(BuildContext context, String text) {
    String decoded = text
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'<br\s*/?>'), '\n')
        .replaceAll(RegExp(r'<[^>]*>'), '');

    final urlPattern = RegExp(r'https?://[^\s<>\[\]]+', caseSensitive: false);
    final spans = <InlineSpan>[];
    int lastEnd = 0;

    for (final match in urlPattern.allMatches(decoded)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: decoded.substring(lastEnd, match.start)));
      }
      final url = match.group(0)!;
      spans.add(TextSpan(
        text: url,
        style: const TextStyle(color: Colors.lightBlueAccent),
        recognizer: TapGestureRecognizer()
          ..onTap = () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < decoded.length) {
      spans.add(TextSpan(text: decoded.substring(lastEnd)));
    }
    return TextSpan(
      children: spans,
      style: DefaultTextStyle.of(context).style.copyWith(fontSize: 13, color: Colors.white70),
    );
  }

  String _formatMeta(int? views, String? uploadDate) {
    String viewsStr = views != null ? '${_formatCount(views)} views' : '';
    if (uploadDate != null && uploadDate.isNotEmpty && uploadDate != '0') {
      return viewsStr.isEmpty ? uploadDate : '$viewsStr • $uploadDate';
    }
    return viewsStr;
  }

  String _formatCount(int count) {
    if (count >= 100000000) {
      return '${(count / 100000000).toStringAsFixed(1)}B';
    } else if (count >= 1000000) {
      return '${(count / 1000000).toStringAsFixed(1)}M';
    } else if (count >= 1000) {
      return '${(count / 1000).toStringAsFixed(1)}K';
    }
    return count.toString();
  }

  Widget _buildShimmer() {
    return const Padding(
      padding: EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(height: 16),
        ],
      ),
    );
  }
}
