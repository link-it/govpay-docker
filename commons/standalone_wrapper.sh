#!/bin/bash
exec 6<> /tmp/standalone_wrapper_debug.log
exec 2>&6
set -x

## Const
GOVPAY_STARTUP_CHECK_SKIP=${GOVPAY_STARTUP_CHECK_SKIP:=FALSE}
GOVPAY_STARTUP_CHECK_FIRST_SLEEP_TIME=${GOVPAY_STARTUP_CHECK_FIRST_SLEEP_TIME:=20}
GOVPAY_STARTUP_CHECK_SLEEP_TIME=${GOVPAY_STARTUP_CHECK_SLEEP_TIME:=5}
GOVPAY_STARTUP_CHECK_MAX_RETRY=${GOVPAY_STARTUP_CHECK_MAX_RETRY:=60}

declare -r JVM_PROPERTIES_FILE='/etc/wildfly/wildfly.properties'
declare -r ENTRYPOINT_D='/docker-entrypoint-widlflycli.d/'
declare -r CUSTOM_INIT_FILE="${JBOSS_HOME}/standalone/configuration/custom_wildlfy_init"


    
case "${GOVPAY_DB_TYPE:-hsql}" in
postgresql|oracle)

    #
    # Sanity check variabili minime attese
    #
    if [ -n "${GOVPAY_DB_SERVER}" -a -n  "${GOVPAY_DB_USER}" -a -n "${GOVPAY_DB_PASSWORD}" -a -n "${GOVPAY_DB_NAME}" ] 
    then
            echo "INFO: Sanity check variabili ... ok."
    else
        echo "FATAL: Sanity check variabili ... fallito."
        echo "FATAL: Devono essere settate almeno le seguenti variabili:
GOVPAY_DB_SERVER: ${GOVPAY_DB_SERVER}
GOVPAY_DB_NAME: ${GOVPAY_DB_NAME}
GOVPAY_DB_USER: ${GOVPAY_DB_USER}
GOVPAY_DB_PASSWORD: ${GOVPAY_DB_NAME:+xxxxx}
"
        exit 1
    fi
    if [ "${GOVPAY_DB_TYPE:-hsql}" == 'oracle' ]
    then
        if [ -z "${GOVPAY_ORACLE_JDBC_PATH}" -o ! -f "${GOVPAY_ORACLE_JDBC_PATH}" ]
        then
            echo "FATAL: Sanity check variabili ... fallito."
            echo "FATAL: Il path al driver jdbc oracle, non è stato indicato o non è leggibile: [GOVPAY_ORACLE_JDBC_PATH=${GOVPAY_ORACLE_JDBC_PATH}] "
            exit 1
        fi
        if [ "${GOVPAY_ORACLE_JDBC_URL_TYPE^^}" != 'SERVICENAME' -a "${GOVPAY_ORACLE_JDBC_URL_TYPE^^}" != 'SID' ]
        then
            echo "FATAL: Sanity check variabili ... fallito."
            echo "FATAL: Valore non consentito per la variabile GOVPAY_ORACLE_JDBC_URL_TYPE: [GOVPAY_ORACLE_JDBC_URL_TYPE=${GOVPAY_ORACLE_JDBC_URL_TYPE}]."
            echo "       Valori consentiti: [ servicename , sid ]"
            exit 1
        fi
    fi
    # Setting valori di Default per i datasource GOVPAY


    # Settaggio Valori per i parametri dei datasource GOVPAY

    ## parametri di connessione URL JDBC (default vuoto)
    [ -n "${GOVPAY_DS_CONN_PARAM}" ] &&  export DATASOURCE_CONN_PARAM="?${GOVPAY_DS_CONN_PARAM}"


    case "${GOVPAY_DB_TYPE:-hsql}" in
    postgresql)
        export GOVPAY_DRIVER_JDBC="/opt/postgresql-${POSTGRES_JDBC_VERSION}.jar"
        export GOVPAY_DS_DRIVER_CLASS='org.postgresql.Driver'
        export GOVPAY_DS_VALID_CONNECTION_SQL='SELECT 1;'
        export GOVPAY_HYBERNATE_DIALECT=org.hibernate.dialect.PostgreSQLDialect
    ;;
    oracle)
        export GOVPAY_DRIVER_JDBC="${JBOSS_HOME}/modules/oracleMod/main/oracle-jdbc.jar"
        export GOVPAY_DS_DRIVER_CLASS='oracle.jdbc.OracleDriver'
        export GOVPAY_DS_VALID_CONNECTION_SQL='SELECT 1 FROM DUAL'
        export GOVPAY_HYBERNATE_DIALECT=org.hibernate.dialect.Oracle10gDialect
        rm -rf "${GOVPAY_DRIVER_JDBC}"
        cp "${GOVPAY_ORACLE_JDBC_PATH}"  "${GOVPAY_DRIVER_JDBC}"

        if [ "${GOVPAY_ORACLE_JDBC_URL_TYPE^^}" != 'SID' ] 
        then
            export ORACLE_JDBC_SERVER_PREFIX='//'
            export ORACLE_JDBC_DB_SEPARATOR='/'
        else
            export ORACLE_JDBC_SERVER_PREFIX=''
            export ORACLE_JDBC_DB_SEPARATOR=':'
        fi
    ;;
    esac
;;
hsql|*)
    export GOVPAY_DRIVER_JDBC="/opt/hsqldb-${HSQLDB_FULLVERSION}/hsqldb/lib/hsqldb-jdk8.jar"
    export GOVPAY_DS_DRIVER_CLASS='org.hsqldb.jdbc.JDBCDriver'
    export GOVPAY_DS_VALID_CONNECTION_SQL='SELECT * FROM (VALUES(1));'
    export GOVPAY_HYBERNATE_DIALECT=org.hibernate.dialect.HSQLDialect
esac


#
# Startup
#

# Impostazione Dinamica dei limiti di memoria per container
export JAVA_OPTS="$JAVA_OPTS -XX:MaxRAMPercentage=${MAX_JVM_PERC:-80.0}"


# Inizializzazione del database
${JBOSS_HOME}/bin/initgovpay.sh || { echo "FATAL: Database non inizializzato."; exit 1; }

# Eventuali inizializzazioni custom widfly
if [ -d "${ENTRYPOINT_D}" -a ! -f ${CUSTOM_INIT_FILE} ]
then
    local f
	for f in ${ENTRYPOINT_D}/*
    do
		case "$f" in
			*.sh)
				if [ -x "$f" ]; then
					echo "INFO: Customizzazioni ... eseguo $f"
					"$f"
				else
					echo "INFO: Customizzazioni ... eseguo $f"
					. "$f"
				fi
				;;
			*.cli)
                echo "INFO: Customizzazioni ... eseguo $f"; 
                ${JBOSS_HOME}/bin/jboss-cli.sh --file=$f
                ;;
			*) echo "INFO: Customizzazioni ... ignoro $f" ;;
		esac
		echo
	done
    touch ${CUSTOM_INIT_FILE}
fi

# Azzero un'eventuale log di startup precedente (utile in caso di restart)
> ${GOVPAY_LOGDIR}/govpay_startup.log

# Forzo file di un eventuale file di properties jvm da passare all'avvio
if [ -f ${JVM_PROPERTIES_FILE} ]
then
    declare -a CMDLINARGS
    SKIP=0
    FOUND=0
    for prop in $@
    do
        [ $SKIP -eq 1 ] && SKIP=0 && continue
        if [ "$prop" == '-p' ]
        then
            CMDLINARGS+=("-p")
            CMDLINARGS+=("${JVM_PROPERTIES_FILE}")
            SKIP=1
            FOUND=1
        elif [ "${prop%%=*}" == '--properties' ]
        then
            CMDLINARGS+=("--properties=${JVM_PROPERTIES_FILE}")
            FOUND=1
        else
            CMDLINARGS+=($prop)
        fi
    done
    [ $FOUND -eq 0 ] && CMDLINARGS+=("--properties=${JVM_PROPERTIES_FILE}")
    ${JBOSS_HOME}/bin/standalone.sh ${CMDLINARGS[@]} &
else
    ${JBOSS_HOME}/bin/standalone.sh $@ &
fi

PID=$!
trap "kill -TERM $PID; export NUM_RETRY=${GOVPAY_STARTUP_CHECK_MAX_RETRY};" TERM INT


if [ "${GOVPAY_STARTUP_CHECK_SKIP}" == "FALSE" ]
then

	/bin/rm -f  /tmp/govpay_ready
	echo "INFO: Avvio di GovPay ... attendo"
	sleep ${GOVPAY_STARTUP_CHECK_FIRST_SLEEP_TIME}s
	GOVPAY_READY=1
	NUM_RETRY=0
	while [ ${GOVPAY_READY} -ne 0 -a ${NUM_RETRY} -lt ${GOVPAY_STARTUP_CHECK_MAX_RETRY} ]
	do
        HTTP_CODE=$(curl -s -w '%{http_code}' -u 'gpadmin:Password1!' -o /tmp/check-db.json http://localhost:8082/govpay/backend/api/backoffice/rs/basic/v1/sonde/check-db)
        [ "${HTTP_CODE}" == "200" ]
		GOVPAY_READY=$?
		NUM_RETRY=$(( ${NUM_RETRY} + 1 ))
		if [  ${GOVPAY_READY} -ne 0 ]
                then
			echo "INFO: Avvio di GovPay ... attendo"
			sleep ${GOVPAY_STARTUP_CHECK_SLEEP_TIME}s
		fi
	done

	if [ ${NUM_RETRY} -eq ${GOVPAY_STARTUP_CHECK_MAX_RETRY} ]
	then
		echo "FATAL: Avvio di GovPay ... NON avviato dopo $((${GOVPAY_STARTUP_CHECK_SLEEP_TIME=} * ${GOVPAY_STARTUP_CHECK_MAX_RETRY})) secondi"
		kill -15 ${PID}
	else
		touch /tmp/govpay_ready
		echo "INFO: Avvio di Govpay ... GovPay avviato"
	fi
else
		touch /tmp/govpay_ready
fi



wait $PID
wait $PID
EXIT_STATUS=$?

echo "INFO: GovPay arrestato"
exec 6>&-

exit $EXIT_STATUS
