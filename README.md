# Local Kubernetes Cluster using Vagrant

The project builds a Kubernetes cluster on a local environment using Vagrant to run a simple 'Hello World' web application written in Python. 

## Prerequisites
At least 4 GBs of free memory available is recommended.

Also, following tools need to be installed on your machine:
 - Oracle VirtualBox
 - Ansible
 - Vagrant

## How To: Setup
1. Open a terminal on your machine.
2. Go to root directory of the project.
3. Run :
    ```Bash
    bash up.sh
    ```
Wait until the script ends (appr. 15-20 minutes).

Then open a browser and go to http://192.168.50.11:31320 to access the application.

### up.sh:
```Bash
git -C ~/ clone https://github.com/baturayozcan/python-helloworld.git
vagrant plugin install vagrant-reload
vagrant up
```
- clones the public repository of Python application
- installs *vagrant-reload* plugin
- runs Vagrantfile

## Tool Stack
**Vagrant:** to create local environment for Kubernetes cluster

**VirtualBox:** to be used as provider in Vagrant

**Ansible:** to build Kubernetes cluster inside VMs and make configurations for CI/CD operations

**Skaffold:** to build and deploy the application on the Kubernetes cluster

## Project Components


## 1. Application
A simple 'Hello World' web application written in Python. It uses Flask as web server and MySQL as database. Database connection variables are read through environment variables and the application is run on port 3000.

You can access the public repository of the application through the link: https://github.com/baturayozcan/python-helloworld

### hello.py:

```Python
import os
import flask
import pymysql
pymysql.install_as_MySQLdb()
import MySQLdb

application = flask.Flask(__name__)
application.debug = True

@application.route('/')
def hello_world():
  storage = Storage()
  storage.populate()
  score = storage.score()
  return "Hello Devops 123, %d!" % score

class Storage():
  def __init__(self):
    self.db = MySQLdb.connect(
      user   = os.getenv('MYSQL_USERNAME'),
      passwd = os.getenv('MYSQL_PASSWORD'),
      db     = os.getenv('MYSQL_INSTANCE_NAME'),
      host   = os.getenv('MYSQL_PORT_3306_TCP_ADDR'),
      port   = int(os.getenv('MYSQL_PORT_3306_TCP_PORT'))
    )

    cur = self.db.cursor()
    cur.execute("CREATE TABLE IF NOT EXISTS scores(score INT)")

  def populate(self):
    cur = self.db.cursor()
    cur.execute("INSERT INTO scores(score) VALUES(1234)")

  def score(self):
    cur = self.db.cursor()
    cur.execute("SELECT * FROM scores")
    row = cur.fetchone()
    return row[0]

if __name__ == "__main__":
  application.run(host='0.0.0.0', port=3000)
```

In order *MySQLdb* module to work with Python3, a workaround solution is implemented: *pymysql* module is installed as MySQLdb.
```Python
import pymysql
pymysql.install_as_MySQLdb()
```
### requirements.txt:
```TXT
Flask
pymysql
```
These modules are required for the application and installed via *pip* in Dockerfile.

### Dockerfile:
```Dockerfile
FROM alpine:3.12.1

RUN apk add --no-cache python3 && \ 
   apk add --no-cache py-pip && \
   apk add build-base && \
   apk add python3-dev && \
   apk add libffi-dev && \
   apk add openssl-dev

RUN pip install cryptography

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY . .

CMD ["python3", "hello.py"]
```

*pymysql* module needs *cryptography* package to work proper and that package also requires *build-base, python3-dev, libffi-dev and openssl-dev* packages. Therefore all these packages are installed into the container image.


### skaffold.yaml:
```YAML
apiVersion: skaffold/v2beta10
kind: Config
metadata:
  name: python-helloworld
build:
  artifacts:
  - image: hello-python
    docker:
      dockerfile: Dockerfile
  local:
    push: false
deploy:
  kubectl:
    manifests:
    - /vagrant/manifests/app-deployment.yaml
```
When *skaffold run* command is run, skaffold reads and runs this file. It creates a container image using Dockerfile and apply the deployment yaml file (detailed in Manifests section.) onto the Kubernetes cluster. Container images are kept in VMs itself so they are not pushed to any registry.
```YAML
local:
    push: false
```

## 2. Ansible

Ansible is used to create Kubernetes cluster and to make necessary configurations for build and deploy operations of the application into the cluster. Playbooks are run during the provision state of Vagrantfile. 

### master-playbook.yaml:
```YAML
---
- hosts: all
  become: true
  roles:
    - docker
    - swap
    - k8s-binaries
    - k8s-initialize
    - kubeconfig
    - flannel
    - join-command
  handlers:
    - name: docker status
      service: name=docker state=started
```
The script is run on Master Node of the Kubernetes cluster to do following operations respectively:

- install Docker and its dependencies
- add Vagrant user to docker group
- disable swap on the system, otherwise Kubelet will not start
- install Kubernetes binaries (kubelet, kubeadm, kubectl)
- initialize the cluster (10.244.0.0/16 subnet is set as pod network cidr so that flannel works proper)
- setup kubeconfig for vagrant user and fetch it to the local (will be used later on)
- install flannel as network plugin
- create a token for nodes to join the cluster and fetch it to the local as a file(will be used later on)


In order vagrant user to run docker operations on the VM, after adding vagrant user to docker group, logoff/login is needed. **vagrant-reload** plugin is installed to make it happen (will be detailed in Vagrantfile section). Tasks are separated as before and after the reload operation.

### node-playbook-before.yaml:
```YAML
---
- hosts: all
  become: true
  roles:
    - docker
    - swap
    - pwgen
    - skaffold
    - k8s-binaries
    - kubejoin
  handlers:
    - name: docker status
      service: name=docker state=started
```
The script is run on Worker Node of the Kubernetes cluster to do following operations respectively:

- install Docker and its dependencies
- add Vagrant user to docker group
- disable swap on the system, otherwise Kubelet will not start
- install pwgen package to generate random passwords (needed for MySQL, will be explained later in this section)
- install skaffold for build and deploy operations of the applicaton
- install Kubernetes binaries (kubelet, kubeadm, kubectl)
- copy kubejoin file (fetched before) to the node and run it to join the node into the cluster

### node-playbook-after.yaml:
```YAML
---
- hosts: all
  become: true
  roles:
    - launch
  handlers:
    - name: docker status
      service: name=docker state=started
```
The script is run on Worker Node of the Kubernetes cluster to do following operations respectively:

- create .kube directory for vagrant user
- upload kubeconfig to the node (to run kubectl operations)
- install flannel as network plugin
- run *launch.sh*

### launch.sh:
```Bash
#!/bin/bash

export DB_PASSWORD=`pwgen -Bs1 12`
kubectl apply -f /vagrant/manifests/mysql-deployment.yaml
kubectl apply -f /vagrant/manifests/mysql-service.yaml
kubectl apply -f /vagrant/manifests/app-service.yaml
cd /home/vagrant/hello-python
skaffold run
```

- generate a random password to be used as root password of the database while applying MySQL deployment
- apply MySQL deployment to the cluster
- apply a ClusterIP service for MySQL to the cluster
- apply a NodePort service for Python application to the cluster
- go to root directory of the Python application (synced with Vagrantfile, will be detailed in Vagrantfile section) and run ***skaffold run*** to start build and deploy operations of the Python application.


## 3. Manifests
4 Kubernetes manifest files are created to apply:

- MySQL deployment
- MySQL ClusterIP service
- Python app deployment
- Python app NodePort service

### mysql-deployment.yaml:

```YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: mysql
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: mysql
  template:
    metadata:
      labels:
        app: mysql
    spec:
      containers:
        - name: mysql
          image: mysql
          ports:
            - containerPort: 3306
          env:
            - name: MYSQL_ROOT_PASSWORD
              value: "${DB_PASSWORD}"
            - name: MYSQL_USER
              value: "python"
            - name: MYSQL_PASSWORD
              value: "mysecretpassword"
            - name: MYSQL_DATABASE
              value: main
```

pulls *mysql* image from Dockerhub and runs it on port 3306 taking following environment variables:
**MYSQL_ROOT_PASSWORD:** randomly generated

**MYSQL_USER_PASSWORD:** 'python' as username to be created for Python app

**MYSQL_PASSWORD:** 'mysecretpassword' as password to be created for Python app (since it is a local environment, security concerns ignored)

**MYSQL_DATABASE:** 'main' as database name to be created for Python app

### mysql-service.yaml:

```YAML
apiVersion: v1
kind: Service
metadata:
  name: service-mysql
spec:
  selector:
    app: mysql
  ports:
    - port: 3306
```
creates a ClusterIP type service to expose MySQL on port 3306

### app-deployment.yaml:

```YAML
apiVersion: apps/v1
kind: Deployment
metadata:
  name: hello-app
  namespace: default
spec:
  replicas: 1
  selector:
    matchLabels:
      app: hello-app
  template:
    metadata:
      labels:
        app: hello-app
    spec:
      containers:
        - name: hello-app
          image: hello-python
          ports:
            - containerPort: 3000
          env:
            - name: MYSQL_USERNAME
              value: "python"
            - name: MYSQL_PASSWORD
              value: "mysecretpassword"
            - name: MYSQL_INSTANCE_NAME
              value: "main"
            - name: MYSQL_PORT_3306_TCP_ADDR
              value: $(SERVICE_MYSQL_SERVICE_HOST)
            - name: MYSQL_PORT_3306_TCP_PORT
              value: "3306"
```
runs the Python application from the image 'hello-python' (created with skaffold) taking following environment variables:

**MYSQL_USERNAME:** set as 'python' while creating MySQL deployment

**MYSQL_PASSWORD:** set as 'mysecretpassword' while creating MySQL deployment

**MYSQL_INSTANCE_NAME:** set as 'main' while creating MySQL deployment

**MYSQL_PORT_3306_TCP_ADDR:** ClusterIP of the MySQL service as environment variable $(SERVICE_MYSQL_SERVICE_HOST)

**MYSQL_PORT_3306_TCP_PORT:** Port of the MySQL service as 3306

### app-service.yaml:

```YAML
apiVersion: v1
kind: Service
metadata:
  name: service-app
spec:
  selector:
    app: hello-app
  ports:
    - port: 3000
      nodePort: 31320
      protocol: TCP
      targetPort: 3000
  type: NodePort
```
creates a NodePort type service to expose Python app on port 31320 of the node

## 4. Vagrantfile
```Vagrantfile
IMAGE_NAME = "ubuntu/focal64"
N = 1

Vagrant.configure("2") do |config|
    config.ssh.insert_key = false

    config.vm.provider "virtualbox" do |v|
        v.memory = 4096
        v.cpus = 4
    end

    config.vm.define "k8s-master" do |master|
        master.vm.box = IMAGE_NAME
        master.vm.network "private_network", ip: "192.168.50.10"
        master.vm.hostname = "k8s-master"
        master.vm.provision "ansible" do |ansible|
            ansible.playbook = "ansible/master-playbook.yaml"
            ansible.extra_vars = {
                node_ip: "192.168.50.10",
            }
        end
    end

    (1..N).each do |i|
        config.vm.define "node-#{i}" do |node|
            node.vm.box = IMAGE_NAME
            node.vm.network "private_network", ip: "192.168.50.#{i + 10}"
            node.vm.hostname = "node-#{i}"
            node.vm.provision "ansible" do |ansible|
                ansible.playbook = "ansible/node-playbook-before.yaml"
                ansible.extra_vars = {
                    node_ip: "192.168.50.#{i + 10}",
                }
            end
            node.vm.provision :reload
            node.vm.provision "ansible" do |ansible|
                ansible.playbook = "ansible/node-playbook-after.yaml"
                ansible.extra_vars = {
                    node_ip: "192.168.50.#{i + 10}",
                }
            end
            node.vm.synced_folder "~/python-helloworld/", "/home/vagrant/hello-python"
        end
    end
end
```
Creates a local environment with 2 virtual machines (1 for Kubernetes Master Node, 1 for Kubernetes Worker Node) using *ubuntu/focal64* as base image and *virtualbox* as provider. Virtual memory and virtual CPU values are set as 4096 and 4 respectively for each VM to avoid resource issues.

On the master node,

- IP address is set as '192.168.50.10'
- Hostname as 'k8s-master'
- 'master-playbook.yaml' is run in the provision state

On the worker node,

- IP address is set as automatically '192.168.50.#{i + 10}'
- Hostname as 'node-#{i}'
- 'node-playbook-before.yaml' is run in the first provision state
- then VM is reloaded in order vagrant user to run docker operations
- 'node-playbook-after.yaml' is run in the last provision state
- '~/python-helloworld/' folder (Python app repository is cloned here) is synced to the '/home/vagrant/hello-python' path in the VM

## Challenges/Missing Parts
Continous Delivery cannot be implemented. Many solutions has been tried but the main problem is to notify the VM when there is a file change on the local machine. Although the application directory is synced with Vagrant, VM cannot detect the changes (File sync works by the way). Solutions like *vagrant-notify-forwarder* or *vagrant-fsnotify* did not work. The main objective was to detect file changes in VM and run **skaffold run**.

Before thinking to run skaffold in the VM, running it on the local has also been tried. However, issue with that approach was pushing container images into the VM. Creating a private Docker registry in the VM might be the solution but it also came with other issues and canceled.

Therefore, after the code changes, **vagrant ssh node-1 -- -c 'cd /home/vagrant/hello-python && skaffold run; /bin/bash'** should be run manually on local machine or **skaffold run** in the VM.