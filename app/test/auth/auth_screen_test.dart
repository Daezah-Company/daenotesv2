import 'dart:async';

import 'package:daenotes/core/ds.dart';
import 'package:daenotes/data/api/api_client.dart';
import 'package:daenotes/data/api/token_storage.dart';
import 'package:daenotes/data/auth/auth_repository.dart';
import 'package:daenotes/data/providers.dart';
import 'package:daenotes/features/auth/auth_fields.dart';
import 'package:daenotes/features/auth/auth_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

/// Stands in for the wire: records what the screen asked for and answers with
/// whatever the test needs. `restore`, `login` and `register` are all
/// overridden, so [TokenStorage] (flutter_secure_storage) is never touched and
/// no socket is opened.
class _FakeAuthRepository extends AuthRepository {
  _FakeAuthRepository()
    : super(ApiClient(tokens: TokenStorage()), TokenStorage());

  final calls = <String>[];
  Object? failure;
  Completer<AuthSession>? gate;
  final session = const AuthSession(
    token: 'tok-1',
    userId: 7,
    name: 'Rina',
    email: 'rina@surel.com',
  );

  @override
  Future<AuthSession?> restore() async => null;

  @override
  Future<AuthSession> login(String email, String password) =>
      _call('login', null, email, password);

  @override
  Future<AuthSession> register(String name, String email, String password) =>
      _call('register', name, email, password);

  Future<AuthSession> _call(
    String op,
    String? name,
    String email,
    String password,
  ) {
    calls.add('$op:$name:$email:$password');
    final f = failure;
    if (f != null) return Future.error(f);
    final g = gate?.future;
    return g ?? Future.value(session);
  }
}

void main() {
  late _FakeAuthRepository repo;

  setUp(() => repo = _FakeAuthRepository());

  Widget harness({required Widget screen, bool reduceMotion = false}) {
    Widget home = screen;
    if (reduceMotion) {
      // Inside MaterialApp's own MediaQuery so size/textScale survive and only
      // disableAnimations flips — the switch ThreadRail listens to.
      home = Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: true),
          child: screen,
        ),
      );
    }
    return ProviderScope(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(theme: DsTheme.dark(), home: home),
    );
  }

  Future<void> open(
    WidgetTester tester,
    Widget screen, {
    bool reduceMotion = false,
  }) async {
    await tester.pumpWidget(
      harness(screen: screen, reduceMotion: reduceMotion),
    );
    await tester.pumpAndSettle();
  }

  Finder field(AuthFieldKind kind) => find.byKey(AuthField.inputKey(kind));

  Future<void> enter(WidgetTester tester, AuthFieldKind kind, String text) =>
      tester.enterText(field(kind), text);

  Future<void> type(
    WidgetTester tester, {
    String? name,
    String? email,
    String? password,
  }) async {
    if (name != null) await enter(tester, AuthFieldKind.name, name);
    if (email != null) await enter(tester, AuthFieldKind.email, email);
    if (password != null) await enter(tester, AuthFieldKind.password, password);
    await tester.pump();
  }

  AuthSession? sessionOf(WidgetTester tester) {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(AuthScreen)),
      listen: false,
    );
    return container.read(authControllerProvider).value;
  }

  group('validasi sisi klien', () {
    testWidgets(
      'submit kosong menahan panggilan jaringan dan menjelaskan per field',
      (tester) async {
        await open(tester, const LoginScreen());
        await tester.tap(find.text('MASUK'));
        await tester.pump();

        expect(repo.calls, isEmpty, reason: 'nothing may reach the wire');
        expect(find.text('Isi email Anda.'), findsOneWidget);
        expect(find.text('Isi kata sandi.'), findsOneWidget);
      },
    );

    testWidgets('email tanpa @ ditolak dengan contoh konkret', (tester) async {
      await open(tester, const LoginScreen());
      await type(tester, email: 'rina', password: 'rahasia12');
      await tester.tap(find.text('MASUK'));
      await tester.pump();

      expect(repo.calls, isEmpty);
      expect(find.text('Email memakai pola nama@surel.com.'), findsOneWidget);
    });

    testWidgets('register menuntut nama dan sandi 8 karakter', (tester) async {
      await open(tester, const RegisterScreen());
      await type(tester, email: 'rina@surel.com', password: 'singkat');
      await tester.tap(find.text('DAFTAR'));
      await tester.pump();

      expect(repo.calls, isEmpty);
      expect(find.text('Isi nama Anda.'), findsOneWidget);
      expect(find.text('Kata sandi minimal 8 karakter.'), findsOneWidget);
    });

    testWidgets('kesalahan per field hilang saat field itu diperbaiki', (
      tester,
    ) async {
      await open(tester, const RegisterScreen());
      await tester.tap(find.text('DAFTAR'));
      await tester.pump();

      await enter(tester, AuthFieldKind.email, 'rina@surel.com');
      await tester.pump();

      expect(find.text('Isi email Anda.'), findsNothing);
      expect(find.text('Isi nama Anda.'), findsOneWidget);
      expect(find.text('Isi kata sandi.'), findsOneWidget);
    });
  });

  group('kirim', () {
    testWidgets(
      'login mengirim kredensial dan menyerahkan navigasi ke router',
      (tester) async {
        await open(tester, const LoginScreen());
        await type(tester, email: 'rina@surel.com', password: 'rahasia12');
        await tester.tap(find.text('MASUK'));
        await tester.pumpAndSettle();

        expect(repo.calls, ['login:null:rina@surel.com:rahasia12']);
        expect(sessionOf(tester)?.token, 'tok-1');
        // No GoRouter in the harness: a self-navigation would have thrown. The
        // screen simply stays put until the redirect swaps it for /inbox.
        expect(find.byType(LoginScreen), findsOneWidget);
      },
    );

    testWidgets('register mengirim nama, email, dan sandi', (tester) async {
      await open(tester, const RegisterScreen());
      await type(
        tester,
        name: 'Rina',
        email: 'rina@surel.com',
        password: 'rahasia12',
      );
      await tester.tap(find.text('DAFTAR'));
      await tester.pumpAndSettle();

      expect(repo.calls, ['register:Rina:rina@surel.com:rahasia12']);
      expect(sessionOf(tester)?.email, 'rina@surel.com');
    });

    testWidgets('tombol mati selama menunggu dan tidak mengirim dua kali', (
      tester,
    ) async {
      final gate = Completer<AuthSession>();
      repo.gate = gate;

      await open(tester, const LoginScreen());
      await type(tester, email: 'rina@surel.com', password: 'rahasia12');
      await tester.tap(find.text('MASUK'));
      await tester.pump();

      final busy = find.text('MEMPROSES');
      expect(busy, findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      final button = tester.widget<DsButton>(
        find.ancestor(of: busy, matching: find.byType(DsButton)).first,
      );
      expect(button.onPressed, isNull);

      await tester.tap(busy, warnIfMissed: false);
      await tester.pump();
      expect(repo.calls, hasLength(1));

      gate.complete(repo.session);
      await tester.pumpAndSettle();
      expect(sessionOf(tester)?.name, 'Rina');
      expect(repo.calls, hasLength(1));
    });
  });

  group('galat server', () {
    testWidgets(
      'fieldErrors tampil di field yang benar, bukan sebagai pesan umum',
      (tester) async {
        repo.failure = ApiError(
          'The given data was invalid.',
          statusCode: 422,
          fieldErrors: const {
            'email': ['Email sudah dipakai.'],
          },
        );

        await open(tester, const RegisterScreen());
        await type(
          tester,
          name: 'Rina',
          email: 'rina@surel.com',
          password: 'rahasia12',
        );
        await tester.tap(find.text('DAFTAR'));
        await tester.pumpAndSettle();

        expect(find.text('Email sudah dipakai.'), findsOneWidget);
        expect(
          find.text('The given data was invalid.'),
          findsNothing,
          reason: 'no generic banner when the message belongs to a field',
        );
        final decorator = tester.widget<InputDecorator>(
          find
              .descendant(
                of: field(AuthFieldKind.email),
                matching: find.byType(InputDecorator),
              )
              .first,
        );
        expect(decorator.decoration.errorText, 'Email sudah dipakai.');
      },
    );

    testWidgets(
      'tanpa fieldErrors: pesan ditampilkan sebagai teks dan live region',
      (tester) async {
        repo.failure = ApiError(
          'Kombinasi email dan kata sandi salah.',
          statusCode: 401,
        );

        await open(tester, const LoginScreen());
        await type(tester, email: 'rina@surel.com', password: 'salah');
        await tester.tap(find.text('MASUK'));
        await tester.pumpAndSettle();

        expect(
          find.descendant(
            of: find.byKey(AuthFailureBanner.failureKey),
            matching: find.text('Kombinasi email dan kata sandi salah.'),
          ),
          findsOneWidget,
        );
        final live = tester.widget<Semantics>(
          find.byKey(AuthFailureBanner.failureKey),
        );
        expect(live.properties.liveRegion, isTrue);
      },
    );

    testWidgets(
      'memperbaiki isian menyembunyikan galat, dan kegagalan ulang tampil lagi',
      (tester) async {
        repo.failure = ApiError('Server sedang sibuk, coba lagi.');

        await open(tester, const LoginScreen());
        await type(tester, email: 'rina@surel.com', password: 'rahasia12');
        await tester.tap(find.text('MASUK'));
        await tester.pumpAndSettle();
        expect(find.text('Server sedang sibuk, coba lagi.'), findsOneWidget);

        await tester.enterText(
          field(AuthFieldKind.email),
          'rina.baru@surel.com',
        );
        await tester.pump();
        expect(find.text('Server sedang sibuk, coba lagi.'), findsNothing);

        await tester.tap(find.text('MASUK'));
        await tester.pumpAndSettle();
        expect(
          find.text('Server sedang sibuk, coba lagi.'),
          findsOneWidget,
          reason: 'a repeated failure must be announced again',
        );
      },
    );
  });

  group('aksesibilitas dan mode', () {
    testWidgets(
      'setiap field punya label yang terlihat dan terhubung ke inputnya',
      (tester) async {
        await open(tester, const RegisterScreen());

        for (final (label, kind) in const [
          ('Nama', AuthFieldKind.name),
          ('Email', AuthFieldKind.email),
          ('Kata sandi', AuthFieldKind.password),
        ]) {
          final decorator = tester.widget<InputDecorator>(
            find
                .descendant(
                  of: field(kind),
                  matching: find.byType(InputDecorator),
                )
                .first,
          );
          expect(decorator.decoration.labelText, label);
          expect(find.text(label), findsOneWidget);
        }
      },
    );

    testWidgets('kata sandi bisa ditampilkan dan disembunyikan lagi', (
      tester,
    ) async {
      await open(tester, const LoginScreen());

      TextField input() =>
          tester.widget<TextField>(field(AuthFieldKind.password));
      expect(input().obscureText, isTrue);

      await tester.tap(find.byTooltip('Tampilkan sandi'));
      await tester.pump();
      expect(input().obscureText, isFalse);

      await tester.tap(find.byTooltip('Sembunyikan sandi'));
      await tester.pump();
      expect(input().obscureText, isTrue);
    });

    testWidgets('pergantian mode hanya mengubah isian, tanpa navigasi', (
      tester,
    ) async {
      await open(tester, const RegisterScreen());
      expect(field(AuthFieldKind.name), findsOneWidget);

      await tester.tap(find.text('MASUK'));
      await tester.pumpAndSettle();

      expect(field(AuthFieldKind.name), findsNothing);
      expect(find.text('Masuk kembali'), findsOneWidget);
      expect(find.text('Sudah punya akun?'), findsNothing);
      // Still the same route surface — the screen switched mode by itself,
      // it did not navigate.
      expect(find.byType(RegisterScreen), findsOneWidget);
    });
  });

  group('momen koreografi', () {
    testWidgets('rail wordmark digambar bertahap lalu penuh', (tester) async {
      await tester.pumpWidget(harness(screen: const LoginScreen()));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final rail = find.descendant(
        of: find.byType(AuthMasthead),
        matching: find.byType(ThreadRail),
      );
      // The draw is a growing clip, so the thread keeps its full layout height
      // and only the painted part advances down the spine.
      Size drawn() {
        final clip = find.descendant(of: rail, matching: find.byType(ClipRect));
        final clipper = tester.widget<ClipRect>(clip).clipper!;
        return clipper
            .getClip(const Size(Ds.railWidth, AuthMasthead.markHeight))
            .size;
      }

      expect(drawn().height, greaterThan(0));
      expect(drawn().height, lessThan(AuthMasthead.markHeight));
      expect(tester.hasRunningAnimations, isTrue);

      await tester.pumpAndSettle();
      expect(drawn().height, AuthMasthead.markHeight);
    });

    testWidgets('reduce-motion: rail langsung penuh, tanpa animasi', (
      tester,
    ) async {
      await tester.pumpWidget(
        harness(screen: const LoginScreen(), reduceMotion: true),
      );
      await tester.pump();

      expect(tester.hasRunningAnimations, isFalse);
      final line = find.descendant(
        of: find.descendant(
          of: find.byType(AuthMasthead),
          matching: find.byType(ThreadRail),
        ),
        matching: find.byType(ColoredBox),
      );
      expect(tester.getSize(line).height, AuthMasthead.markHeight);
    });

    testWidgets('chrome auth tetap bichrome — hanya galat yang memakai warna', (
      tester,
    ) async {
      await open(tester, const LoginScreen());

      expect(
        find.descendant(
          of: find.byType(AuthMasthead),
          matching: find.byType(ThreadRail),
        ),
        findsOneWidget,
      );
      final rail = tester.widget<ThreadRail>(
        find.descendant(
          of: find.byType(AuthMasthead),
          matching: find.byType(ThreadRail),
        ),
      );
      expect(rail.thread, isNot(Ds.threadAmber));
      expect(rail.thread, isNot(Ds.threadMoss));
      expect(rail.thread, isNot(Ds.threadSlate));
      expect(rail.thread, isNot(Ds.threadRose));
      expect(rail.thread, Ds.paper, reason: 'ink/paper chrome only');
      expect(find.byType(AuthFailureBanner), findsNothing);
    });
  });
}
