export DB_PASSWORD=`pwgen -Bs1 12`
kubectl apply -f /vagrant/manifests/mysql-deployment.yaml
kubectl apply -f /vagrant/manifests/mysql-service.yaml
kubectl apply -f /vagrant/manifests/app-service.yaml
cd /home/vagrant/hello-python
skaffold dev </dev/null &>/dev/null &