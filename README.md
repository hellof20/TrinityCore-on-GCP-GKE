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

## Deploy CRD include wow,sdk,auth,realm
```
kubectl apply -f wow-operator/crd/
```

## Deploy WoW operator
```
kubectl apply -f wow-operator/wow-operator.yaml
```
Wait for the wow-operator pod to be running
```
kubectl -n wow-operator get po
```


## Deploy WoW
- deploy your WoW
```
kubectl apply -f wow/wow.yaml
```

- At begining, you will see wow status is 'creating', wait some minutes until wow status are 'ok'.
```
kubectl get wow
```

- get sdk server external ip address
```
kubectl get sdk
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

