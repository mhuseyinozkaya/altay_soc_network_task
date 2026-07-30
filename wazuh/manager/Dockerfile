FROM wazuh/wazuh-manager:4.9.2

ARG WAZUH_REGISTRATION_PASSWORD
ARG QUARANTINE_MODE=block

USER root
RUN (command -v apt-get >/dev/null && apt-get update && apt-get install -y --no-install-recommends curl jq && rm -rf /var/lib/apt/lists/*) || \
    (command -v dnf >/dev/null && dnf install -y --allowerasing curl jq) || \
    (command -v yum >/dev/null && yum install -y --allowerasing curl jq) || true

# ---- Ozel tespit kurallari ----
COPY config/local_rules.xml /var/ossec/etc/rules/local_rules.xml

# ---- ar.conf duzeltmesi ----
# Bilinen wazuh-docker sorunu: konfigurasyon dosyalari /wazuh-config-mount
# uzerinden bind-mount edilmek yerine (bizim yaptigimiz gibi) build zamaninda
# COPY ile eklendiginde, cont-init.d/0-wazuh-init betigi "mount edilecek
# dosya yok" dallanmasina girip /var/ossec/etc/shared/ar.conf dosyasini hic
# olusturmuyor. Sonuc: wazuh-analysisd "Could not open file 'etc/shared/ar.conf'"
# hatasiyla surekli crash-loop'a giriyor (bkz. wazuh/wazuh-docker#1167).
# Dosyayi burada garantiye aliyoruz.
RUN mkdir -p /var/ossec/etc/shared/default && \
    touch /var/ossec/etc/shared/ar.conf && \
    chown -R wazuh:wazuh /var/ossec/etc/shared && \
    chmod 640 /var/ossec/etc/shared/ar.conf

# ---- Active-response komut scriptleri ----
COPY active-response/soc-log-vpn-action.sh /var/ossec/active-response/bin/soc-log-vpn-action.sh
COPY active-response/soc-quarantine.sh /var/ossec/active-response/bin/soc-quarantine.sh
RUN chmod 750 /var/ossec/active-response/bin/soc-log-vpn-action.sh \
              /var/ossec/active-response/bin/soc-quarantine.sh

# ---- Agent kayit (enrollment) sirri ----
# NOT: echo yerine printf kullaniliyor - echo, dosyanin sonuna otomatik bir
# newline (\n) ekliyordu. agent-auth ise sifreyi ortam degiskeninden ciplak
# (newline'siz) gonderiyor; wazuh-authd dosyanin TAMAMINI (trailing \n dahil)
# byte-byte karsilastirdigi icin bu fark "Invalid password provided" hatasina
# yol aciyordu.
RUN printf '%s' "${WAZUH_REGISTRATION_PASSWORD}" > /var/ossec/etc/authd.pass && \
    chmod 640 /var/ossec/etc/authd.pass

# ---- ossec.conf'a komut tanimlari + active-response bloklarini ekle ----
COPY config/soc-extra.conf.template /tmp/soc-extra.conf.template
RUN if [ "${QUARANTINE_MODE}" = "quarantine" ]; then \
        ENFORCE_DISABLED=yes; QUARANTINE_DISABLED=no; \
    else \
        ENFORCE_DISABLED=no; QUARANTINE_DISABLED=yes; \
    fi && \
    sed -e "s/__ENFORCE_DISABLED__/${ENFORCE_DISABLED}/g" \
        -e "s/__QUARANTINE_DISABLED__/${QUARANTINE_DISABLED}/g" \
        /tmp/soc-extra.conf.template >> /var/ossec/etc/ossec.conf && \
    rm /tmp/soc-extra.conf.template
