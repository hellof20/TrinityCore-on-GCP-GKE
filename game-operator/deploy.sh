#!/bin/bash
#docker build -t asia.gcr.io/gcp-wow/wow-operator:v2 .
#docker push asia.gcr.io/gcp-wow/wow-operator:v2
docker build -t hellof20/wow-operator:v2 .
docker push hellof20/wow-operator:v2
kubectl delete -f wow-operator.yaml
sleep 2
kubectl apply -f wow-operator.yaml
