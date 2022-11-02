# WoW-on-gke

**WoW-on-gke** help you to deploy World of Warcraft 3.3.5 backend service to Google Cloud GKE. To simplify deployment complexity, the wow operator is used to complete the auth server and world server deployment.

World of Warcraft 3.3.5 backend service base on [TrinityCore](https://github.com/TrinityCore/TrinityCore).

TrinityCore container image from [here](https://gitlab.com/nicolaw/trinitycore/-/tree/master).

The k8s operator develop framework is [shell-operator](https://github.com/flant/shell-operator).

In order to register an account more conveniently, I developed [a simple program](https://github.com/hellof20/TrinityCoreRegisiter) that can be registered just through the UI. 

## Before you begin
- You have two options to run World of Warcraft game client.
  1. PC computer with Windows OS.
  2. VM from Google CLoud with GPU and use Parsec to streaming.
- You have installed gcloud and kubectl command tool.
- You have necessary permission to create GKE cluster.
- You have necessary permission to manage role and rolebinding in your GKE cluster.
- Please deploy under GKE default namespace.

## Prepare GKE Cluster（Optional）
if you already have a gke cluster, you can skip this step.
- create your GKE Cluster
```
gcloud container clusters create wow \
    --cluster-version=1.23 \
    --no-enable-autoupgrade \
    --machine-type=e2-standard-4 \
    --num-nodes=1 \
    --zone asia-east2-a
```
- validate the Cluster
```
kubectl get nodes
```

## Deploy MySQL on GKE（Optional）
If you already have MySQL, you can skip this step.
- create MySQL
```
kubectl apply -f mysql/mysql.yaml
```
- create K8S configmap from your MySQL parameters
```
kubectl create configmap mysql-config --from-literal=host="mysql" --from-literal=user="root" --from-literal=password="password"
```
Notice: if you don't create mysql use previous step, then you need to replace values of host, user and password.


## Deploy WoW operator
- create auth server and world server crd
```
kubectl apply -f wow-operator/auth-crd.yaml
kubectl apply -f wow-operator/realm-crd.yaml
```
- create rbac
```
kubectl apply -f wow-operator/wow-operator-rbac.yaml
```
- create operator pod
```
kubectl apply -f wow-operator/wow-operator-pod.yaml
```

## Deploy backend service
- deploy sdk server

sdk server is used to register user account.
```
kubectl apply -f wow/sdk.yaml
```
- deploy realm server
```
kubectl apply -f wow/realm.yaml
```
- deploy auth server
```
kubectl apply -f wow/auth.yaml
```

- check auth server and realm status are health

At begining, you will see auth and realm status is 'creating', wait some minutes until auth and realm status are 'ok'.
```
kubectl get auth
kubectl get realm
```

- get sdk server external ip address
```
kubectl get svc -l "app=sdk"
```
EXTERNAL-IP column is the sdk external ip address.

- get auth server external ip address
```
kubectl get auth
```
EXTERNAL-IP column is the auth server external ip address.

## Register user account and Download World of Warcraft game client.
- open http://sdk_server_ip_address in your browser
- input your username and password

![image](https://user-images.githubusercontent.com/8756642/199389438-7215ad12-d056-4062-aaa5-60fb15ee3006.png)

- when download is finished, unzip it


## Change client auth IP to your auth IP
- Open realmlist.wtf in Data\zhCN
- replace your auth external ip

![image](https://user-images.githubusercontent.com/8756642/199389288-60ba584d-2051-4ddf-b572-5abc2e7e0b1a.png)


## Play your World of Warcraft
![image](https://user-images.githubusercontent.com/8756642/199390094-b5512728-87a8-4e85-89cc-90c5d6b36f4a.png)


## Add a new realm server
- copy wow/realm.yaml to a new file
- modiy metadata.name, id, name. The id cannot be the same as the existing id
- deploy a new realm server with kubectl
```
kubectl apply -f xxx.yaml
kubectl get realm
```

