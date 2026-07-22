FROM nginx:1.18-alpine
# Not: 1.18 kasıtlı olarak eski/desteklenmeyen bir sürüm (CVE taraması için gerçekçi hedef)

RUN apk add --no-cache php7 php7-fpm

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY index.php /var/www/html/index.php
COPY upload.php /var/www/html/upload.php

# Kasıtlı zafiyet: uploads/ dizini herkes tarafından yazılabilir
# ve PHP-FPM tarafından çalıştırılabilir (uzantı/tip kontrolü yok).
RUN mkdir -p /var/www/html/uploads \
    && chmod 777 /var/www/html/uploads

EXPOSE 80

CMD php-fpm7 -D && nginx -g "daemon off;"
