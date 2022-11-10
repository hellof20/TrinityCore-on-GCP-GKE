#!/usr/bin/env bash
wowAdd(){
  echo "====================================="
  # update wow status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
  
  ## create mysql
  if [[ ${create_mysql} == "yes" ]]; then
    # generate mysql yaml
    envsubst < mysql-template.yaml  > ${namespace}-mysql.yaml
    kubectl -n ${namespace} apply -f ${namespace}-mysql.yaml
    waitTime=0
    until [ $(kubectl -n ${namespace} get deployment/mysql -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc mysql -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
      sleep 10;
      waitTime=$(expr ${waitTime} + 10)
      echo "waited ${waitTime} secconds for mysql to be ready ..."
      if [ ${waitTime} -gt 500 ]; then
        echo "wait too long, failed."
        # update wow status to failed
        curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
        return 1
      fi
    done
    mysql_host=$(kubectl -n ${namespace} get svc mysql -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    echo "mysql_host is ${mysql_host}"
  fi
  # create mysql config for sdk\auth\realm
  kubectl -n ${namespace} create configmap mysql-config --from-literal=host=${mysql_host} --from-literal=user=${mysql_user} --from-literal=password=${mysql_password}

  # generate auth crd resource yaml
  envsubst < auth-crd-template.yaml  > ${namespace}-auth-crd.yaml
  # create auth crd resource
  kubectl -n ${namespace} apply -f ${namespace}-auth-crd.yaml

  # generate realm crd resource yaml
  envsubst < realm-crd-template.yaml  > ${namespace}-realm-${realm_id}-crd.yaml
  # create realm crd resource
  kubectl -n ${namespace} apply -f ${namespace}-realm-${realm_id}-crd.yaml  

  # generate sdk crd resource yaml
  envsubst < sdk-crd-template.yaml  > ${namespace}-sdk-crd.yaml
  # create sdk crd resource
  kubectl -n ${namespace} apply -f ${namespace}-sdk-crd.yaml

  waitTime=0
  ready="ok"
  until [[ $(kubectl -n ${namespace} get sdk/${kind_name}-sdk -o jsonpath='{.status.ready}') == "ok" ]] && [[ $(kubectl -n ${namespace} get auth/${kind_name}-auth-server -o jsonpath='{.status.ready}') == "ok" ]] && [[ $(kubectl -n ${namespace} get realm/${kind_name}-realm-${realm_id}-server -o jsonpath='{.status.ready}') == "ok" ]]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for wow to be ready ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      return 1
    fi
  done

  if [[ ${ready} == "ok" ]];then
    # update wow status
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
  else
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
    return 1
  fi
  echo "====================================="  
  return 0
}

wowDelete(){
  kubectl -n ${namespace} delete configmap mysql-config
  kubectl -n ${namespace} delete -f ${namespace}-sdk-crd.yaml
  kubectl -n ${namespace} delete -f ${namespace}-auth-crd.yaml
  kubectl -n ${namespace} delete -f ${namespace}-realm-${realm_id}-crd.yaml
  if [[ ${create_mysql} == "yes" ]]; then
    kubectl -n ${namespace} delete -f ${namespace}-mysql.yaml
  fi
  kubectl -n ${namespace} patch wow/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
}

sdkAdd(){
  echo "====================================="  
  # generate sdk yaml
  envsubst < sdk-template.yaml  > ${namespace}-sdk.yaml
  # create sdk deploy and svc
  kubectl -n ${namespace} apply -f ${namespace}-sdk.yaml
  # wait unitl sdk pod is running and svc get external ip
  waitTime=0
  ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/sdk -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc sdk -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for sdk to be ready ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      return 1
    fi
  done
  if [[ ${ready} == "ok" ]];then
    external_ip=$(kubectl -n ${namespace} get svc sdk -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # update sdk external ip
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"${external_ip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/sdks/${kind_name}/status
    # update sdk status to ok
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/sdks/${kind_name}/status
  else
    # update sdk status to failed
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/sdks/${kind_name}/status
  fi  
  echo "====================================="  
  return 0
}

sdkDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f ${namespace}-sdk.yaml
  # 删除finalizers标记，sdk自动删除
  kubectl -n ${namespace} patch sdk/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
  echo "====================================="
}

authAdd(){
  echo "====================================="
  export mysql_host=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.host}')
  export mysql_user=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.user}')
  export mysql_password=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.password}')  
  # create auth database
  # mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate auth conf
  envsubst < auth-template.conf  > ${namespace}-auth.conf
  # generate auth yaml
  envsubst < auth-template.yaml  > ${namespace}-auth.yaml
  # create configmap from auth conf
  kubectl -n ${namespace} create configmap auth-configmap --from-file=${namespace}-auth.conf
  # create auth deploy and svc
  kubectl -n ${namespace} apply -f ${namespace}-auth.yaml
  # update auth status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  # update auth external ip to pending
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"pending\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  # wait unitl auth pod is running
  waitTime=0
  ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/auth -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for auth server to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      return 1
    fi
  done
  if [[ ${ready} == "ok" ]];then
    external_ip=$(kubectl -n ${namespace} get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # update auth external ip
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"${external_ip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
    # update auth status to ok
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  else
    # update auth status to failed
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/auths/${kind_name}/status
  fi
  echo "====================================="
  return 0
}

authDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f ${namespace}-auth.yaml
  kubectl -n ${namespace} delete configmap auth-configmap
  # delete auth database
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="drop database auth;"  
  # 删除finalizers标记，auth自动删除
  kubectl -n ${namespace} patch auth/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'  
  echo "====================================="
}

realmAdd(){
  echo "====================================="
  export mysql_host=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.host}')
  export mysql_user=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.user}')
  export mysql_password=$(kubectl -n ${namespace} get configmap mysql-config -o jsonpath='{.data.password}')
  # create realm database
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate realm conf
  envsubst < realm-template.conf  > ${namespace}-realm-${realm_id}.conf
  # generate realm yaml
  envsubst < realm-template.yaml  > ${namespace}-realm-${realm_id}.yaml
  # create configmap from realm conf
  kubectl -n ${namespace} create configmap realm-${realm_id}-configmap --from-file=${namespace}-realm-${realm_id}.conf
  # create realm deploy and svc
  kubectl -n ${namespace} apply -f ${namespace}-realm-${realm_id}.yaml
  # update realm status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  # update realm external ip to pending
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"pending\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status    
  # wait unitl realm pod is running
  waitTime=0
  ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/realm-${realm_id} -o json | jq '.status.availableReplicas') == "1" ] && [ $(kubectl -n ${namespace} get svc realm-${realm_id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "create realm server,waited ${waitTime} secconds for realm server to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      return 1
    fi
  done

  if [[ ${ready} == "ok" ]];then
    # get realm public ip
    publicip=$(kubectl -n ${namespace} get svc realm-${realm_id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # add realm info to auth.realmlist table
    mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="delete from auth.realmlist where id = 1;"
    mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="insert into auth.realmlist(id,name,address) values(${realm_id},'${realm_name}','${publicip}');"
    #restart realm
    kubectl -n ${namespace} delete po -l app=realm-${realm_id}
    # update realms external ip
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"external_ip\":\"${publicip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status    
    # update realm status to ok
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  else
    # update auth status to failed
    curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/realms/${kind_name}/status
  fi
  echo "====================================="
  return 0
}

realmDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f ${namespace}-realm-${realm_id}.yaml
  kubectl -n ${namespace} delete configmap realm-${realm_id}-configmap
  # delete realm info in auth.realmlist table
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="delete from auth.realmlist where id = ${realm_id};"
  # delete realm database
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="drop database ${realm_id}_world;drop database ${realm_id}_characters;"
  # 删除finalizers标记，realm自动删除
  kubectl -n ${namespace} patch realm/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
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
    },
    {
      "apiVersion": "stable.example.com/v1",
      "kind": "SDK",
      "executeHookOnEvent":["Added","Deleted","Modified"],
      "queue": "handle-sdk-queue"
    },
    {
      "apiVersion": "stable.example.com/v1",
      "kind": "WOW",
      "executeHookOnEvent":["Added","Deleted","Modified"],
      "queue": "handle-wow-queue"
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
  export namespace=$(jq -r '.[0].object.metadata.namespace' ${BINDING_CONTEXT_PATH})
  export kind_name=$(jq -r '.[0].object.metadata.name' ${BINDING_CONTEXT_PATH})
  export kind=$(jq -r '.[0].object.kind' ${BINDING_CONTEXT_PATH})

  if [[ $type == "Synchronization" ]] ; then
    echo "Got Synchronization event"
    exit 0
  fi

  if [[ $kind == "WOW" ]]; then
    export realm_id=$(jq -r '.[0].object.spec.realm_id' ${BINDING_CONTEXT_PATH})
    export realm_name=$(jq -r '.[0].object.spec.realm_name' ${BINDING_CONTEXT_PATH})
    export realm_image=$(jq -r '.[0].object.spec.realm_image' ${BINDING_CONTEXT_PATH})
    export auth_image=$(jq -r '.[0].object.spec.auth_image' ${BINDING_CONTEXT_PATH})
    export auth_replicas=$(jq -r '.[0].object.spec.auth_replicas' ${BINDING_CONTEXT_PATH})
    export sdk_port=$(jq -r '.[0].object.spec.sdk_port' ${BINDING_CONTEXT_PATH})
    export sdk_image=$(jq -r '.[0].object.spec.sdk_image' ${BINDING_CONTEXT_PATH})
    export sdk_replicas=$(jq -r '.[0].object.spec.sdk_replicas' ${BINDING_CONTEXT_PATH})
    export mysql_host=$(jq -r '.[0].object.spec.mysql_host' ${BINDING_CONTEXT_PATH})
    export mysql_user=$(jq -r '.[0].object.spec.mysql_user' ${BINDING_CONTEXT_PATH})
    export mysql_password=$(jq -r '.[0].object.spec.mysql_password' ${BINDING_CONTEXT_PATH})
    export create_mysql=$(jq -r '.[0].object.spec.create_mysql' ${BINDING_CONTEXT_PATH})
    echo "create_mysql is ${create_mysql}"

    if [[ $resourceEvent == "Added" ]] ; then
      echo "Trigger WOW Add"
      if wowAdd; then
        echo 'wow add success'
      else
        echo 'wow add failed'
      fi
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      echo ${delete_flag}
      if [ ${#delete_flag} -gt 10 ]; then
        wowDelete
      fi
    fi
  elif [[ $kind == "Realm" ]]; then
    export realm_id=$(jq -r '.[0].object.spec.id' ${BINDING_CONTEXT_PATH})
    export realm_name=$(jq -r '.[0].object.spec.name' ${BINDING_CONTEXT_PATH})
    export realm_image=$(jq -r '.[0].object.spec.image' ${BINDING_CONTEXT_PATH})
    if [[ $resourceEvent == "Added" ]] ; then
      realmAdd
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      echo "Realm Modified event"
      echo ${delete_flag}
      if [ ${#delete_flag} -gt 10 ]; then
        realmDelete
      fi
    fi
  elif [[ $kind == "Auth" ]]; then
    export auth_port=$(jq -r '.[0].object.spec.port' ${BINDING_CONTEXT_PATH})
    export auth_image=$(jq -r '.[0].object.spec.image' ${BINDING_CONTEXT_PATH})
    export auth_replicas=$(jq -r '.[0].object.spec.replicas' ${BINDING_CONTEXT_PATH})
    if [[ $resourceEvent == "Added" ]] ; then
      authAdd
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      if [ ${#delete_flag} -gt 10 ]; then
        authDelete
      fi    
    fi
  elif [[ $kind == "SDK" ]]; then
    export sdk_port=$(jq -r '.[0].object.spec.port' ${BINDING_CONTEXT_PATH})
    export sdk_image=$(jq -r '.[0].object.spec.image' ${BINDING_CONTEXT_PATH})
    export sdk_replicas=$(jq -r '.[0].object.spec.replicas' ${BINDING_CONTEXT_PATH})
    if [[ $resourceEvent == "Added" ]] ; then
      sdkAdd
    elif [[ $resourceEvent == "Modified" ]]; then
      delete_flag=$(jq -r '.[0].object.metadata.deletionTimestamp' ${BINDING_CONTEXT_PATH})
      if [ ${#delete_flag} -gt 10 ]; then
        sdkDelete
      fi    
    fi    
  fi
fi