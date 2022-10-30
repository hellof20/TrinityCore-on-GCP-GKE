#!/bin/bash
docker build -t asia.gcr.io/gcp-wow/wow-operator:v1 .
docker push asia.gcr.io/gcp-wow/wow-operator:v1
kubectl delete -f wow-operator-pod.yaml
kubectl apply -f wow-operator-pod.yaml
