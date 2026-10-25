import 'package:flutter/material.dart';
import '../models/channel.dart';

/// TV Channel Logo component conforming to jiotv_go & JioTV CDN specifications.
/// Loads from primary fast dare_images CDN with automatic failover to mirror and text fallback.
class TvChannelLogo extends StatefulWidget {
  final Channel channel;
  final double? width;
  final double? height;
  final BoxFit fit;

  const TvChannelLogo({
    super.key,
    required this.channel,
    this.width,
    this.height = 42,
    this.fit = BoxFit.contain,
  });

  @override
  State<TvChannelLogo> createState() => _TvChannelLogoState();
}

class _TvChannelLogoState extends State<TvChannelLogo> {
  bool _primaryFailed = false;
  bool _backupFailed = false;

  @override
  void didUpdateWidget(covariant TvChannelLogo oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.channel.channelId != widget.channel.channelId ||
        oldWidget.channel.logoUrl != widget.channel.logoUrl) {
      _primaryFailed = false;
      _backupFailed = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ch = widget.channel;

    // 1. Primary CDN: https://jiotv.catchup.cdn.jio.com/dare_images/images/<file> (jiotv_go specification)
    if (!_primaryFailed && ch.logoUrl.isNotEmpty) {
      return Image.network(
        ch.logoUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_primaryFailed) {
              setState(() => _primaryFailed = true);
            }
          });
          return _buildBackup(ch);
        },
      );
    }

    return _buildBackup(ch);
  }

  // 2. Backup Mirror CDN: https://img.media.jio.com/apis/v1.4/getchannelimage/get/<file>
  Widget _buildBackup(Channel ch) {
    if (!_backupFailed && ch.backupLogoUrl.isNotEmpty && ch.backupLogoUrl != ch.logoUrl) {
      return Image.network(
        ch.backupLogoUrl,
        width: widget.width,
        height: widget.height,
        fit: widget.fit,
        errorBuilder: (_, __, ___) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && !_backupFailed) {
              setState(() => _backupFailed = true);
            }
          });
          return _buildTextFallback(ch);
        },
      );
    }

    return _buildTextFallback(ch);
  }

  // 3. Fallback text badge
  Widget _buildTextFallback(Channel ch) {
    return Container(
      width: widget.width,
      height: widget.height,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Text(
        ch.channelName,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w800,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
