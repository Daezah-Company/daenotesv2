import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/ds.dart';
import '../../data/providers.dart';
import 'auth_fields.dart';

/// Which credential set the form asks for.
enum AuthMode { login, register }

/// Route surface for `/login`.
///
/// It never navigates: `app_router.dart` redirects to `/inbox` as soon as
/// `authControllerProvider` holds a session. This screen only calls the
/// notifier and renders whatever comes back.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AuthScreen(initialMode: AuthMode.login);
}

/// Route surface for `/register`. Same contract as [LoginScreen].
class RegisterScreen extends StatelessWidget {
  const RegisterScreen({super.key});

  @override
  Widget build(BuildContext context) =>
      const AuthScreen(initialMode: AuthMode.register);
}

/// One screen, two modes; the mode switch is local state so the screen stays
/// independent of the router and never triggers a navigation itself.
class AuthScreen extends ConsumerStatefulWidget {
  const AuthScreen({super.key, this.initialMode = AuthMode.login});

  final AuthMode initialMode;

  @override
  ConsumerState<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends ConsumerState<AuthScreen> {
  static const double _formWidth = 420;

  late AuthMode _mode = widget.initialMode;
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _localErrors = <AuthFieldKind, String>{};
  bool _reveal = false;

  /// The wire error the user has already been shown *and* started editing
  /// away. Reset on every submit so a repeat failure is announced again.
  Object? _acknowledgedError;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  /// Typing away a wire failure dismisses it; the next submit re-arms it so a
  /// repeated failure is announced again.
  void _onEditing(AuthFieldKind kind) {
    final error = ref.read(authControllerProvider).error;
    final acknowledgesWireError =
        error != null && !identical(error, _acknowledgedError);
    final clearsLocalError = _localErrors.containsKey(kind);
    if (!acknowledgesWireError && !clearsLocalError) return;
    setState(() {
      if (acknowledgesWireError) _acknowledgedError = error;
      _localErrors.remove(kind);
    });
  }

  void _switchMode() {
    setState(() {
      _mode = _mode == AuthMode.login ? AuthMode.register : AuthMode.login;
      _localErrors.clear();
      _reveal = false;
      _acknowledgedError = null;
    });
  }

  Map<AuthFieldKind, String> _validate() {
    final errors = <AuthFieldKind, String>{};
    if (_mode == AuthMode.register && _name.text.trim().isEmpty) {
      errors[AuthFieldKind.name] = 'Isi nama Anda.';
    }
    final email = _email.text.trim();
    if (email.isEmpty) {
      errors[AuthFieldKind.email] = 'Isi email Anda.';
    } else if (!email.contains('@')) {
      errors[AuthFieldKind.email] = 'Email memakai pola nama@surel.com.';
    }
    final password = _password.text;
    if (password.isEmpty) {
      errors[AuthFieldKind.password] = 'Isi kata sandi.';
    } else if (_mode == AuthMode.register && password.length < 8) {
      errors[AuthFieldKind.password] = 'Kata sandi minimal 8 karakter.';
    }
    return errors;
  }

  Future<void> _submit() async {
    final errors = _validate();
    if (errors.isNotEmpty) {
      setState(
        () => _localErrors
          ..clear()
          ..addAll(errors),
      );
      return;
    }
    setState(() {
      _localErrors.clear();
      _acknowledgedError = null;
    });

    final notifier = ref.read(authControllerProvider.notifier);
    final email = _email.text.trim();
    if (_mode == AuthMode.login) {
      await notifier.login(email, _password.text);
    } else {
      await notifier.register(_name.text.trim(), email, _password.text);
    }
    // Success puts a session in authControllerProvider; the router's redirect
    // moves the user to /inbox. Nothing to navigate from here.
  }

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    final auth = ref.watch(authControllerProvider);
    final busy = auth.isLoading || auth.isRefreshing;
    final wireError = auth.error;
    final failure =
        wireError == null || identical(wireError, _acknowledgedError)
        ? null
        : authFailureFrom(wireError);

    final errors = <AuthFieldKind, String>{
      ..._localErrors,
      if (failure != null) ...failure.fieldErrors,
    };

    final registering = _mode == AuthMode.register;

    return Scaffold(
      backgroundColor: dae.background,
      body: SafeArea(
        child: Align(
          alignment: Alignment.topCenter,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(Ds.s5, Ds.s8, Ds.s5, Ds.s8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: _formWidth),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const AuthMasthead(),
                  const SizedBox(height: Ds.s6),
                  DsText.displaySm(registering ? 'Buat akun' : 'Masuk kembali'),
                  const SizedBox(height: Ds.s2),
                  Text(
                    registering
                        ? 'Satu akun untuk catatan dan tugas. Item Anda mulai '
                              'saling terhubung sejak benang pertama.'
                        : 'Lanjutkan benang Anda. Semua item tetap terbuka di '
                              'perangkat ini, dengan atau tanpa jaringan.',
                    style: DsType.body(color: dae.onSurfaceSecondary),
                  ),
                  const SizedBox(height: Ds.s5),
                  if (failure != null && failure.hasMessage)
                    AuthFailureBanner(message: failure.message!),
                  if (registering)
                    AuthField(
                      kind: AuthFieldKind.name,
                      label: 'Nama',
                      hint: 'nama yang tampil di akun Anda',
                      controller: _name,
                      error: errors[AuthFieldKind.name],
                      onChanged: (_) => _onEditing(AuthFieldKind.name),
                      keyboardType: TextInputType.name,
                      autofillHints: const [AutofillHints.name],
                    ),
                  AuthField(
                    kind: AuthFieldKind.email,
                    label: 'Email',
                    hint: 'anda@surel.com',
                    controller: _email,
                    error: errors[AuthFieldKind.email],
                    onChanged: (_) => _onEditing(AuthFieldKind.email),
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                  AuthField(
                    kind: AuthFieldKind.password,
                    label: 'Kata sandi',
                    hint: registering
                        ? 'minimal 8 karakter'
                        : 'kata sandi akun Anda',
                    controller: _password,
                    error: errors[AuthFieldKind.password],
                    onChanged: (_) => _onEditing(AuthFieldKind.password),
                    obscure: !_reveal,
                    revealTooltip: _reveal
                        ? 'Sembunyikan sandi'
                        : 'Tampilkan sandi',
                    onToggleReveal: () => setState(() => _reveal = !_reveal),
                    keyboardType: TextInputType.visiblePassword,
                    textInputAction: TextInputAction.done,
                    autofillHints: registering
                        ? const [AutofillHints.newPassword]
                        : const [AutofillHints.password],
                    onSubmitted: () => _submit(),
                  ),
                  const SizedBox(height: Ds.s2),
                  Semantics(
                    button: true,
                    enabled: !busy,
                    child: DsButton.filled(
                      label: busy
                          ? 'Memproses'
                          : registering
                          ? 'Daftar'
                          : 'Masuk',
                      loading: busy,
                      expanded: true,
                      onPressed: busy ? null : _submit,
                    ),
                  ),
                  const SizedBox(height: Ds.s4),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      DsText.body(
                        registering ? 'Sudah punya akun?' : 'Belum punya akun?',
                      ),
                      const SizedBox(width: Ds.s2),
                      Semantics(
                        button: true,
                        enabled: !busy,
                        child: DsButton.ghost(
                          label: registering ? 'Masuk' : 'Daftar',
                          onPressed: busy ? null : _switchMode,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: Ds.s5),
                  DsText.caption(
                    registering
                        ? 'BENANG PERTAMA · SINKRONISASI JALAN DI LATAR'
                        : 'SINKRONISASI JALAN DI LATAR',
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

/// Wordmark plus the signature: one thread drawn down the left of the name,
/// as the mark of things being connected. Monochrome on purpose — on this
/// surface nothing is linked yet, so no accent hue may be worn as
/// decoration (contract §6). [ThreadRail] collapses the draw under
/// reduce-motion, so this is the only choreography on the screen.
class AuthMasthead extends StatelessWidget {
  const AuthMasthead({super.key});

  /// Height of the original DaeNotes wordmark beside the signature rail.
  static const double markHeight = 64;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Semantics(
      header: true,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ExcludeSemantics(
            child: SizedBox(
              height: markHeight,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [ThreadRail(thread: dae.onSurface, drawOn: true)],
              ),
            ),
          ),
          const SizedBox(width: Ds.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Semantics(
                  label: 'DaeNotes',
                  image: true,
                  child: ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      dae.onSurface,
                      BlendMode.srcIn,
                    ),
                    child: Image.asset(
                      'assets/branding/daenotes_wordmark.png',
                      width: 94,
                      height: markHeight,
                      alignment: Alignment.centerLeft,
                      fit: BoxFit.contain,
                      excludeFromSemantics: true,
                    ),
                  ),
                ),
                const SizedBox(height: Ds.s1),
                const DsEyebrow('catatan & tugas yang terhubung'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Wire failure the form could not attach to one field. The monochrome rail reads as
/// a status; the words carry the meaning, and the live region re-announces it
/// for screen readers.
class AuthFailureBanner extends StatelessWidget {
  const AuthFailureBanner({super.key, required this.message});

  /// Key of the live region itself — the announced surface tests can assert on.
  static const Key failureKey = ValueKey('auth-failure');

  final String message;

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s4),
      child: Semantics(
        key: failureKey,
        liveRegion: true,
        child: DsCard(
          thread: Ds.threadRose,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const DsEyebrow('Perlu diperiksa'),
              const SizedBox(height: Ds.s2),
              Text(message, style: DsType.body(color: dae.onSurface)),
            ],
          ),
        ),
      ),
    );
  }
}
