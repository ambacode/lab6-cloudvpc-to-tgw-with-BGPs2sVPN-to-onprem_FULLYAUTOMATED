#!/bin/bash

# Log everything to a file for tshooting
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "--- Starting Phase 1: System Preparation ---"

# 1. Install StrongSwan and FRR
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y strongswan iptables-persistent frr frr-pythontools

# 2. Add private pem key so it can be a bastion host for testing connectivity later
echo "--- Saving SSH Private Key to /home/ubuntu/ ---"
cat << EOF > /home/ubuntu/ec2_private_key.pem
${PRIVATE_KEY_PEM}
EOF
chown ubuntu:ubuntu /home/ubuntu/ec2_private_key.pem
chmod 400 /home/ubuntu/ec2_private_key.pem

# 3. Configure Kernel Parameters for Routing
cat << EOF > /etc/sysctl.conf
net.ipv4.ip_forward=1
net.ipv4.conf.all.rp_filter=2
EOF
sysctl -p

# 4. Enable the BGP daemon in FRR
sed -i "s/bgpd=no/bgpd=yes/" /etc/frr/daemons

# 5. Configure the StrongSwan service to not manage routes
cat << EOF > /etc/strongswan.conf
charon {
    install_routes = no
    load_modular = yes
    plugins {
        include strongswan.d/charon/*.conf
    }
}
include strongswan.d/*.conf
EOF

# 6. Configure a base iptables firewall and make it persistent
# Note: The 'ens5' interface name is hardcoded here. Adjust if necessary.
iptables -t mangle -A FORWARD -o Tunnel+ -p tcp --tcp-flags SYN,RST SYN -j TCPMSS --clamp-mss-to-pmtu
iptables -A FORWARD -i ens5 -o Tunnel+ -m state --state NEW,RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i Tunnel+ -o ens5 -m state --state RELATED,ESTABLISHED -j ACCEPT
netfilter-persistent save

# 7. Enable services to start on boot (they will be restarted after manual config)
systemctl enable frr
systemctl enable strongswan-starter

# 8. Create a Message of the Day (MOTD) with next steps for the user
cat << EOF > /etc/motd
********************************************************************************
*** AWS VPN Gateway - Phase 1 Complete ***
********************************************************************************
This server has been prepared with StrongSwan and FRR.

To complete the setup, you must manually configure the VPN tunnels.

1. Get VPN values from AWS Console

2. Use the values to create the following configuration files:
   - /etc/frr/frr.conf
   - /etc/ipsec.secrets
   - /etc/ipsec.conf

3. Create the VTI interfaces using 'ip link' and 'ip addr' commands.

A detailed runbook is available in the project's GitHub repository.

After manual configuration, restart services:
sudo systemctl restart frr
sudo ipsec restart
********************************************************************************
EOF

echo "--- System preparation complete. Please SSH in and follow the MOTD for Phase 2 configuration. ---"