<!DOCTYPE html>
<html lang="tr">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Vardiya Siber Güvenlik Danışmanlığı</title>
<style>
    :root {
        --bg: #101820;
        --panel: #17222c;
        --panel-border: #223140;
        --text: #dbe4ec;
        --text-muted: #7c8ea1;
        --accent: #4fd1c5;
    }

    * { box-sizing: border-box; }

    body {
        margin: 0;
        background: var(--bg);
        color: var(--text);
        font-family: -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
        line-height: 1.5;
    }

    header {
        border-bottom: 1px solid var(--panel-border);
        padding: 28px 40px;
        display: flex;
        align-items: baseline;
        justify-content: space-between;
    }

    .brand {
        font-size: 20px;
        font-weight: 700;
        letter-spacing: 0.02em;
    }

    .brand span {
        color: var(--accent);
        font-family: "Courier New", monospace;
    }

    .tagline {
        color: var(--text-muted);
        font-size: 13px;
        font-family: "Courier New", monospace;
        letter-spacing: 0.08em;
        text-transform: uppercase;
    }

    main {
        max-width: 880px;
        margin: 0 auto;
        padding: 56px 24px 80px;
    }

    .eyebrow {
        font-family: "Courier New", monospace;
        color: var(--accent);
        font-size: 13px;
        letter-spacing: 0.1em;
        margin-bottom: 8px;
    }

    h1.hero {
        font-size: 34px;
        font-weight: 700;
        margin: 0 0 12px;
        max-width: 640px;
    }

    .hero-sub {
        color: var(--text-muted);
        max-width: 540px;
        margin-bottom: 48px;
    }

    .grid {
        display: grid;
        grid-template-columns: 1fr 1fr;
        gap: 24px;
    }

    @media (max-width: 700px) {
        .grid { grid-template-columns: 1fr; }
        header { padding: 20px; }
        main { padding: 40px 16px 64px; }
    }

    .card {
        background: var(--panel);
        border: 1px solid var(--panel-border);
        border-radius: 10px;
        padding: 28px;
    }

    .card h2 {
        font-size: 17px;
        margin: 0 0 6px;
    }

    .card p.desc {
        color: var(--text-muted);
        font-size: 14px;
        margin: 0 0 20px;
    }

    label {
        display: block;
        font-size: 13px;
        color: var(--text-muted);
        margin-bottom: 6px;
    }

    input[type="text"],
    input[type="email"],
    input[type="file"],
    textarea {
        width: 100%;
        background: #0d151c;
        border: 1px solid var(--panel-border);
        color: var(--text);
        border-radius: 6px;
        padding: 10px 12px;
        font-size: 14px;
        margin-bottom: 16px;
        font-family: inherit;
    }

    textarea { min-height: 90px; resize: vertical; }

    button {
        background: var(--accent);
        color: #0a1015;
        border: none;
        border-radius: 6px;
        padding: 10px 20px;
        font-size: 14px;
        font-weight: 600;
        cursor: pointer;
    }

    button:hover { background: #6adfd4; }

    footer {
        text-align: center;
        color: var(--text-muted);
        font-size: 12px;
        font-family: "Courier New", monospace;
        padding: 24px;
        border-top: 1px solid var(--panel-border);
    }
</style>
</head>
<body>

<header>
    <div class="brand">VARDIYA <span>//</span> SİBER GÜVENLİK</div>
    <div class="tagline">Ağ Güvenliği &amp; Danışmanlık</div>
</header>

<main>
    <div class="eyebrow">KURUMSAL PORTAL</div>
    <h1 class="hero">Ağ güvenliği danışmanlığında güvenilir çözüm ortağınız.</h1>
    <p class="hero-sub">
        Sızma testi, güvenlik denetimi ve SOC danışmanlığı hizmetleri sunuyoruz.
        Belge paylaşımı ve iletişim taleplerinizi aşağıdan iletebilirsiniz.
    </p>

    <div class="grid">
        <div class="card">
            <h2>Belge Yükleme Portalı</h2>
            <p class="desc">Rapor veya belge paylaşmak için dosyanızı yükleyin.</p>
            <form action="upload.php" method="POST" enctype="multipart/form-data">
                <input type="file" name="dosya">
                <button type="submit">Yükle</button>
            </form>
        </div>

        <div class="card">
            <h2>Bize Ulaşın</h2>
            <p class="desc">Danışmanlık talebiniz için bilgilerinizi bırakın.</p>
            <form action="contact.php" method="POST">
                <label>Ad Soyad</label>
                <input type="text" name="isim">
                <label>E-posta</label>
                <input type="email" name="email">
                <label>Mesajınız</label>
                <textarea name="mesaj"></textarea>
                <button type="submit">Gönder</button>
            </form>
        </div>
    </div>
</main>

<footer>© 2026 Vardiya Siber Güvenlik Danışmanlığı</footer>

</body>
</html>
