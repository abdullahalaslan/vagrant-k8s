sudo apt-get update
sudo apt-get install virtualbox -y
sudo apt-get install vagrant -y
sudo apt-get install ansible -y
sudo apt-get install pwgen -y
vagrant up
export DB_PASSWORD=`pwgen Bs1 12`