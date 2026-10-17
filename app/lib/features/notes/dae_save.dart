import 'dart:async';

/// Coalesces rapid edits into one trailing write so the editor autosaves
/// without a blocking "Save" button (contract §5 UX: capture should flow).
class DaeDebouncer {
  DaeDebouncer({this.delay = const Duration(milliseconds: 650)});

  final Duration delay;
  Timer? _timer;
  void Function()? _pending;

  /// Schedule [action], replacing any pending one.
  void schedule(void Function() action) {
    _pending = action;
    _timer?.cancel();
    _timer = Timer(delay, _run);
  }

  /// Run any pending action immediately (used on dispose / blur).
  void flush() {
    _timer?.cancel();
    _run();
  }

  void cancel() {
    _timer?.cancel();
    _pending = null;
  }

  bool get hasPending => _timer?.isActive ?? false;

  void _run() {
    final action = _pending;
    _pending = null;
    _timer = null;
    action?.call();
  }
}
