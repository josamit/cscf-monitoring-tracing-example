#!/usr/bin/env bash

set -e

# check the status if 0 all is good else delete and restart
if [[ $(minikube status | grep 'fix') = *fix* ]]; then
  echo -e "\nMinikube was stopped, starting MiniKube Installation"

  minikube config set vm-driver hyperkit
  echo -e "\nStarting MiniKube Installation"
  minikube start --cpus 4 --memory 4096

  echo -e "\nMiniKube Configured"
elif ! minikube status &> /dev/null; then
  minikube stop
  echo -e "\nDeleting MiniKube Installation"
  minikube delete

  minikube config set vm-driver hyperkit
  echo -e "\nStarting MiniKube Installation"
  minikube start --cpus 4 --memory 4096

  echo -e "\nMiniKube Configured"
fi

eval $(minikube docker-env)

export dockerHost=$(env | grep DOCKER | grep DOCKER_HOST | cut -d = -f 2-)
echo -e "\nDocker Host $dockerHost"

#run build
echo -e "\nCreating docker Images for account and order manager."
mvn clean install docker:build -Djdk.tls.client.protocols=TLSv1.2 -DdockerHost=$dockerHost

echo -e "\nAdding and updating helm repos."
# Add helm repos
helm repo add stable https://kubernetes-charts.storage.googleapis.com/
helm repo update

# install prometheus components
if [[ $(helm status prometheus | grep STATUS | cut -d : -f 2-) = *deployed* ]]; then
  echo -e "\nPrometheus is already installed, skipping!"
elif [[ $(helm status prometheus | grep STATUS | cut -d : -f 2-) = *failed* ]]; then
  echo -e "\nPrevious prometheus installation failed."
  echo -e "\nDeleting previous prometheus installation."
  helm delete prometheus > /dev/null 2>&1
  echo -e "\nInstalling prometheus services."
  helm install prometheus stable/prometheus-operator
else
  echo -e "\nInstalling prometheus services."
  helm install prometheus stable/prometheus-operator
fi

# apply service definitions
echo -e "\nInstalling service definitions."
kubectl apply -f ./Deployment/

# install jaeger components
echo -e "\nInstalling jaeger services."
kubectl apply -f ./jaeger

# enable port forwarding for prometheus, alert manager and grafana
while [[ $(kubectl get pods --selector=app=prometheus -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for prometheus pod to be up..." && sleep 1; done
kubectl port-forward $(kubectl get pods --selector=app=prometheus --output=jsonpath="{.items..metadata.name}") -n default 9090 > /dev/null 2>&1 &
echo -e "\nPrometheus UI is now available at : http://localhost:9090"

while [[ $(kubectl get pods --selector=app=alertmanager -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for prometheus pod to be up..." && sleep 1; done
kubectl port-forward $(kubectl get pods --selector=app=alertmanager --output=jsonpath="{.items..metadata.name}") -n default 9093 > /dev/null 2>&1 &
echo -e "\nAlertManager UI is now available at : http://localhost:9093"

while [[ $(kubectl get pods --selector=app.kubernetes.io/name=grafana -o 'jsonpath={..status.conditions[?(@.type=="Ready")].status}') != "True" ]]; do echo "waiting for prometheus pod to be up..." && sleep 1; done
kubectl port-forward $(kubectl get pods --selector=app.kubernetes.io/name=grafana --output=jsonpath="{.items..metadata.name}") -n default 3000 > /dev/null 2>&1 &
echo -e "\nGrafana is now available at : http://localhost:3000"

export jaegerQueryUi=$(minikube service --url jaeger-query)
echo -e "\nJaeger Query UI is now available at : $jaegerQueryUi"

echo -e "\nUpgrading prometheus service definitions."
helm upgrade prometheus stable/prometheus-operator --values=./prometheus/prometheus-values.yaml

read -r -p "Do you want to generate api calls for metrics and traces? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo -e "\nGenerating random api calls..."
  export ORDERMGR=$(minikube service order-manager --url)
  ./genorders.sh > /dev/null 2>&1 &
fi

read -r -p "Do you want to open minikube dashboard? [y/N] " response
if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]
then
  echo -e "\nStarting minikube dashboard..."
  minikube dashboard > /dev/null 2>&1 &
else
  echo -e "\nFinished"
fi
