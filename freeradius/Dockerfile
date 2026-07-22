FROM debian:bookworm-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    freeradius \
    freeradius-utils \
    freeradius-rest \
    openssl \
    && rm -rf /var/lib/apt/lists/*

# Kendi imzalı CA + server sertifikası (test/lab amaçlı).
# freeradius'un kendi CA scriptleri /etc/freeradius/3.0/certs altında hazır gelir.
WORKDIR /etc/freeradius/3.0/certs
RUN make all 2>/dev/null || true

COPY clients.conf /etc/freeradius/3.0/clients.conf
COPY eap.conf /etc/freeradius/3.0/mods-available/eap
COPY users /etc/freeradius/3.0/users

# --- rlm_rest: FastAPI Policy Engine entegrasyonu ---
COPY mods-rest /etc/freeradius/3.0/mods-available/rest
COPY policy-soc /etc/freeradius/3.0/policy.d/soc
COPY dictionary.local /etc/freeradius/3.0/dictionary.local
RUN echo '$INCLUDE dictionary.local' >> /etc/freeradius/3.0/dictionary

RUN ln -sf ../mods-available/rest /etc/freeradius/3.0/mods-enabled/rest

# post-auth { } bloğunun içine policy çağrısını enjekte et.
# NOT: default site dosyasının tam içeriği bu ortamda görüntülenemediği için
# bu sed komutu ilk "post-auth {" satırından hemen sonrasına ekleme yapar.
# Build sonrası `freeradius -CX` ile syntax doğrulaması yapılmalı.
RUN sed -i '0,/post-auth {/s//post-auth {\n\tsoc_policy_engine/' \
    /etc/freeradius/3.0/sites-available/default

RUN chown -R freerad:freerad /etc/freeradius/3.0

EXPOSE 1812/udp 1813/udp

CMD ["freeradius", "-f", "-l", "stdout"]
