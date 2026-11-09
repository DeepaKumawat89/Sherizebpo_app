// import 'dart:async';

// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter/material.dart';
// import 'package:lucide_icons/lucide_icons.dart';
// import 'package:video_player/video_player.dart';
// import '../../core/constants/constants.dart';
// import '../../routes.dart';

// /// Onboarding Screen — First screen shown to new users.
// class OnboardingScreen extends StatefulWidget {
//   const OnboardingScreen({Key? key}) : super(key: key);

//   @override
//   State<OnboardingScreen> createState() => _OnboardingScreenState();
// }

// class _OnboardingScreenState extends State<OnboardingScreen>
//     with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
//   late AnimationController _animController;
//   late Animation<double> _fadeIn;
//   late Animation<Offset> _slideUp;
//   final ScrollController _scrollController = ScrollController();
//   final GlobalKey _videoKey = GlobalKey();

//   VideoPlayerController? _videoController;
//   bool _videoError = false;
//   bool _routeIsActive = true;
//   bool _appIsActive = true;
//   bool _videoIsVisible = true;
//   bool _playbackSyncRunning = false;
//   bool _playbackSyncPending = false;
//   bool _visibilityCheckScheduled = false;
//   ModalRoute<void>? _route;

//   static const _assetName = 'assets/plant_growth_new.mp4';

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _appIsActive =
//         WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
//     _scrollController.addListener(_scheduleVisibilityCheck);

//     // ── Entrance animation ──────────────────────────────────────
//     _animController = AnimationController(
//       vsync: this,
//       duration: const Duration(milliseconds: 1200),
//     );
//     _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
//     _slideUp = Tween<Offset>(
//       begin: const Offset(0, 0.15),
//       end: Offset.zero,
//     ).animate(
//       CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
//     );
//     _animController.addStatusListener((status) {
//       if (status == AnimationStatus.completed && mounted) {
//         _maybeInitializeVideo();
//       }
//     });
//     _animController.forward();
//   }

//   @override
//   void didChangeDependencies() {
//     super.didChangeDependencies();
//     final route = ModalRoute.of<void>(context);
//     if (route != _route) {
//       if (_route != null) AppRoutes.routeObserver.unsubscribe(this);
//       _route = route;
//       if (route != null) AppRoutes.routeObserver.subscribe(this, route);
//     }
//     _scheduleVisibilityCheck();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     _appIsActive = state == AppLifecycleState.resumed;
//     _maybeInitializeVideo();
//     unawaited(_syncVideoPlayback());
//   }

//   @override
//   void didPush() {
//     _routeIsActive = true;
//     _maybeInitializeVideo();
//     unawaited(_syncVideoPlayback());
//   }

//   @override
//   void didPushNext() {
//     _routeIsActive = false;
//     unawaited(_syncVideoPlayback());
//   }

//   @override
//   void didPopNext() {
//     _routeIsActive = true;
//     _maybeInitializeVideo();
//     _scheduleVisibilityCheck();
//   }

//   void _maybeInitializeVideo() {
//     if (mounted &&
//         _animController.status == AnimationStatus.completed &&
//         _appIsActive &&
//         _routeIsActive &&
//         _videoIsVisible &&
//         !_videoError &&
//         _videoController == null) {
//       unawaited(_initVideo());
//     }
//   }

//   /// Initialises the video player with a platform-aware URL strategy and
//   /// robust mounted-checks to prevent setState after dispose.
//   Future<void> _initVideo() async {
//     if (!mounted || _videoController != null) return;

//     final VideoPlayerController controller;

//     if (kIsWeb) {
//       // On Flutter Web, bundled assets are served under `assets/<asset-key>`.
//       // The asset key already starts with `assets/`, so the real URL has the
//       // prefix twice (…/assets/assets/plant_growth_new.mp4). Resolve against
//       // the page's base URL so it works under any hosting sub-path.
//       final Uri assetUri = Uri.base.resolve('assets/$_assetName');
//       controller = VideoPlayerController.networkUrl(assetUri);
//     } else {
//       controller = VideoPlayerController.asset(_assetName);
//     }

//     // Store reference so dispose() can clean it up even if init is pending
//     _videoController = controller;

//     try {
//       await controller.initialize();
//       if (!mounted || !identical(_videoController, controller)) return;

//       await controller.setLooping(false);
//       await controller.setVolume(0.0);
//       if (mounted) {
//         setState(() {});
//         _scheduleVisibilityCheck();
//       }
//     } catch (e) {
//       if (identical(_videoController, controller)) {
//         _videoController = null;
//         await controller.dispose();
//       }
//       debugPrint('OnboardingScreen: video init failed — $e');
//       if (mounted) setState(() => _videoError = true);
//     }
//   }

//   void _scheduleVisibilityCheck() {
//     if (_visibilityCheckScheduled || !mounted) return;
//     _visibilityCheckScheduled = true;
//     WidgetsBinding.instance.addPostFrameCallback((_) {
//       _visibilityCheckScheduled = false;
//       if (!mounted) return;
//       final renderObject =
//           _videoKey.currentContext?.findRenderObject() as RenderBox?;
//       if (renderObject == null || !renderObject.hasSize) return;
//       final top = renderObject.localToGlobal(Offset.zero).dy;
//       final bottom = top + renderObject.size.height;
//       final viewportHeight = MediaQuery.sizeOf(context).height;
//       _videoIsVisible = bottom > 0 && top < viewportHeight;
//       _maybeInitializeVideo();
//       unawaited(_syncVideoPlayback());
//     });
//   }

//   Future<void> _syncVideoPlayback() async {
//     if (_playbackSyncRunning) {
//       _playbackSyncPending = true;
//       return;
//     }
//     _playbackSyncRunning = true;
//     try {
//       do {
//         _playbackSyncPending = false;
//         final controller = _videoController;
//         if (controller == null) {
//           _maybeInitializeVideo();
//           continue;
//         }
//         if (!controller.value.isInitialized) continue;
//         final shouldPlay = mounted &&
//             _appIsActive &&
//             _routeIsActive &&
//             _videoIsVisible &&
//             !_videoError &&
//             controller.value.position < controller.value.duration;
//         if (shouldPlay && !controller.value.isPlaying) {
//           await controller.play();
//         } else if (!shouldPlay && controller.value.isPlaying) {
//           await controller.pause();
//         }
//       } while (_playbackSyncPending);
//     } catch (error) {
//       debugPrint('OnboardingScreen: video playback update failed — $error');
//     } finally {
//       _playbackSyncRunning = false;
//       if (_playbackSyncPending && mounted) {
//         _playbackSyncPending = false;
//         unawaited(_syncVideoPlayback());
//       }
//     }
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     AppRoutes.routeObserver.unsubscribe(this);
//     _scrollController
//       ..removeListener(_scheduleVisibilityCheck)
//       ..dispose();
//     _animController.dispose();
//     final controller = _videoController;
//     _videoController = null;
//     if (controller != null) unawaited(controller.dispose());
//     super.dispose();
//   }

//   @override
//   Widget build(BuildContext context) {
//     final screenHeight = MediaQuery.of(context).size.height;

//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: SafeArea(
//         child: FadeTransition(
//           opacity: _fadeIn,
//           child: SlideTransition(
//             position: _slideUp,
//             child: CustomScrollView(
//               controller: _scrollController,
//               slivers: [
//                 SliverFillRemaining(
//                   hasScrollBody: false,
//                   child: Column(
//                       children: [
//                         SizedBox(height: screenHeight * 0.10),

//                         // ── Video ────────────────────────────────────────
//                         _buildVideoWidget(),

//                         SizedBox(height: screenHeight * 0.06),

//                         // ── Headline ─────────────────────────────────────
//                         const Text(
//                           'Grow with Sherize',
//                           style: TextStyle(
//                             color: Colors.black87,
//                             fontSize: 32,
//                             fontWeight: FontWeight.w700,
//                             letterSpacing: -0.5,
//                           ),
//                           textAlign: TextAlign.center,
//                         ),
//                         const SizedBox(height: 12),
//                         const Padding(
//                           padding: EdgeInsets.symmetric(horizontal: 32),
//                           child: Text(
//                             'Join our network. Complete tasks, earn securely, and let your career blossom.',
//                             style: TextStyle(
//                               color: Colors.black54,
//                               fontSize: 15,
//                               height: 1.6,
//                             ),
//                             textAlign: TextAlign.center,
//                           ),
//                         ),
//                         const SizedBox(height: 48),

//                         // ── Get Started Button ────────────────────────────
//                         Padding(
//                           padding: const EdgeInsets.symmetric(
//                             horizontal: AppSizes.screenPaddingH,
//                           ),
//                           child: SizedBox(
//                             width: double.infinity,
//                             height: 56,
//                             child: ElevatedButton(
//                               onPressed: () => Navigator.of(context)
//                                   .pushReplacementNamed(AppRoutes.login),
//                               style: ElevatedButton.styleFrom(
//                                 backgroundColor: AppColors.primary,
//                                 foregroundColor: Colors.white,
//                                 shape: RoundedRectangleBorder(
//                                   borderRadius:
//                                       BorderRadius.circular(AppSizes.radiusLg),
//                                 ),
//                                 elevation: 8,
//                                 shadowColor:
//                                     AppColors.primary.withValues(alpha: 0.3),
//                               ),
//                               child: const Row(
//                                 mainAxisAlignment: MainAxisAlignment.center,
//                                 children: [
//                                   Text(
//                                     'Get Started',
//                                     style: TextStyle(
//                                       fontSize: 18,
//                                       fontWeight: FontWeight.w700,
//                                     ),
//                                   ),
//                                   SizedBox(width: 8),
//                                   Icon(LucideIcons.arrowRight, size: 22),
//                                 ],
//                               ),
//                             ),
//                           ),
//                         ),
//                         const SizedBox(height: 12),

//                         // ── Admin Login Link ──────────────────────────────
//                         TextButton(
//                           onPressed: () => Navigator.of(context)
//                               .pushNamed(AppRoutes.adminLogin),
//                           child: const Text(
//                             'Admin? Login here',
//                             style: TextStyle(
//                               color: Colors.black54,
//                               fontSize: 14,
//                               fontWeight: FontWeight.w500,
//                             ),
//                           ),
//                         ),
//                         const Spacer(),
//                       ],
//                   ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildVideoWidget() {
//     final double size = MediaQuery.of(context).size.width * 0.85;
//     final vc = _videoController;
//     final bool ready = vc != null && vc.value.isInitialized;

//     return Center(
//       key: _videoKey,
//       child: SizedBox(
//         width: size,
//         height: size,
//         child: _videoError
//             // Graceful fallback if video fails on this platform
//             ? const SizedBox.shrink()
//             : ready
//                 ? FittedBox(
//                     fit: BoxFit.cover,
//                     child: SizedBox(
//                       width: vc.value.size.width,
//                       height: vc.value.size.height,
//                       child: VideoPlayer(vc),
//                     ),
//                   )
//                 : const Center(
//                     child: CircularProgressIndicator(
//                       color: AppColors.primary,
//                       strokeWidth: 2,
//                     ),
//                   ),
//       ),
//     );
//   }
// }



import 'dart:async';
 
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:video_player/video_player.dart';
import '../../core/constants/constants.dart';
import '../../routes.dart';
 
/// Onboarding Screen — First screen shown to new users.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({Key? key}) : super(key: key);
 
  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}
 
class _OnboardingScreenState extends State<OnboardingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver, RouteAware {
  late AnimationController _animController;
  late Animation<double> _fadeIn;
  late Animation<Offset> _slideUp;
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _videoKey = GlobalKey();
 
  VideoPlayerController? _videoController;
  bool _videoError = false;
  bool _routeIsActive = true;
  bool _appIsActive = true;
  bool _videoIsVisible = true;
  bool _playbackSyncRunning = false;
  bool _playbackSyncPending = false;
  bool _visibilityCheckScheduled = false;
  ModalRoute<void>? _route;
 
  static const _assetName = 'assets/plant_growth_new.mp4';
 
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _appIsActive =
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _scrollController.addListener(_scheduleVisibilityCheck);
 
    // ── Entrance animation ──────────────────────────────────────
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
    _fadeIn = CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _slideUp = Tween<Offset>(
      begin: const Offset(0, 0.15),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _animController, curve: Curves.easeOutCubic),
    );
    _animController.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        _maybeInitializeVideo();
      }
    });
    _animController.forward();
  }
 
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of<void>(context);
    if (route != _route) {
      if (_route != null) AppRoutes.routeObserver.unsubscribe(this);
      _route = route;
      if (route != null) AppRoutes.routeObserver.subscribe(this, route);
    }
    _scheduleVisibilityCheck();
  }
 
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _appIsActive = state == AppLifecycleState.resumed;
    _maybeInitializeVideo();
    unawaited(_syncVideoPlayback());
  }
 
  @override
  void didPush() {
    _routeIsActive = true;
    _maybeInitializeVideo();
    unawaited(_syncVideoPlayback());
  }
 
  @override
  void didPushNext() {
    _routeIsActive = false;
    unawaited(_syncVideoPlayback());
  }
 
  @override
  void didPopNext() {
    _routeIsActive = true;
    _maybeInitializeVideo();
    _scheduleVisibilityCheck();
  }
 
  void _maybeInitializeVideo() {
    if (mounted &&
        _animController.status == AnimationStatus.completed &&
        _appIsActive &&
        _routeIsActive &&
        _videoIsVisible &&
        !_videoError &&
        _videoController == null) {
      unawaited(_initVideo());
    }
  }
 
  /// Initialises the video player with a platform-aware URL strategy and
  /// robust mounted-checks to prevent setState after dispose.
  Future<void> _initVideo() async {
    if (!mounted || _videoController != null) return;
 
    final VideoPlayerController controller;
 
    if (kIsWeb) {
      // On Flutter Web, bundled assets are served under `assets/<asset-key>`.
      // The asset key already starts with `assets/`, so the real URL has the
      // prefix twice (…/assets/assets/plant_growth_new.mp4). Resolve against
      // the page's base URL so it works under any hosting sub-path.
      final Uri assetUri = Uri.base.resolve('assets/$_assetName');
      controller = VideoPlayerController.networkUrl(assetUri);
    } else {
      controller = VideoPlayerController.asset(_assetName);
    }
 
    // Store reference so dispose() can clean it up even if init is pending
    _videoController = controller;
 
    try {
      await controller.initialize();
      if (!mounted || !identical(_videoController, controller)) return;
 
      await controller.setLooping(false);
      await controller.setVolume(0.0);
      if (mounted) {
        setState(() {});
        _scheduleVisibilityCheck();
      }
    } catch (e) {
      if (identical(_videoController, controller)) {
        _videoController = null;
        await controller.dispose();
      }
      debugPrint('OnboardingScreen: video init failed — $e');
      if (mounted) setState(() => _videoError = true);
    }
  }
 
  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled || !mounted) return;
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _visibilityCheckScheduled = false;
      if (!mounted) return;
      final renderObject =
          _videoKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderObject == null || !renderObject.hasSize) return;
      final top = renderObject.localToGlobal(Offset.zero).dy;
      final bottom = top + renderObject.size.height;
      final viewportHeight = MediaQuery.sizeOf(context).height;
      _videoIsVisible = bottom > 0 && top < viewportHeight;
      _maybeInitializeVideo();
      unawaited(_syncVideoPlayback());
    });
  }
 
  Future<void> _syncVideoPlayback() async {
    if (_playbackSyncRunning) {
      _playbackSyncPending = true;
      return;
    }
    _playbackSyncRunning = true;
    try {
      do {
        _playbackSyncPending = false;
        final controller = _videoController;
        if (controller == null) {
          _maybeInitializeVideo();
          continue;
        }
        if (!controller.value.isInitialized) continue;
        final shouldPlay = mounted &&
            _appIsActive &&
            _routeIsActive &&
            _videoIsVisible &&
            !_videoError &&
            controller.value.position < controller.value.duration;
        if (shouldPlay && !controller.value.isPlaying) {
          await controller.play();
        } else if (!shouldPlay && controller.value.isPlaying) {
          await controller.pause();
        }
      } while (_playbackSyncPending);
    } catch (error) {
      debugPrint('OnboardingScreen: video playback update failed — $error');
    } finally {
      _playbackSyncRunning = false;
      if (_playbackSyncPending && mounted) {
        _playbackSyncPending = false;
        unawaited(_syncVideoPlayback());
      }
    }
  }
 
  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    AppRoutes.routeObserver.unsubscribe(this);
    _scrollController
      ..removeListener(_scheduleVisibilityCheck)
      ..dispose();
    _animController.dispose();
    final controller = _videoController;
    _videoController = null;
    if (controller != null) unawaited(controller.dispose());
    super.dispose();
  }
 
  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;
 
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // ── Soft background: gradient wash + decorative circles ─────────
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.primary.withValues(alpha: 0.10),
                    Colors.white,
                    Colors.white,
                  ],
                  stops: const [0.0, 0.45, 1.0],
                ),
              ),
            ),
          ),
          Positioned(
            top: -80,
            right: -60,
            child: Container(
              width: 220,
              height: 220,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.07),
              ),
            ),
          ),
          Positioned(
            top: 180,
            left: -90,
            child: Container(
              width: 170,
              height: 170,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withValues(alpha: 0.05),
              ),
            ),
          ),
          SafeArea(
            child: FadeTransition(
              opacity: _fadeIn,
              child: SlideTransition(
                position: _slideUp,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const BouncingScrollPhysics(),
                  slivers: [
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Column(
                        children: [
                          SizedBox(height: screenHeight * 0.07),
 
                          // ── Video ────────────────────────────────────────
                          _buildVideoWidget(),
 
                          SizedBox(height: screenHeight * 0.05),
 
                          // ── Headline ─────────────────────────────────────
                          const Text(
                            'Grow with Sherize',
                            style: TextStyle(
                              color: AppColors.textDark,
                              fontSize: 32,
                              fontWeight: FontWeight.w800,
                              letterSpacing: -0.6,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              'Join our network. Complete tasks, earn securely, and let your career blossom.',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 15,
                                height: 1.6,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(height: 40),
 
                          // ── Get Started Button ────────────────────────────
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSizes.screenPaddingH,
                            ),
                            child: Container(
                              width: double.infinity,
                              height: 58,
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.centerLeft,
                                  end: Alignment.centerRight,
                                  colors: [
                                    AppColors.primary,
                                    AppColors.primary.withValues(alpha: 0.78),
                                  ],
                                ),
                                borderRadius:
                                    BorderRadius.circular(AppSizes.radiusLg),
                                boxShadow: [
                                  BoxShadow(
                                    color:
                                        AppColors.primary.withValues(alpha: 0.35),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  borderRadius:
                                      BorderRadius.circular(AppSizes.radiusLg),
                                  onTap: () => Navigator.of(context)
                                      .pushReplacementNamed(AppRoutes.login),
                                  child: const Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Get Started',
                                        style: TextStyle(
                                          color: Colors.white,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w700,
                                        ),
                                      ),
                                      SizedBox(width: 10),
                                      Icon(LucideIcons.arrowRight,
                                          size: 22, color: Colors.white),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
 
                          // ── Admin Login Link ──────────────────────────────
                          TextButton.icon(
                            onPressed: () => Navigator.of(context)
                                .pushNamed(AppRoutes.adminLogin),
                            icon: const Icon(LucideIcons.shieldCheck,
                                size: 16, color: Colors.black45),
                            label: const Text(
                              'Admin? Login here',
                              style: TextStyle(
                                color: Colors.black54,
                                fontSize: 14,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          const Spacer(),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
 
  Widget _buildVideoWidget() {
    final double size = MediaQuery.of(context).size.width * 0.85;
    final vc = _videoController;
    final bool ready = vc != null && vc.value.isInitialized;
 
    return Center(
      key: _videoKey,
      child: SizedBox(
        width: size,
        height: size,
        child: _videoError
            // Graceful fallback if video fails on this platform
            ? const SizedBox.shrink()
            : Container(
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.05),
                  borderRadius: BorderRadius.circular(32),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.primary.withValues(alpha: 0.18),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                  ],
                ),
                child: ready
                    ? FittedBox(
                        fit: BoxFit.cover,
                        child: SizedBox(
                          width: vc.value.size.width,
                          height: vc.value.size.height,
                          child: VideoPlayer(vc),
                        ),
                      )
                    : const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                          strokeWidth: 2,
                        ),
                      ),
              ),
      ),
    );
  }
}