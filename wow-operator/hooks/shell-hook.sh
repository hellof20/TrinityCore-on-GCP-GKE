#!/usr/bin/env bash
wowAdd(){
  echo "====================================="
  # update wow status to creating
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"creating\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
  
  ## create mysql
  if [[ ${create_mysql} == "yes" ]]; then
    # generate mysql yaml
    envsubst < mysql-template.yaml  > mysql.yaml
    kubectl -n ${namespace} apply -f mysql.yaml
    waitTime=0
    until [ $(kubectl -n ${namespace} get deployment/mysql -o json | jq '.status.availableReplicas') -ge 1 ]; do
      sleep 10;
      echo "waited ${waitTime} secconds for mysql to be ready ..."
      if [ ${waitTime} -gt 300 ]; then
        echo "wait too long, failed."
        # update wow status to failed
        curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
        return 1
      fi
    done
    mysql_host=$(kubectl -n ${namespace} get svc mysql -o jsonpath='{.spec.clusterIP}')
    echo "mysql_host is ${mysql_host}"
  fi


  ## create sdk
  # generate sdk yaml
  envsubst < sdk-template.yaml  > sdk.yaml
  # create sdk deploy and svc
  kubectl -n ${namespace} apply -f sdk.yaml
  # wait unitl sdk pod is running and svc get external ip
  waitTime=0
  sdk_ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/sdk -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc sdk -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for sdk to be ready ..."
    if [ ${waitTime} -gt 300 ]; then
      sdk_ready="failed"
      echo "wait too long, failed."
      # update wow status to failed
      curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status      
      return 1
    fi
  done
  sdk_external_ip=$(kubectl -n ${namespace} get svc sdk -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  # update wow sdk external ip
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"sdk_external_ip\":\"${sdk_external_ip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status

  ## create realm server
  # create realm database
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate realm conf
  envsubst < realm-template.conf  > realm-${realm_id}.conf
  # generate realm yaml
  envsubst < realm-template.yaml  > realm-${realm_id}.yaml
  # create configmap from realm conf
  kubectl -n ${namespace} create configmap realm-${realm_id}-configmap --from-file=realm-${realm_id}.conf
  # create realm deploy and svc
  kubectl -n ${namespace} apply -f realm-${realm_id}.yaml
  # wait unitl realm pod is running
  waitTime=0
  realm_ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/realm-${realm_id} -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc realm-${realm_id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for realm to running ..."
    if [ ${waitTime} -gt 300 ]; then
      realm_ready="failed"
      echo "wait too long, failed."
      # update wow status to failed
      curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status      
      return 1
    fi
  done
  # get realm public ip
  realm_external_ip=$(kubectl -n ${namespace} get svc realm-${realm_id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  # add realm info to auth.realmlist table
  mysql --host=$host --user=$user --password=$password --execute="insert into auth.realmlist(id,name,address) values(${realm_id},'${realm_name}','${realm_external_ip}');"


  ## create auth server
  # generate auth conf
  envsubst < auth-template.conf  > auth.conf
  # generate auth yaml
  envsubst < auth-template.yaml  > auth.yaml
  # create configmap from auth conf
  kubectl -n ${namespace} create configmap auth-configmap --from-file=auth.conf
  # create auth deploy and svc
  kubectl -n ${namespace} apply -f auth.yaml
  # wait unitl auth pod and svc is running
  waitTime=0
  auth_ready="ok"
  until [ $(kubectl -n ${namespace} get deployment/auth -o json | jq '.status.availableReplicas') -ge 1 ] && [ $(kubectl -n ${namespace} get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}') ]; do
    sleep 10;
    waitTime=$(expr ${waitTime} + 10)
    echo "waited ${waitTime} secconds for auth to running ..."
    if [ ${waitTime} -gt 300 ]; then
      auth_ready="failed"
      echo "wait too long, failed."
      # update wow status to failed
      curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"failed\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
      return 1
    fi
  done
  auth_external_ip=$(kubectl -n ${namespace} get svc auth -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
  # update auth external ip
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"auth_external_ip\":\"${authexternal_ip}\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status
  # update wow status to ok
  curl -X PATCH --cacert ${CACERT} -H "Content-Type: application/merge-patch+json" --header "Authorization: Bearer ${TOKEN}" -d "{\"status\":{\"ready\":\"ok\"}}" ${APISERVER}/apis/stable.example.com/v1/namespaces/${namespace}/wows/${kind_name}/status    
  echo "====================================="  
  return 0
}

wowDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f sdk.yaml
  kubectl -n ${namespace} delete -f auth.yaml
  kubectl -n ${namespace} delete configmap auth-configmap
  kubectl -n ${namespace} delete -f realm-${realm_id}.yaml
  kubectl -n ${namespace} delete configmap realm-${realm_id}-configmap
  mysql --host=${mysql_host} --user=${mysql_user} --password=${mysql_password} --execute="drop database auth;drop database ${realm_id}_world;drop database ${realm_id}_characters;"  
  if [[ ${create_mysql} == "yes" ]]; then
    kubectl -n ${namespace} delete -f mysql.yaml
  fi
  # 删除finalizers标记，wow自动删除
  kubectl -n ${namespace} patch wow/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'  
  echo "=====================================" 
}


sdkAdd(){
  echo "====================================="  
  # generate sdk yaml
  envsubst < sdk-template.yaml  > sdk.yaml
  # create sdk deploy and svc
  kubectl -n ${namespace} apply -f sdk.yaml
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
      break
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
}

sdkDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f sdk.yaml
  # 删除finalizers标记，sdk自动删除
  kubectl -n ${namespace} patch sdk/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'
  echo "====================================="
}

authAdd(){
  echo "====================================="
  # create auth database
  mysql --host=$host --user=$user --password=$password --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate auth conf
  envsubst < auth-template.conf  > auth.conf
  # generate auth yaml
  envsubst < auth-template.yaml  > auth.yaml
  # create configmap from auth conf
  kubectl -n ${namespace} create configmap auth-configmap --from-file=auth.conf
  # create auth deploy and svc
  kubectl -n ${namespace} apply -f auth.yaml
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
    echo "waited ${waitTime} secconds for auth pod to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      break
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
}

authDelete(){
  echo "====================================="
  kubectl -n ${namespace} delete -f auth.yaml
  kubectl -n ${namespace} delete configmap auth-configmap
  # delete auth database
  mysql --host=$host --user=$user --password=$password --execute="drop database auth;"  
  # 删除finalizers标记，auth自动删除
  kubectl -n ${namespace} patch auth/${kind_name} --type json --patch='[ { "op": "remove", "path": "/metadata/finalizers" } ]'  
  echo "====================================="
}

realmAdd(){
  echo "====================================="
  # create realm database
  mysql --host=$host --user=$user --password=$password --execute="CREATE DATABASE IF NOT EXISTS auth DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_world DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;CREATE DATABASE IF NOT EXISTS ${realm_id}_characters DEFAULT CHARACTER SET utf8 COLLATE utf8_general_ci;"
  # generate realm conf
  envsubst < realm-template.conf  > realm-${realm_id}.conf
  # generate realm yaml
  envsubst < realm-template.yaml  > realm-${realm_id}.yaml
  # create configmap from realm conf
  kubectl -n ${namespace} create configmap realm-${realm_id}-configmap --from-file=realm-${realm_id}.conf
  # create realm deploy and svc
  kubectl -n ${namespace} apply -f realm-${realm_id}.yaml
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
    echo "waited ${waitTime} secconds for realm pod to running ..."
    if [ ${waitTime} -gt 300 ]; then
      ready="failed"
      echo "wait too long, failed."
      break
    fi
  done

  if [[ ${ready} == "ok" ]];then
    # get realm public ip
    publicip=$(kubectl -n ${namespace} get svc realm-${realm_id} -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
    # add realm info to auth.realmlist table
    mysql --host=$host --user=$user --password=$password --execute="insert into auth.realmlist(id,name,address) values(${realm_id},'${realm_name}','${publicip}');"
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
  kubectl -n ${namespace} delete -f realm-${realm_id}.yaml
  kubectl -n ${namespace} delete configmap realm-${realm_id}-configmap
  # delete realm info in auth.realmlist table
  mysql --host=$host --user=$user --password=$password --execute="delete from auth.realmlist where id = ${realm_id};"
  # delete realm database
  mysql --host=$host --user=$user --password=$password --execute="drop database ${realm_id}_world;drop database ${realm_id}_characters;"
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
      echo "Trigger WOW Delete"
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