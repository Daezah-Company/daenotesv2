# DaeNotes Android app

Klien Flutter untuk DaeNotes. Data disimpan secara lokal menggunakan Drift; `SyncEngine` mengirim dan menerima perubahan dari API Laravel. Ringkasan setup seluruh repositori ada di [README utama](../README.md).

## Menjalankan

```bash
cd app
flutter pub get
flutter run
```

URL API default adalah `https://apidaenotes.daezah.com/api`. Untuk mengarahkan aplikasi ke backend lokal, gunakan `DAENOTES_API_URL`:

```bash
# Android Emulator
flutter run --dart-define=DAENOTES_API_URL=http://10.0.2.2:8000/api

# Genymotion; sesuaikan alamat jika konfigurasi jaringan berbeda
flutter run --dart-define=DAENOTES_API_URL=http://10.0.3.2:8000/api
```

Untuk perangkat fisik, gunakan IP LAN komputer yang menjalankan backend. Backend perlu mendengarkan pada `0.0.0.0` dan dapat dijangkau dari ponsel.

## Build APK

```bash
flutter build apk --release --dart-define=DAENOTES_API_URL=https://apidaenotes.daezah.com/api
```

Hasilnya ada di `build/app/outputs/flutter-apk/app-release.apk`.

## Verifikasi dan code generation

```bash
flutter analyze
flutter test
dart run build_runner build --delete-conflicting-outputs
```

Jalankan `build_runner` setelah mengubah tabel atau query Drift yang memerlukan pembaruan `lib/data/db/database.g.dart`.

## Area utama kode

- `lib/data/db/` — database lokal Drift.
- `lib/data/sync/` — antrean perubahan dan sinkronisasi API.
- `lib/data/auth/` — sesi dan autentikasi akun.
- `lib/features/` — layar catatan, tugas, graph, kolaborasi, pengingat, dan pengaturan.
- `android/app/src/main/` — konfigurasi Android, notifikasi, dan widget layar utama.
- `test/` — pengujian unit dan widget.
