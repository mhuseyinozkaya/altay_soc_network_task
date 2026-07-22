FROM postgres:16-alpine

# postgres image'ı /docker-entrypoint-initdb.d altındaki .sql dosyalarını
# ilk container başlatıldığında (boş veritabanında) otomatik çalıştırır.
COPY schema.sql /docker-entrypoint-initdb.d/01-schema.sql
