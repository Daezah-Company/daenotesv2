import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'app_shell.dart';
import 'core/ds.dart';
import 'data/providers.dart';
import 'features/auth/auth_screen.dart';
import 'features/graph/graph_screen.dart';
import 'features/notes/dae_inbox.dart';
import 'features/notes/note_editor.dart';
import 'features/reminders/reminders_screen.dart';
import 'features/todos/todo_editor.dart';

/// Canonical route names. Feature agents register subroutes against these —
/// detail screens go under [noteDetail]/[todoDetail], never new top levels.
abstract final class DaeRouteNames {
  static const inbox = 'inbox';
  static const graph = 'graph';
  static const reminders = 'reminders';
  static const noteDetail = 'noteDetail';
  static const todoDetail = 'todoDetail';
  static const login = 'login';
  static const register = 'register';

  static String notePath(String uuid) => '/note/$uuid';
  static String todoPath(String uuid) => '/todo/$uuid';
}

/// The guarded router. Watching [authControllerProvider] rebuilds it whenever
/// the session changes, so the redirect below always sees a fresh session.
final appRouterProvider = Provider<GoRouter>((ref) {
  final auth = ref.watch(authControllerProvider);
  final signedIn = auth.value != null;
  final deciding = auth.isLoading || auth.isRefreshing;

  return GoRouter(
    initialLocation: '/inbox',
    redirect: (context, state) {
      final loc = state.matchedLocation;
      final onAuthScreen = loc == '/login' || loc == '/register';
      if (deciding) return null; // stay put while the session is rehydrated
      if (!signedIn && !onAuthScreen) return '/login';
      if (signedIn && onAuthScreen) return '/inbox';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        name: DaeRouteNames.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: '/register',
        name: DaeRouteNames.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, shell) => AppShell(navigationShell: shell),
        branches: [
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/inbox',
                name: DaeRouteNames.inbox,
                builder: (context, state) => const DaeInboxScreen(),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/graph',
                name: DaeRouteNames.graph,
                // `/graph?focus=<uuid>` centres that node (deep link from any
                // other surface).
                builder: (context, state) => GraphScreen(
                  onOpenItem: (type, uuid) => context.push(
                    type == DaeItemType.note
                        ? DaeRouteNames.notePath(uuid)
                        : DaeRouteNames.todoPath(uuid),
                  ),
                  focusUuid: state.uri.queryParameters['focus'],
                ),
              ),
            ],
          ),
          StatefulShellBranch(
            routes: [
              GoRoute(
                path: '/reminders',
                name: DaeRouteNames.reminders,
                builder: (context, state) => const RemindersScreen(),
              ),
            ],
          ),
        ],
      ),
      GoRoute(
        path: '/note/:uuid',
        name: DaeRouteNames.noteDetail,
        builder: (context, state) =>
            NoteDetailScreen(uuid: state.pathParameters['uuid']!),
      ),
      GoRoute(
        path: '/todo/:uuid',
        name: DaeRouteNames.todoDetail,
        builder: (context, state) =>
            TodoDetailScreen(uuid: state.pathParameters['uuid']!),
      ),
    ],
    errorBuilder: (context, state) => Scaffold(
      body: Center(child: DsText.caption('Rute tidak dikenal: ${state.uri}')),
    ),
  );
});
