# K3S
![image](https://github.com/user-attachments/assets/a3db63b9-4434-40c4-9212-55682d99c707)
I'll give you the streamlined commands assuming DHCP/default networking. Let's start:
1. Initial VM Setup (Run on ALL nodes)
bashCopy# Update system
sudo apt update && sudo apt upgrade -y

# Set hostnames (run appropriate one on each node)
# On Rancher management node:
sudo hostnamectl set-hostname rancher-server

# On master node:
sudo hostnamectl set-hostname k3s-master

# On worker nodes:
sudo hostnamectl set-hostname k3s-worker-1  # (increment for each worker)
2. Install Docker (Run on ALL nodes)
bashCopy# Install Docker
curl https://releases.rancher.com/install-docker/20.10.sh | sh

# Add user to docker group
sudo usermod -aG docker $USER

# Log out and log back in
exit
# Log back in
3. Install Rancher (Only on rancher-server node)
bashCopy# Run Rancher
docker run -d --restart=unless-stopped \
  -p 80:80 -p 443:443 \
  --privileged \
  rancher/rancher:latest

# Get the bootstrap password
docker logs  $(docker ps | grep rancher/rancher | awk '{print $1}') 2>&1 | grep "Bootstrap Password:"
4. Access Rancher UI

Open browser and go to: https://<rancher-server-ip>
Enter the bootstrap password
Set new admin password
Set Rancher server URL (use your server's IP)

5. Create Cluster in Rancher UI

Click "Create"
Select "Custom"
Name it "prod-cluster"
Leave most defaults, but:

Disable Nginx Ingress
Keep Network Provider as Canal
Click Next



6. Add Nodes to Cluster
In the Rancher UI, you'll get registration commands:
bashCopy# On master node (k3s-master):
# Copy and run the command with ALL roles selected (etcd, control-plane, worker)

# On worker nodes:
# Copy and run the command with only worker role selected
7. Install Longhorn (After cluster is active)
bashCopy# On ALL nodes:
sudo apt-get install -y open-iscsi
sudo systemctl enable --now iscsid

# Then in Rancher UI:
1. Go to Apps > Charts
2. Search for "Longhorn"
3. Click Install
4. Accept defaults
5. Click Install
8. Install Cert-Manager
bashCopykubectl apply -f https://github.com/cert-manager/cert-manager/releases/download/v1.12.0/cert-manager.yaml

# Create Let's Encrypt issuer
cat <<EOF | kubectl apply -f -
apiVersion: cert-manager.io/v1
kind: ClusterIssuer
metadata:
  name: letsencrypt-prod
spec:
  acme:
    server: https://acme-v02.api.letsencrypt.org/directory
    email: your-email@korczewski.de
    privateKeySecretRef:
      name: letsencrypt-prod
    solvers:
    - http01:
        ingress:
          class: traefik
EOF
9. Deploy Nextcloud
bashCopy# Add Helm repo
helm repo add nextcloud https://nextcloud.github.io/helm/
helm repo update

# Create namespace
kubectl create namespace nextcloud

# Create Nextcloud admin secret
kubectl -n nextcloud create secret generic nextcloud-creds \
  --from-literal=admin-password='YourSecurePassword'

# Create Nextcloud values file
cat <<EOF > nextcloud-values.yaml
nextcloud:
  host: nextcloud.korczewski.de
  username: admin
  existingSecret:
    enabled: true
    secretName: nextcloud-creds
  
persistence:
  enabled: true
  storageClass: longhorn
  size: 30Gi
  
ingress:
  enabled: true
  annotations:
    kubernetes.io/ingress.class: traefik
    cert-manager.io/cluster-issuer: letsencrypt-prod
  hosts:
    - host: nextcloud.korczewski.de
      paths:
        - path: /
          pathType: Prefix
  tls:
    - secretName: nextcloud-tls
      hosts:
        - nextcloud.korczewski.de

mariadb:
  enabled: true
  architecture: standalone
  auth:
    database: nextcloud
    username: nextcloud
  primary:
    persistence:
      enabled: true
      storageClass: longhorn
      size: 8Gi

redis:
  enabled: true
  architecture: standalone
  auth:
    enabled: true
  master:
    persistence:
      enabled: true
      storageClass: longhorn
      size: 8Gi
EOF

# Install Nextcloud
helm install nextcloud nextcloud/nextcloud \
  --namespace nextcloud \
  --values nextcloud-values.yaml
10. Verify Installation
bashCopy# Check pods
kubectl -n nextcloud get pods

# Check ingress
kubectl -n nextcloud get ingress

# Check PVCs
kubectl -n nextcloud get pvc
Do you want to start with the installation? We should begin with step 1 on your first VM. Once that's working, we can proceed step by step. Would you like me to provide any specific clarification about any of these steps?
