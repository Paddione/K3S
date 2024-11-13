#!/bin/bash
# Resilient Master Node Setup Script for K3s Cluster with Rancher
# Save this as setup-master.sh and run with:
# chmod +x setup-master.sh
# sudo ./setup-master.sh

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print status messages
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check if a service is running
service_running() {
    systemctl is-active --quiet "$1"
}

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Set hostname for master node
setup_hostname() {
    print_status "Checking hostname..."
    if [[ $(hostname) != "k3s-master" ]]; then
        print_status "Setting hostname to k3s-master..."
        hostnamectl set-hostname k3s-master || print_warning "Hostname change failed, continuing anyway..."
    else
        print_status "Hostname already set correctly"
    fi
}

# System updates
update_system() {
    print_status "Updating system packages..."
    apt update || print_warning "apt update failed, continuing anyway..."
    apt upgrade -y || print_warning "apt upgrade failed, continuing anyway..."
    apt install -y curl openssh-server net-tools || print_warning "Some packages failed to install, continuing anyway..."
}

# Install and configure Docker
install_docker() {
    if command_exists docker; then
        print_status "Docker already installed, checking version..."
        docker --version

        # Check if docker group exists and user is in it
        if getent group docker > /dev/null; then
            if groups $SUDO_USER | grep -q "\bdocker\b"; then
                print_status "User already in docker group"
            else
                print_status "Adding user to docker group..."
                usermod -aG docker $SUDO_USER || print_warning "Failed to add user to docker group"
            fi
        fi
    else
        print_status "Installing Docker..."
        curl https://releases.rancher.com/install-docker/20.10.sh | sh || {
            print_error "Docker installation failed"
            return 1
        }
        usermod -aG docker $SUDO_USER || print_warning "Failed to add user to docker group"
    fi

    # Configure Docker daemon regardless of installation status
    if [ ! -d "/etc/docker" ]; then
        mkdir -p /etc/docker
    fi

    cat > /etc/docker/daemon.json <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "100m",
    "max-file": "3"
  },
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 64000,
      "Soft": 64000
    }
  }
}
EOF

    # Restart Docker only if it's running
    if service_running docker; then
        systemctl restart docker || print_warning "Docker restart failed"
    else
        systemctl start docker || print_warning "Docker start failed"
    fi
}

# Install Rancher
install_rancher() {
    print_status "Checking for existing Rancher installation..."

    if docker ps | grep -q "rancher/rancher"; then
        print_warning "Rancher container already running"
        CONTAINER_ID=$(docker ps | grep rancher/rancher | awk '{print $1}')
        print_status "Getting bootstrap password from existing installation..."
    else
        print_status "Installing Rancher..."
        docker run -d --restart=unless-stopped \
          -p 80:80 -p 443:443 \
          --privileged \
          rancher/rancher:latest || {
            print_error "Failed to start Rancher container"
            return 1
        }

        CONTAINER_ID=$(docker ps | grep rancher/rancher | awk '{print $1}')
        print_status "Waiting for Rancher to start (this may take a few minutes)..."
        sleep 30
    fi

    # Try to get bootstrap password multiple times
    for i in {1..5}; do
        BOOTSTRAP_PASSWORD=$(docker logs $CONTAINER_ID 2>&1 | grep "Bootstrap Password:" | awk '{print $NF}')
        if [ ! -z "$BOOTSTRAP_PASSWORD" ]; then
            print_status "Rancher installation complete!"
            print_warning "Bootstrap Password: $BOOTSTRAP_PASSWORD"
            print_warning "Access Rancher UI at: https://$(hostname -I | awk '{print $1}')"
            break
        else
            if [ $i -eq 5 ]; then
                print_warning "Could not retrieve bootstrap password. Please check manually with: docker logs $CONTAINER_ID | grep Bootstrap"
            else
                print_status "Waiting for bootstrap password (attempt $i of 5)..."
                sleep 10
            fi
        fi
    done
}

# Install required packages for Longhorn
install_longhorn_deps() {
    print_status "Checking Longhorn dependencies..."

    # Check for existing installations
    if dpkg -l | grep -q open-iscsi && dpkg -l | grep -q nfs-common; then
        print_status "Longhorn dependencies already installed"
    else
        print_status "Installing Longhorn dependencies..."
        apt install -y open-iscsi nfs-common || print_warning "Some Longhorn dependencies failed to install"
    fi

    # Enable iscsid regardless of installation status
    systemctl enable iscsid || print_warning "Failed to enable iscsid"
    systemctl start iscsid || print_warning "Failed to start iscsid"
}

# System optimizations for K3s
optimize_system() {
    print_status "Applying system optimizations..."

    # Create sysctl config if it doesn't exist
    cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.swappiness = 0
EOF

    # Apply sysctl parameters, continue on failure
    sysctl --system || print_warning "Failed to apply some sysctl parameters"

    # Disable swap
    swapoff -a || print_warning "Failed to disable swap"
    sed -i '/swap/d' /etc/fstab || print_warning "Failed to remove swap from fstab"
}

# Ask if this should be a Rancher server
ask_rancher_install() {
    print_warning "Do you want to install Rancher on this node? (y/n)"
    read -p "This should only be done on the management node, not on cluster nodes: " answer
    case ${answer:0:1} in
        y|Y )
            return 0
        ;;
        * )
            return 1
        ;;
    esac
}

# Main installation process
main() {
    print_status "Starting master node setup..."

    # Run each step, continue on failure
    setup_hostname
    update_system
    optimize_system
    install_docker
    install_longhorn_deps

    if ask_rancher_install; then
        install_rancher
        print_status "Rancher management server setup complete!"
    else
        print_status "Master node base setup complete!"
        print_warning "Next steps:"
        print_warning "1. Copy the master node registration command from Rancher UI"
        print_warning "2. Run the command on this node to join the cluster as a master"
        print_warning "3. Verify node status in Rancher UI"
    fi

    print_warning "IMPORTANT: Log out and log back in for Docker group changes to take effect"
}

# Run main installation
main || print_warning "Some parts of the installation failed, but setup continued"

# Print node IP for reference
echo -e "\nNode IP addresses:"
ip -4 addr show | grep inet | grep -v "127.0.0.1"