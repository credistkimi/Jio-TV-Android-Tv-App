import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'models/channel.dart';
import 'models/program.dart';
import 'screens/account_screen.dart';
import 'screens/auth_screen.dart';
import 'screens/catchup_screen.dart';
import 'screens/epg_screen.dart';
import 'screens/home_screen.dart';
import 'screens/player_screen.dart';
import 'screens/search_screen.dart';
import 'screens/splash_screen.dart';
import 'services/api_service.dart';
import 'services/channel_service.dart';
import 'services/fire_tv_epg_service.dart';
import 'services/storage_service.dart';
import 'theme/tv_colors.dart';
import 'widgets/tv_nav_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Force TV landscape orientation
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.landscapeLeft,
    DeviceOrientation.landscapeRight,
  ]);

  // Hide system status bar for immersive 10-foot TV experience
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  final storageService = await StorageService.create();
  final apiService = ApiService();
  final channelService = ChannelService(apiService, storageService);
  final fireTvEpgService = FireTvEpgService();
  await channelService.initialize();

  runApp(JioTvApp(
    storageService: storageService,
    apiService: apiService,
    channelService: channelService,
    fireTvEpgService: fireTvEpgService,
  ));
}

class JioTvApp extends StatelessWidget {
  final StorageService storageService;
  final ApiService apiService;
  final ChannelService channelService;
  final FireTvEpgService fireTvEpgService;

  const JioTvApp({
    super.key,
    required this.storageService,
    required this.apiService,
    required this.channelService,
    required this.fireTvEpgService,
  });

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'JioTV+ TV',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: TvColors.bgCanvas,
        colorScheme: const ColorScheme.dark(
          primary: TvColors.accentPrimary,
          surface: TvColors.bgSurface1,
        ),
      ),
      home: TvMainController(
        storageService: storageService,
        apiService: apiService,
        channelService: channelService,
        fireTvEpgService: fireTvEpgService,
      ),
    );
  }
}

class TvMainController extends StatefulWidget {
  final StorageService storageService;
  final ApiService apiService;
  final ChannelService channelService;
  final FireTvEpgService fireTvEpgService;
  final bool showSplashOnInit;
  final Duration? splashDuration;

  const TvMainController({
    super.key,
    required this.storageService,
    required this.apiService,
    required this.channelService,
    required this.fireTvEpgService,
    this.showSplashOnInit = true,
    this.splashDuration,
  });

  @override
  State<TvMainController> createState() => _TvMainControllerState();
}

class _TvMainControllerState extends State<TvMainController> {
  TvNavDestination _currentScreen = TvNavDestination.liveGuide;
  Channel? _playerChannel;
  Program? _playerProgram;
  bool _isPlayerOpen = false;
  late bool _showSplash;
  late final FocusNode _globalKeyFocusNode;

  @override
  void initState() {
    super.initState();
    _showSplash = widget.showSplashOnInit;
    _globalKeyFocusNode = FocusNode(debugLabel: 'GlobalKeyFocus', canRequestFocus: false);
    widget.channelService.addListener(_onChannelServiceChanged);

    // Register Amazon Fire TV Guide integration listeners
    widget.fireTvEpgService.setOnChannelSelectedListener(_handleChannelFromFireTv);
    _checkInitialChannelFromFireTv();

    // Auto-sync channels to Fire TV Live Guide after launch
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.channelService.rawChannels.isNotEmpty) {
        widget.fireTvEpgService.syncChannelsToFireTv(widget.channelService.rawChannels);
      }
    });

    final token = widget.storageService.getSsoToken();
    if (token == null || token.isEmpty) {
      _currentScreen = TvNavDestination.auth;
    }
  }

  Future<void> _checkInitialChannelFromFireTv() async {
    final chId = await widget.fireTvEpgService.getInitialChannelId();
    if (chId != null && chId.isNotEmpty) {
      _handleChannelFromFireTv(chId);
    }
  }

  void _handleChannelFromFireTv(String channelId) {
    final channels = widget.channelService.rawChannels;
    if (channels.isEmpty) return;
    final match = channels.firstWhere(
      (c) => c.channelId == channelId || c.channelNo.toString() == channelId,
      orElse: () => channels.first,
    );
    _openPlayer(match);
  }

  void _onChannelServiceChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  void dispose() {
    widget.channelService.removeListener(_onChannelServiceChanged);
    _globalKeyFocusNode.dispose();
    super.dispose();
  }

  void _openPlayer(Channel channel, [Program? program]) {
    setState(() {
      _playerChannel = channel;
      _playerProgram = program;
      _isPlayerOpen = true;
    });
  }

  void _closePlayer() {
    setState(() {
      _isPlayerOpen = false;
    });
  }

  /// Handles TV Remote & system back navigation according to User specifications:
  /// - Fullscreen Player -> Closes player and returns to current screen
  /// - Favorites Filter -> Turns off filter and displays all channels on For You
  /// - Catch Up / Digital TV (EPG) / Search / Account -> Returns to For You section
  /// - For You (Default) -> Allows system pop / exit
  bool _handleBackNavigation() {
    if (_isPlayerOpen) {
      _closePlayer();
      return true;
    }

    if (widget.channelService.filterOnlyFavorites) {
      widget.channelService.toggleFavoritesFilter();
      setState(() {
        _currentScreen = TvNavDestination.liveGuide;
      });
      return true;
    }

    if (_currentScreen != TvNavDestination.liveGuide && _currentScreen != TvNavDestination.auth) {
      setState(() {
        _currentScreen = TvNavDestination.liveGuide;
      });
      return true;
    }

    return false;
  }

  void _handleGlobalKeys(KeyEvent event) {
    if (event is! KeyDownEvent) return;

    // TV Remote Back / Escape Key Interception
    if (event.logicalKey == LogicalKeyboardKey.escape ||
        event.logicalKey == LogicalKeyboardKey.goBack) {
      if (_handleBackNavigation()) return;
    }

    // Remote color button shortcuts (F1=Red, F2=Green, F3=Yellow, F4=Blue)
    if (event.logicalKey == LogicalKeyboardKey.f1) {
      setState(() {
        _isPlayerOpen = false;
        _currentScreen = TvNavDestination.liveGuide;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.f2) {
      setState(() {
        _isPlayerOpen = false;
        _currentScreen = TvNavDestination.catchup;
      });
    } else if (event.logicalKey == LogicalKeyboardKey.f3) {
      widget.channelService.toggleFavoritesFilter();
    } else if (event.logicalKey == LogicalKeyboardKey.f4) {
      setState(() {
        _isPlayerOpen = false;
        _currentScreen = TvNavDestination.epgGrid;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canPopNow = !_isPlayerOpen &&
        _currentScreen == TvNavDestination.liveGuide &&
        !widget.channelService.filterOnlyFavorites;

    return PopScope(
      canPop: canPopNow,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _handleBackNavigation();
      },
      child: KeyboardListener(
        focusNode: _globalKeyFocusNode,
        autofocus: false,
        onKeyEvent: _handleGlobalKeys,
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: _buildActiveScreen(),
        ),
      ),
    );
  }

  Widget _buildActiveScreen() {
    // 0. Themed Splash Screen with Left-to-Right Reveal & Audio
    if (_showSplash) {
      return SplashScreen(
        key: const ValueKey('splash_screen'),
        duration: widget.splashDuration ?? const Duration(milliseconds: 2400),
        onFinish: () {
          if (mounted) {
            setState(() => _showSplash = false);
          }
        },
      );
    }

    // 1. Fullscreen Player has highest presentation priority
    if (_isPlayerOpen && _playerChannel != null) {
      return PlayerScreen(
        initialChannel: _playerChannel!,
        targetProgram: _playerProgram,
        channelService: widget.channelService,
        onBack: _closePlayer,
      );
    }

    // 2. Auth Screen
    if (_currentScreen == TvNavDestination.auth) {
      return AuthScreen(
        apiService: widget.apiService,
        storageService: widget.storageService,
        onLoginSuccess: () async {
          await widget.channelService.initialize();
          if (mounted) {
            setState(() => _currentScreen = TvNavDestination.liveGuide);
          }
        },
      );
    }

    // 3. Search Screen (Image 5 Reference)
    if (_currentScreen == TvNavDestination.search) {
      return SearchScreen(
        channelService: widget.channelService,
        onOpenPlayer: (ch) => _openPlayer(ch),
        onBack: () => setState(() => _currentScreen = TvNavDestination.liveGuide),
      );
    }

    // 4. Account Screen
    if (_currentScreen == TvNavDestination.account) {
      return AccountScreen(
        storageService: widget.storageService,
        channelService: widget.channelService,
        fireTvEpgService: widget.fireTvEpgService,
        onSignOut: () async {
          await widget.storageService.clearAuth();
          setState(() => _currentScreen = TvNavDestination.auth);
        },
        onBack: () => setState(() => _currentScreen = TvNavDestination.liveGuide),
      );
    }

    // 5. EPG Guide Screen (Image 2 & 3 Reference)
    if (_currentScreen == TvNavDestination.epgGrid) {
      return EpgScreen(
        channelService: widget.channelService,
        onPlayProgram: (ch, prog) => _openPlayer(ch, prog),
        onBack: () => setState(() => _currentScreen = TvNavDestination.liveGuide),
        onNavigate: (dest) {
          if (dest == TvNavDestination.favorites) {
            widget.channelService.toggleFavoritesFilter();
            setState(() => _currentScreen = TvNavDestination.liveGuide);
          } else {
            setState(() => _currentScreen = dest);
          }
        },
      );
    }

    // 6. 7-Day Catchup Screen
    if (_currentScreen == TvNavDestination.catchup) {
      return CatchupScreen(
        channelService: widget.channelService,
        onPlayProgram: (ch, prog) => _openPlayer(ch, prog),
        onBack: () => setState(() => _currentScreen = TvNavDestination.liveGuide),
        onNavigate: (dest) {
          if (dest == TvNavDestination.favorites) {
            widget.channelService.toggleFavoritesFilter();
            setState(() => _currentScreen = TvNavDestination.liveGuide);
          } else {
            setState(() => _currentScreen = dest);
          }
        },
      );
    }

    // 7. Default Home / Live Guide Screen (Image 1 & 4 Reference)
    return HomeScreen(
      channelService: widget.channelService,
      storageService: widget.storageService,
      onOpenPlayer: (ch) => _openPlayer(ch),
      onNavigate: (dest) {
        if (dest == TvNavDestination.favorites) {
          widget.channelService.toggleFavoritesFilter();
          setState(() => _currentScreen = TvNavDestination.liveGuide);
        } else {
          setState(() => _currentScreen = dest);
        }
      },
    );
  }
}
