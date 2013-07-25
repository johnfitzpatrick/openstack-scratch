#!/bin/bash

#This scripts is based on the steps here https://<<Internal Website Removed>>/display/rightscale/OpenStack+Install
#Assumes a single node install.  Created/tested on server running in AWS
#You must pass the Public IP & MySQL Password as params to the script
#
#John Fitzpatrick July 2013

################################################################
#NOTES:                                                        #
#Changed version numbers to v1 for all Cinder urls on line 131 #
#Added /v1 to glance endpoint urls                              #
################################################################

EXPECTED_ARGS=2
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: installopenstack.sh <Public IP Address> <MySQL Password>"
#  echo "You're also prompted for the MySQL Password during install.  The value provided here must be the same."
exit $E_BADARGS
fi

#++++++++++++++++++++++++++++
#Using figlet to banner some installation feedback
apt-get install figlet -y
figlet Installing OpenStack -t
# Could use 'toilet'
# apt-get install toilet -y
#toilet -f mono12 -F metal Installing OpenStack
#++++++++++++++++++++++++++++

KEYSTONE_PUB_IP=$1
NOVA_PUB_IP=$1
CINDER_PUB_IP=$1
GLANCE_PUB_IP=$1

KEYSTONE_HOST=localhost
KEYSTONE_PRIV_IP=localhost
NOVA_PRIV_IP=localhost
CINDER_PRIV_IP=localhost
GLANCE_PRIV_IP=localhost

#PASSWORDS
#You're prompted for the MySQL Password during install.  The value in this script must be the same.
TOKEN=012345SECRET99TOKEN012345
#GLANCEPASSWORD=glance
GLANCEPASSWORD=admin
MYSQLPWORD=$2 

##Keystone Package Install
figlet Keystone Package -t
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/folsom main" >> /etc/apt/sources.list.d/folsom.list

sudo apt-get install ubuntu-cloud-keyring -y
apt-get install debconf-utils
echo "mysql-server-5.5 mysql-server/root_password_again password $MYSQLPWORD" | debconf-set-selections
echo "mysql-server-5.5 mysql-server/root_password password $MYSQLPWORD" | debconf-set-selections
#apt-get install mysql-server -y
#apt-get install python-mysqldb keystone -y
apt-get install mysql-server python-mysqldb keystone -y

#Not sure if I should do this, but bombs out otherwise
sed -i -r "s/bind/#bind/i" /etc/mysql/my.cnf

service mysql restart

mysql -uroot -p$MYSQLPWORD -s -N -e "CREATE DATABASE keystone"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON keystone.* TO 'keystone'@'%' IDENTIFIED BY '$MYSQLPWORD'"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON keystone.* TO 'keystone'@'localhost' IDENTIFIED BY '$MYSQLPWORD'"

figlet Glance Package -t
sudo apt-get install glance -y

sed -i -r "s/admin_token = ADMIN/admin_token = $TOKEN/i" /etc/keystone/keystone.conf
sed -i -r "s/connection = sqlite:\/\/\/\/var\/lib\/keystone\/keystone.db/connection = mysql:\/\/keystone:$MYSQLPWORD@localhost\/keystone/i" /etc/keystone/keystone.conf

keystone-manage db_sync
service keystone restart

figlet User/Tenant Config -t
sleep 2
echo "User and Tenant Configuration"
#User and Tenant Configuration
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 tenant-create --name default --description "Default Tenant";sleep 0.5
TENANT_ID_DEFAULT=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.tenant where name='default'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 role-create --name admin;sleep 0.5
ROLE_ID_ADMIN=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.role where name='admin'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_DEFAULT --name admin --pass admin;sleep 0.5
USER_ID_ADMIN=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='admin'"`;sleep 0.5

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_ADMIN --tenant $TENANT_ID_DEFAULT --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 tenant-create --name service --description "Service Tenant";sleep 0.5
TENANT_ID_SERVICE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.tenant where name='service'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name glance --pass $GLANCEPASSWORD;sleep 0.5
USER_ID_GLANCE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='glance'"`;sleep 0.5

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_GLANCE --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name nova --pass nova;sleep 0.5
USER_ID_NOVA=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='nova'"`;sleep 0.5

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_NOVA --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name ec2 --pass ec2;sleep 0.5
USER_ID_EC2=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='ec2'"`;sleep 0.5

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_EC2 --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name swift --pass swift;sleep 0.5
USER_ID_SWIFT=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='swift'"`;sleep 0.5

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_SWIFT --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN


figlet Service/Endpoint Config -t
echo "Service and Endpoint Configuration"
#Service and Endpoint Setup
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=keystone --type=identity --description="Keystone Identity Service";sleep 0.5
SERVICE_ID_KEYSTONE_IDENTITY=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='identity'"`;sleep 0.5
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_KEYSTONE_IDENTITY --publicurl=http://$KEYSTONE_PUB_IP:5000/v2.0 --internalurl=http://$KEYSTONE_PRIV_IP:5000/v2.0 --adminurl=http://$KEYSTONE_PUB_IP:35357/v2.0

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=nova --type=compute --description="Nova Compute Service";sleep 0.5
SERVICE_ID_NOVA_COMPUTE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='compute'"`;sleep 0.5
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_NOVA_COMPUTE --publicurl=http://$NOVA_PUB_IP:8774/v2/%\(tenant_id\)s --internalurl=http://$NOVA_PRIV_IP:8774/v2/%\(tenant_id\)s --adminurl=http://$NOVA_PUB_IP:8774/v2/%\(tenant_id\)s

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=cinder --type=volume --description="Cinder Volume Service";sleep 0.5
SERVICE_ID_CINDER_VOLUME=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='volume'"`;sleep 0.5
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_CINDER_VOLUME --publicurl=http://$CINDER_PUB_IP:8776/v1/%\(tenant_id\)s --internalurl=http://$CINDER_PRIV_IP:8776/v1/%\(tenant_id\)s --adminurl=http://$CINDER_PUB_IP:8776/v1/%\(tenant_id\)s

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=glance --type=image --description="Glance Image Service";sleep 0.5
SERVICE_ID_GLANCE_IMAGE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='image'"`;sleep 0.5
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_GLANCE_IMAGE --publicurl=http://$GLANCE_PUB_IP:9292/v1 --internalurl=http://$GLANCE_PRIV_IP:9292/v1 --adminurl=http://$GLANCE_PUB_IP:9292/v1

sudo apt-get install python-paste glance glance-client python-mysqldb -y

figlet Glance Config -t
#MySQL Config - Glance
mysql -uroot -p$MYSQLPWORD -s -N -e "CREATE DATABASE glance"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCEPASSWORD'"
#mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON glance.* TO 'glance'@'$GLANCE_PRIV_IP' IDENTIFIED BY '$GLANCEPASSWORD'"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON glance.* TO 'glance'@'localhost' IDENTIFIED BY '$GLANCEPASSWORD'"


rm /var/lib/glance/glance.sqlite

#Configure /etc/glance/glance-api-paste.ini
sed -i -r "s/auth_host = 127.0.0.1/auth_host = $KEYSTONE_PRIV_IP/i" /etc/glance/glance-api-paste.ini
sed -i -r "s/auth_uri = http:\/\/127.0.0.1:5000/auth_uri = http:\/\/$KEYSTONE_PRIV_IP:5000/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_tenant_name = %SERVICE_TENANT_NAME%/admin_tenant_name = service/i" /etc/glance/glance-api-paste.ini
sed -i -r "s/admin_user = %SERVICE_USER%/admin_user = glance/i" /etc/glance/glance-api-paste.ini
sed -i -r "s/admin_password = %SERVICE_PASSWORD%/admin_password = $GLANCEPASSWORD/i" /etc/glance/glance-api-paste.ini

#Configure /etc/glance/glance-api.conf
cat >> /etc/glance/glance-api.conf << EOF
sql_connection = mysql://glance:$GLANCEPASSWORD@$GLANCE_PRIV_IP/glance

[keystone_authtoken]
auth_host = 127.0.0.1
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
#admin_user = glance
#admin_password = glance
admin_user = admin
admin_password = admin

[paste-deploy]
flavor=keystone
config_file = /etc/glance/glance-api-paste.ini

#Think this should be v1
enable_v1_api=True
enable_v2_api=False
EOF

service glance-api restart

#Configure /etc/glance/glance-registry-paste.ini
sed -i -r "s/auth_host = 127.0.0.1/auth_host = $KEYSTONE_PRIV_IP/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/auth_uri = http:\/\/127.0.0.1:5000/auth_uri = http:\/\/$KEYSTONE_PRIV_IP:5000/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_tenant_name = %SERVICE_TENANT_NAME%/admin_tenant_name = service/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_user = %SERVICE_USER%/admin_user = glance/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_password = %SERVICE_PASSWORD%/admin_password = $GLANCEPASSWORD/i" /etc/glance/glance-registry-paste.ini

#Configure /etc/glance/glance-registry.conf
sed -i -r "s/sql_connection = sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/sql_connection = mysql:\/\/glance:$GLANCEPASSWORD@$GLANCE_PRIV_IP\/glance/i" /etc/glance/glance-registry.conf

cat >> /etc/glance/glance-registry.conf << EOF
[keystone_authtoken]
auth_host = 127.0.0.1
auth_port = 35357
auth_protocol = http
admin_tenant_name = service
#admin_user = glance
#admin_password = glance
admin_user = admin
admin_password = admin

[paste_deploy]
config_file = /etc/glance/glance-registry-paste.ini
flavor=keystone
EOF

service glance-registry restart
glance-manage db_sync

#Start glance
figlet Starting Glance -t
cd /etc/init.d
for i in glance-*; do service $i restart; done
glance-manage version_control 0
#glance-manage db_sync

#TRYING UP UPLOAD AN IMAGE HERE, BUT CAN'T GET THIS TO WORK SO REM'd OUT FOR NOW
##Assumming root here
##From http://openstack-folsom-install-guide.readthedocs.org/en/latest/
mkdir /root/images
cd /root/images
wget http://download.cirros-cloud.net/0.3.1/cirros-0.3.1-x86_64-disk.img
#<--THESE COMMANDS BELOW FAIL-->
#glance image-create --name NimbulaTest --is-public true --container-format bare --disk-format qcow2 < cirros-0.3.1-x86_64-disk.img
#glance add name="cirros Tester" is-public=true container-format=bare disk-format=qcow2 < cirros-0.3.1-x86_64-disk.img
#glance add --os_auth_token="012345SECRET99TOKEN012345"  name="cirros Tester" is_public=true disk_format=qcow2 container_format=bare  --host=54.216.212.71 < cirros-0.3.1-x86_64-disk.img

#Install and configure Nova
#http://openstack-folsom-install-guide.readthedocs.org/en/latest/
figlet Installing Nova -t
apt-get install -y nova-api nova-cert novnc nova-consoleauth nova-scheduler  nova-network

mysql -uroot -p$MYSQLPWORD -s -N -e "CREATE DATABASE nova"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON nova.* TO 'novaUser'@'%' IDENTIFIED BY 'novaPass'"


cat >> /etc/nova/api-paste.ini << EOF
signing_dirname = /tmp/keystone-signing-nova
EOF


cat >> /etc/nova/nova.conf << EOF
[DEFAULT]
logdir=/var/log/nova
state_path=/var/lib/nova
lock_path=/run/lock/nova
verbose=True
api_paste_config=/etc/nova/api-paste.ini
scheduler_driver=nova.scheduler.simple.SimpleScheduler
s3_host=localhost
ec2_host=localhost
ec2_dmz_host=localhost
rabbit_host=localhost
cc_host=localhost
metadata_host=localhost
metadata_listen=0.0.0.0
nova_url=http://localhost:8774/v1.1/
sql_connection=mysql://novaUser:novaPass@localhost/nova
ec2_url=http://localhost:8773/services/Cloud
root_helper=sudo nova-rootwrap /etc/nova/rootwrap.conf

# Auth
use_deprecated_auth=false
auth_strategy=keystone
keystone_ec2_url=http://localhost:5000/v2.0/ec2tokens
# Imaging service
glance_api_servers=localhost:9292
#glance_api_servers=localhost:9292/v1
image_service=nova.image.glance.GlanceImageService

# Vnc configuration
novnc_enabled=true
novncproxy_base_url=http://localhost:6080/vnc_auto.html
novncproxy_port=6080
vncserver_proxyclient_address=localhost
vncserver_listen=0.0.0.0

# NETWORK
network_manager=nova.network.manager.FlatDHCPManager
force_dhcp_release=True
dhcpbridge_flagfile=/etc/nova/nova.conf
firewall_driver=nova.virt.libvirt.firewall.IptablesFirewallDriver
# Change my_ip to match each host
my_ip=localhost
public_interface=br100
vlan_interface=eth0
flat_network_bridge=br100
flat_interface=eth0
#Note the different pool, this will be used for instance range
fixed_range=10.33.14.0/24

# Compute #
compute_driver=libvirt.LibvirtDriver

# Cinder #
volume_api_class=nova.volume.cinder.API
osapi_volume_listen_port=5900

EOF

nova-manage db sync
cd /etc/init.d/; for i in $(ls nova-*); do sudo service $i restart; done
nova-manage service list

#Install and configure Horizon
#http://openstack-folsom-install-guide.readthedocs.org/en/latest/
figlet Installing Horizon -t
apt-get install openstack-dashboard memcached -y

figlet Now Test Your Install -t
echo "
http://$1
username: admin
password: admin"
