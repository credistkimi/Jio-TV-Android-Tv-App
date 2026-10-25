import '../constants/tv_api_constants.dart';

class Program {
  final String programId;
  final String channelId;
  final String title;
  final String episode;
  final String synopsis;
  final DateTime startTime;
  final DateTime endTime;
  final String? thumbnailUrl;
  final String? genre;
  final bool hasCatchup;

  const Program({
    required this.programId,
    required this.channelId,
    required this.title,
    this.episode = '',
    this.synopsis = '',
    required this.startTime,
    required this.endTime,
    this.thumbnailUrl,
    this.genre,
    this.hasCatchup = true,
  });

  bool get isLive {
    final now = DateTime.now();
    return now.isAfter(startTime) && now.isBefore(endTime);
  }

  bool get isPast {
    return DateTime.now().isAfter(endTime);
  }

  bool get isFuture {
    return DateTime.now().isBefore(startTime);
  }

  double get progressFraction {
    final now = DateTime.now();
    if (now.isBefore(startTime)) return 0.0;
    if (now.isAfter(endTime)) return 1.0;
    final totalDuration = endTime.difference(startTime).inSeconds;
    if (totalDuration <= 0) return 0.0;
    final elapsed = now.difference(startTime).inSeconds;
    return (elapsed / totalDuration).clamp(0.0, 1.0);
  }

  Duration get duration => endTime.difference(startTime);

  factory Program.fromJson(Map<String, dynamic> json, String channelId) {
    String? thumb = json['episodePoster'] ??
        json['episodeThumbnail'] ??
        json['thumbnailUrl'] ??
        json['poster'] ??
        json['image'];

    if (thumb != null && thumb.isNotEmpty && !thumb.startsWith('http')) {
      thumb = '${TvApiConstants.catchupPosterBaseUrl}$thumb';
    }

    final startEpoch = json['startEpoch'];
    DateTime start;
    if (startEpoch is num) {
      start = DateTime.fromMillisecondsSinceEpoch(startEpoch.toInt());
    } else if (startEpoch is String) {
      final parsed = int.tryParse(startEpoch);
      start = parsed != null
          ? DateTime.fromMillisecondsSinceEpoch(parsed)
          : DateTime.now().subtract(const Duration(minutes: 30));
    } else {
      start = DateTime.now().subtract(const Duration(minutes: 30));
    }

    final endEpoch = json['endEpoch'];
    DateTime end;
    if (endEpoch is num) {
      end = DateTime.fromMillisecondsSinceEpoch(endEpoch.toInt());
    } else if (endEpoch is String) {
      final parsed = int.tryParse(endEpoch);
      end = parsed != null
          ? DateTime.fromMillisecondsSinceEpoch(parsed)
          : start.add(const Duration(minutes: 30));
    } else {
      end = start.add(const Duration(minutes: 30));
    }

    return Program(
      programId: json['id']?.toString() ?? json['programId']?.toString() ?? 'prog_${DateTime.now().millisecondsSinceEpoch}',
      channelId: channelId,
      title: json['showname'] ?? json['title'] ?? 'Live Broadcast',
      episode: json['episode_title'] ?? json['episode'] ?? '',
      synopsis: json['description'] ?? json['synopsis'] ?? '',
      startTime: start,
      endTime: end,
      thumbnailUrl: thumb,
      genre: json['showCategory'] ?? json['genre'] ?? '',
      hasCatchup: json['catchupAvailable'] ?? json['hasCatchup'] ?? true,
    );
  }
}
