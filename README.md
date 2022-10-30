# wow-on-gke

**wow-on-gke** help to deploy World of Warcraft 3.3.5 (TrinityCore) backend service to Google Cloud GKE. To simplify deployment complexity, the wow operator is used to complete the entire deployment

## Before you begin
- You have two options to run World of Warcraft client
1. PC computer with Windows OS.
2. VM from Google CLoud with GPU and use Parsec to streaming.

## Prepare GKE Cluster
- create GKE autopilot Cluster
```
```
- validate the Cluster
```
kubectl get nodes
```

## Deploy MySQL on GKE
- create MySQL
```
```

## Deploy wow operator
- create K8S configmap from MySQL parameters
```
kubectl create configmap mysql-config --from-literal=host="mysql_ip_address" --from-literal=user="mysql_user" --from-literal=password="mysql_password"
```
replace mysql_ip_address, mysql_user and mysql_password

- deploy operator
create wow crd
```
kubectl apply -f wow-operator/auth-crd.yaml
kubectl apply -f wow-operator/realm-crd.yaml
```
create rbac
```
kubectl apply -f wow-operator/wow-operator-rbac.yaml
```

create operator pod
```
kubectl apply -f wow-operator/wow-operator-pod.yaml
```

## Deploy backend service
- deploy sdk server

sdk server is used to register user account.
```
kubectl apply -f wow/sdk.yaml
```
- deploy auth server
```
kubectl apply -f wow/auth.yaml
```
- deploy realm server
```
kubectl apply -f wow/realm.yaml
```

- check auth server and realm status are health

At begining, you will see auth and realm status is 'creating', wait some minutes until auth and realm status are ok.
```
kubectl get auth
kubectl get realm
```

- get sdk server external ip address
```
kubectl get svc -l 
```

- get auth server external ip address
```
kubectl get auth
```

## Register user account.
- open http://sdk_server_ip_address in your browser
- input your username and password


## Download World of Warcraft client
- Open http://sdk_server_ip_address in your browser, you can see the download link. 
- when download is finished, unzip it


## change client auth IP to your auth IP


## Play your World of Warcraft



