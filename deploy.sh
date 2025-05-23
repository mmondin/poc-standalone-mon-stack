#!/bin/bash

# Script to deploy the monitoring stack Helm chart

set -e  # Exit immediately if a command exits with a non-zero status

echo "===========================================" 
echo "Monitoring Stack Deployment Script"
echo "===========================================" 

# Default values
NAMESPACE="monitoring"
RELEASE_NAME="monitoring"
CHART_PATH="."
DRY_RUN="false"
TIMEOUT="10m"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  key="$1"
  case $key in
    -n|--namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    -r|--release)
      RELEASE_NAME="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN="true"
      shift
      ;;
    -t|--timeout)
      TIMEOUT="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: $0 [options]"
      echo "Options:"
      echo "  -n, --namespace NAMESPACE   Target namespace (default: monitoring)"
      echo "  -r, --release RELEASE_NAME  Helm release name (default: monitoring)"
      echo "  --dry-run                   Perform a dry run without installing"
      echo "  -t, --timeout DURATION      Deployment timeout (default: 10m)"
      echo "  -h, --help                  Show this help"
      exit 0
      ;;
    *)
      echo "Unknown option: $key"
      exit 1
      ;;
  esac
done

# Check if kubectl is available
if ! command -v kubectl &> /dev/null; then
    echo "Error: kubectl is not installed or not in PATH"
    exit 1
fi

# Check if Helm is available
if ! command -v helm &> /dev/null; then
    echo "Error: helm is not installed or not in PATH"
    exit 1
fi

echo "Checking Kubernetes connection..."
if ! kubectl get nodes &> /dev/null; then
    echo "Error: Cannot connect to Kubernetes cluster"
    exit 1
fi

echo "Creating namespace $NAMESPACE if it doesn't exist..."
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

echo "Adding Helm repositories..."
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo add grafana https://grafana.github.io/helm-charts
helm repo add open-telemetry https://open-telemetry.github.io/opentelemetry-helm-charts
helm repo update

echo "Validating Chart dependencies..."
helm dependency update $CHART_PATH

# Create the values file array
VALUES_FILES=()
VALUES_FILES+=("-f" "values.yaml")
VALUES_FILES+=("-f" "kube-prometheus-stack-values.yaml")
VALUES_FILES+=("-f" "tempo-values.yaml")
VALUES_FILES+=("-f" "loki-values.yaml")
VALUES_FILES+=("-f" "promtail-values.yaml")
VALUES_FILES+=("-f" "opentelemetry-collector-values.yaml")
VALUES_FILES+=("-f" "beyla-values")

# Base command for helm
HELM_CMD="helm upgrade --install $RELEASE_NAME $CHART_PATH --namespace $NAMESPACE ${VALUES_FILES[@]} --timeout $TIMEOUT"

if [[ "$DRY_RUN" == "true" ]]; then
    echo "Performing dry run..."
    $HELM_CMD --dry-run
    echo "Dry run completed. No resources were created."
else
    echo "Deploying monitoring stack..."
    $HELM_CMD
    
    echo "Waiting for pods to start..."
    kubectl -n $NAMESPACE wait --for=condition=ready pod --all --timeout=300s || true

    echo "===========================================" 
    echo "Deployment completed!"
    echo "-------------------------------------------" 
    echo "To access Grafana:"
    echo "kubectl port-forward -n $NAMESPACE svc/$RELEASE_NAME-grafana 3000:80"
    echo "Then open: http://localhost:3000"
    echo "Default credentials: admin / admin"
    echo "===========================================" 
    
    # Show running pods
    echo "Monitoring stack pods:"
    kubectl get pods -n $NAMESPACE
fi
