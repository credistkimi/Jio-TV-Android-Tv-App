import 'package:flutter/material.dart';
import '../models/channel.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../theme/tv_typography.dart';
import '../widgets/tv_badge.dart';
import '../widgets/tv_focusable.dart';

class QuickSwitcherDrawer extends StatelessWidget {
  final List<Channel> channels;
  final Channel currentChannel;
  final ValueChanged<Channel> onChannelSelected;
  final VoidCallback onClose;

  const QuickSwitcherDrawer({
    super.key,
    required this.channels,
    required this.currentChannel,
    required this.onChannelSelected,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 250,
      width: double.infinity,
      decoration: BoxDecoration(
        color: TvColors.bgSurface2.withValues(alpha: 0.95),
        border: const Border(
          top: BorderSide(color: TvColors.accentPrimary, width: 2),
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black87,
            blurRadius: 30,
            offset: Offset(0, -10),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: TvDimensions.overscanMargin, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Container(
                    width: 4,
                    height: 20,
                    decoration: BoxDecoration(
                      color: TvColors.accentCyan,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text('QUICK CHANNEL SWITCHER', style: TvTypography.sectionHeading),
                ],
              ),
              const Text(
                'Press OK to Switch  •  Press BACK to Close',
                style: TvTypography.timeCode,
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Horizontal Channels List
          Expanded(
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: channels.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) {
                final ch = channels[index];
                final isCurrent = ch.channelId == currentChannel.channelId;

                return TvFocusable(
                  autofocus: isCurrent,
                  onPressed: () => onChannelSelected(ch),
                  borderRadius: BorderRadius.circular(12),
                  backgroundColor: isCurrent ? TvColors.bgSurface3 : TvColors.bgSurface1,
                  padding: const EdgeInsets.all(12),
                  child: SizedBox(
                    width: 220,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: TvColors.accentPrimary,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                '${ch.channelNo}',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                            const Spacer(),
                            if (isCurrent)
                              const TvLiveBadge(size: 8)
                            else if (ch.isHd)
                              const TvHdBadge(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Text(
                          ch.channelName,
                          style: TvTypography.cardPrimary.copyWith(fontSize: 18),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const Spacer(),
                        if (ch.currentProgram != null) ...[
                          Text(
                            ch.currentProgram!.title,
                            style: TvTypography.body.copyWith(
                              fontSize: 14,
                              color: TvColors.textPrimary,
                              fontWeight: FontWeight.w500,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 4),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: ch.currentProgram!.progressFraction,
                              backgroundColor: TvColors.borderSubtle,
                              color: TvColors.accentPrimary,
                              minHeight: 3,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
