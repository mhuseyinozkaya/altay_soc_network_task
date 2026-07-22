<?php
// UYARI: Bu dosya kasıtlı olarak zafiyetlidir (eğitim/lab amaçlı).
// Uzantı, MIME type veya dosya içeriği kontrolü YAPILMAZ.
// Gerçek ortamda ASLA bu şekilde kullanılmamalıdır.

$uploadDir = __DIR__ . '/uploads/';

if (isset($_FILES['dosya']) && $_FILES['dosya']['error'] === UPLOAD_ERR_OK) {
    $originalName = basename($_FILES['dosya']['name']); // path traversal filtresi bile yok
    $target = $uploadDir . $originalName;

    if (move_uploaded_file($_FILES['dosya']['tmp_name'], $target)) {
        echo "Dosya yuklendi: uploads/" . htmlspecialchars($originalName);
    } else {
        echo "Yukleme basarisiz.";
    }
} else {
    echo "Dosya secilmedi veya hata olustu.";
}
