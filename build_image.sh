#!/bin/bash

function printHelp() {
echo "Usage $(basename $0) [ -t <repository>:<tagname> | <Installer Sorgente> | <Personalizzazioni> | <Avanzate> | -h ]"
echo 
echo "Options
-t <TAG>       : Imposta il nome del TAG ed il repository locale utilizzati per l'immagine prodotta 
                 NOTA: deve essere rispettata la sintassi <repository>:<tagname>
-h             : Mostra questa pagina di aiuto

Installer Sorgente:
-v <VERSIONE>  : Imposta la versione dell'installer binario da utilizzare per il build (default: ${LATEST_GOVPAY_RELEASE})
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
"
}

DOCKERBIN="$(which docker)"
if [ -z "${DOCKERBIN}" ]
then
   echo "Impossibile trovare il comando \"docker\""
   exit 2 
fi



TAG=
VER=
DB=
LOCALFILE=
TEMPLATE=
ARCHIVI=
CUSTOM_MANAGER=
CUSTOM_MANAGER=
CUSTOM_WIDLFLY_CLI=

LATEST_LINK="$(curl -qw '%{redirect_url}\n' https://github.com/link-it/govpay/releases/latest 2> /dev/null)"
LATEST_GOVPAY_RELEASE="${LATEST_LINK##*/}"

while getopts "ht:v:d:jl:i:a:r:m:w:o:e:f:" opt; do
  case $opt in
    t) TAG="$OPTARG"; NO_COLON=${TAG//:/}
      [ ${#TAG} -eq ${#NO_COLON} -o "${TAG:0:1}" == ':' -o "${TAG:(-1):1}" == ':' ] && { echo "Il tag fornito \"$TAG\" non utilizza la sintassi <repository>:<tagname>"; exit 2; } ;;
    v) VER="$OPTARG"  ;;
    d) DB="${OPTARG}"; case "$DB" in hsql);;postgresql);;mysql);;mariadb);;oracle);;*) echo "Database non supportato: $DB"; exit 2;; esac ;;
    l) LOCALFILE="$OPTARG"
        [ ! -f "${LOCALFILE}" ] && { echo "Il file indicato non esiste o non e' raggiungibile [${LOCALFILE}]."; exit 3; } 
       ;;
    j) JENKINS="true"
        [ -n "${LOCALFILE}" ] && { echo "Le opzioni -j e -l sono incompatibili. Impostare solo una delle due."; exit 2; }
       ;;
    i) TEMPLATE="${OPTARG}"
        [ ! -f "${TEMPLATE}" ] && { echo "Il file indicato non esiste o non e' raggiungibile [${TEMPLATE}]."; exit 3; } 
        ;;
    r) CUSTOM_RUNTIME="${OPTARG}"
        [ ! -d "${CUSTOM_RUNTIME}" ] && { echo "la directory indicata non esiste o non e' raggiungibile [${CUSTOM_RUNTIME}]."; exit 3; }
        [ -z "$(ls -A ${CUSTOM_RUNTIME})" ] && { echo "la directory [${CUSTOM_RUNTIME}] e' vuota.";  }
        ;;
    w) CUSTOM_WIDLFLY_CLI="${OPTARG}"
        [ ! -d "${CUSTOM_WIDLFLY_CLI}" ] && { echo "la directory indicata non esiste o non e' raggiungibile [${CUSTOM_WIDLFLY_CLI}]."; exit 3; }
        [ -z "$(ls -A ${CUSTOM_WIDLFLY_CLI})" ] && { echo "la directory [${CUSTOM_WIDLFLY_CLI}] e' vuota.";  }
        ;;
    e) CUSTOM_GOVPAY_HOME="${OPTARG}" ;;
    f) CUSTOM_GOVPAY_LOG="${OPTARG}" ;;
    h) printHelp
       exit 0
       ;;
    \?)
      echo "Opzione non valida: -$opt"
      exit 1
      ;;
  esac
done


rm -rf buildcontext
mkdir -p buildcontext/
cp -fr commons buildcontext/

DOCKERBUILD_OPT=()
DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "govpay_fullversion=${VER:-${LATEST_GOVPAY_RELEASE}}")
[ -n "${TEMPLATE}" ] &&  cp -f "${TEMPLATE}" buildcontext/commons/
[ -n "${CUSTOM_GOVPAY_HOME}" ] && DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "govpay_home=${CUSTOM_GOVPAY_HOME}")
[ -n "${CUSTOM_GOVPAY_LOG}" ] && DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "govpay_log=${CUSTOM_GOVPAY_LOG}")
if [ -n "${CUSTOM_RUNTIME}" ]
then
  cp -r ${CUSTOM_RUNTIME}/ buildcontext/runtime
  DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "runtime_custom_archives=runtime")
fi

# Build immagine installer
if [ -n "${JENKINS}" ]
then
  INSTALLER_DOCKERFILE="govpay/Dockerfile.jenkins"
elif [ -n "${LOCALFILE}" ]
then
  INSTALLER_DOCKERFILE="govpay/Dockerfile.daFile"
  cp -f "${LOCALFILE}" buildcontext/
else
  INSTALLER_DOCKERFILE="govpay/Dockerfile.github"
fi

if [ -n "${DB}" ]
then
  if [ "${DB}" == 'mariadb' ]
  then
    DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "govpay_database_vendor=mysql")
  else
    DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "govpay_database_vendor=${DB}")
  fi
fi

"${DOCKERBIN}" build "${DOCKERBUILD_OPTS[@]}" \
  -t linkitaly/govpay-installer_${DB:-hsql}:${VER:-${LATEST_GOVPAY_RELEASE}} \
  -f ${INSTALLER_DOCKERFILE} buildcontext
RET=$?
[ ${RET} -eq  0 ] || exit ${RET}
 
if [ "${DB}" == 'mariadb' ]
then
  c=$(( ${#DOCKERBUILD_OPTS[@]} - 1 ))
  unset  DOCKERBUILD_OPTS[$c]
  DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} "govpay_database_vendor=mariadb")
fi
# Build imagine govpay

if [ -z "$TAG" ] 
then
  REPO=linkitaly/govpay
  TAGNAME=${VER:-${LATEST_GOVPAY_RELEASE}}
  
  # mantengo i nomi dei tag compatibili con quelli usati in precedenza
  case "${DB:-hsql}" in
  hsql) TAG="${REPO}:${TAGNAME}" ;;
  postgresql) TAG="${REPO}:${TAGNAME}_postgres" ;;
  *) TAG="${REPO}:${TAGNAME}_${DB}" ;;
  esac
fi

if [ -n "${CUSTOM_WIDLFLY_CLI}" ]
then
  cp -r ${CUSTOM_WIDLFLY_CLI}/ buildcontext/custom_widlfly_cli
  DOCKERBUILD_OPTS=(${DOCKERBUILD_OPTS[@]} '--build-arg' "wildfly_custom_scripts=custom_widlfly_cli")
fi

"${DOCKERBIN}" build "${DOCKERBUILD_OPTS[@]}" \
  --build-arg source_image=linkitaly/govpay-installer_${DB:-hsql} \
  -t "${TAG}" \
  -f govpay/Dockerfile.govpay buildcontext
RET=$?
[ ${RET} -eq  0 ] || exit ${RET}


if [ "${DB:-hsql}" != 'hsql' ]
then
  mkdir -p compose/govpay_{conf,log}
  chmod 777 compose/govpay_{conf,log}

  SHORT=${TAG#*:}
  cat - << EOYAML > compose/docker-compose.yaml
version: '2'
services:
  govpay:
    container_name: govpay_${SHORT}
    image: ${TAG}
    depends_on:
        - database
    ports:
        - 8080:8080
        - 8443:8443
        - 8445:8445
    volumes:
        - ./govpay_log:${CUSTOM_GOVPAY_LOG:-/var/log/govpay}
EOYAML
  if [ "${DB:-hsql}" == 'postgresql' ]
  then
    cat - << EOYAML >> compose/docker-compose.yaml
          # Il driver deve essere compiato manualmente nella directory corrente
        - ./postgresql-42.4.0.jar:/tmp/postgresql-42.4.0.jar 
    environment:
        - GOVPAY_DB_SERVER=pg_govpay_${SHORT}
        - GOVPAY_DB_NAME=govpaydb
        - GOVPAY_DB_USER=govpay
        - GOVPAY_DB_PASSWORD=govpay
        - GOVPAY_POSTGRESQL_JDBC_PATH=/tmp/postgresql-42.4.0.jar 
        - GOVPAY_POP_DB_SKIP=false
  database:
    container_name: pg_govpay_${SHORT}
    image: postgres:13
    environment:
        - POSTGRES_DB=govpaydb
        - POSTGRES_USER=govpay
        - POSTGRES_PASSWORD=govpay
EOYAML
    echo 
    echo "ATTENZIONE: Copiare il driver jdbc postgresql 'postgresql-42.4.0.jar' dentro la directory './compose/'"
    echo
    echo "ATTENZIONE: Copiare il driver jdbc postgresql 'postgresql-42.4.0.jar' dentro la directory './compose/'" > compose/README.first
  elif [ "${DB:-hsql}" == 'mariadb' ]
  then
    cat - << EOYAML >> compose/docker-compose.yaml
        # Il driver deve essere compiato manualmente nella directory corrente
        - ./mariadb-java-client-3.0.6.jar:/tmp/mariadb-java-client-3.0.6.jar 
    environment:
        - GOVPAY_DB_SERVER=my_govpay_${SHORT}
        - GOVPAY_DB_NAME=govpaydb
        - GOVPAY_DB_USER=govpay
        - GOVPAY_DB_PASSWORD=govpay
        - GOVPAY_MARIADB_JDBC_PATH=/tmp/mariadb-java-client-3.0.6.jar
        - GOVPAY_POP_DB_SKIP=false
  database:
    container_name: my_govpay_${SHORT}
    image: mariadb:10.6
    environment:
      - MARIADB_DATABASE=govpaydb
      - MARIADB_USER=govpay
      - MARIADB_PASSWORD=govpay
      - MARIADB_ROOT_PASSWORD=my-secret-pw
    ports:
       - 3306:3306
EOYAML
    echo 
    echo "ATTENZIONE: Copiare il driver jdbc Mariadb 'mariadb-java-client-3.0.6.jar' dentro la directory './compose/'"
    echo
    echo "ATTENZIONE: Copiare il driver jdbc Mariadb 'mariadb-java-client-3.0.6.jar' dentro la directory './compose/'" > compose/README.first
  elif [ "${DB:-hsql}" == 'mysql' ]
  then
    cat - << EOYAML >> compose/docker-compose.yaml
        # Il driver deve essere compiato manualmente nella directory corrente
        - ./mysql-connector-java-8.0.29.jar:/tmp/mysql-connector-java-8.0.29.jar 
    environment:
        - GOVPAY_DB_SERVER=my_govpay_${SHORT}
        - GOVPAY_DB_NAME=govpaydb
        - GOVPAY_DB_USER=govpay
        - GOVPAY_DB_PASSWORD=govpay
        - GOVPAY_MYSQL_JDBC_PATH=/tmp/mysql-connector-java-8.0.29.jar
        - GOVPAY_POP_DB_SKIP=false
  database:
    container_name: my_govpay_${SHORT}
    image: mysql:8.0
    environment:
      - MYSQL_DATABASE=govpaydb
      - MYSQL_USER=govpay
      - MYSQL_PASSWORD=govpay
      - MYSQL_ROOT_PASSWORD=my-secret-pw
    ports:
       - 3306:3306
EOYAML
    echo 
    echo "ATTENZIONE: Copiare il driver jdbc Mysql 'mysql-connector-java-8.0.29.jar' dentro la directory './compose/'"
    echo
    echo "ATTENZIONE: Copiare il driver jdbc Mysql 'mysql-connector-java-8.0.29.jar' dentro la directory './compose/'" > compose/README.first


  elif [ "${DB:-hsql}" == 'oracle' ]
  then
    mkdir -p compose/oracle_startup
    mkdir compose/ORADATA
    chmod 777 compose/ORADATA
    cat - << EOSQL > compose/oracle_startup/create_db_and_user.sql
alter session set container = GOVPAYPDB;
-- USER GOVPAY
CREATE USER "GOVPAY" IDENTIFIED BY "GOVPAY"  
DEFAULT TABLESPACE "USERS"
TEMPORARY TABLESPACE "TEMP";
ALTER USER "GOVPAY" QUOTA UNLIMITED ON "USERS";
GRANT "CONNECT" TO "GOVPAY" ;
GRANT "RESOURCE" TO "GOVPAY" ;
EOSQL

    cat - << EOYAML >> compose/docker-compose.yaml
        # Il driver deve essere compiato manualmente nella directory corrente
        - ./ojdbc10.jar:/tmp/ojdbc10.jar 
    environment:
        - GOVPAY_DB_SERVER=or_govpay_${SHORT}
        - GOVPAY_DB_NAME=GOVPAYPDB
        - GOVPAY_DB_USER=GOVPAY
        - GOVPAY_DB_PASSWORD=GOVPAY
        - GOVPAY_ORACLE_JDBC_PATH=/tmp/ojdbc10.jar
        - GOVPAY_ORACLE_JDBC_URL_TYPE=servicename
        - GOVPAY_POP_DB_SKIP=false
        # il container oracle puo impiegare anche 20 minuti ad avviarsi
        - GOVPAY_LIVE_DB_CHECK_MAX_RETRY=120
        - GOVPAY_READY_DB_CHECK_MAX_RETRY=600
  database:
    container_name: or_govpay_${SHORT}
    image: container-registry.oracle.com/database/enterprise:19.3.0.0
    shm_size: 2g
    environment:
      - ORACLE_PDB=GOVPAYPDB
      - ORACLE_PWD=123456
    volumes:
       - ./ORADATA:/opt/oracle/oradata
       - ./oracle_startup:/opt/oracle/scripts/startup
    ports:
       - 1521:1521
EOYAML
    echo 
    echo "ATTENZIONE: Copiare il driver jdbc Oracle 'ojdbc10.jar' dentro la directory './compose/'"
    echo
    echo "ATTENZIONE: Copiare il driver jdbc Oracle 'ojdbc10.jar' dentro la directory './compose/'" > compose/README.first
  fi
fi
exit 0
