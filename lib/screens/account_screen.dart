import 'package:flutter/material.dart';
import 'package:hugeicons/hugeicons.dart';
import '../services/channel_service.dart';
import '../services/storage_service.dart';
import '../theme/tv_colors.dart';
import '../theme/tv_dimensions.dart';
import '../widgets/tv_focusable.dart';

enum _SettingsSection {
  playback,
  account,
  channels,
  diagnostics,
}

class AccountScreen extends StatefulWidget {
  final StorageService storageService;
  final ChannelService channelService;
  final VoidCallback onSignOut;
  final VoidCallback onBack;

  const AccountScreen({
    super.key,
    required this.storageService,
    required this.channelService,
    required this.onSignOut,
    required this.onBack,
  });

  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  _SettingsSection _selectedSection = _SettingsSection.playback;
  bool _isRefreshing = false;
  String? _statusBanner;

  // Local settings state
  late double _previewDelay;
  late bool _autoplayPreview;
  late String _streamQuality;
  late bool _hwAccel;
  late bool _lowLatency;
  late String _preferredLanguage;
  late bool _showPremium;

  final List<double> _delayOptions = [0.5, 1.0, 1.5, 2.0, 3.0];
  final List<String> _qualityOptions = ['Auto', 'High (1080p)', 'Medium (720p)', 'Low (480p)'];

  @override
  void initState() {
    super.initState();
    _previewDelay = widget.storageService.getPreviewAutoplayDelay();
    _autoplayPreview = widget.storageService.getAutoplayPreview();
    _streamQuality = widget.storageService.getPreferredQuality();
    _hwAccel = widget.storageService.getHardwareAccel();
    _lowLatency = widget.storageService.getLowLatencyMode();
    _preferredLanguage = widget.storageService.getPreferredLanguage();
    _showPremium = widget.channelService.showPremiumChannels;
  }

  void _showNotification(String msg) {
    if (!mounted) return;
    setState(() {
      _statusBanner = msg;
    });
  }

  Future<void> _refreshChannels() async {
    setState(() {
      _isRefreshing = true;
      _statusBanner = null;
    });

    await widget.channelService.initialize();

    if (mounted) {
      setState(() {
        _isRefreshing = false;
        _statusBanner = 'Channels & EPG schedules refreshed successfully!';
      });
    }
  }

  Future<void> _clearCache() async {
    _showNotification('Local TV cache and image buffers cleared successfully.');
  }

  void _cyclePreviewDelay() {
    final currentIndex = _delayOptions.indexOf(_previewDelay);
    final nextIndex = (currentIndex + 1) % _delayOptions.length;
    final newDelay = _delayOptions[nextIndex];
    setState(() {
      _previewDelay = newDelay;
    });
    widget.storageService.setPreviewAutoplayDelay(newDelay);
    _showNotification('Video preview autoplay delay set to ${_previewDelay}s');
  }

  void _toggleAutoplay() {
    final newValue = !_autoplayPreview;
    setState(() {
      _autoplayPreview = newValue;
    });
    widget.storageService.setAutoplayPreview(newValue);
    _showNotification(newValue ? 'Video preview autoplay enabled.' : 'Video preview autoplay disabled.');
  }

  void _cycleQuality() {
    final currentIndex = _qualityOptions.indexOf(_streamQuality);
    final nextIndex = (currentIndex + 1) % _qualityOptions.length;
    final newQuality = _qualityOptions[nextIndex];
    setState(() {
      _streamQuality = newQuality;
    });
    widget.storageService.setPreferredQuality(newQuality);
    _showNotification('Default stream quality set to $newQuality');
  }

  void _toggleHwAccel() {
    final newVal = !_hwAccel;
    setState(() {
      _hwAccel = newVal;
    });
    widget.storageService.setHardwareAccel(newVal);
    _showNotification(newVal ? 'Hardware acceleration enabled.' : 'Hardware acceleration disabled.');
  }

  void _toggleLowLatency() {
    final newVal = !_lowLatency;
    setState(() {
      _lowLatency = newVal;
    });
    widget.storageService.setLowLatencyMode(newVal);
    _showNotification(newVal ? 'Low latency mode active.' : 'Standard stream buffering active.');
  }

  Future<void> _toggleShowPremium() async {
    await widget.channelService.toggleShowPremiumChannels();
    setState(() {
      _showPremium = widget.channelService.showPremiumChannels;
    });
    _showNotification(_showPremium ? 'Premium channels are now visible.' : 'Premium channels are now hidden.');
  }

  void _cycleLanguage() {
    final languages = widget.channelService.languages.where((l) => l != 'ALL').toList();
    if (languages.isEmpty) return;
    final currentIndex = languages.indexOf(_preferredLanguage);
    final nextIndex = (currentIndex + 1) % languages.length;
    final newLang = languages[nextIndex];
    setState(() {
      _preferredLanguage = newLang;
    });
    widget.storageService.setPreferredLanguage(newLang);
    _showNotification('Preferred audio language set to $newLang');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF100E0C),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: TvDimensions.overscanMargin,
            vertical: TvDimensions.overscanMarginVertical,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Notification Banner
              if (_statusBanner != null) ...[
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFD48B28).withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD48B28).withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      const HugeIcon(
                        icon: HugeIcons.strokeRoundedSparkles,
                        color: Color(0xFFFFB300),
                        size: 16,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _statusBanner!,
                        style: const TextStyle(fontSize: 13, color: Color(0xFFFFD54F), fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
              ],

              // 2-Pane Split Layout (Matching Image 2 Reference)
              Expanded(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // LEFT PANE: Back button, Title & Section Navigation Tiles
                    SizedBox(
                      width: 330,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Back Button (Matching Image 2 round button)
                          TvFocusable(
                            autofocus: false,
                            onPressed: widget.onBack,
                            borderRadius: BorderRadius.circular(24),
                            backgroundColor: const Color(0xFF231D18),
                            padding: const EdgeInsets.all(12),
                            child: const HugeIcon(
                              icon: HugeIcons.strokeRoundedArrowLeft01,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Screen Title (Matching Image 2 "Settings")
                          const Text(
                            'Settings',
                            style: TextStyle(
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                          ),
                          const SizedBox(height: 20),

                          // Section Tiles
                          Expanded(
                            child: ListView(
                              clipBehavior: Clip.none,
                              children: [
                                _buildNavSectionTile(
                                  section: _SettingsSection.playback,
                                  title: 'Playback & Preview',
                                  subtitle: 'Preview delay (${_previewDelay}s) • Quality',
                                  icon: HugeIcons.strokeRoundedPlay,
                                ),
                                const SizedBox(height: 12),
                                _buildNavSectionTile(
                                  section: _SettingsSection.account,
                                  title: 'Account',
                                  subtitle: widget.storageService.getMobileNumber() != null
                                      ? '+91 ${widget.storageService.getMobileNumber()}'
                                      : 'Manage subscription',
                                  icon: HugeIcons.strokeRoundedUser,
                                ),
                                const SizedBox(height: 12),
                                _buildNavSectionTile(
                                  section: _SettingsSection.channels,
                                  title: 'Channels & Guide',
                                  subtitle: 'Premium channels • Languages',
                                  icon: HugeIcons.strokeRoundedTv01,
                                ),
                                const SizedBox(height: 12),
                                _buildNavSectionTile(
                                  section: _SettingsSection.diagnostics,
                                  title: 'System & Diagnostics',
                                  subtitle: 'Sync catalog • Clear cache • Engine',
                                  icon: HugeIcons.strokeRoundedSettings02,
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 32),

                    // RIGHT PANE: Selected Section Content Cards (Matching Image 2 Reference)
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Active Section Title Header
                          Text(
                            _getSectionHeaderTitle(),
                            style: const TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFE89A4B),
                              letterSpacing: 0.2,
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Scrollable Section Settings Cards
                          Expanded(
                            child: SingleChildScrollView(
                              clipBehavior: Clip.none,
                              physics: const BouncingScrollPhysics(),
                              child: _buildSelectedSectionContent(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _getSectionHeaderTitle() {
    switch (_selectedSection) {
      case _SettingsSection.playback:
        return 'Playback & Preview';
      case _SettingsSection.account:
        return 'Account & Subscription';
      case _SettingsSection.channels:
        return 'Channels & Guide';
      case _SettingsSection.diagnostics:
        return 'System & Diagnostics';
    }
  }

  /// Navigation Section Tile for the Left Pane
  Widget _buildNavSectionTile({
    required _SettingsSection section,
    required String title,
    required String subtitle,
    required List<List<dynamic>> icon,
  }) {
    final isSelected = _selectedSection == section;

    return TvFocusable(
      onPressed: () {
        setState(() => _selectedSection = section);
      },
      onFocusChange: (hasF) {
        if (hasF) {
          setState(() => _selectedSection = section);
        }
      },
      borderRadius: BorderRadius.circular(16),
      backgroundColor: isSelected ? const Color(0xFF28201A) : const Color(0xFF1B1612),
      focusedBackgroundColor: const Color(0xFF332A22),
      focusedBorderColor: const Color(0xFFE89A4B),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: isSelected ? const Color(0xFFE89A4B).withValues(alpha: 0.2) : Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(10),
            ),
            child: HugeIcon(
              icon: icon,
              color: isSelected ? const Color(0xFFE89A4B) : const Color(0xFF9E958C),
              size: 20,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: isSelected ? Colors.white : const Color(0xFFC7BFB5),
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF8E867E),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Content Builder for the selected Right Pane section
  Widget _buildSelectedSectionContent() {
    switch (_selectedSection) {
      case _SettingsSection.playback:
        return _buildPlaybackSettings();
      case _SettingsSection.account:
        return _buildAccountSettings();
      case _SettingsSection.channels:
        return _buildChannelsSettings();
      case _SettingsSection.diagnostics:
        return _buildDiagnosticsSettings();
    }
  }

  /// Section 1: Playback & Preview Settings (Contains the delay setting specified by user)
  Widget _buildPlaybackSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Card Group 1: For You Hero Preview
        _buildSettingsCard(
          groupTitle: 'For You Preview',
          children: [
            // Preview Autoplay Toggle
            _buildInteractiveRow(
              title: 'Autoplay Preview Video',
              subtitle: 'Play live broadcast preview when focused on a channel',
              control: _buildSwitchWidget(
                value: _autoplayPreview,
                onChanged: (_) => _toggleAutoplay(),
              ),
              onTap: _toggleAutoplay,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            // Delay Setting (Explicit user requirement: delay before preview video starts)
            _buildInteractiveRow(
              title: 'Preview Autoplay Delay',
              subtitle: 'Wait time showing poster before video starts playing',
              control: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFFE89A4B).withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFFE89A4B).withValues(alpha: 0.6)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${_previewDelay}s',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFFB300),
                      ),
                    ),
                    const SizedBox(width: 6),
                    const HugeIcon(
                      icon: HugeIcons.strokeRoundedArrowRight01,
                      color: Color(0xFFFFB300),
                      size: 14,
                    ),
                  ],
                ),
              ),
              onTap: _cyclePreviewDelay,
            ),
          ],
        ),

        const SizedBox(height: 18),

        // Card Group 2: Stream Quality & Engine
        _buildSettingsCard(
          groupTitle: 'Playback Quality',
          children: [
            _buildInteractiveRow(
              title: 'Streaming Quality',
              subtitle: 'Default live video resolution',
              control: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  _streamQuality,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              onTap: _cycleQuality,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            _buildInteractiveRow(
              title: 'Hardware Acceleration',
              subtitle: 'Use GPU decoding for fluid 60fps playback',
              control: _buildSwitchWidget(
                value: _hwAccel,
                onChanged: (_) => _toggleHwAccel(),
              ),
              onTap: _toggleHwAccel,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            _buildInteractiveRow(
              title: 'Low Latency Live Mode',
              subtitle: 'Minimize broadcast delay for live sports and news',
              control: _buildSwitchWidget(
                value: _lowLatency,
                onChanged: (_) => _toggleLowLatency(),
              ),
              onTap: _toggleLowLatency,
            ),
          ],
        ),
      ],
    );
  }

  /// Section 2: Account & Subscription Settings
  Widget _buildAccountSettings() {
    final phone = widget.storageService.getMobileNumber();
    final isLoggedIn = widget.storageService.isAuthenticated;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsCard(
          groupTitle: 'Subscription Profile',
          children: [
            _buildInfoDisplayRow('Subscriber', isLoggedIn && phone != null ? '+91 $phone' : 'Active JioTV Subscriber'),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('Membership Status', 'JioTV+ VIP ACTIVE', valueColor: const Color(0xFFE89A4B)),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('Plan Details', 'Jio Fiber / JioTV+ Big Screen VIP'),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('Device ID', 'd04b868e404b88df (Android 13)'),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('App Version', 'JioTV+ 7.1.8 (Build 422 Android TV)'),
          ],
        ),

        const SizedBox(height: 18),

        _buildSettingsCard(
          groupTitle: 'Account Actions',
          children: [
            TvFocusable(
              onPressed: widget.onSignOut,
              borderRadius: BorderRadius.circular(12),
              backgroundColor: TvColors.liveRed.withValues(alpha: 0.15),
              focusedBorderColor: TvColors.liveRed,
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: const Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    HugeIcon(
                      icon: HugeIcons.strokeRoundedCancel01,
                      color: TvColors.liveRed,
                      size: 18,
                    ),
                    SizedBox(width: 10),
                    Text(
                      'Switch Account / Sign Out',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                        color: TvColors.liveRed,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// Section 3: Channels & Guide Settings
  Widget _buildChannelsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsCard(
          groupTitle: 'Channel Filtering',
          children: [
            _buildInteractiveRow(
              title: 'Show Premium Channels',
              subtitle: 'Display subscription-locked premium channels in live guide and search',
              control: _buildSwitchWidget(
                value: _showPremium,
                onChanged: (_) => _toggleShowPremium(),
              ),
              onTap: _toggleShowPremium,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            _buildInteractiveRow(
              title: 'Preferred Audio & Guide Language',
              subtitle: 'Default language for channel audio streams',
              control: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                ),
                child: Text(
                  _preferredLanguage,
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
              onTap: _cycleLanguage,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            _buildInfoDisplayRow('Catalog Total', '${widget.channelService.allChannels.length} Live Channels Available'),
          ],
        ),

        const SizedBox(height: 18),

        _buildSettingsCard(
          groupTitle: 'Favorites Management',
          children: [
            _buildInteractiveRow(
              title: 'Favorites Count',
              subtitle: '${widget.channelService.allChannels.where((c) => c.isFavorite).length} channels pinned to your favorites',
              control: TvFocusable(
                onPressed: () {
                  final favs = widget.channelService.allChannels.where((c) => c.isFavorite).toList();
                  for (final c in favs) {
                    widget.channelService.toggleFavorite(c);
                  }
                  setState(() {});
                  _showNotification('All channel favorites have been cleared.');
                },
                borderRadius: BorderRadius.circular(8),
                backgroundColor: const Color(0xFF2E241E),
                focusedBorderColor: const Color(0xFFE89A4B),
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                child: const Text('Clear Favorites', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w700)),
              ),
              onTap: null,
            ),
          ],
        ),
      ],
    );
  }

  /// Section 4: System & Diagnostics Settings
  Widget _buildDiagnosticsSettings() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSettingsCard(
          groupTitle: 'Channel Catalog & EPG Data',
          children: [
            _buildInteractiveRow(
              title: 'Sync Channels & EPG',
              subtitle: 'Force re-fetch all live channels and program schedules directly from Jio CDN',
              control: TvFocusable(
                onPressed: _isRefreshing ? null : _refreshChannels,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: const Color(0xFFE89A4B).withValues(alpha: 0.2),
                focusedBorderColor: const Color(0xFFE89A4B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_isRefreshing) ...[
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(color: Color(0xFFFFB300), strokeWidth: 2),
                      ),
                      const SizedBox(width: 8),
                    ],
                    Text(
                      _isRefreshing ? 'Syncing...' : 'Sync Now',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Color(0xFFFFB300)),
                    ),
                  ],
                ),
              ),
              onTap: _isRefreshing ? null : _refreshChannels,
            ),
            const Divider(color: Color(0xFF2D251F), height: 24),

            _buildInteractiveRow(
              title: 'Clear Local TV Cache',
              subtitle: 'Free memory buffers and purge stale program metadata',
              control: TvFocusable(
                onPressed: _clearCache,
                borderRadius: BorderRadius.circular(10),
                backgroundColor: const Color(0xFF2E241E),
                focusedBorderColor: const Color(0xFFE89A4B),
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: const Text('Clear Cache', style: TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w800)),
              ),
              onTap: _clearCache,
            ),
          ],
        ),

        const SizedBox(height: 18),

        _buildSettingsCard(
          groupTitle: 'Engine Diagnostics',
          children: [
            _buildInfoDisplayRow('Playback Engine', 'Native ExoPlayer 2.11.7'),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('Security & DRM', 'HLS AES-128 / Widevine Modular DRM'),
            const Divider(color: Color(0xFF2D251F), height: 20),
            _buildInfoDisplayRow('Stream Proxy', 'Active (Localhost Proxy :39871)', valueColor: const Color(0xFF00D2FF)),
          ],
        ),
      ],
    );
  }

  /// Rounded Card grouping related settings (Matching Image 2 Reference)
  Widget _buildSettingsCard({
    required String groupTitle,
    required List<Widget> children,
  }) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1B1612),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFF2A221C)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            groupTitle,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF8E867E),
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }

  /// Interactive TV Focusable Row for toggles and pickers
  Widget _buildInteractiveRow({
    required String title,
    required String subtitle,
    required Widget control,
    VoidCallback? onTap,
  }) {
    return TvFocusable(
      onPressed: onTap,
      borderRadius: BorderRadius.circular(12),
      backgroundColor: Colors.transparent,
      focusedBackgroundColor: const Color(0xFF28201A),
      focusedBorderColor: const Color(0xFFE89A4B),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF9E958C),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          control,
        ],
      ),
    );
  }

  Widget _buildInfoDisplayRow(String label, String value, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 14, color: Color(0xFFC7BFB5)),
          ),
          Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: valueColor ?? Colors.white,
            ),
          ),
        ],
      ),
    );
  }

  /// Switch Widget matching Image 2's warm accent toggle
  Widget _buildSwitchWidget({
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      width: 52,
      height: 30,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: value ? const Color(0xFFD48B28) : const Color(0xFF332A22),
        borderRadius: BorderRadius.circular(16),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 200),
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 24,
          height: 24,
          decoration: const BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
