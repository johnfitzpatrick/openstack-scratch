#!/bin/bash

#This scripts is based on the steps here https://<<Internal Website Removed>>/display/rightscale/OpenStack+Install
#John Fitzpatrick June 2013

#++++++++++++++++++++++++++++
#Use the following if installing on a single node, to ensure the IP Address is populated in script
#Comment it out otherwise
EXPECTED_ARGS=2
E_BADARGS=65

if [ $# -ne $EXPECTED_ARGS ]
then
  echo "Usage: installopenstack.sh <IP Address> <MySQL Password>"
  echo "You're prompted for the MySQL Password during install.  The value provided here must be the same."
exit $E_BADARGS
fi
KEYSTONE_PUB_IP=$1
NOVA_PUB_IP=$1
CINDER_PUB_IP=$1
GLANCE_PUB_IP=$1

#You're prompted for the MySQL Password during install.  The value in this script must be the same.
MYSQLPWORD=$2 
#++++++++++++++++++++++++++++


#++++++++++++++++++++++++++++

#Just for fun
apt-get install figlet -y
figlet Installing OpenStack -t
# Could use 'toilet'
# apt-get install toilet -y
#toilet -f mono12 -F metal Installing OpenStack

#Passwords
TOKEN=012345SECRET99TOKEN012345
#KEYSTONE_HOST=192.168.2.1
GLANCEPASSWORD=glance
#++++++++++++++++++++++++++++

KEYSTONE_HOST=localhost
KEYSTONE_PRIV_IP=localhost
NOVA_PRIV_IP=localhost
CINDER_PRIV_IP=localhost
GLANCE_PRIV_IP=localhost
#KEYSTONE_PUB_IP=54.216.5.192
#NOVA_PUB_IP=54.216.5.192
#CINDER_PUB_IP=54.216.5.192
#GLANCE_PUB_IP=54.216.5.192

##Keystone Package Install
figlet Keystone Package -t
echo "deb http://ubuntu-cloud.archive.canonical.com/ubuntu precise-updates/folsom main" >> /etc/apt/sources.list.d/folsom.list

sudo apt-get install ubuntu-cloud-keyring -y

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
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 tenant-create --name default --description "Default Tenant"
sleep 0.5;TENANT_ID_DEFAULT=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.tenant where name='default'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 role-create --name admin
sleep 0.5;ROLE_ID_ADMIN=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.role where name='admin'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_DEFAULT --name admin --pass admin
sleep 0.5;USER_ID_ADMIN=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='admin'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_ADMIN --tenant $TENANT_ID_DEFAULT --role $ROLE_ID_ADMIN


keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 tenant-create --name service --description "Service Tenant"
sleep 0.5;TENANT_ID_SERVICE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.tenant where name='service'"`

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name glance --pass $GLANCEPASSWORD
sleep 0.5;USER_ID_GLANCE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='glance'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_GLANCE --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name nova --pass nova
sleep 0.5;USER_ID_NOVA=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='nova'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_NOVA --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name ec2 --pass ec2
sleep 0.5;USER_ID_EC2=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='ec2'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_EC2 --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-create --tenant $TENANT_ID_SERVICE --name swift --pass swift
sleep 0.5;USER_ID_SWIFT=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.user where name='swift'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 user-role-add --user $USER_ID_SWIFT --tenant $TENANT_ID_SERVICE --role $ROLE_ID_ADMIN


figlet Service/Endpoint Config -t
echo "Service and Endpoint Configuration"
#Service and Endpoint Setup
keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=keystone --type=identity --description="Keystone Identity Service"
sleep 0.5;SERVICE_ID_KEYSTONE_IDENTITY=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='identity'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_KEYSTONE_IDENTITY --publicurl=http://$KEYSTONE_PUB_IP:5000/v2.0 --internalurl=http://$KEYSTONE_PRIV_IP:5000/v2.0 --adminurl=http://$KEYSTONE_PUB_IP:35357/v2.0

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=nova --type=compute --description="Nova Compute Service"
sleep 0.5;SERVICE_ID_NOVA_COMPUTE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='compute'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_NOVA_COMPUTE --publicurl=http://$NOVA_PUB_IP:8774/v2/%\(tenant_id\)s --internalurl=http://$NOVA_PRIV_IP:8774/v2/%\(tenant_id\)s --adminurl=http://$NOVA_PUB_IP:8774/v2/%\(tenant_id\)s

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=cinder --type=volume --description="Cinder Volume Service"
sleep 0.5;SERVICE_ID_CINDER_VOLUME=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='volume'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_CINDER_VOLUME --publicurl=http://$CINDER_PUB_IP:8776/v1/%\(tenant_id\)s --internalurl=http://$CINDER_PRIV_IP:8776/v1/%\(tenant_id\)s --adminurl=http://$CINDER_PUB_IP:8776/v2/%\(tenant_id\)s

keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 service-create --name=glance --type=image --description="Glance Image Service"
sleep 0.5;SERVICE_ID_GLANCE_IMAGE=`mysql -uroot -p$MYSQLPWORD -s -N -e "SELECT id from keystone.service where type='image'"`
sleep 0.5;keystone --token $TOKEN --endpoint http://$KEYSTONE_HOST:35357/v2.0 endpoint-create --region RegionOne --service=$SERVICE_ID_GLANCE_IMAGE --publicurl=http://$GLANCE_PUB_IP:9292 --internalurl=http://$GLANCE_PRIV_IP:9292 --adminurl=http://$GLANCE_PUB_IP:9292


sudo apt-get install python-paste glance glance-client python-mysqldb -y

figlet Glance Config -t
#MySQL Config - Glance
mysql -uroot -p$MYSQLPWORD -s -N -e "CREATE DATABASE glance"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON glance.* TO 'glance'@'%' IDENTIFIED BY '$GLANCEPASSWORD'"
mysql -uroot -p$MYSQLPWORD -s -N -e "GRANT ALL ON glance.* TO 'glance'@'$GLANCE_PRIV_IP' IDENTIFIED BY '$GLANCEPASSWORD'"


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
[paste-deploy]
flavor=keystone
EOF

#Configure /etc/glance/glance-registry-paste.ini
sed -i -r "s/auth_host = 127.0.0.1/auth_host = $KEYSTONE_PRIV_IP/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/auth_uri = http:\/\/127.0.0.1:5000/auth_uri = http:\/\/$KEYSTONE_PRIV_IP:5000/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_tenant_name = %SERVICE_TENANT_NAME%/admin_tenant_name = service/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_user = %SERVICE_USER%/admin_user = glance/i" /etc/glance/glance-registry-paste.ini
sed -i -r "s/admin_password = %SERVICE_PASSWORD%/admin_password = $GLANCEPASSWORD/i" /etc/glance/glance-registry-paste.ini



#Configure /etc/glance/glance-registry.conf
sed -i -r "s/sql_connection = sqlite:\/\/\/\/var\/lib\/glance\/glance.sqlite/sql_connection = mysql:\/\/glance:$GLANCEPASSWORD@$GLANCE_PRIV_IP\/glance/i" /etc/glance/glance-registry.conf

cat >> /etc/glance/glance-registry.conf << EOF
[paste-deploy]
flavor=keystone
EOF

#Start glance
figlet Starting Glance -t
cd /etc/init.d
for i in glance-*; do service $i restart; done
glance-manage version_control 0
glance-manage db_sync

##Assumming root here
##From http://openstack-folsom-install-guide.readthedocs.org/en/latest/
#mkdir /root/images
#cd /root/images
#wget https://launchpad.net/cirros/trunk/0.3.0/+download/cirros-0.3.0-x86_64-disk.img
#<--THIS FAILS-->
#glance image-create --name NimbulaTest --is-public true --container-format bare --disk-format qcow2 < cirros-0.3.0-x86_64-disk.img

#glance add name="NimbulaTest" is-public=true container-format=bare disk-format=qcow2 < cirros-0.3.0-x86_64-disk.img

#Install and configure Horizon
#http://openstack-folsom-install-guide.readthedocs.org/en/latest/
figlet Installing Horizon -t
apt-get install openstack-dashboard memcached -y

figlet Now Test Your Install -t
echo "
http://$1
username: admin
password: admin"


