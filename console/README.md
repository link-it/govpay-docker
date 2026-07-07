# Console GovPay — Config.js esterno alla war

Procedura per servire il `Config.js` della console GovPay da un **file esterno alla war**,
montato sul volume `/etc/govpay`, senza ricostruire `govpay-console.war`.

## Cosa fa

Lo script `console-static-config.sh` va montato in `/docker-entrypoint-govpay.d/` e viene
eseguito dall'entrypoint **prima** dell'avvio di Tomcat. Ad ogni avvio:

1. **Seed Config.js** — se `/etc/govpay/static/govpay/web-console/assets/Config.js` non esiste,
   lo estrae da `govpay-console.war`; se esiste, usa quello del volume (le modifiche persistono).
2. **Context `/static`** — scrive `conf/Catalina/localhost/static.xml` con
   `docBase=/etc/govpay/static`, che serve la directory esterna
   (URL: `/static/govpay/web-console/assets/Config.js`).
3. **index.html** — estrae `index.html` dalla war e ne riscrive il tag
   `<script src="assets/Config.js">` in `<script src="/static/govpay/web-console/assets/Config.js">`
   (path assoluto → ignora il `<base href="/govpay-console/">`). File derivato, rigenerato ad ogni
   avvio in `conf/govpay-console-override/` (fuori dal volume).
4. **Context console** — scrive `conf/Catalina/localhost/govpay-console.xml` che sovrappone
   l'`index.html` modificato alla war via `PreResources`/`FileResourceSet` (nessuna ricompattazione).

## Layout sul volume

```
/etc/govpay/
└── static/
    └── govpay/
        └── web-console/
            └── assets/
                └── Config.js      <-- editabile, persistente
```

## Uso con docker-compose

```yaml
services:
  govpay:
    image: linkitaly/govpay:3.9.3        # adatta al tag/AS (tomcat11)
    volumes:
      - govpay_home:/etc/govpay
      - ../console/console-static-config.sh:/docker-entrypoint-govpay.d/30-console-static-config.sh:ro
volumes:
  govpay_home:
```

Lo script è già eseguibile (viene lanciato come processo; se il bit `x` si perde è comunque
sicuro perché l'entrypoint lo esegue con `source` e lo script non usa `exit`/`set -e`).

## Note

- Il `Config.js` nel volume dev'essere il file **finale** (senza token `@...@`): bypassa l'installer.
- Gli `addScript('assets/config/...')` interni a Config.js restano relativi e sono serviti dalla
  war (context `/govpay-console`): invariati.
- Per rigenerare il Config.js dal war: cancellalo dal volume e riavvia il container.
- Per disattivare l'override: rimuovi lo script dalla hook dir (i descriptor si possono cancellare
  da `conf/Catalina/localhost/`).
- Path validi per **immagine Tomcat 11** (`CATALINA_HOME=/usr/local/tomcat`,
  `GOVPAY_HOME=/etc/govpay`, `unzip` presente).
