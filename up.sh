#sudo apt-get update
#sudo apt-get install virtualbox -y
#sudo apt-get install vagrant -y
#sudo apt-get install ansible -y
#sudo apt-get install pwgen -y
#curl -Lo skaffold https://storage.googleapis.com/skaffold/releases/latest/skaffold-linux-amd64 && sudo install skaffold /usr/local/bin/ -y
vagrant up
export DB_PASSWORD=`pwgen Bs1 12`