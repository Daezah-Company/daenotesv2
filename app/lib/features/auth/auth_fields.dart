import 'package:flutter/material.dart';

import '../../core/ds.dart';
import '../../data/auth/auth_repository.dart';

/// Which credential an input (or a server `errors` key) refers to.
enum AuthFieldKind { name, email, password }

/// One labelled credential input.
///
/// Label, hint and error all live inside the [InputDecorator] so a screen
/// reader announces `label, edit box` and the failure is *spoken text*, not a
/// colour change (contract §6 keeps colour for relation/status only). The
/// floating label is the mono eyebrow voice, so form chrome reads like every
/// other DaeNotes surface without a second, unlabelled copy of the text.
class AuthField extends StatelessWidget {
  const AuthField({
    super.key,
    required this.kind,
    required this.label,
    required this.controller,
    this.hint,
    this.error,
    this.obscure = false,
    this.revealTooltip,
    this.onToggleReveal,
    this.keyboardType,
    this.textInputAction = TextInputAction.next,
    this.autofillHints,
    this.onSubmitted,
  });

  final AuthFieldKind kind;
  final String label;
  final TextEditingController controller;
  final String? hint;

  /// Explained in text under the field; wins over any earlier client message.
  final String? error;
  final bool obscure;
  final String? revealTooltip;
  final VoidCallback? onToggleReveal;
  final TextInputType? keyboardType;
  final TextInputAction textInputAction;
  final Iterable<String>? autofillHints;
  final VoidCallback? onSubmitted;

  /// Stable hook for integration tests and focus order.
  static Key inputKey(AuthFieldKind kind) =>
      ValueKey('auth-field-${kind.name}');

  @override
  Widget build(BuildContext context) {
    final dae = context.dae;
    return Padding(
      padding: const EdgeInsets.only(bottom: Ds.s4),
      child: TextField(
        key: inputKey(kind),
        controller: controller,
        obscureText: obscure,
        keyboardType: keyboardType,
        textInputAction: textInputAction,
        autofillHints: autofillHints,
        autocorrect: false,
        enableSuggestions: !obscure,
        maxLines: 1,
        minLines: 1,
        textCapitalization: kind == AuthFieldKind.name
            ? TextCapitalization.words
            : TextCapitalization.none,
        onSubmitted: onSubmitted == null ? null : (_) => onSubmitted!(),
        style: DsType.body(color: dae.onSurface),
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          errorText: error,
          errorMaxLines: 3,
          counterText: '',
          isDense: true,
          labelStyle: DsType.eyebrow(color: dae.onSurfaceSecondary),
          floatingLabelStyle: DsType.eyebrow(
            color: error == null ? dae.onSurfaceSecondary : Ds.threadRose,
            weight: FontWeight.w600,
          ),
          hintStyle: DsType.caption(color: dae.onSurfaceSecondary),
          errorStyle: DsType.body(
            color: dae.onSurface,
            weight: FontWeight.w500,
          ),
          suffixIcon: onToggleReveal == null
              ? null
              : IconButton(
                  tooltip: revealTooltip,
                  iconSize: 18,
                  onPressed: onToggleReveal,
                  icon: Icon(
                    obscure
                        ? Icons.visibility_outlined
                        : Icons.visibility_off_outlined,
                    color: dae.onSurfaceSecondary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// A wire failure flattened into what this form can render: per-field messages
/// first, and one banner only for what cannot be placed on a field.
@immutable
class AuthFormFailure {
  const AuthFormFailure({this.message, this.fieldErrors = const {}});

  final String? message;
  final Map<AuthFieldKind, String> fieldErrors;

  bool get hasMessage => message != null && message!.isNotEmpty;
}

/// Maps [ApiError.fieldErrors] onto fields. Unknown keys (and the bare
/// `message` when there are no field errors at all) fall back to the banner,
/// so nothing the server says is ever lost.
AuthFormFailure authFailureFrom(Object error) {
  if (error is! ApiError) {
    return AuthFormFailure(message: AuthRepository.describeError(error));
  }
  if (error.fieldErrors.isEmpty) return AuthFormFailure(message: error.message);

  final mapped = <AuthFieldKind, String>{};
  final unplaced = <String>[];
  for (final entry in error.fieldErrors.entries) {
    final text = entry.value
        .map((m) => m.trim())
        .where((m) => m.isNotEmpty)
        .join(' ');
    if (text.isEmpty) continue;
    final kind = _kindFor(entry.key);
    if (kind == null) {
      unplaced.add(text);
    } else {
      mapped.putIfAbsent(kind, () => text);
    }
  }
  if (mapped.isEmpty) {
    return AuthFormFailure(
      message: unplaced.isEmpty ? error.message : unplaced.join(' · '),
    );
  }
  return AuthFormFailure(
    message: unplaced.isEmpty ? null : unplaced.join(' · '),
    fieldErrors: mapped,
  );
}

AuthFieldKind? _kindFor(String key) {
  final k = key.trim().toLowerCase();
  if (k == 'name' || k == 'nama') return AuthFieldKind.name;
  if (k == 'email') return AuthFieldKind.email;
  if (k == 'password' || k.startsWith('password_')) {
    return AuthFieldKind.password;
  }
  return null;
}
