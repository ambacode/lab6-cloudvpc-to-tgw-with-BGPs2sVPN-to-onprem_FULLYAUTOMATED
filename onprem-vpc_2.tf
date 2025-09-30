# onprem-vpc.tf


/*
  VPC 2 - Mocking up an on-prem network with a VPN device and a second device
*/
resource "aws_vpc" "vpc2" {
  cidr_block = "10.20.0.0/16"
  tags       = { Name = "vpc2-strongswan" }
}

resource "aws_internet_gateway" "vpc2_igw" {
  vpc_id = aws_vpc.vpc2.id
  tags   = { Name = "vpc2-igw" }
}

# This public subnet is just for the StrongSwan gateway
resource "aws_subnet" "vpc2_public" {
  vpc_id                  = aws_vpc.vpc2.id
  cidr_block              = "10.20.1.0/24"
  availability_zone       = var.az1
  map_public_ip_on_launch = true
  tags                    = { Name = "vpc2-public-subnet" }
}

resource "aws_route" "vpc2_igw_default" {
  route_table_id         = aws_vpc.vpc2.main_route_table_id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.vpc2_igw.id
}

resource "aws_route_table_association" "vpc2_public_assoc" {
  subnet_id      = aws_subnet.vpc2_public.id
  route_table_id = aws_vpc.vpc2.main_route_table_id
}

# Private Subnet for internal "on-prem" devices
resource "aws_subnet" "vpc2_private" {
  vpc_id            = aws_vpc.vpc2.id
  cidr_block        = "10.20.2.0/24" # A separate CIDR block for private instances
  availability_zone = var.az1
  tags              = { Name = "vpc2-private-subnet" }
}

# Route Table for the Private Subnet
# Its only job is to send all traffic to the StrongSwan server to be routed.
resource "aws_route_table" "vpc2_private_rt" {
  vpc_id = aws_vpc.vpc2.id

  route {
    cidr_block           = "0.0.0.0/0"
    network_interface_id = aws_network_interface.strongswan_eni.id
  }

  tags = { Name = "vpc2-private-rt" }
}

# Association for the private subnet and route table
resource "aws_route_table_association" "vpc2_private_assoc" {
  subnet_id      = aws_subnet.vpc2_private.id
  route_table_id = aws_route_table.vpc2_private_rt.id
}


resource "aws_security_group" "vpc2_sg" {
  name        = "vpc2-strongswan-sg"
  vpc_id      = aws_vpc.vpc2.id
  description = "Allow SSH, IPSEC, ICMP, and remote subnet"
  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "SSH (restrict to your IP in prod)"
  }
  # IPSEC stuff (next 2)
  ingress {
    from_port   = 500
    to_port     = 500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "IKE"
  }
  ingress {
    from_port   = 4500
    to_port     = 4500
    protocol    = "udp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "IPsec NAT-T"
  }
  # Allow full traffic from remote VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.10.0.0/16"]
  }
  # Allow all traffic from the local private subnet
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
    description = "Allow traffic from internal on-prem devices"
  }
  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# create private rsa key for the next resource..
resource "tls_private_key" "rsa_example" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

# use that to create key pair for ssh access to onprem ec2s
resource "aws_key_pair" "ec2_pair" {
  key_name   = "my-generated-ssh-key"
  public_key = tls_private_key.rsa_example.public_key_openssh
}

# save key locally to be able to ssh to onprem ec2s
resource "local_file" "private_key_file" {
  content         = tls_private_key.rsa_example.private_key_pem
  filename        = "ec2_private_key.pem"
  file_permission = "0400" # local permissions for file
}

# create a network interface for the strongswan instance so we can disable source_dest_check
resource "aws_network_interface" "strongswan_eni" {
  subnet_id       = aws_subnet.vpc2_public.id
  description     = "strongswan-eni"
  security_groups = [aws_security_group.vpc2_sg.id]
  tags            = { Name = "strongswan-eni" }
  # disable source/dest check so it can route
  source_dest_check = false
}

# create ec2 for strongswan to act as customer router/gateway
resource "aws_instance" "strongswan" {
  ami           = data.aws_ami.ubuntu.id
  instance_type = "t3.micro"
  key_name      = aws_key_pair.ec2_pair.key_name
  primary_network_interface {
    network_interface_id = aws_network_interface.strongswan_eni.id
  }
  tags = { Name = "strongswan-cgw" }

  # Use the configure-strongswan.sh.tpl script for the user_data
  user_data = data.template_file.strongswan_config.rendered
}

# allocate an EIP for the strongswan instance (this will be the public customer gateway IP)
resource "aws_eip" "strongswan_eip" {
  network_interface = aws_network_interface.strongswan_eni.id
  depends_on        = [aws_instance.strongswan]
  tags              = { Name = "strongswan-eip" }
}

# this will act as an onprem device behind the vpn server in a private subnet
resource "aws_instance" "onprem_device" {
  ami             = data.aws_ami.ubuntu.id
  instance_type   = "t3.micro"
  key_name        = aws_key_pair.ec2_pair.key_name
  subnet_id       = aws_subnet.vpc2_private.id
  security_groups = [aws_security_group.vpc2_sg.id]
  tags            = { Name = "onprem_device" }
}