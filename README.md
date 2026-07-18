# Kubernetes Blue-Green Deployment via Envoy Gateway API

A production-ready infrastructure blueprint for zero-downtime (Blue-Green) traffic switching using the modern Kubernetes Gateway API standard, complete with automated TLS termination.

---

## Architecture Overview

1. **GatewayClass & Gateway**: Infrastructure setup using Envoy Gateway as the controller.
2. **Cert-Manager Integration**: Certificate generation via a ClusterIssuer for HTTPS support.
3. **Application Stack**: Blue and Green deployments running inside the `app` namespace.
4. **Routing**: An `HTTPRoute` mapped to `app.local`, directing traffic to `app-svc`.
5. **Switching Logic**: A bash script that updates the Service selector dynamically to point to either the `blue` or `green` version.

---

## 1. GatewayClass (`gatewayclass.yaml`)

Defines the gateway class using Envoy Gateway as the controller.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: GatewayClass
metadata:
  name: eg
spec:
  controllerName: gateway.envoyproxy.io/gatewayclass-controller
```

## 2. Gateway (`gateway.yaml`)

Configures listeners for HTTP (port 80) and HTTPS (port 443) with TLS termination.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: eg
  namespace: gateway
spec:
  gatewayClassName: eg
  listeners:
    - name: http
      protocol: HTTP
      port: 80
      allowedRoutes:
        namespaces:
          from: All
    - name: https
      protocol: HTTPS
      port: 443
      allowedRoutes:
        namespaces:
          from: All
      tls:
        mode: Terminate
        certificateRefs:
          - kind: Secret
            name: app-local-tls
```

## 3. Service (`service.yaml`)

The target service that routing layers bind to. The version selector is changed during blue-green switches.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: app-svc
  namespace: app
spec:
  selector:
    app: vishva
    version: blue
  ports:
    - name: http
      port: 5000
      targetPort: 5000
```

## 4. Blue Deployment (`dep-blue.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-blue
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vishva
      version: blue
  template:
    metadata:
      labels:
        app: vishva
        version: blue
    spec:
      containers:
        - image: shatakratu/vishva:alpine
          imagePullPolicy: IfNotPresent
          name: backend
          ports:
            - containerPort: 5000
```

## 5. HTTPRoute (`httproute.yaml`)

Configures routing rules for `app.local`.

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-httproute
  namespace: app
spec:
  parentRefs:
    - name: eg
      namespace: gateway
  hostnames:
    - "app.local"
  rules:
    - backendRefs:
        - group: ""
          kind: Service
          name: app-svc
          port: 5000
          weight: 1
      matches:
        - path:
            type: PathPrefix
            value: /
```

## 6. TLS Certificate (`certificate.yaml`)

Uses `cert-manager` to provision local certificates for HTTPS.

```yaml
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: app-local-tls
  namespace: gateway
spec:
  secretName: app-local-tls
  dnsNames:
    - app.local
  issuerRef:
    name: dev-ca-issuer
    kind: ClusterIssuer
  privateKey:
    algorithm: RSA
    size: 2048
```

## 7. Green Deployment (`dep-green.yaml`)

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: app-green
  namespace: app
spec:
  replicas: 1
  selector:
    matchLabels:
      app: vishva
      version: green
  template:
    metadata:
      labels:
        app: vishva
        version: green
    spec:
      containers:
        - image: shatakratu/vishva:exp
          imagePullPolicy: IfNotPresent
          name: backend
          ports:
            - containerPort: 5000
```

## 8. Automation Script (`switch-script.sh`)

Bash script for patching the Kubernetes service selector to switch between environments.

```bash
#!/bin/bash

set -e

NAMESPACE=app
SERVICE=app-svc
VERSION=$1

if [[ "$VERSION" != "green" && "$VERSION" != "blue" ]]; then
  echo "Usage: ./switch-script.sh [blue|green]"
  exit 1
fi

echo "Switching service selector to version=$VERSION..."

kubectl patch svc "$SERVICE" -n "$NAMESPACE" \
  -p '{"spec":{"selector":{"app":"vishva","version":"'"$VERSION"'"}}}'

echo "Switched to $VERSION"
```

## 9. Usage and Operations

To make the script executable and trigger environment switches, use the following commands:

```bash
# Make the script executable
chmod +x switch-script.sh

# Switch to the green version
./switch-script.sh green

# Switch to the blue version
./switch-script.sh blue
```