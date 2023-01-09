# TrinityCore-on-GCP-GKE

**TrinityCore-on-GCP-GKE** help you to deploy open source MMORPG framework(TrinityCore) backend service to Google Cloud GKE. To simplify deployment complexity, the kubernetes operator is used to complete the auth server and world server deployment.

Open source MMORPG framework backend service base on [TrinityCore](https://github.com/TrinityCore/TrinityCore).

TrinityCore container image from [here](https://gitlab.com/nicolaw/trinitycore/-/tree/master).

The Kubernetes operator develop framework is [shell-operator](https://github.com/flant/shell-operator).

In order to register an account more conveniently, I developed [a simple program](https://github.com/hellof20/TrinityCoreRegisiter) that can be registered through the web UI. 

# Architeure

<img width="819" alt="image" src="https://user-images.githubusercontent.com/8756642/211265827-a4f2674f-f66d-4c11-a400-496e363a1fda.png">



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
gcloud container clusters create mygameclsuter \
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
kubectl apply -f game-operator/crd/
```

## Deploy the operator
```
kubectl apply -f game-operator/game-operator.yaml
```
Wait for the game-operator pod to be running
```
kubectl -n game-operator get po
```


## Deploy Guide
- deploy the game
```
kubectl apply -f game/game.yaml
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

## Register user account and Download game client.
- open http://sdk_server_ip_address in your browser
- input your username and password

![image](https://user-images.githubusercontent.com/8756642/199389438-7215ad12-d056-4062-aaa5-60fb15ee3006.png)

- when download is finished, unzip it


## Change client auth IP to your auth IP
- Open realmlist.wtf in Data\zhCN
- replace your auth external ip

![image](https://user-images.githubusercontent.com/8756642/199389288-60ba584d-2051-4ddf-b572-5abc2e7e0b1a.png)


## Play the game


## Add a new realm server
- copy game/realm.yaml to a new yaml file
- modiy metadata.name, id, name. The id cannot be the same as the existing id
- deploy a new realm server with kubectl
```
kubectl apply -f xxx.yaml
kubectl get realm
```

