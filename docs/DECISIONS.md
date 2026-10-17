# Keputusan (di luar / melengkapi CONTRACT.md)

## Lapisan data klien — sinkronisasi murni uuid (menggantikan catatan lama)

Baris-baris di bagian ini dulunya menulis sinkron link/reminder dengan asumsi
server mengirim `source_id/target_id/item_id` dan `accepted: [{type, uuid, id?}]`.
Asumsi itu salah: backend hanya berbicara uuid (`SyncController.php`, CONTRACT §3–§4),
jadi seluruh konsep `serverId` lokal sudah dibuang. Isi sekarang:

- Payload push `links[]`/`reminders[]` dinormalisasi field-per-field oleh
  `SyncEngine.linkPushPayload`/`reminderPushPayload` dan hanya berisi
  `source_uuid`/`target_uuid`/`item_uuid`. Baris outbox sisa build lama yang masih
  membawa `*_id` tidak bisa membocorkan kunci itu ke wire; baris tanpa referensi
  uuid wajib tetap antre dan tidak dikirim.
- Tidak ada deferral: link dan reminder ikut siklus push pertama (dulu tertahan di
  `pending_changes` menunggu `serverId` yang tidak pernah datang).
- Kolom `server_id`, `source_id`, `target_id`, `item_id` dihapus dari skema drift.
  `schemaVersion` sengaja tetap 1 tanpa `DROP COLUMN`: kolom itu nullable dan tidak
  ada pembaca tersisa, sedangkan SQL drift menyebut kolom secara eksplisit, jadi DB
  lokal lama tetap jalan. `id` auto-increment lokal tiap tabel tetap dipakai sebagai
  rowid SQLite dan tidak pernah keluar ke API.
- Jalur pull: `applyLink`/`applyReminder` menyimpan uuid apa adanya — referensi
  dangling diterima (item tuju bisa menyusul di pull berikutnya). `markSynced(table,
  uuid)` hanya menulis `synced_at` dan jadi no-op untuk links/reminders.
- Deviasi yang ditemukan saat membersihkan: `SyncController::TYPES` melabeli
  `accepted`/`conflicts` dengan nama **tunggal** (`note`, `link`, …) sementara klien
  me-queue dengan nama bucket jamak. `_tableForWire` hanya mengenali yang jamak,
  sehingga terhadap server sungguhan outbox tidak pernah terkuras dan `synced_at`
  tidak pernah terisi. Sekarang kedua ejaan diterima dan nama kanonis jamak yang
  diteruskan. Dikunci test di `app/test/sync/sync_wire_uuid_test.dart`.
- Bentuk `accepted` pada /api/sync/push adalah `[{type, uuid}]` (tanpa id); parser
  toleran terhadap string uuid polos maupun map. `type` memakai nama tabel:
  `notes|todos|links|reminders`, sama untuk `deletes:[{type,uuid}]`.
- Payload upsert sync selalu menyertakan `updated_at` (UTC ISO8601) agar server bisa LWW.
- Conflict /api/sync/push: klien menang bila `updated_at` lokal >= server (retry push);
  server menang hanya bila strictly lebih baru.

## Keputusan lain

- Warna type mark (chip NOTE/TODO, bagian "type marks" §5): note=amber, todo=slate; moss
  tetap khusus benang note<->todo, rose khusus reminder/status.
- Nama rute (§7 tidak menamai rute): `inbox` (/inbox), `graph` (/graph), `reminders`
  (/reminders), `noteDetail` (/note/:uuid), `todoDetail` (/todo/:uuid), `login`, `register`.
- Auth screen bukan bagian foundation; router guard hanya membaca `authControllerProvider`.

# Keputusan backend — relasi antar-item memakai uuid (CONTRACT §3–§4 revisi)

- Migrasi: migration asal (`..._create_links_table`, `..._create_reminders_table`) **diedit**,
  bukan migration baru yang `ALTER`. Skema tidak punya riwayat deploy — MySQL dibangun ulang
  dengan `migrate:fresh` — jadi satu migration per tabel lebih bersih dan tidak meninggalkan
  kolom `source_id/target_id/item_id` yang sudah mati.
- `links`: `source_uuid`/`target_uuid` string(36) + `source_type`/`target_type`,
  UNIQUE(`user_id`,`source_uuid`,`target_uuid`), index tambahan (`user_id`,`target_uuid`) untuk
  query sisi target. `reminders`: `item_uuid` string(36) + index (`user_id`,`item_uuid`).
  `id` bigint tetap primary key internal dan tidak pernah dipakai untuk relasi.
- Indeks unik tidak menyertakan `deleted_at`, jadi POST pasangan yang barisnya soft-deleted
  **membangkitkan baris lama** (check duplikat selalu `withTrashed()`), bukan menabrak indeks.
  Keunikan tetap searah (A->B dan B->A baris berbeda), sama seperti perilaku sebelumnya.
- Resolusi uuid lewat `App\Support\ItemResolver`, selalu di bawah global scope `OwnedByUser`:
  uuid tak dikenal / milik user lain tidak ditemukan, sehingga `POST /api/links` dan
  `POST /api/reminders` menjawab **404** (sebelumnya 422 untuk id tak ada) — tidak pernah 403.
- Item yang sedang soft-deleted tidak bisa ditaut/dijadwalkan ulang lewat REST (404); lewat
  sync push uuid such-row tetap dianggap dikenal, karena batch klien bisa memuat link dan
  delete item dalam satu snapshot.
- `GET /api/links` difilter dengan `item_uuid`; nama lama `item_id` diterima sebagai alias
  tetapi isinya juga uuid — id integer tidak pernah diterima di permukaan API.
- `/api/graph`: node `{type,uuid,title}` dan edge `{uuid,source_type,source_uuid,target_type,
  target_uuid,label}` — id integer dibuang. BFS tetap per level: 1 query links + maksimal 2
  query item per level, dengan `whereIn` pada uuid (bukan klause per simpul), jadi jumlah query
  datar saat graf membesar; test membuktikan `queries(12 node) == queries(24 node)`.
- `POST /api/sync/push` kebal terhadap urutan dalam satu request, tiga lapis: (1) baris link
  dan reminder menyimpan uuid sehingga tidak butuh resolusi saat ditulis; (2) `SyncPushRequest`
  menganggap uuid yang muncul di bucket `notes`/`todos` pada request yang sama sebagai target
  yang ada (1 query per tipe item untuk seluruh batch, soft-deleted termasuk); (3) bucket
  diproses menurut `PUSH_ORDER` notes→todos→links→reminders, bukan urutan key JSON klien.
  Reference yang benar-benar tak dikenal = 422 per path field (`links.0.target_uuid`).
- Resource link & reminder tidak lagi mengekspos `id`; resource note/todo tetap seperti semula
  (di luar cakupan defek ini, `id`-nya tidak dipakai sebagai referensi).
- `Relation::morphMap` di `AppServiceProvider` dipertahankan meski `morphTo` di `Link`/`Reminder`
  sudah hilang; tidak ada relasi polymorphic ber-id bigint yang tersisa.
- Teks CONTRACT §4 masih menulis `GET /api/links ?item_type&item_id`; dipahami sebagai filter
  berdasarkan uuid item (alasan §3 berlaku sama), maka `item_uuid` menjadi nama baku dan
  `item_id` dibiarkan sebagai alias ber-isi-uuid agar klien lama tidak langsung rusak.

# Keputusan backend — normalisasi zona waktu pada semua gerbang datetime

- Defek: `POST /api/reminders` dengan `scheduled_at = "...T18:00:00+07:00"` tersimpan sebagai
  `18:00:00` (offset dibuang, instant meleset 7 jam). Akar: nilai string mentah masuk Eloquent lalu
  diformat memakai timezone milik nilai itu sendiri (`castBinding`/`fromDateTime` = `Y-m-d H:i:s`),
  bukan konversi ke UTC — bahkan `Carbon` ber-offset pun ikut salah; hanya `Carbon` UTC yang benar.
- Perbaikan di boundary, BUKAN dengan mengubah `config/app.php` timezone (tetap UTC). Helper baru
  `App\Support\Timestamp::utc()` mengubah wire value (terima `Z`, offset angka `+07:00`, dan string
  naive) menjadi `Carbon` UTC; nilai tak terparse ditolak `ValidationException` dengan pesan sama
  seperti `parse()`. `parse()` kini melimpah ke `utc()` sehingga filter query ikut benar.
- String naive tanpa offset diperlakukan sebagai instant UTC terdokumentasi API; server tidak menebak
  zona lokal klien (diberi komentar di kode).
- Diterapkan ke SETIAP jalur tulis: `scheduled_at` (StoreReminder), `due_at`/`remind_at`/`done_at`
  (Store/UpdateTodo), `archived_at`/`synced_at`/`fired_at` via normalisasi cast model, seluruh payload
  `POST /api/sync/push` (notes/todos/links/reminders + `updated_at` konflik), serta filter
  `GET /api/sync/changes?since=` dan `updated_since` pada notes/todos. `Timestamp::forModel()`
  menormalkan kolom bertipe cast datetime model, jadi tiap jalur tulis identik.
- Serialisasi respons disatukan lewat trait `App\Http\Resources\Concerns\FormatsTimestamps::ts()`
  (dipakai Note/Todo/Link/Reminder/User resource) — semua datetime keluar sebagai UTC ISO8601 dengan
  designator eksplisit `Z` (`Y-m-d\TH:i:s\Z`), sehingga klien tak bisa salah baca offset.
- Test regresi: `tests/Unit/TimestampTest.php` (helper) dan `tests/Feature/TimezoneTest.php` — offset
  `+07:00` jadi `2026-10-18T11:00:00Z` di DB + round-trip, input `Z` tak berubah, `due_at` ber-offset
  selamat lewat PUT dan siklus sync push/pull, dan filter `sync/changes?since=` ber-offset membandingkan
  instant yang benar. Total suite: 66 test / 355 assertions (dari 52/312).

# Keputusan integrasi — notifikasi, boot, dan copy

- Notifikasi dinyalakan: `flutter_local_notifications 22.3.2` + `timezone 0.11.2`, dan
  `FlutterNotificationAdapter` adalah scheduler produksi (`DisabledNotificationAdapter`
  dihapus karena tidak ada pembaca tersisa). API v22 berbeda dari draft v18:
  `initialize({required settings, …})`, `zonedSchedule(...)` tanpa
  `uiLocalNotificationDateInterpretation`, `cancel({required int id})`.
- uuid reminder → id plugin dengan hash FNV-1a 32-bit (`pluginIdFor`), bukan
  `String.hashCode` yang tidak dijamin stabil antar proses; uuid juga dikirim sebagai
  `payload` supaya `scheduledIds()` dapat dipulihkan setelah restart.
- Android: `POST_NOTIFICATIONS`, `RECEIVE_BOOT_COMPLETED`, `SCHEDULE_EXACT_ALARM`, plus
  dua receiver plugin (`ScheduledNotificationReceiver`, `ScheduledNotificationBootReceiver`).
  Izin exact alarm diminta in-app dan fallback ke `inexactAllowWhileIdle` saat ditolak —
  reminder tetap datang, hanya tidak tepat-detik.
- Jadwal dihitung `tz.TZDateTime.from(when.toUtc(), tz.local)`, jadi 18:00 tetap 18:00
  saat DST bergeser. Named zone eksplisit (`flutter_timezone`) sengaja tidak diambil:
  satu dependensi native lagi untuk kasus yang belum ada di produk ini.
- `main.dart` me-`init()` scheduler sekali lalu `reconcile()` setiap app resume; baris
  drift tetap sumber kebenaran, kegagalan adapter tidak menjatuhkan app (yang belum
  terkirim tampil di grup Tertunda dan dicoba lagi saat resume).
- `TodoDetailScreen` tidak lagi menulis `remind_at` sendiri: ia memanggil
  `ReminderActions.scheduleForTodo`, sehingga baris reminder, `remind_at`, dan notifikasi
  bergerak bersamaan. `scheduleForTodo` sekarang menggantikan reminder hidup milik todo
  yang sama (sebelumnya tiap pilih waktu menumpuk baris + buzz baru).
- Copy permukaan produk satu bahasa: Beranda / Graf / Pengingat, "benang", "tautan",
  "belum tertaut" — termasuk label Semantics graph dan tooltip status sinkron. Tombol
  cari mati di header shell dibuang (inbox sudah punya pencarian sendiri).

# Keputusan motion — satu kosakata `DsMotion`

- Kepribadian gerak: **calm/premium** — tanpa bounce/overshoot; masuk melambat
  (`enter = Cubic(0.05, 0.7, 0.1, 1)`), keluar mempercepat (`exit = Cubic(0.4, 0, 1, 1)`),
  perubahan on-screen mulus di kedua ujung (`onScreen = Cubic(0.2, 0, 0, 1)`). Durasi dan
  kurva tidak ditulis inline di feature lagi; semuanya lewat `app/lib/core/ds_motion.dart`,
  dan token lama `Ds.motionQuick`/`Ds.motionThreadDraw` dihapus supaya tidak ada dua sumber
  kebenaran.
- Budget durasi: `press 110` / `release 190` untuk sentuhan, `micro 150` untuk perubahan
  kecil, `standard 240` untuk state, `panel 320` untuk elemen yang membuka, `page 420` /
  `pageExit 260` untuk rute (masuk > keluar), `railDraw 420` dan `canvasReveal 1100` khusus
  untuk tanda tangan produk (gambar benang).
- Stagger daftar dibatasi: `DsMotion.stagger = 34ms` dengan plafon baris ke-`staggerLastRow`
  (8) sehingga kaskade total tidak melewati 500ms walau daftarnya panjang. `DsEnter`
  melipat delay ke dalam `Interval` milik `TweenAnimationBuilder`, jadi tidak ada `Timer`
  yang menggantung dan `pumpAndSettle` tetap selesai di test.
- **Gambar benang di-clip, bukan di-layout.** Rail dulu tumbuh dengan `LayoutBuilder` yang
  mengukur tinggi; itu melempar "LayoutBuilder does not support returning intrinsic
  dimensions" begitu rail masuk `DsCard` (card memakai `IntrinsicHeight` untuk memberi
  tinggi ke rail). Sekarang rail selalu menempati tinggi penuh di layout dan hanya
  `ClipRect` + `_DrawDownClipper` yang tumbuh ke bawah. Konsekuensinya test yang dulu
  mengecek tinggi box sekarang mengecek `clipper.getClip(...)`, dan `DsCard` tetap bisa
  dipakai di dalam `ListView`.
- Tab switch **sengaja tidak** diberi cross-fade antar branch: shell tetap
  `StatefulShellRoute.indexedStack` supaya scroll position dan state graf bertahan. Rasa
  "pindah tab yang mulus" datang dari garis bawah yang bergerak sebagai satu bar
  (`AnimatedPositioned` di `DsTabBar`) plus stagger baris per layar.
- Transisi rute detail/auth memakai `DsRouteTransition` lewat `pageBuilder`: halaman masuk
  bergerak 24px + fade; halaman keluar menyusut 4% dan meredup 45% dan sudah selesai sebelum
  halaman baru mendarat (via `secondaryAnimation`), jadi tidak ada frame dengan dua halaman
  yang terasa sama penting.
- Sheet tidak lagi memanggil `showModalBottomSheet` langsung; semua lewat
  `app/lib/core/ds_sheet.dart::showDsSheet` supaya warna permukaan, radius atas, dan
  `sheetAnimationStyle` (buka `panel/enter`, tutup `standard/exit`) identik di mana-mana.
- Reduce-motion adalah jalur pertama, bukan tempelan: `context.reduceMotion`
  (`MediaQuery.maybeDisableAnimationsOf`) membuang displacement dan menjaga opacity —
  `DsEnter` tidak memasang `Transform`, underline tab pakai `Positioned` biasa, `DsPulse`
  berhenti (tidak ada animasi loop yang membuat test tidak pernah settle), `showDsSheet`
  berdurasi nol. Dikunci di `app/test/ds_motion_test.dart`.
- Copy: "dentang" (typo satu-satunya di repo, `reminders_screen.dart`) → "terjadwal";
  tidak ada test yang mengklaim teks lama.
- Verifikasi: `flutter analyze` bersih, `dart format` bersih, 113/113 test hijau,
  `flutter build bundle` debug + release exit 0. **Pengecekan visual belum dilakukan** —
  mesin ini tidak punya JDK (APK tidak bisa dibangun) dan `libsecret-1-dev` belum ada
  (build linux gagal), jadi rasa gerak masih perlu dinilai user setelah toolchain lengkap.
