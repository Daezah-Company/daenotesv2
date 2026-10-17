# DaeNotes — app Flutter

Offline-first: semua baca/tulis lewat drift (`lib/data/db/`), sinkronisasi behind
melalui outbox + `SyncEngine`. Lihat `docs/CONTRACT.md` untuk kontrak API dan
`docs/DECISIONS.md` untuk deviation.

## Menjalankan

```bash
# 1. backend (dari repo root)
cd ../backend && cp .env.example .env   # lalu isi DB_* + php artisan key:generate
php artisan migrate --force
php artisan serve                        # http://localhost:8000

# 2. app
flutter pub get
flutter run
```

URL API dibaca dari `String.fromEnvironment(DAENOTES_API_URL)`, default
`http://localhost:8000/api`. Untuk emulator Android, `localhost` adalah perangkat
itu sendiri, jadi arahkan ke host:

```bash
flutter run --dart-define=DAENOTES_API_URL=http://10.0.2.2:8000/api
```

## Verifikasi

```bash
flutter analyze
flutter test
dart run build_runner build --delete-conflicting-outputs   # regenerasi database.g.dart
```

`flutter test` butuh `dart format` yang jalan (pre-commit pakai `dart format lib test`).

## Catatan platform

Notifikasi reminder memakai `flutter_local_notifications` + `timezone`; izin
`POST_NOTIFICATIONS` dan exact alarm diminta saat pertama boot scheduler
(`lib/main.dart`). build APK butuh JDK 17 yang belum terpasang di mesin ini, dan
build desktop Linux butuh `libsecret-1-dev` (dependensi `flutter_secure_storage`).
