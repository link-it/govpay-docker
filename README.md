# Immagine docker per GovPay

Questo progetto fornisce tutto il necessario per produrre un'ambiente di prova GovPay funzionante, containerizzato in formato Docker. L'ambiente consente di produrre immagini in due modalità:
- **standalone** : in questa modalità l'immagine contiene oltre al gateway anche un database HSQL con persistenza su file, dove vengongono memorizzate le configurazioni e le informazioni elaborate durante l'esercizio.
- **orchestrate** : in questa modalità l'immagine viene preparata in modo da collegarsi ad un database esterno

## Build immagine Docker
Per semplificare il più possibile la preparazione dell'ambiente, sulla root del progetto è presente uno script di shell che si occupa di prepare il buildcontext e di avviare il processo di build con tutti gli argomenti necessari. 
Lo script può essere avviato senza parametri per ottenere il build dell'immagine di default, ossia una immagine in modalità standalone realizzata a partire dalla release binaria disponibile su GitHub.
Lo script di build consente did personalizzare l'immagine prodotta, impostando opportunamente i parametri, come descritti qui di seguito:

```console
Usage build_image.sh [ -t <repository>:<tagname> | <Installer Sorgente> | <Personalizzazioni> | <Avanzate> | -h ]

Options
-t <TAG>       : Imposta il nome del TAG ed il repository locale utilizzati per l'immagine prodotta 
                 NOTA: deve essere rispettata la sintassi <repository>:<tagname>
-h             : Mostra questa pagina di aiuto

Installer Sorgente:
-v <VERSIONE>  : Imposta la versione dell'installer binario da utilizzare per il build (default: 3.6.0)
-l <FILE>      : Usa un'installer binario sul filesystem locale (incompatibile con -j)
-j             : Usa l'installer prodotto dalla pipeline jenkins https://jenkins.link.it/govpay/risultati-testsuite/installer/govpay-installer-<version>.tgz

Personalizzazioni:
-d <TIPO>      : Prepara l'immagine per essere utilizzata su un particolare database  (valori: [ hsql, postgresql, mysql, mariadb, oracle] , default: hsql)
-e <PATH>      : Imposta il path interno utilizzato per i file di configurazione di govpay 
-f <PATH>      : Imposta il path interno utilizzato per i log di govpay

Avanzate:
-i <FILE>      : Usa il template ant.installer.properties indicato per la generazione degli archivi dall'installer
-r <DIRECTORY> : Inserisce il contenuto della directory indicata, tra i contenuti custom 
-w <DIRECTORY> : Esegue tutti gli scripts widlfly contenuti nella directory indicata

```

## Avvio immagine Docker

Una volta eseguito il build dell'immagine tramite lo script fornito, l'immagine puo essere eseguita con i normali comandi di run docker:
```shell
./build_image.sh 
docker run \
  -v ~/govpay_log:/var/log/govpay -v ~/govpay_conf:/etc/govpay \
  -e GOVPAY_POP_DB_SKIP=false \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 8445:8445 \
linkitaly/govpay:3.6.0

```

In modalità orchestrate al termine delle operazioni di build, lo script predispone uno scenario di test avviabile con docker-compose, all'interno della directory **"compose"**. Ad esempio lo scenario di test per una immagine preparata per database PostgreSQL, può quindi essere avviato come segue:

```
./build_image.sh -d postgresql
cp ./postgresql-42.4.0.jar compose/
cd compose
docker-compose up
```

## Driver JDBC
Tutte le immagini create in modalità orchestrate sono distribuite senza il necessario driver JDBC, che quindi deve essere obbligatoriamente fornito all'avvio tramite un volume montato sul container; inoltre il path sul filesystem del container, da cui leggere il driver deve essere specificato tramite una delle segeuntei variabili'dambiente:

* GOVPAY_POSTGRESQL_JDBC_PATH
* GOVPAY_MYSQL_JDBC_PATH
* GOVPAY_MARIADB_JDBC_PATH
* GOVPAY_ORACLE_JDBC_PATH

Ad esempio: 

```shell
docker run \
  -v ~/govpay_log:/var/log/govpay -v ~/govpay_conf:/etc/govpay \
  -v $PWD/postgresql-42.4.0.jar:/tmp/postgresql-42.4.0.jar \
  -e GOVPAY_POSTGRESQL_JDBC_PATH=/tmp/postgresql-42.4.0.jar \
  -e GOVPAY_POP_DB_SKIP=false \
  -p 8080:8080 \
  -p 8443:8443 \
  -p 8445:8445 \
linkitaly/govpay:3.6.0

```

## Informazioni di Base

A prescindere dalla modalità di costruzione dell'immagine, vengono utilizzati i seguenti path:
- **/etc/govpay** path le properties di configurazione (riconfigurabile al momento del build). 
- **/var/log/govpay** path dove vengono scritti i files di log (riconfigurabile al momento del build).

Se l'immagine è stata prodotta in modalità standalone: 
- **/opt/hsqldb-2.6.1/hsqldb/database** database interno HSQL 

si possono rendere queste location persistenti, montando devi volumi su queste directory.
 

All'avvio del container, sia in modalià standalone che in modaliatà orchestrate, vengono eseguite delle verifiche sul database per assicurarne la raggiungibilità ed il corretto popolamento; in caso venga riconosciuto che il database non è popolato, vengono utilizzatti gli scripts SQL interni, per avviare l'inizializzazione.
Se si vuole esaminare gli script o utilizzarli manualmente, è possibile recuperarli dall'immagine in una delle directory standard:
- **/opt/hsql**
- **/opt/postgresql** 
- **/opt/mysql** 
- **/opt/mariadb** 
- **/opt/oracle**

```shell
CONTAINER_ID=$(docker create linkitaly/govpay:3.6.0_postgres)
docker cp ${CONTAINER_ID}:/opt/postgresql .
```

Le immagini prodotte utilizzano come application server ospite WildFly 18.0.1.Final, in ascolto sia in protocollo _**AJP**_ sulla porta **8009** sia in _**HTTP**_ su 3 porte per gestire il traffico nelle seguenti modalità:
- **8080**: Listener HTTP ingresso (max-thread-pool default: 100)
- **8443**: Listener HTTPS (max-thread-pool default: 100)
- **8445**: Listener HTTPS con mutua autenticazione obbligatoria (max-thread-pool default: 100)

Tutte queste porte sono esposte dal container e per accedere ai servizi dall'esterno, si devono pubblicare al momento dell'avvio del immagine. 
La dashboard di monitoraggio e configurazione è disponibile alla URL:

```
 http://<indirizzo IP>:8080/govpay/backend/gui/backoffice
```
L'account di default per l'accesso:
 * username: gpadmin
 * password: Password1!

### Connettività HTTPS e keystores
I connettori HTTPS configurati all'avvio necessitano di un certificato da esporre, per questo all'interno dell'immagine è presente un keystore contenente un certificato selfsigned al path ${JBOSS_HOME}/standalone/configuration/testkeystore.jks.
Il keystore è utilizzabile solamente a scopo di test, mentre in situazioni reali è preferibile sostiturlo con un keystore contenente chiave primaria e certificato firmato da una Certification Authority pubblica. Per farlo è sufficiente montare sul container il path contenete il keystore da utilizzare e popolare le segeunti variabili d'ambiente:

* WILDFLY_KEYSTORE: Path al keystore contenente chiave primaria e relativo certificato da utilizzare sui connettori HTTPS
* WILDFLY_KEYSTORE_PASSWORD: Password di accesso al keystore 
* WILDFLY_KEYSTORE_KEY_PASSWORD: Password della chiave privata (se non specificata viene utilizzato il valore di WILDFLY_KEYSTORE_PASSWORD)
* WILDFLY_KEYSTORE_TIPO: formato del file keystore (valori ammessi: JKS,PKCS12 - default: JKS)

Il connettore HTTPS con mutua autenticazione necessita anche di un truststore contenente i certificati delle CA da utilizzare per il trust dei certificati client. Per configurarlo sul container è sufficiente montare sul container il path contenete il keystore da utilizzare e popolare le segeunti variabili d'ambiente:

* WILDFLY_TRUSTSTORE: Path al truststore contenente i certificati CA da utilizzare per il trust sul connttore HTTPS con mutua autenticazione
* WILDFLY_TRUSTSTORE_PASSWORD: Password di accesso al truststore 
* WILDFLY_TRUSTSTORE_TIPO: formato del file truststore (valori ammessi: JKS,PKCS12 - default: JKS)

## Personalizzazioni
Attraverso l'impostazione di alcune variabili d'ambiente note è possibile personalizzare alcuni aspetti del funzionamento del container. Le variabili supportate al momento sono queste:

### Controlli all'avvio del container

A runtime il container esegue i controlli di: raggiungibilita del database, di popolamento del database e di avvio di govpay. Questi controlli possono essere abilitati o meno impostando le seguenti variabili d'ambiente:

* GOVPAY_LIVE_DB_CHECK_SKIP: Salta il controllo di raggiungibilità dei server database allo startup (default: FALSE)

* GOVPAY_READY_DB_CHECK_SKIP: Salta il controllo di popolamento dei database allo startup (default: FALSE)

* GOVPAY_STARTUP_CHECK_SKIP: Salta il controllo di avvio di govpay allo startup (default: FALSE)

* GOVPAY_POP_DB_SKIP: Salta il popolamento automatico delle tabelle (default: TRUE)

E' possibile personalizzare il ciclo di controllo di raggiungibilità dei server database impostando le seguenti variabili d'ambiente:
* GOVPAY_LIVE_DB_CHECK_FIRST_SLEEP_TIME: tempo di attesa, in secondi, prima di effettuare la prima verifica (default: 0)
* GOVPAY_LIVE_DB_CHECK_SLEEP_TIME: tempo di attesa, in secondi, tra un tentativo di connessione faallito ed il successivo (default: 2)
* GOVPAY_LIVE_DB_CHECK_MAX_RETRY: Numero massimo di tentativi di connessione (default: 30)
* GOVPAY_LIVE_DB_CHECK_CONNECT_TIMEOUT: Timeout di connessione al server, in secondi (default: 5)


E' possibile personalizzare il ciclo di controllo di popolamento dei server database impostando le seguenti variabili d'ambiente:
* GOVPAY_READY_DB_CHECK_SLEEP_TIME: tempo di attesa, in secondi, tra un tentativo di connessione faallito ed il successivo (default: 2)
* GOVPAY_READY_DB_CHECK_MAX_RETRY: Numero massimo di tentativi di connessione (default: 5)


E' possibile personalizzare il ciclo di controllo di avvio di govpay impostando le seguenti variabili d'ambiente:
* GOVPAY_STARTUP_CHECK_FIRST_SLEEP_TIME: tempo di attesa, in secondi, prima di effettuare il primo controllo (default: 20)
* GOVPAY_STARTUP_CHECK_SLEEP_TIME: tempo di attesa, in secondi, tra un controllo fallito ed il successivo  (default: 5)
* GOVPAY_STARTUP_CHECK_MAX_RETRY: Numero massimo di controlli effettuati (default: 60)

### Connessione a database esterni 

* GOVPAY_DB_SERVER: nome dns o ip address del server database (obbligatorio in modalita orchestrate)
* GOVPAY_DB_NAME: Nome del database (obbligatorio in modalita orchestrate)
* GOVPAY_DB_USER: username da utiliizare per l'accesso al database (obbligatorio in modalita orchestrate)
* GOVPAY_DB_PASSWORD: password di accesso al database (obbligatorio in modalita orchestrate)


#### Connessione a database Oracle ####
Quando ci si connette ad un database esterno Oracle devono essere indicate anche le seguenti variabili d'ambiente

* GOVPAY_ORACLE_JDBC_URL_TYPE: indica se connettersi ad un SID o ad un ServiceName Oracle (default: SERVICENAME)

### Pooling connessioni database

* GOVPAY_MAX_POOL: Numero massimo di connessioni stabilite(default: 50)
* GOVPAY_MIN_POOL: Numero minimo di connessioni stabilite (default: 2)
* GOVPAY_DS_BLOCKING_TIMEOUT: Tempo di attesa, im millisecondi, per una connessione libera dal pool (default: 30000)
* GOVPAY_DS_IDLE_TIMEOUT: Tempo trascorso, in minuti, prima di eliminare una connessione dal pool per inattivita (default: 5)
* GOVPAY_DS_CONN_PARAM: parametri JDBC aggiuntivi (default: vuoto)
* GOVPAY_DS_PSCACHESIZE: dimensione della cache usata per le prepared statements (default: 20)

### Pooling connessioni Http
I listener HTTP configurati sul wildfly possono 
* WILDFLY_AJP_WORKER-MAX-THREADS: impostazione del numero massimo di thread, sul worker del listener AJP, (default: 50)
* WILDFLY_HTTP_WORKER-MAX-THREADS: impostazione del numero massimo di thread, sul worker del listener HTTP, (default: 20)
* WILDFLY_HTTPS_WORKER-MAX-THREADS: impostazione del numero massimo di thread, sul worker del listener HTTPS, (default: 100)
* WILDFLY_HTTPS_CLIENTAUTH_WORKER-MAX-THREADS: impostazione del numero massimo di thread, sul worker del listener HTTPS con mutua autenticazione, (default: 100)