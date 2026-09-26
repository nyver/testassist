import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/app_failure.dart';
import '../../../shared/failure_messages.dart';
import '../../../shared/l10n.dart';
import '../domain/server_service.dart';
import 'trust_dialog.dart';

/// First-run screen: address, name and token of the user's server.
class ServerSetupScreen extends ConsumerStatefulWidget {
  const ServerSetupScreen({super.key});

  @override
  ConsumerState<ServerSetupScreen> createState() => _ServerSetupScreenState();
}

class _ServerSetupScreenState extends ConsumerState<ServerSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _url = TextEditingController();
  final _name = TextEditingController();
  final _token = TextEditingController();

  bool _busy = false;
  bool _showToken = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    _name.dispose();
    _token.dispose();
    super.dispose();
  }

  String? _validateUrl(String? value) {
    final l10n = context.l10n;
    final parsed = parseServerUrl(value ?? '');
    switch (parsed.problem) {
      case null:
        return null;
      case ServerUrlProblem.notHttps:
        return l10n.setupUrlNotHttps;
      case ServerUrlProblem.invalid:
        return l10n.setupUrlInvalid;
    }
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    final url = parseServerUrl(_url.text).url;
    if (url == null) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    final outcome = await ref
        .read(serverServiceProvider)
        .connect(
          baseUrl: url,
          name: _name.text,
          token: _token.text.trim(),
          confirmTrust: (fingerprint) async {
            if (!mounted) return false;
            return showTrustDialog(
              context,
              url: url.toString(),
              fingerprint: fingerprint,
            );
          },
        );
    if (!mounted) return;

    switch (outcome) {
      case SetupSuccess():
        context.go('/');
      case SetupCancelled():
        setState(() => _busy = false);
      case SetupError(:final failure):
        setState(() {
          _busy = false;
          _error = _messageFor(failure);
        });
    }
  }

  String _messageFor(AppFailure failure) {
    final l10n = context.l10n;
    if (failure is ApiFailure && failure.code == ApiErrorCodes.unauthorized) {
      return l10n.setupTokenInvalid;
    }
    if (failure is ServerMismatchFailure) return l10n.setupServerMismatch;
    return failureMessage(l10n, failure);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Scaffold(
      appBar: AppBar(title: Text(l10n.setupTitle)),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Form(
              key: _formKey,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  Text(l10n.setupIntro),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('setup-url'),
                    controller: _url,
                    enabled: !_busy,
                    keyboardType: TextInputType.url,
                    autocorrect: false,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.setupUrlLabel,
                      hintText: l10n.setupUrlHint,
                      border: const OutlineInputBorder(),
                    ),
                    validator: _validateUrl,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('setup-name'),
                    controller: _name,
                    enabled: !_busy,
                    textInputAction: TextInputAction.next,
                    decoration: InputDecoration(
                      labelText: l10n.setupNameLabel,
                      border: const OutlineInputBorder(),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l10n.setupNameRequired
                        : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    key: const Key('setup-token'),
                    controller: _token,
                    enabled: !_busy,
                    obscureText: !_showToken,
                    autocorrect: false,
                    enableSuggestions: false,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _submit(),
                    decoration: InputDecoration(
                      labelText: l10n.setupTokenLabel,
                      border: const OutlineInputBorder(),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _showToken ? Icons.visibility_off : Icons.visibility,
                        ),
                        onPressed: () =>
                            setState(() => _showToken = !_showToken),
                      ),
                    ),
                    validator: (value) => (value ?? '').trim().isEmpty
                        ? l10n.setupTokenRequired
                        : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    Text(
                      _error!,
                      key: const Key('setup-error'),
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    key: const Key('setup-connect'),
                    onPressed: _busy ? null : _submit,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                    ),
                    child: _busy
                        ? Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(l10n.setupConnecting),
                            ],
                          )
                        : Text(l10n.setupConnect),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
