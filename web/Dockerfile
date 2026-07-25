FROM nginx:1.18-alpine

RUN apk add --no-cache php7 php7-fpm findutils bash python3 libcap

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.php /var/www/html/index.php
COPY upload.php /var/www/html/upload.php
COPY contact.php /var/www/html/contact.php

# Kasıtlı zafiyet: uploads/ dizini herkes tarafından yazılabilir
# ve PHP-FPM tarafından çalıştırılabilir (uzantı/tip kontrolü yok).
RUN mkdir -p /var/www/html/uploads \
    && chmod 777 /var/www/html/uploads

# İletişim formu loglarının yazıldığı normal (root olmayan) dizin.
RUN mkdir -p /var/www/data \
    && chmod 777 /var/www/data

RUN setcap cap_setuid=+ep $(readlink -f $(which python3))

# "Hassas" müşteri kayıtları (sahte/demo veri) - sadece root okuyabilir,
# privilege escalation sonrası ele geçirilmesi hedeflenen "ödül" bu.
RUN mkdir -p /var/lib/webapp \
    && printf "Ahmet Yilmaz|ahmet@ornek.com|Danismanlik hizmeti hakkinda bilgi almak istiyorum\nZeynep Kaya|zeynep@ornek.com|Sizinle bir toplanti ayarlamak istiyorum\n" > /var/lib/webapp/contacts.db \
    && chown root:www-data /var/lib/webapp/contacts.db \
    && chmod 620 /var/lib/webapp/contacts.db

EXPOSE 80

CMD php-fpm7 -D && nginx -g "daemon off;"
