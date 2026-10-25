import '../constants/tv_api_constants.dart';
import 'program.dart';

class Channel {
  final String channelId;
  final int channelNo;
  final String channelName;
  final String logoUrl;
  final String logoFilename;
  final String backupLogoUrl;
  final String streamUrl;
  final String category;
  final String language;
  final bool isHd;
  final bool isCatchup;
  final bool isPremium;
  final String channelPrice;
  final String businessType;
  final int? stbChannelNumber;
  bool isFavorite;
  Program? currentProgram;
  List<Program> epgSchedule;

  Channel({
    required this.channelId,
    required this.channelNo,
    required this.channelName,
    required this.logoUrl,
    String? logoFilename,
    String? backupLogoUrl,
    required this.streamUrl,
    required this.category,
    required this.language,
    this.isHd = true,
    this.isCatchup = true,
    this.isPremium = false,
    this.channelPrice = 'Free',
    this.businessType = 'free',
    this.stbChannelNumber,
    this.isFavorite = false,
    this.currentProgram,
    List<Program>? epgSchedule,
  })  : logoFilename = (logoFilename != null && logoFilename.isNotEmpty)
            ? logoFilename
            : (logoUrl.isNotEmpty ? logoUrl.split('/').last.split('?').first : ''),
        backupLogoUrl = backupLogoUrl ??
            ((logoFilename != null && logoFilename.isNotEmpty)
                ? '${TvApiConstants.channelLogoFallbackUrl}$logoFilename'
                : (logoUrl.isNotEmpty
                    ? '${TvApiConstants.channelLogoFallbackUrl}${logoUrl.split('/').last.split('?').first}'
                    : '')),
        epgSchedule = epgSchedule ?? [];

  Program get activeProgram {
    if (currentProgram != null) return currentProgram!;
    final now = DateTime.now();
    final roundedMinutes = (now.minute ~/ 30) * 30;
    final start = DateTime(now.year, now.month, now.day, now.hour, roundedMinutes);
    final end = start.add(const Duration(minutes: 30));
    return Program(
      programId: 'live_$channelId',
      channelId: channelId,
      title: '$channelName Live Broadcast',
      episode: '$category Special',
      synopsis: 'Watch live continuous broadcast of $channelName in HD quality with catchup support on JioTV+ TV.',
      startTime: start,
      endTime: end,
      genre: category,
      hasCatchup: isCatchup,
    );
  }

  factory Channel.fromJson(Map<String, dynamic> json) {
    final chId = json['channel_id']?.toString() ?? json['channelId']?.toString() ?? '0';

    // Parse category: handle integer ID or string
    String cat = 'Entertainment';
    final rawCatId = json['channelCategoryId'] ?? json['category'];
    if (rawCatId is int) {
      cat = TvApiConstants.categoryMap[rawCatId] ?? 'General';
    } else if (rawCatId is String) {
      final parsedInt = int.tryParse(rawCatId);
      if (parsedInt != null && TvApiConstants.categoryMap.containsKey(parsedInt)) {
        cat = TvApiConstants.categoryMap[parsedInt]!;
      } else if (rawCatId.isNotEmpty) {
        cat = rawCatId;
      }
    }

    // Parse language: handle integer ID or string
    String lang = 'Hindi';
    final rawLangId = json['channelLanguageId'] ?? json['language'];
    if (rawLangId is int) {
      lang = TvApiConstants.languageMap[rawLangId] ?? 'Hindi';
    } else if (rawLangId is String) {
      final parsedInt = int.tryParse(rawLangId);
      if (parsedInt != null && TvApiConstants.languageMap.containsKey(parsedInt)) {
        lang = TvApiConstants.languageMap[parsedInt]!;
      } else if (rawLangId.isNotEmpty) {
        lang = rawLangId;
      }
    }

    // Parse logo URL: if upstream gives filename like "ColorsHD1.png", prepend CDN URL
    String rawLogo = json['logoUrl'] ?? json['logo'] ?? json['channel_logo'] ?? '';
    String filename = rawLogo.trim();
    if (filename.startsWith('/')) filename = filename.substring(1);
    if (filename.startsWith('http://') || filename.startsWith('https://')) {
      final uri = Uri.tryParse(filename);
      filename = uri != null && uri.pathSegments.isNotEmpty ? uri.pathSegments.last : filename;
    }
    if (filename.isEmpty) {
      filename = '$chId.png';
    }

    final logo = '${TvApiConstants.channelLogoBaseUrl}$filename';
    final backupLogo = '${TvApiConstants.channelLogoFallbackUrl}$filename';

    final name = json['channel_name'] ?? json['name'] ?? 'Channel';
    final isHd = json['isHD'] == true || name.toUpperCase().contains('HD');

    // Parse channel number / order safely without TypeError on String
    final rawOrder = json['channel_order'];
    int order;
    if (rawOrder is num) {
      order = rawOrder.toInt();
    } else if (rawOrder is String) {
      order = int.tryParse(rawOrder) ?? int.tryParse(chId) ?? 100;
    } else {
      order = int.tryParse(chId) ?? 100;
    }

    // stbChannelNumber
    final rawStb = json['stbChannelNumber'];
    int? stb;
    if (rawStb is num) {
      stb = rawStb.toInt();
    } else if (rawStb is String) {
      stb = int.tryParse(rawStb);
    }

    // businessType & isPremium
    final bizType = json['business_type']?.toString().toLowerCase() ?? 'free';
    final price = json['channelPrice']?.toString().trim() ?? '';
    final isPrem = json['is_premium'] == true ||
        bizType == 'premium' ||
        (price.isNotEmpty && price.toLowerCase() != 'free');

    // isCatchup
    final isCatchup = json['isCatchupAvailable'] == true ||
        json['isCatchup'] == true ||
        json['stbCatchup'] == true;

    return Channel(
      channelId: chId,
      channelNo: stb ?? (order > 0 ? order : int.tryParse(chId) ?? 100),
      channelName: name,
      logoUrl: logo,
      logoFilename: filename,
      backupLogoUrl: backupLogo,
      streamUrl: json['streamUrl'] ?? '',
      category: cat,
      language: lang,
      isHd: isHd,
      isCatchup: isCatchup,
      isPremium: isPrem,
      channelPrice: price.isNotEmpty ? price : (isPrem ? 'Premium' : 'Free'),
      businessType: bizType,
      stbChannelNumber: stb,
      isFavorite: json['isFavorite'] == true,
    );
  }
}
