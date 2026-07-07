#!/bin/bash
# Esternalizza Config.js della console GovPay sul volume /etc/govpay e ripunta index.html.
#
#   Volume:     /etc/govpay/static/govpay/web-console/assets/Config.js   (seed da war se assente)
#   Context 1:  conf/Catalina/localhost/static.xml         -> /static  (serve la dir esterna)
#   index.html: <script src="/static/govpay/web-console/assets/Config.js">  (reso assoluto)
#   Context 2:  conf/Catalina/localhost/govpay-console.xml -> override /index.html via PreResources
#
# Bakata nell'immagine in /docker-entrypoint-govpay.d/ : eseguita dall'entrypoint prima
# dell'avvio di Tomcat. Disattivabile con GOVPAY_CONSOLE_EXTERNAL_CONFIG=false.
# Scritta senza 'exit'/'set -e' (logica in una funzione) per essere sicura anche se
# l'entrypoint la esegue con 'source'.

_govpay_console_external_config() {
    local GOVPAY_HOME="${GOVPAY_HOME:-/etc/govpay}"
    local STATIC_ROOT="${GOVPAY_HOME}/static"
    local CONSOLE_ASSETS_DIR="${STATIC_ROOT}/govpay/web-console/assets"
    local CONFIG_JS="${CONSOLE_ASSETS_DIR}/Config.js"

    # URL assoluto con cui index.html carichera' il Config.js (servito dal context /static)
    local CONFIG_JS_URL="/static/govpay/web-console/assets/Config.js"

    # War / webapp esplosa della console
    local CONSOLE_WAR CONSOLE_EXPLODED
    CONSOLE_WAR=$(ls "${CATALINA_HOME}"/webapps/govpay-console*.war 2>/dev/null | head -1)
    CONSOLE_EXPLODED=$(ls -d "${CATALINA_HOME}"/webapps/govpay-console*/ 2>/dev/null | head -1)

    # Descriptor Tomcat (il nome file = context path)
    local CTX_DIR="${CATALINA_HOME}/conf/Catalina/localhost"
    local STATIC_CTX="${CTX_DIR}/static.xml"                 # -> /static
    local CONSOLE_CTX="${CTX_DIR}/govpay-console.xml"        # -> /govpay-console

    # index.html modificato (file derivato: rigenerato ad ogni avvio, fuori dal volume)
    local OVERRIDE_DIR="${CATALINA_HOME}/conf/govpay-console-override"
    local OVERRIDE_INDEX="${OVERRIDE_DIR}/index.html"

    mkdir -p "${CONSOLE_ASSETS_DIR}" "${CTX_DIR}" "${OVERRIDE_DIR}"

    # --- 1. Seed Config.js dal war (solo se assente nel volume: dato utente, persiste) ---
    if [ -f "${CONFIG_JS}" ]; then
        echo "INFO: Config.js gia' presente nel volume: ${CONFIG_JS} (uso quello)."
    elif [ -n "${CONSOLE_WAR}" ] && [ -f "${CONSOLE_WAR}" ]; then
        echo "INFO: Estraggo assets/Config.js da ${CONSOLE_WAR} -> ${CONFIG_JS}"
        unzip -o -j "${CONSOLE_WAR}" "assets/Config.js" -d "${CONSOLE_ASSETS_DIR}"
    elif [ -n "${CONSOLE_EXPLODED}" ] && [ -f "${CONSOLE_EXPLODED}assets/Config.js" ]; then
        echo "INFO: Copio assets/Config.js dalla war esplosa -> ${CONFIG_JS}"
        cp -f "${CONSOLE_EXPLODED}assets/Config.js" "${CONFIG_JS}"
    else
        echo "WARN: govpay-console.war non trovata: seed di Config.js saltato."
    fi

    # --- 2. Context /static che serve la directory esterna ---
    cat > "${STATIC_CTX}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- Risorse statiche console GovPay dal volume: /static/govpay/web-console/assets/Config.js -->
<Context
    docBase="${STATIC_ROOT}"
    path="/static"
    reloadable="false"
    privileged="false">
    <!-- Impedisce di usare link all'interno delle directory sotto static -->
    <Resources allowLinking="false" />

    <!-- Previene sessioni non necessarie -->
    <Manager pathname="" />
</Context>
EOF
    echo "INFO: static.xml -> context /static (docBase=${STATIC_ROOT})"

    # --- 3. index.html: ripunta il Config.js all'URL assoluto (derivato, rigenerato ogni avvio) ---
    local INDEX_SRC=""
    if [ -n "${CONSOLE_WAR}" ] && [ -f "${CONSOLE_WAR}" ]; then
        unzip -p "${CONSOLE_WAR}" "index.html" > "${OVERRIDE_INDEX}.orig" 2>/dev/null
        [ -s "${OVERRIDE_INDEX}.orig" ] && INDEX_SRC="${OVERRIDE_INDEX}.orig"
    elif [ -n "${CONSOLE_EXPLODED}" ] && [ -f "${CONSOLE_EXPLODED}index.html" ]; then
        INDEX_SRC="${CONSOLE_EXPLODED}index.html"
    fi

    if [ -n "${INDEX_SRC}" ]; then
        sed -E \
            -e "s#src=\"assets/Config\.js\"#src=\"${CONFIG_JS_URL}\"#g" \
            -e "s#src=\"@GOVPAY_CONFIG_JS_FILE_PATH@\"#src=\"${CONFIG_JS_URL}\"#g" \
            "${INDEX_SRC}" > "${OVERRIDE_INDEX}"
        rm -f "${OVERRIDE_INDEX}.orig"

        # --- 4. Context della console con override di /index.html ---
        cat > "${CONSOLE_CTX}" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!-- Override di index.html per caricare Config.js dal context /static -->
<Context>
    <Resources>
        <PreResources
            className="org.apache.catalina.webresources.FileResourceSet"
            base="${OVERRIDE_INDEX}"
            webAppMount="/index.html"
            readOnly="true" />
    </Resources>
</Context>
EOF
        echo "INFO: index.html ripuntato a ${CONFIG_JS_URL}; govpay-console.xml scritto."
    else
        echo "WARN: index.html non trovato nel war: override saltato."
    fi

    # --- Permessi (tomcat e' nel gruppo 0) ---
    chmod -R g+rwX "${STATIC_ROOT}" "${OVERRIDE_DIR}" 2>/dev/null

    echo "INFO: Esternalizzazione console GovPay completata."
}

if [ "${GOVPAY_CONSOLE_EXTERNAL_CONFIG:-true}" = "true" ]; then
    _govpay_console_external_config
else
    echo "INFO: Esternalizzazione Config.js console disabilitata (GOVPAY_CONSOLE_EXTERNAL_CONFIG=${GOVPAY_CONSOLE_EXTERNAL_CONFIG})."
fi
