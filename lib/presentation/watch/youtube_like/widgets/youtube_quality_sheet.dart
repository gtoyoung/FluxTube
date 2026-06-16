import 'package:flutter/material.dart';
import 'package:fluxtube/core/colors.dart';
import 'package:fluxtube/domain/watch/playback/models/generic_quality_info.dart';

/// YouTube-style quality selection bottom sheet.
class YouTubeQualitySheet extends StatelessWidget {
  const YouTubeQualitySheet({
    super.key,
    required this.qualities,
    required this.currentQuality,
    required this.onQualityChanged,
  });

  final List<GenericQualityInfo> qualities;
  final String? currentQuality;
  final Function(GenericQualityInfo) onQualityChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 8, bottom: 4),
            width: 32,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white30,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                const Icon(Icons.settings_rounded,
                    color: Colors.white, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Quality',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: const Icon(Icons.close, color: Colors.white54),
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Quality list
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: qualities.length,
              separatorBuilder: (_, __) =>
                  const Divider(height: 1, indent: 16, endIndent: 16),
              itemBuilder: (context, index) {
                final quality = qualities[index];
                final isSelected = quality.label == currentQuality;
                return _QualityTile(
                  quality: quality,
                  isSelected: isSelected,
                  onTap: () => onQualityChanged(quality),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _QualityTile extends StatelessWidget {
  const _QualityTile({
    required this.quality,
    required this.isSelected,
    required this.onTap,
  });

  final GenericQualityInfo quality;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      leading: isSelected
          ? const Icon(Icons.check, color: Colors.white, size: 20)
          : const SizedBox(width: 20),
      title: Text(
        quality.displayLabel,
        style: TextStyle(
          color: isSelected ? Colors.white : Colors.white70,
          fontSize: 14,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      trailing: quality.fps != null
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                '${quality.fps}fps',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
