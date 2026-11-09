<?php
$app_name = "DAENOTES";
$app_tagline = "TUGAS & CATATAN MINIMALIS.";
$app_description = "Aplikasi task dan note manager lokal dengan tema hitam putih. Cepat, ringan, dan tanpa gangguan.";
$app_version = "1.2.5";
$year = date("Y");
?>
<!DOCTYPE html>
<html lang="id">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=5.0">
<title><?= $app_name ?> — <?= $app_tagline ?></title>
<meta name="description" content="<?= $app_description ?>">
<meta name="theme-color" content="#ffffff">
<meta property="og:title" content="<?= $app_name ?> — <?= $app_tagline ?>">
<meta property="og:description" content="<?= $app_description ?>">
<meta property="og:image" content="daenotes-brand.png">
<meta property="og:image:width" content="4096">
<meta property="og:image:height" content="2800">
<meta property="og:type" content="website">
<meta name="twitter:card" content="summary">
<meta name="twitter:title" content="<?= $app_name ?> — <?= $app_tagline ?>">
<meta name="twitter:description" content="<?= $app_description ?>">
<meta name="twitter:image" content="daenotes-brand.png">
<link rel="icon" href="daenotes-brand.png" type="image/png">
<link rel="apple-touch-icon" href="daenotes-brand.png">
<style>
*,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
html{scroll-behavior:smooth;-webkit-tap-highlight-color:transparent}
body{
  font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Roboto,Oxygen,Ubuntu,Cantarell,sans-serif;
  background:#fff;color:#000;line-height:1.6;overflow-x:hidden;
  -webkit-font-smoothing:antialiased;-moz-osx-font-smoothing:grayscale;
}
img{max-width:100%;height:auto;display:block}
a{color:inherit;text-decoration:none}
::selection{background:#000;color:#fff}
::-moz-selection{background:#000;color:#fff}

#loader{position:fixed;inset:0;z-index:999;background:#fff;display:flex;align-items:center;justify-content:center;transition:opacity .6s,visibility .6s}
#loader.hidden{opacity:0;visibility:hidden;pointer-events:none}
#loader span{width:28px;height:28px;border:2.5px solid #000;border-top-color:transparent;border-radius:50%;animation:spin .7s linear infinite}
@keyframes spin{to{transform:rotate(360deg)}}

.hero{
  min-height:100vh;display:flex;flex-direction:column;align-items:center;
  justify-content:center;text-align:center;padding:40px 24px;position:relative;background:#fff;
}
.hero-grid{
  position:absolute;inset:0;overflow:hidden;pointer-events:none;
  display:grid;grid-template-columns:repeat(10,1fr);opacity:.03;
}
.hero-grid span{height:100vh;border-right:1px solid #000}
.hero-grid span:last-child{border-right:none}

.hero h1{
  font-size:clamp(44px,10vw,88px);font-weight:900;letter-spacing:6px;
  line-height:1.05;margin-bottom:8px;
}
.hero-tagline{
  font-size:clamp(13px,2.5vw,18px);font-weight:600;letter-spacing:4px;
  color:#666;margin-bottom:32px;text-transform:uppercase;
}
.hero-desc{
  max-width:480px;font-size:clamp(15px,2vw,17px);color:#444;
  margin-bottom:48px;line-height:1.8;
}

.hero-company{margin-bottom:48px}
.hero-company img{max-width:420px;width:85%;height:auto;display:block;margin:0 auto}

.btn-group{display:flex;gap:16px;flex-wrap:wrap;justify-content:center}
.btn{
  display:inline-flex;align-items:center;gap:10px;
  padding:18px 40px;font-size:13px;font-weight:700;letter-spacing:2.5px;
  border:2.5px solid #000;cursor:pointer;text-transform:uppercase;
  transition:all .25s cubic-bezier(.34,1.56,.64,1);position:relative;
  background:#fff;color:#000;border-radius:0;
}
.btn:hover{background:#000;color:#fff;transform:translateY(-3px)}
.btn:active{transform:translateY(0);transition-duration:.05s}
.btn-primary{background:#000;color:#fff}
.btn-primary:hover{background:#fff;color:#000}
.btn-arrow{transition:transform .25s;display:inline-block}
.btn:hover .btn-arrow{transform:translateX(4px)}
.btn-ghost{border-color:#ccc;color:#666}
.btn-ghost:hover{border-color:#000;color:#000;background:transparent}

.scroll-indicator{
  position:absolute;bottom:40px;left:50%;transform:translateX(-50%);
  display:flex;flex-direction:column;align-items:center;gap:8px;
  color:#999;font-size:9px;letter-spacing:2px;animation:float 2.5s ease-in-out infinite;
}
.scroll-indicator .line{width:1.5px;height:32px;background:#ccc;position:relative;overflow:hidden}
.scroll-indicator .line::after{
  content:'';position:absolute;top:-100%;left:0;width:100%;height:100%;background:#000;animation:scrollLine 2s ease-in-out infinite;
}
@keyframes float{0%,100%{transform:translateX(-50%) translateY(0)}50%{transform:translateX(-50%) translateY(-6px)}}
@keyframes scrollLine{0%{top:-100%}100%{top:100%}}

.section{padding:120px 24px;max-width:1200px;margin:0 auto;border-top:1.5px solid #f0f0f0}
.section:first-of-type{border-top:none;padding-top:0}
.section-label{font-size:10px;font-weight:700;letter-spacing:3px;color:#999;margin-bottom:16px;text-transform:uppercase}
.section-title{font-size:clamp(28px,5vw,48px);font-weight:900;letter-spacing:2px;line-height:1.15;margin-bottom:20px}
.section-desc{max-width:540px;font-size:16px;color:#555;line-height:1.8;margin-bottom:48px}

.features{display:grid;grid-template-columns:repeat(3,1fr);gap:2px;background:#e8e8e8}
.feature{
  background:#fff;padding:48px 32px;display:flex;flex-direction:column;
  transition:all .3s;position:relative;overflow:hidden;
}
.feature::after{
  content:'';position:absolute;bottom:0;left:0;width:100%;height:3px;
  background:#000;transform:scaleX(0);transform-origin:left;
  transition:transform .4s cubic-bezier(.34,1.56,.64,1);
}
.feature:hover::after{transform:scaleX(1)}
.feature:hover{background:#fafafa}
.feature svg{display:block;margin-bottom:24px;flex-shrink:0}
.feature h3{font-size:15px;font-weight:800;letter-spacing:1.5px;margin-bottom:10px;text-transform:uppercase}
.feature p{font-size:14px;color:#666;line-height:1.7}

.showcase{display:grid;grid-template-columns:1fr 1fr;gap:80px;align-items:center}
.showcase-visual{
  aspect-ratio:9/19;max-width:320px;width:100%;margin:0 auto;
  border:2.5px solid #000;position:relative;overflow:hidden;background:linear-gradient(180deg,#f8f8f8 0%,#fff 30%);
}
.showcase-visual .mock-header{
  padding:20px 20px 12px;border-bottom:1.5px solid #e8e8e8;display:flex;align-items:center;gap:12px;
}
.showcase-visual .mock-header .mock-logo{width:28px;height:28px;flex-shrink:0}
.showcase-visual .mock-header .mock-logo img{width:100%;height:100%;object-fit:contain}
.showcase-visual .mock-header .text{font-size:9px;font-weight:700;letter-spacing:2px}
.showcase-visual .mock-body{padding:16px 20px}
.showcase-visual .mock-item{
  border:1.5px solid #000;padding:12px 14px;margin-bottom:8px;
  display:flex;align-items:center;gap:12px;
}
.showcase-visual .mock-item .box{width:18px;height:18px;border:2px solid #000;flex-shrink:0}
.showcase-visual .mock-item .box.filled{background:#000;position:relative}
.showcase-visual .mock-item .box.filled::after{
  content:'';position:absolute;left:4px;top:1px;width:6px;height:10px;
  border:solid #fff;border-width:0 2.5px 2.5px 0;transform:rotate(45deg);
}
.showcase-visual .mock-item .line{height:10px;background:#e8e8e8;flex:1}
.showcase-visual .mock-item .line.w70{max-width:70%}
.showcase-visual .mock-item .line.w50{max-width:50%}
.showcase-visual .mock-item .line.w40{max-width:40%}
.showcase-visual .mock-item.done{border-color:#e8e8e8;opacity:.6}
.showcase-visual .mock-item.done .line{background:#f0f0f0}

.showcase-text .pill{
  display:inline-block;font-size:9px;font-weight:700;letter-spacing:2px;
  padding:6px 16px;border:1.5px solid #000;margin-bottom:20px;
}
.showcase-text h2{font-size:clamp(24px,4vw,40px);font-weight:900;letter-spacing:2px;line-height:1.2;margin-bottom:16px}
.showcase-text p{font-size:15px;color:#555;line-height:1.8;margin-bottom:24px}
.showcase-text ul{list-style:none;display:flex;flex-direction:column;gap:12px}
.showcase-text ul li{display:flex;align-items:center;gap:12px;font-size:14px;color:#333}
.showcase-text ul li svg{flex-shrink:0}

.download-wrap{display:flex;gap:80px;align-items:center}
.download-info{flex:1}
.download-actions{flex:1;display:flex;flex-direction:column;gap:16px}
.download-card{
  border:2.5px solid #000;padding:32px;display:flex;align-items:center;gap:20px;
  transition:all .25s;cursor:pointer;
}
.download-card:hover{background:#000;color:#fff;transform:translateY(-3px)}
.download-card:hover .dl-sub{color:#aaa}
.download-card .dl-icon{
  width:48px;height:48px;border:2px solid #000;display:flex;
  align-items:center;justify-content:center;flex-shrink:0;
  background:#fff;transition:background .25s;
}
.download-card:hover .dl-icon{background:#000;border-color:#fff}
.download-card:hover .dl-icon svg{color:#fff}
.download-card .dl-info{flex:1}
.download-card .dl-info h4{font-size:14px;font-weight:800;letter-spacing:1.5px;text-transform:uppercase}
.download-card .dl-info .dl-sub{font-size:12px;color:#888;margin-top:2px;transition:color .25s}
.download-card .dl-arrow{transition:transform .4s cubic-bezier(.34,1.56,.64,1)}
.download-card:hover .dl-arrow{transform:translateX(6px)}
.download-card.loading{pointer-events:none;border-color:#666;transition:border-color .3s}
.download-card.loading .dl-arrow{animation:dl-bounce .6s ease infinite;transform:none}
.download-card.loading .dl-arrow svg{transition:transform .4s;transform:rotate(90deg)}
.download-card.done{border-color:#34C759;background:#fafff5;transition:all .4s}
.download-card.done .dl-arrow{animation:none;transform:none}
.download-card.done .dl-arrow svg{stroke:#34C759;transition:stroke .3s}
.download-card.done .dl-sub{color:#34C759}
@keyframes dl-bounce{0%,100%{transform:translateY(0)}50%{transform:translateY(5px)}}

.footer{
  border-top:1.5px solid #e8e8e8;padding:48px 24px;text-align:center;background:#fafafa;
}
.footer .f-brand{font-size:13px;font-weight:900;letter-spacing:3px;margin-bottom:8px}
.footer .f-meta{font-size:11px;color:#999;letter-spacing:1px}
.footer .f-company{display:flex;align-items:center;justify-content:center;margin-top:20px}
.footer .f-company img{height:32px;width:auto;opacity:.4;transition:opacity .25s}
.footer .f-company img:hover{opacity:.7}
.footer .f-links{display:flex;gap:24px;justify-content:center;margin-top:16px;flex-wrap:wrap}
.footer .f-links a{font-size:11px;color:#666;letter-spacing:1px;text-transform:uppercase;transition:color .25s}
.footer .f-links a:hover{color:#000}

@media(max-width:900px){
  .features{grid-template-columns:1fr}
  .showcase{grid-template-columns:1fr;gap:48px}
  .download-wrap{flex-direction:column;gap:32px}
}
@media(max-width:600px){
  .hero{padding:32px 20px}
  .hero-company img{max-width:280px}
  .section{padding:80px 20px}
  .feature{padding:36px 24px}
  .showcase-visual{max-width:260px}
  .download-card{padding:24px;flex-wrap:wrap}
}
@media(prefers-reduced-motion:reduce){
  *{animation-duration:.01ms!important;animation-iteration-count:1!important;transition-duration:.01ms!important}
}

.reveal{opacity:0;transform:translateY(30px);transition:opacity .7s,transform .7s cubic-bezier(.16,1,.3,1)}
.reveal.visible{opacity:1;transform:translateY(0)}
</style>
</head>
<body>

<div id="loader"><span></span></div>

<!-- ─── HERO ─── -->
<section class="hero" id="home">
  <div class="hero-grid"><?php for($i=0;$i<10;$i++): ?><span></span><?php endfor; ?></div>

  <div class="hero-company">
    <img src="daenotes-brand.png" alt="DaeNotes">
  </div>

  <div class="scroll-indicator" aria-hidden="true">
    <span>GULIR</span>
    <div class="line"></div>
  </div>
</section>

<!-- ─── FITUR ─── -->
<section class="section reveal" id="fitur">
  <p class="section-label">✦ Fitur</p>
  <h2 class="section-title">Dibuat untuk<br>fokus dan produktif.</h2>
  <p class="section-desc">Tanpa gangguan, tanpa database server. Semua data tersimpan aman di perangkat kamu.</p>

  <div class="features">
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="3" width="18" height="18" rx="2" ry="2"/><line x1="3" y1="9" x2="21" y2="9"/><line x1="9" y1="21" x2="9" y2="9"/></svg>
      <h3>Manajemen Tugas</h3>
      <p>Buat, atur, dan selesaikan tugas dengan prioritas, tenggat waktu, subtugas, dan pengulangan otomatis.</p>
    </div>
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M11 4H4a2 2 0 0 0-2 2v14a2 2 0 0 0 2 2h14a2 2 0 0 0 2-2v-7"/><path d="M18.5 2.5a2.121 2.121 0 0 1 3 3L12 15l-4 1 1-4 9.5-9.5z"/></svg>
      <h3>Catatan Cepat</h3>
      <p>Catat ide kapan saja dengan dukungan tag, pencarian, dan pengelompokan per grup.</p>
    </div>
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="10"/><circle cx="12" cy="12" r="6"/><circle cx="12" cy="12" r="2"/></svg>
      <h3>Progress Visual</h3>
      <p>Pantau kemajuan tugas melalui progress ring pada setiap grup, plus tampilan hari ini yang fokus pada prioritas.</p>
    </div>
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M12 22s-8-4.5-8-11.8A8 8 0 0 1 12 2a8 8 0 0 1 8 8.2c0 7.3-8 11.8-8 11.8z"/><circle cx="12" cy="10" r="3"/></svg>
      <h3>Offline First</h3>
      <p>Semua data tersimpan lokal di perangkat. Bekerja tanpa internet, privasi tetap terjaga.</p>
    </div>
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
      <h3>Backup &amp; Restore</h3>
      <p>Ekspor data ke file JSON kapan saja. Aman dipindahkan antar perangkat atau sekadar arsip.</p>
    </div>
    <div class="feature">
      <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><circle cx="12" cy="12" r="5"/><line x1="12" y1="1" x2="12" y2="3"/><line x1="12" y1="21" x2="12" y2="23"/><line x1="4.22" y1="4.22" x2="5.64" y2="5.64"/><line x1="18.36" y1="18.36" x2="19.78" y2="19.78"/><line x1="1" y1="12" x2="3" y2="12"/><line x1="21" y1="12" x2="23" y2="12"/><line x1="4.22" y1="19.78" x2="5.64" y2="18.36"/><line x1="18.36" y1="5.64" x2="19.78" y2="4.22"/></svg>
      <h3>Tema Monokrom</h3>
      <p>Tampilan hitam-putih yang elegan dengan dukungan tema terang, gelap, dan mengikuti sistem.</p>
    </div>
  </div>
</section>

<!-- ─── DOWNLOAD ─── -->
<section class="section reveal" id="download">
  <p class="section-label">✦ Download</p>
  <h2 class="section-title">Dapatkan<br><?= $app_name ?> sekarang.</h2>
  <p class="section-desc">Gratis. Tanpa iklan. Tanpa izin berlebihan.</p>

  <div class="download-wrap">
    <div class="download-info">
      <div style="border:2.5px solid #000;padding:40px 32px;text-align:center;max-width:320px">
        <img src="daenotes-brand.png" alt="<?= $app_name ?>" style="width:64px;height:64px;object-fit:contain;margin:0 auto 16px">
        <div style="font-size:11px;font-weight:700;letter-spacing:3px">DAENOTES</div>
        <div style="font-size:9px;color:#999;letter-spacing:2px;margin-top:4px">v<?= $app_version ?></div>
      </div>
    </div>
    <div class="download-actions">
      <a class="download-card" href="downloads/daenotes.apk" download rel="noopener" id="dl-android">
        <div class="dl-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="2" width="16" height="20" rx="2" ry="2"/><line x1="8" y1="6" x2="16" y2="6"/><line x1="12" y1="10" x2="12" y2="18"/><line x1="8" y1="14" x2="16" y2="14"/></svg>
        </div>
        <div class="dl-info">
          <h4>Android APK</h4>
          <div class="dl-sub">File .apk — side loading</div>
        </div>
        <span class="dl-arrow">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>
        </span>
      </a>
    </div>
  </div>
</section>

<!-- ─── DOWNLOAD ─── -->
<section class="section reveal" id="download">
  <p class="section-label">✦ Download</p>
  <h2 class="section-title">Dapatkan<br>DAENOTES V2 sekarang.</h2>
  <p class="section-desc">Gratis. Tanpa iklan. Tanpa izin berlebihan.</p>

  <div class="download-wrap">
    <div class="download-info">
      <div style="border:2.5px solid #000;padding:40px 32px;text-align:center;max-width:320px">
        <img src="daenotes-brand.png" alt="<?= $app_name ?>" style="width:64px;height:64px;object-fit:contain;margin:0 auto 16px">
        <div style="font-size:11px;font-weight:700;letter-spacing:3px">DAENOTES V2</div>
        <div style="font-size:9px;color:#999;letter-spacing:2px;margin-top:4px">v1.0.6+9</div>
      </div>
    </div>
    <div class="download-actions">
      <a class="download-card" href="downloads/DaeNotesV2.apk" download rel="noopener" id="dl-android">
        <div class="dl-icon">
          <svg width="24" height="24" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="4" y="2" width="16" height="20" rx="2" ry="2"/><line x1="8" y1="6" x2="16" y2="6"/><line x1="12" y1="10" x2="12" y2="18"/><line x1="8" y1="14" x2="16" y2="14"/></svg>
        </div>
        <div class="dl-info">
          <h4>Android APK</h4>
          <div class="dl-sub">File .apk — side loading</div>
        </div>
        <span class="dl-arrow">
          <svg width="20" height="20" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2.5" stroke-linecap="round" stroke-linejoin="round"><line x1="5" y1="12" x2="19" y2="12"/><polyline points="12 5 19 12 12 19"/></svg>
        </span>
      </a>
    </div>
  </div>
</section>

<!-- ─── FOOTER ─── -->
<footer class="footer">
  <div class="f-brand"><?= $app_name ?></div>
  <div class="f-company">
    <img src="logo-company.png" alt="Daezah Company">
  </div>
  <div class="f-links">
    <a href="#home">Beranda</a>
    <a href="#fitur">Fitur</a>
    <a href="#download">Download</a>
  </div>
</footer>

<script>
window.addEventListener('load',function(){setTimeout(function(){document.getElementById('loader').classList.add('hidden')},400)});

var observer=new IntersectionObserver(function(e){
  e.forEach(function(entry){
    if(entry.isIntersecting){entry.target.classList.add('visible');observer.unobserve(entry.target)}
  });
},{threshold:.12});
document.querySelectorAll('.reveal').forEach(function(el){observer.observe(el)});

document.getElementById('dl-android').addEventListener('click',function(e){
  e.preventDefault();
  var link=this;
  link.classList.add('loading');
  setTimeout(function(){
    var a=document.createElement('a');
    a.href=link.href;
    a.download='daenotes.apk';
    a.click();
    link.classList.remove('loading');
    link.classList.add('done');
    setTimeout(function(){link.classList.remove('done')},2000);
  },600);
});
</script>
</body>
</html>
