# DaeNotes API

REST API untuk aplikasi DaeNotes, dibuat dengan Laravel 12 dan Laravel Sanctum. README utama di [root repositori](../README.md) menjelaskan setup aplikasi dan backend secara menyeluruh.

## Menjalankan secara lokal

Persyaratan: PHP 8.2+, Composer, dan MySQL yang dapat diakses.

```bash
cd backend
composer install
cp .env.example .env
```

Atur `DB_HOST`, `DB_PORT`, `DB_DATABASE`, `DB_USERNAME`, dan `DB_PASSWORD` di `.env`, lalu jalankan:

```bash
php artisan key:generate
php artisan migrate
php artisan serve --host=0.0.0.0
```

API lokal berjalan di `http://127.0.0.1:8000/api` dari komputer. Gunakan alamat jaringan yang sesuai saat mengaksesnya dari emulator atau perangkat lain. Jangan gunakan kredensial contoh untuk produksi.

## Cakupan API

- Autentikasi akun dengan token Sanctum.
- Operasi catatan, tugas, arsip, pengingat, dan relasi antar-item.
- Graph relasi catatan dan tugas.
- Sinkronisasi perubahan dari klien offline-first menggunakan UUID.
- Berbagi catatan atau tugas dengan izin `viewer` dan `editor`.

Daftar route ada di `routes/api.php`. Kontrak data dan perilaku sinkronisasi didokumentasikan di [`docs/CONTRACT.md`](../docs/CONTRACT.md).

## Menjalankan pengujian

```bash
php artisan test
```

Konfigurasikan database pengujian secara terpisah dari database pengembangan maupun produksi.

## Produksi

Atur `.env` produksi melalui pengelola rahasia hosting, gunakan HTTPS, jalankan migrasi saat deployment, dan pastikan document root mengarah ke direktori `public/`. Jangan commit file `.env`, kredensial, atau token.
