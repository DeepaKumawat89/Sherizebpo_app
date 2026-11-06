import 'package:flutter/material.dart';
import 'package:lucide_icons/lucide_icons.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/app_update_service.dart';

class AppUpdateGate extends StatefulWidget {
  const AppUpdateGate(
      {super.key, required this.child, this.service, this.openStore});

  final Widget child;
  final AppUpdateService? service;
  final Future<bool> Function()? openStore;

  @override
  State<AppUpdateGate> createState() => _AppUpdateGateState();
}

class _AppUpdateGateState extends State<AppUpdateGate>
    with WidgetsBindingObserver {
  late final AppUpdateService _service;
  bool _openingStore = false;
  String _storeError = '';

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? AppUpdateService();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _service.init();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _service.refresh();
  }

  Future<void> _openStore() async {
    setState(() {
      _openingStore = true;
      _storeError = '';
    });
    try {
      final opened = await (widget.openStore?.call() ??
          launchUrl(
            Uri.https('play.google.com', '/store/apps/details',
                {'id': 'in.sherize.app'}),
            mode: LaunchMode.externalApplication,
          ));
      if (!opened) throw StateError('Store unavailable');
    } catch (_) {
      if (mounted) {
        setState(() =>
            _storeError = 'Could not open Google Play. Please try again.');
      }
    } finally {
      if (mounted) setState(() => _openingStore = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (widget.service == null) _service.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _service,
        builder: (context, _) {
          final requirement = _service.requirement;
          final blocked =
              !_service.ready || requirement != AppUpdateRequirement.none;
          final mandatory = requirement == AppUpdateRequirement.required;
          return Stack(fit: StackFit.expand, children: [
            ExcludeFocus(
                excluding: blocked,
                child: ExcludeSemantics(
                    excluding: blocked,
                    child:
                        IgnorePointer(ignoring: blocked, child: widget.child))),
            if (blocked)
              Scaffold(
                body: SafeArea(
                    child: Center(
                        child: SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 400),
                    child: !_service.ready
                        ? const Center(child: CircularProgressIndicator())
                        : Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                                Image.asset('assets/images/sherize_logo.png',
                                    height: 72, semanticLabel: 'Sherize'),
                                const SizedBox(height: 32),
                                Text(
                                    mandatory
                                        ? 'Update required'
                                        : 'Update available',
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .headlineSmall),
                                const SizedBox(height: 16),
                                Text(
                                    _service.message.isNotEmpty
                                        ? _service.message
                                        : mandatory
                                            ? 'Please update Sherize to continue.'
                                            : 'A newer version of Sherize is ready.',
                                    textAlign: TextAlign.center),
                                const SizedBox(height: 24),
                                FilledButton.icon(
                                    onPressed:
                                        _openingStore ? null : _openStore,
                                    icon: const Icon(LucideIcons.download,
                                        size: 20),
                                    label: Text(_openingStore
                                        ? 'Opening Google Play...'
                                        : 'Update now')),
                                if (!mandatory)
                                  TextButton(
                                      onPressed: _service.dismissOptional,
                                      child: const Text('Later')),
                                TextButton.icon(
                                    onPressed: _service.checking
                                        ? null
                                        : _service.refresh,
                                    icon: const Icon(LucideIcons.refreshCw,
                                        size: 18),
                                    label: Text(_service.checking
                                        ? 'Checking...'
                                        : 'Check again')),
                                if (_storeError.isNotEmpty ||
                                    _service.error.isNotEmpty)
                                  Text(
                                      _storeError.isNotEmpty
                                          ? _storeError
                                          : _service.error,
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error)),
                              ]),
                  ),
                ))),
              ),
          ]);
        },
      );
}
