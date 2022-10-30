#!/usr/bin/env bash

authAdd(){
  echo "====================================="
  # create auth database
  mysql --host=$host --user=$user --password=$password --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate auth conf
  envsubst < auth-template.conf  > auth.conf
  # generate auth yaml
  envsubst < auth-template.yaml  > auth.yaml
  # create configmap from auth conf
  kubectl create configmap auth-configmap --from-file=auth.conf
  # create auth deploy and svc
  kubectl apply -f auth.yaml
  # update auth status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  # update auth external ip to pending
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"pending\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  # wait unitl auth pod is running
  waitTime=0
  ready="ok"
  until [ $(kubectl get deployment/auth -o json | jq '.status.availableReplicas') == "1" ] && [ $(kubectl get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for auth pod to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      break
    fi
  done
  if [[ ${ready} == "ok" ]];then
    external_ip=$(kubectl get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # update auth external ip
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"${external_ip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
    # update auth status to ok
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  else
    # update auth status to failed
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  fi
  echo "====================================="
}

authDelete(){
  echo "====================================="
  kubectl delete -f auth.yaml
  kubectl delete configmap auth-configmap
  # delete auth database
  mysql --host=$host --user=$user --password=$password --execute="drop database auth;"  
  echo "====================================="
}

realmAdd(){
  echo "====================================="
  # create realm database
  mysql --host=$host --user=$user --password=$password --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${id}_world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${id}_characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate realm conf
  envsubst < realm-template.conf  > realm-${id}.conf
  # generate realm yaml
  envsubst < realm-template.yaml  > realm-${id}.yaml
  # create configmap from realm conf
  kubectl create configmap realm-${id}-configmap --from-file=realm-${id}.conf
  # create realm deploy and svc
  kubectl apply -f realm-${id}.yaml
  # update realm status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  # update realm external ip to pending
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"pending\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status    
  # wait unitl realm pod is running
  waitTime=0
  ready="ok"
  until [ $(kubectl get deployment/realm-${id} -o json | jq '.status.availableReplicas') == "1" ] && [ $(kubectl get svc realm-${id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for realm pod to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      break
    fi
  done

  if [[ ${ready} == "ok" ]];then
    # get realm public ip
    publicip=$(kubectl get svc realm-${id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # add realm info to auth.realmlist table
    mysql --host=$host --user=$user --password=$password --execute="insert into auth.realmlist(id,name,address) values(${id},'${name}','${publicip}');"
    # update realms external ip
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"${publicip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status    
    # update realm status to ok
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  else
    # update auth status to failed
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  fi
  echo "====================================="
}

realmDelete(){
  echo "====================================="
  kubectl delete -f realm-${id}.yaml
  kubectl delete configmap realm-${id}-configmap
  # delete realm info in auth.realmlist table
  mysql --host=$host --user=$user --password=$password --execute="delete from auth.realmlist where id = ${id};"
  # delete realm database
  mysql --host=$host --user=$user --password=$password --execute="drop database ${id}_world;drop database ${id}_characters;"
  echo "====================================="
}

if [[ $1 == "--config" ]] ; then
  cat <<EOF
{
  "configVersion":"v1",
  "kubernetes":[
    {
      "apiVersion": "stable.example.com/v1",
      "kind": "Realm",
      "executeHookOnEvent":["Added","Deleted","Modified"],
      "queue": "handle-realm-queue"
    },
    {
      "apiVersion": "stable.example.com/v1",
      "kind": "Auth",
      "executeHookOnEvent":["Added","Deleted","Modified"],
      "queue": "handle-auth-queue"
    }
  ]
}
EOF
else
  type=$(jq -r '.[0].type' ${BINDING_CONTEXT_PATH})
  resourceEvent=`jq -r ".[0].watchEvent" $BINDING_CONTEXT_PATH`
  APISERVER=https://kubernetes.default.svc
  SERVICEACCOUNT=/var/run/secrets/kubernetes.io/serviceaccount
  TOKEN=$(cat ${SERVICEACCOUNT}/token)
  CACERT=${SERVICEACCOUNT}/ca.crt
  namespace=$(jq -r '.[0].object.metadata.namespace' ${BINDING_CONTEXT_PATH})
  kind_name=$(jq -r '.[0].object.metadata.name' ${BINDING_CONTEXT_PATH})
  kind=$(jq -r '.[0].object.kind' ${BINDING_CONTEXT_PATH})

  # mysql, todo: configmap
  export host=$host
  export user=$user
  export password=$password

  if [[ $type == "Synchronization" ]] ; then
    echo "Got Synchronization event"
    exit 0
  fi

  if [[ $kind == "Realm" ]]; then
    export id=$(jq -r '.[0].object.spec.id' ${BINDING_CONTEXT_PATH})
    export name=$(jq -r '.[0].object.spec.name' ${BINDING_CONTEXT_PATH})
    export image=$(jq -r '.[0].object.spec.image' ${BINDING_CONTEXT_PATH})
    if [[ $resourceEvent == "Added" ]] ; then
      realmAdd
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      echo "Realm Modified event"
      echo ${delete_flag}
      if [ ${#delete_flag} -gt 10 ]; then
        realmDelete
        # 删除finalizers标记，realm自动删除
        kubectl patch realm/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
      fi
    fi
  elif [[ $kind == "Auth" ]]; then
    export port=$(jq -r '.[0].object.spec.port' ${BINDING_CONTEXT_PATH})
    export image=$(jq -r '.[0].object.spec.image' ${BINDING_CONTEXT_PATH})
    if [[ $resourceEvent == "Added" ]] ; then
      authAdd
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      if [ ${#delete_flag} -gt 10 ]; then
        authDelete
        # 删除finalizers标记，auth自动删除
        kubectl patch auth/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
      fi    
    fi
  fi
fi