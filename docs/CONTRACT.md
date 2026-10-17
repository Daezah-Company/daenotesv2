# DaeNotes — Shared Contract

Sumber kebenaran tunggal untuk semua pekerjaan. Jika sebuah agent butuh keputusan yang
tidak ada di sini, ia harus memilih yang paling konsisten dengan dokumen ini dan
mencatatnya di `docs/DECISIONS.md`, bukan mengarang struktur baru.

## 1. Produk

Catatan + todo yang **saling terhubung**. Nilai intinya bukan menyimpan item, melainkan
benang penghubung antar item. Tiga permukaan: daftar (inbox), editor, dan graph.

- Audience: satu orang, perangkat pribadi, uso intensif harian.
- Prinsip: UX-first, minimalis, offline-first, dark-first.

## 2. Topologi

```
DaeNotesV2/
  backend/   Laravel 12 API + Sanctum, MySQL 8.4        -> dimiliki agent BACKEND
  app/       Flutter (offline-first, custom canvas)     -> dimiliki agent APP
  docs/      kontrak ini + catatan keputusan
```

Agent **tidak boleh** menulis di folder milik domain lain.

## 3. Basis data (MySQL)

Tombstone/soft delete wajib karena klien offline perlu menghapus secara idempoten.

```
users        id, name, email(unique), password, created_at, updated_at
notes        id, user_id, uuid, title, body(longtext), color(null), pinned(bool),
             archived_at(null), deleted_at(null), synced_at, updated_at
todos        id, user_id, uuid, title, notes(null), done(bool), done_at(null),
             priority(enum: low|normal|high), due_at(null), remind_at(null),
             archived_at(null), deleted_at(null), synced_at, updated_at
links        id, user_id, uuid, source_type(note|todo), source_uuid(string36),
             target_type(note|todo), target_uuid(string36), label(null),
             deleted_at(null), created_at, updated_at
             UNIQUE(user_id,source_uuid,target_uuid)
reminders    id, user_id, uuid, item_type(note|todo), item_uuid(string36),
             scheduled_at, title, fired_at(null), deleted_at(null), updated_at
```

**Semua referensi antar-item memakai uuid, bukan id integer internal.** Alasannya keras dan
tidak boleh dibalik: klien offline-first membuat catatan lebih dulu dan hanya memegang uuid
selama item itu belum tersinkron, jadi id integer tidak akan ada saat user menautkan.
`id` bigint tetap ada sebagai primary key, tetapi tidak pernah muncul di permukaan API.
Server me-resolve uuid -> baris milik user tersebut; uuid tak dikenal = 404.

`uuid` (string 36) dibuat di klien dan menjadi kunci idempotensi sinkronisasi.
Server memakai uuid bila dikirim, dan tidak pernah membuat duplikat baris untuk uuid yang sudah ada.

## 4. API (REST, JSON, prefix `/api`)

Auth: Sanctum bearer token. Semua response dibungkus `{"data": ...}` atau
`{"data": [...], "meta": {...}}`. Error: `{"message": "...", "errors": {field: [msgs]}}`.

```
POST   /api/auth/register      {name,email,password}         -> {token,user}
POST   /api/auth/login         {email,password}              -> {token,user}
POST   /api/auth/logout
GET    /api/auth/me                                         -> {user}

GET    /api/notes             ?q&archived&updated_since&per_page&page&sort
POST   /api/notes             {uuid,title,body,color,pinned}
GET    /api/notes/{uuid}
PUT    /api/notes/{uuid}
DELETE /api/notes/{uuid}
POST   /api/notes/{uuid}/archive    | /restore

GET    /api/todos             ?q&done&due&updated_since&page
POST   /api/todos             {uuid,title,notes,priority,due_at,remind_at}
PUT    /api/todos/{uuid}
PATCH  /api/todos/{uuid}/toggle
DELETE /api/todos/{uuid}

GET    /api/links             ?item_type&item_id            -> tetangga 1 hop
POST   /api/links             {uuid,source_type,source_uuid,target_type,target_uuid,label}
DELETE /api/links/{uuid}
GET    /api/graph             ?depth=1|2&types=note,todo&root=<uuid>   -> {nodes:[],edges:[]}

GET    /api/sync/changes      ?since=ISO8601
   -> {notes:[],todos:[],links:[],reminders:[],deleted:{notes:[uuid],...},server_time}
POST   /api/sync/push         {notes:[],todos:[],links:[],reminders:[],deletes:[{type,uuid}]}
   -> {accepted:[],conflicts:[{type,uuid,server}],server_time}

GET    /api/reminders         ?upcoming&fired
POST   /api/reminders         {uuid,item_type,item_uuid,title,scheduled_at}
PATCH  /api/reminders/{uuid}/fire
```

`updated_since` dan `since` memakai `updated_at > since` termasuk baris yang di-soft-delete,
sehingga klien dapat menghapus item yang hilang di server.

## 5. Waktu di atas jaringan

Semua kolom datetime server bertipe `timestamp` dan **selalu disimpan sebagai instant UTC**.
Kewaran: klien mengirim `dateTime.toUtc().toIso8601String()` (berakhiran `Z`); server
mengembalikan string dengan designator zona eksplisit. Server **tidak pernah** menyimpulkan
zona lokal dari string tanpa offset — nilai naive diperlakukan sebagai UTC.
Di perangkat, item dibaca `.toLocal()` sesaat sebelum ditampilkan/dijadwalkan; simpanan lokal
Flutter memakai waktu dinding lokal supaya reminder tetap 18:00 saat pengguna pindah zona.

Aturan ini ada karena bug nyata: `18:00+07:00` pernah tersimpan sebagai `18:00:00` naive
(offset dibuang Eloquent), membuat pengingat meleset 7 jam.

## 6. Identitas visual (Flutter)

**Konsep: "color is relation, not decoration."** Antarmuka inti keras bichrome
(graphite/paper). Warna **hanya** muncul pada benang koneksi, penanda tipe, dan status.
Ini yang membedakan DaeNotes dari template Material default dan membuat graph langsung terbaca.

### Warna

```
ink        #282828   permukaan gelap, teks di atas paper
inkDeep    #1C1C1B   latar belakang terdalam (canvas graph)
inkLift    #353533   kartu/panel terangkat
paper      #FFFFFF   permukaan terang, teks di atas ink
paperVeil  #8B8B84   teks sekunder/hairline
threadAmber   #E3B23C   note -> note
threadMoss    #6FA88A   note -> todo
threadSlate   #7FA0C8   todo -> todo
threadRose    #C9768F   reminder / pengingat aktif
```

Mode gelap adalah default produk; mode terang memakai token yang sama, dipertukarkan.

### Tipografi

- Display/heading: **Bricolage Grotesque** (variable, opsz) — tegas, sedikit ganjil, bukan grotesk netral.
- Body/UI: **IBM Plex Sans** — warisan mesin tik catatan, tinggi x besar, tahan di ukuran kecil.
- Utility/data/tanggal: **IBM Plex Mono** — untuk计数 tanggal, relative time, ID.

Skala: display 34/28, section 20 (Bricolage 600), body 15 Plex 400, caption 12 Plex Mono 500
letterSpacing 0.06em uppercase untuk eyebrow; mono dipakai untuk tanggal relatif dan hitungan.

### Layout

Daftar sebagai "spine" — setiap baris punya rail kiri 3px yang menampilkan warna benang
item yang punya koneksi, kosong bila terisolasi. Ini insentif visual untuk menghubungkan item.

```
┌──────────────────────────────────────────┐
│ DaeNotes            [search]      [◎]    │  eyebrow mono + wordmark Bricolage
├──────────────────────────────────────────┤
│ NOTE ────────────── todo ─────────── graph│  tab underline, bukan Material tabs
├──┬───────────────────────────────────────┤
│▌ │ Judul catatan                  2h      │  ▌ = thread rail
│  │ potongan isi dua baris…               │
├──┴───────────────────────────────────────┤
│ ✓ Beli kopi        │ ◉ hari ini    besok │
└──────────────────────────────────────────┘
```

### Motion

Satu momen koreografi per permukaan, bukan efek tersebar. Signature: **thread draw** —
saat graph atau detail item muncul, benang digambar dengan path-trim dari simpul sumber.
Semua animasi hormati `reduceMotion` (langsung tampil, tanpa draw-on).

## 7. Aturan teknis Flutter

- State: Riverpod (`flutter_riverpod`), tidak bloc.
- Lokal: `drift` (SQLite). Repo membaca lokal, `SyncEngine` menulis ke server di background.
- Network: `dio` + interceptor bearer token; `flutter_secure_storage` untuk token.
- Router: `go_router`.
- Graph: `CustomPainter` + simulasi gaya sendiri, tanpa paket graph pihak ketiga.
- Notifikasi: `flutter_local_notifications` + `timezone`; jadwal lokal dari `remind_at`.
- Font dari `google_fonts` atau asset; jangan menggantung pada jaringan saat build.
- Tema dibangun dari token di atas (`Ds` class), bukan `ThemeData` bawaan langsung di widget.

## 8. Batas file antar agent (fase fitur)

```
app/lib/core/           design system, tema, widget primitif   -> FOUNDATION (tulis lebih dulu)
app/lib/data/           drift, model, api client, sync engine  -> FOUNDATION
app/lib/features/notes/        -> agent NOTES
app/lib/features/todos/        -> agent NOTES
app/lib/features/graph/        -> agent GRAPH
app/lib/features/reminders/    -> agent REMINDERS
app/lib/app_router.dart        -> HANYA main agent (integrasi)
```

Tiap fitur mengekspos `routes` dan halaman miliknya sendiri, tidak mengedit file fitur lain.
