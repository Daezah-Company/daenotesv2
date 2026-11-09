import 'dart:async';

import 'package:daenotes/app_router.dart';
import 'package:daenotes/data/api/api_client.dart';
import 'package:daenotes/data/api/token_storage.dart';
import 'package:daenotes/data/auth/auth_repository.dart';
import 'package:daenotes/data/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _PendingRestoreRepository extends AuthRepository {
  _PendingRestoreRepository()
    : super(ApiClient(tokens: TokenStorage()), TokenStorage());

  final restoreGate = Completer<AuthSession?>();

  @override
  Future<AuthSession?> restore() => restoreGate.future;
}

void main() {
  testWidgets('protected routes wait behind session check before dashboard', (
    tester,
  ) async {
    final repository = _PendingRestoreRepository();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repository)],
        child: Consumer(
          builder: (context, ref, _) =>
              MaterialApp.router(routerConfig: ref.watch(appRouterProvider)),
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MEMERIKSA SESI'), findsOneWidget);
    expect(find.text('Beranda'), findsNothing);

    repository.restoreGate.complete(null);
    await tester.pumpAndSettle();

    expect(find.text('Masuk kembali'), findsOneWidget);
    expect(find.text('Beranda'), findsNothing);
  });
}
