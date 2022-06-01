#!/bin/bash -x
CLI_SCRIPT_FILE="$1"  
CLI_SCRIPT_CUSTOM_DIR="${JBOSS_HOME}/standalone/configuration/custom_cli"

case "${GOVPAY_DB_TYPE:-hsql}" in
postgresql)
    GOVPAY_DRIVER_JDBC="/opt/postgresql-${POSTGRES_JDBC_VERSION}.jar"
    GOVPAY_DS_DRIVER_CLASS='org.postgresql.Driver'
    GOVPAY_DS_VALID_CONNECTION_SQL='SELECT 1;'

    # Le variabili DATASOURCE_CONN_PARAM, DATASOURCE_{CONF,TRAC,STAT}_CONN_PARAM, sono impostate dallo standalone_wrapper.sh
    JDBC_RUN_URL='jdbc:postgresql://\${env.GOVPAY_DB_SERVER}/\${env.GOVPAY_DB_NAME}\${env.DATASOURCE_CONN_PARAM:}'
    JDBC_RUN_AUTH="/subsystem=datasources/data-source=govpay: write-attribute(name=user-name, value=\${env.GOVPAY_DB_USER})
/subsystem=datasources/data-source=govpay: write-attribute(name=password, value=\${env.GOVPAY_DB_PASSWORD})"

;;
oracle)
    ORACLE_DRIVER_JDBC=
    declare -a lista_jar=( /var/tmp/oracle_custom_jdbc/*.jar )
    if [ ${#lista_jar[@]} -eq 1 -a "${lista_jar[0]}" == '/var/tmp/oracle_custom_jdbc/*.jar' ]
    then
        echo "Driver JDBC oracle non presente"
        #exit 1
    elif [ ${#lista_jar[@]} -eq 1 ]
    then
        # è presente solo un jar: lo utilizzo
        ORACLE_DRIVER_JDBC="${lista_jar[0]}" 
    elif [ ${#lista_jar[@]} -gt 1 ]
    then
        # sono presenti diversi jar: provo a riconoscere la versione e ad usare il più recente 
        ORACLE_DRIVER_JDBC=
        MAX=0
        for j in ${lista_jar[@]}
        do
            JAR_NAME=$(basename $j)
            if [ "${JAR_NAME:0:5}" == 'ojdbc' ]
            then
                OJDBC_VERSION_FULL="${JAR_NAME:5:(-4)}"
                OJDBC_VERSION="${OJDBC_VERSION_FULL%%[._-]*}"
                # skippo ojdbc14 che va bene per java 1.4
                [ ${OJDBC_VERSION} -eq 14 ] && continue
                [ ${OJDBC_VERSION} -gt ${MAX} ] && ORACLE_DRIVER_JDBC=$j && MAX=${OJDBC_VERSION}
            fi
        done
        if [ ${MAX} -eq  0 ]
        then
            # non ho trovato un jar con il nome giusto. Prendo il file con la data piu recente
            MAX=0
            for j in ${lista_jar[@]}
            do
                AGE=$(stat "$j" --printf '%Z')
                [ ${AGE} -gt ${MAX} ] && ORACLE_DRIVER_JDBC=$j && MAX=${AGE}
            done
        fi
    fi
    [ -n "${ORACLE_DRIVER_JDBC}" ] && cp -f ${ORACLE_DRIVER_JDBC} /var/tmp/oracle-jdbc.jar
    GOVPAY_DRIVER_JDBC='/var/tmp/oracle-jdbc.jar'
    GOVPAY_DS_DRIVER_CLASS='oracle.jdbc.OracleDriver'
    GOVPAY_DS_VALID_CONNECTION_SQL='SELECT 1 FROM DUAL'

    # Le variabili ORACLE_JDBC_SERVER_PREFIX ed ORACLE_JDBC_DB_SEPARATOR sono impostate dallo standalone_wrapper.sh
    # Le variabili DATASOURCE_CONN_PARAM, DATASOURCE_{CONF,TRAC,STAT}_CONN_PARAM, sono impostate dallo standalone_wrapper.sh
    JDBC_RUN_URL='jdbc:oracle:thin:@\${env.ORACLE_JDBC_SERVER_PREFIX}\${env.GOVPAY_DB_SERVER}\${env.ORACLE_JDBC_DB_SEPARATOR}\${env.GOVPAY_DB_NAME}\${env.DATASOURCE_CONN_PARAM:}'
    JDBC_RUN_AUTH="/subsystem=datasources/data-source=govpay: write-attribute(name=user-name, value=\${env.GOVPAY_DB_USER})
/subsystem=datasources/data-source=govpay: write-attribute(name=password, value=\${env.GOVPAY_DB_PASSWORD})"

;;
hsql|*)
    GOVPAY_DRIVER_JDBC="opt/hsqldb-${HSQLDB_FULLVERSION}/hsqldb/lib/hsqldb.jar"
    GOVPAY_DS_DRIVER_CLASS='org.hsqldb.jdbc.JDBCDriver'
    GOVPAY_DS_VALID_CONNECTION_SQL='SELECT * FROM (VALUES(1));'

    JDBC_RUN_URL="jdbc:hsqldb:file:/opt/hsqldb-${HSQLDB_FULLVERSION}/hsqldb/database/govpay;shutdown=true"
    JDBC_RUN_AUTH="/subsystem=datasources/data-source=govpay: write-attribute(name=user-name, value=govpay)
/subsystem=datasources/data-source=govpay: write-attribute(name=password, value=govpay)"

;;
esac

cat - << EOCLI >> "${CLI_SCRIPT_FILE}"
embed-server --server-config=standalone.xml --std-out=echo
echo "Carico modulo e driver JDBC per ${GOVPAY_DB_TYPE:-hsql}"
module add --name=${GOVPAY_DB_TYPE:-hsql}Mod --resources=${GOVPAY_DRIVER_JDBC} --dependencies=javax.api,javax.transaction.api --allow-nonexistent-resources
/subsystem=datasources/jdbc-driver=${GOVPAY_DB_TYPE:-hsql}Driver:add(driver-name=${GOVPAY_DB_TYPE:-hsql}Driver, driver-module-name=${GOVPAY_DB_TYPE:-hsql}Mod, driver-class-name=${GOVPAY_DS_DRIVER_CLASS})
stop-embedded-server
embed-server --server-config=standalone.xml --std-out=echo
echo "Preparo datasource govpay"
/subsystem=datasources/data-source=govpay: add(jndi-name=java:/govpay,enabled=true,use-java-context=true,use-ccm=true, connection-url="${JDBC_RUN_URL}", driver-name=${GOVPAY_DB_TYPE:-hsql}Driver)
${JDBC_RUN_AUTH}
/subsystem=datasources/data-source=govpay: write-attribute(name=driver-class, value="${GOVPAY_DS_DRIVER_CLASS}")
/subsystem=datasources/data-source=govpay: write-attribute(name=check-valid-connection-sql, value="${GOVPAY_DS_VALID_CONNECTION_SQL}")
/subsystem=datasources/data-source=govpay: write-attribute(name=new-connection-sql, value="${GOVPAY_DS_VALID_CONNECTION_SQL}")
/subsystem=datasources/data-source=govpay: write-attribute(name=validate-on-match, value=true)
/subsystem=datasources/data-source=govpay: write-attribute(name=idle-timeout-minutes,value=\${env.GOVPAY_DS_IDLE_TIMEOUT:5})
/subsystem=datasources/data-source=govpay: write-attribute(name=blocking-timeout-wait-millis,value=\${env.GOVPAY_DS_BLOCKING_TIMEOUT:30000})
/subsystem=datasources/data-source=govpay: write-attribute(name=pool-prefill, value=true)
/subsystem=datasources/data-source=govpay: write-attribute(name=prepared-statements-cache-size, value=\${env.GOVPAY_DS_PSCACHESIZE:20})
/subsystem=datasources/data-source=govpay: write-attribute(name=pool-use-strict-min, value=false)
/subsystem=datasources/data-source=govpay: write-attribute(name=min-pool-size, value=\${env.GOVPAY_MIN_POOL:2})
/subsystem=datasources/data-source=govpay: write-attribute(name=max-pool-size, value=\${env.GOVPAY_MAX_POOL:50})
EOCLI


if [ -d "${CLI_SCRIPT_CUSTOM_DIR}" -a -n "$(ls -A ${CLI_SCRIPT_CUSTOM_DIR} 2>/dev/null)" ]
then
    cli=""
	for cli in ${CLI_SCRIPT_CUSTOM_DIR}/*
    do
		echo >> "${CLI_SCRIPT_FILE}"
        cat ${cli} >> "${CLI_SCRIPT_FILE}"
	done
fi

