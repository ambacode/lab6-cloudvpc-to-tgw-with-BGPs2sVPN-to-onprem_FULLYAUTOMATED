# main.tf
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 4.0"
    }
  }
  required_version = ">= 1.2.0"
}

provider "aws" {
  region = var.region
}

/*
  VARIABLES
*/
variable "region" {
  type    = string
  default = "us-east-1"
}

variable "az1" {
  type    = string
  default = "us-east-1a"
}


# DATA Section:

# Ubuntu AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-focal-20.04-amd64-server-*"]
  }
}

# Defining variables for the strongswan server script
data "template_file" "strongswan_config" {
  template = file("${path.module}/configure-strongswan.sh.tpl")

  vars = {
    PRIVATE_KEY_PEM  = tls_private_key.rsa_example.private_key_pem
    LOCAL_PRIVATE_IP = aws_network_interface.strongswan_eni.private_ip
  }
}

# Outputs:

# strongswan server's public IP
output "strongswan_eip" {
  value = aws_eip.strongswan_eip.public_ip
}

# ec2 behind strongswan (onprem device) private IP
output "onprem_private" {
      description = "Onprem device public IP"
      value       = aws_instance.onprem_device.private_ip
    }

# endpoint used to test connection from on-prem to the cloud via the VPN
output "AWS_VPC_EC2_private" {
      description = "Cloud EC2 private IP"
      value       = aws_instance.vpc1_host.private_ip
}

# This output combines all the necessary VPN values into a single JSON object for Ansible
output "ansible_vars" {
  value = {
    CGW_PUBLIC_IP       = aws_eip.strongswan_eip.public_ip
    LOCAL_PRIVATE_IP    = aws_network_interface.strongswan_eni.private_ip

    T1_AWS_PUBLIC_IP    = aws_vpn_connection.tgw_to_strongswan.tunnel1_address
    T1_PSK              = aws_vpn_connection.tgw_to_strongswan.tunnel1_preshared_key
    T1_LOCAL_PTP_CIDR   = aws_vpn_connection.tgw_to_strongswan.tunnel1_inside_cidr
    
    # Calculate the second usable IP (.2) for our side of the tunnel
    T1_LOCAL_PTP        = cidrhost(aws_vpn_connection.tgw_to_strongswan.tunnel1_inside_cidr, 2)
    # Calculate the first usable IP (.1) for the AWS side of the tunnel
    T1_REMOTE_PTP       = cidrhost(aws_vpn_connection.tgw_to_strongswan.tunnel1_inside_cidr, 1)

    T2_AWS_PUBLIC_IP    = aws_vpn_connection.tgw_to_strongswan.tunnel2_address
    T2_PSK              = aws_vpn_connection.tgw_to_strongswan.tunnel2_preshared_key
    T2_LOCAL_PTP_CIDR   = aws_vpn_connection.tgw_to_strongswan.tunnel2_inside_cidr

    # Calculate the second usable IP (.2) for our side of the tunnel
    T2_LOCAL_PTP        = cidrhost(aws_vpn_connection.tgw_to_strongswan.tunnel2_inside_cidr, 2)
    # Calculate the first usable IP (.1) for the AWS side of the tunnel
    T2_REMOTE_PTP       = cidrhost(aws_vpn_connection.tgw_to_strongswan.tunnel2_inside_cidr, 1)
  }
  sensitive = true
}

# This resource creates an inventory file for Ansible with info how to connect to strongswan ec2
resource "local_file" "ansible_inventory" {
  content = <<-EOF
    [strongswan]
    ${aws_eip.strongswan_eip.public_ip}

    [strongswan:vars]
    ansible_user=ubuntu
    ansible_ssh_private_key_file=./ec2_private_key.pem
    EOF
  filename = "hosts.ini"
}