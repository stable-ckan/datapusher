#!/bin/bash

##########################################################################
# Check supported DISTRO_NAME
##########################################################################

# Locate *NIX distribution by looking for match from various detection strategies
# We start with /etc/os-release, as this will also work for Docker containers
for command in "grep -E \"^NAME=\" /etc/os-release" \
               "lsb_release -i" \
               "cat /proc/version" \
               "uname -a" ; do
    distro_string=$(eval $command 2>/dev/null)
    unset DISTRO_NAME
    if [[ ${distro_string,,} == *"debian"* ]]; then
      DISTRO_NAME=Debian
    elif [[ ${distro_string,,} == *"red hat"* ]]; then
      DISTRO_NAME=RedHat
    elif [[ ${distro_string,,} == *"centos"* ]]; then
      DISTRO_NAME=CentOS
    elif [[ ${distro_string,,} == *"ubuntu"* ]]; then
      DISTRO_NAME=Ubuntu
    elif [[ ${distro_string,,} == *"suse"* ]]; then
      echo "Sorry, this script does not support Suse."
      exit 1
    elif [[ ${distro_string,,} == *"darwin"* ]]; then
      echo "Sorry, this script does not support macOS."
      exit 1
    fi
    if [[ $DISTRO_NAME ]] ; then break ; fi
done
if [[ ! $DISTRO_NAME ]] ; then
  echo -e "\nERROR: Unable to auto-detect your *NIX distribution!\n" 1>&2
  exit 1
fi

##########################################################################
# Configuration global variables
##########################################################################

# Install folder path
DATAPUSHER_INSTALL_DIR="$(dirname "$(dirname "$(readlink -fm "$0")")")"
DATAPUSHER_INSTALL_DEPLOYMENT_DIR=$DATAPUSHER_INSTALL_DIR/deployment

# Ckan home dir for files
CKAN_LIB_DIR=/usr/lib/ckan
CKAN_LIB_DEFAULT_DIR=$CKAN_LIB_DIR/default
DATAPUSHER_LIB_DEFAULT_DIR=$CKAN_LIB_DIR/datapusher

# Configuration folder ckan
CKAN_ETC_DIR=/etc/ckan
DATAPUSHER_ETC_DEFAULT_DIR=$CKAN_ETC_DIR/datapusher

# Configuration file generate for installer
CKAN_CONFIG_INI=${CKAN_ETC_DEFAULT_DIR}/production.ini

# Var folder using create inner files
CKAN_VAR_LIB=/var/lib/ckan/

# Configuration apache2
APACHE_ETC_DIR=/etc/apache2
APACHE_ETC_SITES_DIR=$APACHE_ETC_DIR/sites-available
APACHE_ETC_CONF_DIR=$APACHE_ETC_DIR/conf-available
APACHE_ETC_PORTS=$APACHE_ETC_DIR/ports.conf

# User and group ckan
CKAN_USER_GROUP=ckan

##########################################################################
# Validation requeriments for install
##########################################################################

if [[ $EUID -ne 0 ]]; then
  echo -e "\nERROR: This script must be run as root\n" 1>&2
  exit 1
fi

if [ ! -d "$CKAN_LIB_DEFAULT_DIR" ]; then
  echo -e "\nERROR: Depends Ckan 2.8.2 installed\n" 1>&2
  exit 1
fi

if [ ! -d "$APACHE_ETC_DIR" ]; then
  echo -e "\nERROR: Depends Apache2 installed\n" 1>&2
  exit 1
fi

##########################################################################
# Global functions
##########################################################################

print_error() {
  echo $1
  exit 1
}

##########################################################################
# Start install and configuration
##########################################################################

if [ "$DISTRO_NAME" == "Debian" ] || [ "$DISTRO_NAME" == "Ubuntu" ] ; then
  apt-get install python-dev python-virtualenv build-essential libxslt1-dev libxml2-dev git libffi-dev
fi

mkdir -p $DATAPUSHER_ETC_DEFAULT_DIR
chown -R $CKAN_USER_GROUP:$CKAN_USER_GROUP $CKAN_ETC_DIR

mkdir -p ${DATAPUSHER_LIB_DEFAULT_DIR}
chown -R $CKAN_USER_GROUP:$CKAN_USER_GROUP $CKAN_LIB_DIR

cp $DATAPUSHER_INSTALL_DEPLOYMENT_DIR/datapusher.apache2-4.conf $APACHE_ETC_SITES_DIR/datapusher.conf

grep -Fxq "Listen 8800" $APACHE_ETC_PORTS; [ $? -eq 0 ] || sh -c "echo 'Listen 8800' >> $APACHE_ETC_PORTS" ;

grep -Fxq "NameVirtualHost *:8800" $APACHE_ETC_PORTS; [ $? -eq 0 ] || sh -c "echo 'NameVirtualHost *:8800' >> $APACHE_ETC_PORTS" ;

su -s /bin/bash - $CKAN_USER_GROUP <<EOF

virtualenv --no-site-packages ${DATAPUSHER_LIB_DEFAULT_DIR}
cd ${DATAPUSHER_LIB_DEFAULT_DIR}
. ${DATAPUSHER_LIB_DEFAULT_DIR}/bin/activate
pip install setuptools==36.1
pip install $DATAPUSHER_INSTALL_DIR
pip install -r $DATAPUSHER_INSTALL_DIR/requirements.txt

python $DATAPUSHER_INSTALL_DIR/setup.py install

sed -i 's/flask.ext.login/flask_login/g' ${DATAPUSHER_LIB_DEFAULT_DIR}/lib/python2.7/site-packages/ckanserviceprovider/web.py

deactivate

cp $DATAPUSHER_INSTALL_DEPLOYMENT_DIR/datapusher.wsgi $DATAPUSHER_ETC_DEFAULT_DIR
cp $DATAPUSHER_INSTALL_DEPLOYMENT_DIR/datapusher_settings.py $DATAPUSHER_ETC_DEFAULT_DIR

EOF

rm -rf $CKAN_LIB_DIR/.cache

a2ensite datapusher

systemctl restart apache2