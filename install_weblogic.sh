#!/bin/sh
#Nombre:      install_webligic.sh
#Descripcion: Installation WeblogicServer 11g 
#Fecha:       15/01/2018
#By:          J.J.CH.

#Creacion de usuario y HOME_INIT de oracle
#-------------------------------------------------------------
chmod a+xr /u01/home/app && \
useradd -b /u01/home/app -m -s /bin/bash oracle 

#Descomprimir Archivos
#-------------------------------------------------------------
cd $INSTALL_PATH
tar -xvf files-weblogic.tar

#Instalacion de JROCKIT
#-------------------------------------------------------------
cd $HOME_INIT/soft/;
tar -xzvf jrockit-jdk1.6.0_24-R28.1.3-4.0.1.tar.gz
echo "JROCKIT INSTALADO"

#Configuraciones al sistema operativo  
#-------------------------------------------------------------
sed -i '/.*EOF/d' /etc/security/limits.conf 
echo "* soft nofile 16384" >> /etc/security/limits.conf 
echo "* hard nofile 16384" >> /etc/security/limits.conf  
echo "# EOF"  >> /etc/security/limits.conf


# Change the kernel parameters that need changing.
echo "net.core.rmem_max=4192608" >> $HOME_INIT/.sysctl.conf 
echo "net.core.wmem_max=4192608" >> $HOME_INIT/.sysctl.conf
sysctl -e -p $HOME_INIT/.sysctl.conf

echo "CREACION DE ARCHIVO SILENT"
#Creacion de archivo silent.xml y silent.rps
#----------------------------------------------------------------

cat > $INSTALL_PATH/silent.xml <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<bea-installer> 
  <input-fields>
    <data-value name="BEAHOME" value="$BEA_HOME" />
    <data-value name="USER_WL_HOME" value="$WL_HOME" />
    <data-value name="COMPONENT_PATHS" value="WebLogic Server/Core Application Server|WebLogic Server/Administration Console|WebLogic Server/Configuration Wizard and Upgrade Framework|WebLogic Server/Web 2.0 HTTP Pub-Sub Server|WebLogic Server/WebLogic JDBC Drivers|WebLogic Server/Third Party JDBC Drivers|WebLogic Server/WebLogic Server Clients|WebLogic Server/WebLogic Web Server Plugins|WebLogic Server/UDDI and Xquery Support" />
    <data-value name="INSTALL_NODE_MANAGER_SERVICE" value="yes" />
    <data-value name="INSTALL_SHORTCUT_IN_ALL_USERS_FOLDER" value="no"/>
    <data-value name="LOCAL_JVMS" value="$JVMS"/>
  </input-fields>
</bea-installer>
EOF

###CREACION DE DOMINIO MODO CLUSTER
#----------------------------------------------------------------

cat > $INSTALL_PATH/silent_domain.rsp <<EOF

read template from "${WL_HOME}/common/templates/domains/wls.jar";

set JavaHome "$JVMS"; //Set JDK to use

set ServerStartMode "prod"; //production mode or development mode

//To create a Admin server find it from wls template
find Server "AdminServer" as AdminServer;
set AdminServer.ListenAddress "";
set AdminServer.ListenPort "${ADMIN_PORT}";

//use templates default weblogic user
find User "${USER_WL}" as u1;
set u1.password "${PASS_WL}";

write domain to "${DOMAIN_PATH}/${DOMAIN_NAME}"; 

close template;
EOF

cat $INSTALL_PATH/silent_domain.rsp

#ASIGNACION PERMISOS ORACLE
#---------------------------------------------------------------
chown -Rf oracle:oracle /u01

###SETTING DE VARIABLES EN CUENTA ORACLE Y SUBRROGAR A USUARIO ORACLE
#----------------------------------------------------------------
sudo -u oracle whoami
export JAVA_HOME=/u01/home/app/soft/jrockit-jdk1.6.0_24-R28.1.3-4.0.1
export PATH=$JAVA_HOME/bin:$PATH

#INSTALACION DE BINIARIOS EJECUTABLES WL
#---------------------------------------------------------------

cd $HOME_INIT/soft
java -jar $WLS_PKG -mode=silent -silent_xml=$INSTALL_PATH/silent.xml

#CREACION DEL DOMINIO
#---------------------------------------------------------------

$WL_HOME/common/bin/config.sh -mode=silent -silent_script=$INSTALL_PATH/silent_domain.rsp

#CORREGIR PERMISOS
#---------------------------------------------------------------
sudo -u oracle whoami

#ELIMINAR ARCHIVOS INSTALACION
#---------------------------------------------------------------

rm $WLS_PKG $INSTALL_PATH/silent.xml $HOME_INIT/soft/jrockit-jdk1.6.0_24-R28.1.3-4.0.1.tar.gz $INSTALL_PATH/silent_domain.rsp

#CAMBIAR USER Y PASSOWORD NODEMANAGER
#---------------------------------------------------------------

rm $DOMAIN_PATH/$DOMAIN_NAME/config/nodemanager/nm_password.properties
cat > $DOMAIN_PATH/$DOMAIN_NAME/config/nodemanager/nm_password.properties <<EOF
username=${USER_NM}
password=${PASS_NM}
EOF

#CAMBIAR SCRIPT DE INICIO DE NODEMANAGER Y WEBLOGIC DOMAIN
#---------------------------------------------------------------
rm $DOMAIN_PATH/$DOMAIN_NAME/bin/startWebLogic.sh
cp $HOME_INIT/conf/startWebLogic.sh $DOMAIN_PATH/$DOMAIN_NAME/bin/
chmod 750 $DOMAIN_PATH/$DOMAIN_NAME/bin/startWebLogic.sh

rm $WL_HOME/server/bin/startNodeManager.sh
cp $HOME_INIT/conf/startNodeManager.sh $WL_HOME/server/bin/
chmod 750 $WL_HOME/server/bin/startNodeManager.sh

#SUBIR EL NODEMAMNAGER
#---------------------------------------------------------------
$WL_HOME/common/bin/wlst.sh <<EOF
  startNodeManager(verbose='true', NodeManagerHome='$NM_PATH'\
,ListenAddress='$ADMIN_HOST',ListenPort='$NODEMANAGER'\
,QuitEnabled='true',SecureListener='true', StartScriptEnabled='true')
EOF

## creacion de directorio
##---------------------------------------------------------------

mkdir -p $DOMAIN_PATH/$DOMAIN_NAME/servers/AdminServer/security
mkdir -p $DOMAIN_PATH/$DOMAIN_NAME/servers/AdminServer/tmp
mkdir -p $DOMAIN_PATH/$DOMAIN_NAME/servers/AdminServer/data
chown -Rf oracle:oracle $DOMAIN_PATH/$DOMAIN_NAME/servers/AdminServer/*

##CREACION DE ARCHIVO BOOT.PROPERTIES EN ADMIN SERVER
#---------------------------------------------------------------
cat > $DOMAIN_PATH/$DOMAIN_NAME/servers/AdminServer/security/boot.properties <<EOF
username=${USER_WL}
password=${PASS_WL}
EOF

#SUBIR EL DOMINIO
#---------------------------------------------------------------
$WL_HOME/common/bin/wlst.sh <<EOF
  nmConnect('$USER_NM','$PASS_NM',host='$ADMIN_HOST',port='$NODEMANAGER' \
           ,domainName='$DOMAIN_NAME',domainDir='$DOMAIN_PATH/$DOMAIN_NAME',nmType='ssl')
  nmStart('AdminServer')
  dumpStack()
EOF

##CREACION DE MACHINE
#-------------------------------------------------------------
cd $INSTALL_PATH
$WL_HOME/common/bin/wlst.sh  createMachine.py $ADMIN_HOST $ADMIN_PORT $USER_WL $PASS_WL \
$MACHINE_NAME $NODEMANAGER

#GENERACION DE CERTIFICADO AUTOFIRMADO
#---------------------------------------------------------------
cd $HOME_INIT/certs
source $WL_HOME/server/bin/setWLSEnv.sh
#Generate Key Pair
keytool -genkey -alias $ALIAS_CERT -keyalg RSA -keysize 1024 -dname "CN=${ADMIN_HOST}, OU=Customer Support, O=BEA Systems Inc, L=Denver, ST=Colorado, C=US" -keypass $PASSWORD_CERT -keystore identity_test.jks -storepass $PASSWORD_CERT
#Self Sign the certificates
keytool -selfcert -v -alias $ALIAS_CERT -keypass $PASSWORD_CERT -keystore identity_test.jks -storepass $PASSWORD_CERT -storetype jks
#Export your public key
keytool -export -v -alias $ALIAS_CERT -file rootCA_test.der -keystore identity_test.jks -storepass $PASSWORD_CERT
#Certificate stored in file
#Create a trust store.
keytool -import -v -trustcacerts -alias $ALIAS_CERT -file rootCA_test.der -keystore trust_test.jks -storepass $PASSWORD_CERT -noprompt

#CREAR EL SERVER MANEJADO
#-------------------------------------------------------------
echo "INSTALACION DE SERVER MANEJADO"

cd $INSTALL_PATH
$WL_HOME/common/bin/wlst.sh createServer.py $ADMIN_HOST $ADMIN_PORT $USER_WL $PASS_WL \
$MANAGED_SERVER $S1_PORT $S1_PORT_SSL $MACHINE_NAME $DOMAIN_PATH $DOMAIN_NAME $WL_HOME \
$JAVA_HOME $PATH_CERT $ALIAS_CERT $PASSWORD_CERT

##ENROLAR EL DOMINIO
#--------------------------------------------------------------
$WL_HOME/common/bin/wlst.sh <<EOF
  connect('${USER_WL}','${PASS_WL}','t3://${ADMIN_HOST}:$ADMIN_PORT')
  nmEnroll('${DOMAIN_PATH}/${DOMAIN_NAME}','${NM_PATH}')
  disconnect()
  exit()
EOF

##AÑADIR PERMISOS
#---------------------------------------------------------------
echo "export JAVA_HOME=/u01/home/app/soft/jrockit-jdk1.6.0_24-R28.1.3-4.0.1" >> /u01/home/app/oracle/.bashrc
echo "export PATH=$JAVA_HOME/bin:$PATH" >> /u01/home/app/oracle/.bashrc
echo "export DISPLAY=:0" >> /u01/home/app/oracle/.bashrc

#CORREGIR PERMISOS Y SETTING 
#---------------------------------------------------------------
chown -Rf oracle:oracle /$HOME_INIT
cd $HOME_INIT/conf
rm startNodeManager.sh startWebLogic.sh
chmod +x entrypoint.sh

#SETTING ORACLE 
#---------------------------------------------------------------
#echo 'oracle  ALL=(oracle) ALL' >> /etc/sudoers
echo 'oracle ALL=(ALL) NOPASSWD:ALL' >> /etc/sudoers
echo '%sudo ALL=(ALL:ALL) NOPASSWD:ALL' >> /etc/sudoers