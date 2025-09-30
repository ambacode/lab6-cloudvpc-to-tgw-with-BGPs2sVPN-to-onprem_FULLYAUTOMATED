Cloud to Onprem Hybrid Network Infrastructure fully automated with HA VPN tunnels and dynamic routing

Overview
Using Terraform and Ansible to automatically provision and configure:
Cloud VPC with EC2 connected via Transit Gateway to Site-to-Site VPN using
BGP for dynamic routing; connected to simulated on-prem environment in a second VPC
with 2 subnets - a public subnet with an EC2 with Strongswan for VPN and FRR for BGP,
and a private subnet with an EC2 acting as an on-prem workstation.

I made this lab more automated than the static routing version of this lab to show how we can use data blocks with Terraform to further reduce operational overhead.

Architecture
AWS Services used: VPC, EC2, Transit Gateway, Site-to-site VPN, SGs, Subnets
Tools: Terraform, Ansible, AWS CLI, Git

Setup Instructions:
I used VS Code to create and edit the project but it isn't required to launch it.

Prerequisites:
AWS account
AWS CLI configured with credentials
Terraform installed
Ansible installed (can be installed on Ubuntu with apt which will install Python3 as a dependency)

Steps:

1. Initialize Terraform:
terraform init

2. Validate code:
terraform validate

3. Apply changes (review first!):
terraform 

3. Run ansible playbook
ansible-playbook -i hosts.ini --extra-vars "$(terraform output -json ansible_vars)" playbook.yml

4. Testing/Verification
A. Get your IPs ready on your local device:

First the strongswan public IP:
terraform output strongswan_eip

Then the 'onprem' device's private IP:
terraform output onprem_private

Finally, the private ec2 in the AWS cloud (cloud endpoint across the VPN):
terraform output AWS_VPC_EC2_private

B. SSH to strongswan device:
ssh -i ec2_private_key.pem ubuntu@<public_ip>

C. Test ping to remote vpc subnet device from strongswan itself:
Note: Make sure to use the correct ping syntax or it will source it from the tunnel's 169.254 IP!
Your local private IP can be viewed by doing:
ip addr 
OR by looking at the hostname (such as "Ubuntu@10_2_0_24" in which case the private IP is 10.2.0.24)
And then...
ping -I <local_Private_IP> <AWS_VPC_EC2_private>

D. Connect to private onprem device FROM strongswan device to test ping from there:
ssh -i ./ec2_private_key.pem ubuntu@<onprem_private>
And then...
ping <AWS_VPC_EC2_private>

5. Teardown
terraform destroy

Project Structure

aws-vpc.tf
main.tf
onprem-vpc_2.tf
configure-strongswan.sh.tpl
playbook.yml
templates
    frr.conf.j2
    ipsec.conf.j2
    ipsec.secrets.j2
    vti.service.j2
README.md

Key Learnings
Creating automated solution.
Using BGP for dynamic routing across VPN tunnels
Using Terraform data blocks and also using output to prepare variables for Ansible.
Using Ansible to automate config customization of EC2.