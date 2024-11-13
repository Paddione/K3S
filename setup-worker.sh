#!/bin/bash

# Worker Node Setup Script for K3s Cluster
# Save this as setup-worker.sh and run with:
# chmod +x setup-worker.sh
# sudo ./setup-worker.sh

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

# Check if script is run as root
if [ "$EUID" -ne 0 ]; then 
    print_error "Please run as root (use sudo)"
    exit 1
fi

# Set hostname (will prompt for node number)
setup_hostname() {
    print_status "Setting up hostname..."
    read -p "Enter worker node number (e.g., 1, 2, 3): " node_number
    hostnamectl set-hostname k3s-worker-$node_number
    print_status "Hostname set to k3s-worker-$node_number"
}

# System updates
update_system() {
    print_status "Updating system packages..."
    apt update
    apt upgrade -y
    apt install -y curl openssh-server net-tools
}

# Install and configure Docker
install_docker() {
    print_status "Installing Docker..."
    curl https://releases.rancher.com/install-docker/20.10.sh | sh

    # Add current user to docker group
    usermod -aG docker $SUDO_USER
    
    # Configure Docker daemon
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

    # Restart Docker
    systemctl restart docker
    print_status "Docker installation complete"
}

# Install required packages for Longhorn
install_longhorn_deps() {
    print_status "Installing Longhorn dependencies..."
    apt install -y open-iscsi nfs-common
    systemctl enable --now iscsid
}

# System optimizations for K3s
optimize_system() {
    print_status "Optimizing system for K3s..."
    
    # Set up sysctl parameters
    cat > /etc/sysctl.d/99-kubernetes.conf <<EOF
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
net.bridge.bridge-nf-call-ip6tables = 1
vm.swappiness = 0
EOF
    
    # Apply sysctl parameters
    sysctl --system
    
    # Disable swap
    swapoff -a
    sed -i '/swap/d' /etc/fstab
}

# Main installation process
main() {
    print_status "Starting worker node setup..."
    
    setup_hostname
    update_system
    optimize_system
    install_docker
    install_longhorn_deps
    
    print_status "Base setup complete!"
    print_warning "Next steps:"
    print_warning "1. Copy the worker node registration command from Rancher UI"
    print_warning "2. Run the command on this node to join the cluster"
    print_warning "3. Verify node status in Rancher UI"
    
    # Reminder for Docker group changes
    print_warning "IMPORTANT: Log out and log back in for Docker group changes to take effect"
}

# Run main installation
main

# Print node IP for reference
echo -e "\nNode IP addresses:"
ip -4 addr show | grep inet | grep -v "127.0.0.1"
