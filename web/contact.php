<?php
// İletişim formu: veriler normal bir log dosyasına yazılıyor.
// (Gerçek/hassas müşteri kayıtları ayrı, root'a ait bir dosyada -
// privilege escalation senaryosunun hedefi orası, bkz. Dockerfile.)

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $isim  = $_POST['isim']  ?? '';
    $email = $_POST['email'] ?? '';
    $mesaj = $_POST['mesaj'] ?? '';

    $satir = date('Y-m-d H:i:s') . " | $isim | $email | $mesaj\n";
    file_put_contents('/var/lib/webapp/contacts.db', $satir, FILE_APPEND);

    echo "Talebiniz alindi, tesekkurler.";
} else {
    echo "Sadece POST istekleri kabul edilir.";
}

