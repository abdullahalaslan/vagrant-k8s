export DB_PASSWORD=`pwgen -Bs1 12`
kubectl apply -f /vagrant/manifests/mysql-deployment.yaml
kubectl apply -f /vagrant/manifests/mysql-service.yaml
cd /home/vagrant/hello-python
skaffold run