#aws-vpc.tf

# VPC 1 - PRIVATE SUBNET (the "inside" VPC)

resource "aws_vpc" "vpc1" {
  cidr_block = "10.10.0.0/16"
  tags = { Name = "vpc1-private" }
}

resource "aws_subnet" "vpc1_private" {
  vpc_id            = aws_vpc.vpc1.id
  cidr_block        = "10.10.10.0/24"
  availability_zone = var.az1
  tags = { Name = "vpc1-private-subnet" }
}

resource "aws_security_group" "vpc1_sg" {
  name        = "vpc1-allow-ssh"
  vpc_id      = aws_vpc.vpc1.id
  description = "Allow SSH from anywhere and everything from onprem"
  # Allow SSH in
  ingress {
    description      = "SSH"
    from_port        = 22
    to_port          = 22
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"] # change to your IP for security
  }
  # Allow full traffic from remote VPC
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["10.20.0.0/16"]
  }
  # Allow all egress
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# ec2 host inside vpc1
resource "aws_instance" "vpc1_host" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = "t3.micro"
  subnet_id              = aws_subnet.vpc1_private.id
  vpc_security_group_ids = [aws_security_group.vpc1_sg.id]
  associate_public_ip_address = false
  tags = { Name = "vpc1-private-ec2" }
}

# Transit Gateway
resource "aws_ec2_transit_gateway" "tgw" {
  description = "tgw-for-vpc1-vpn"
  tags = { Name = "example-tgw" }
}

# Attach VPC1 to TGW (we attach private subnet of VPC1)
resource "aws_ec2_transit_gateway_vpc_attachment" "vpc1_attach" {
  transit_gateway_id = aws_ec2_transit_gateway.tgw.id
  vpc_id             = aws_vpc.vpc1.id
  subnet_ids         = [aws_subnet.vpc1_private.id]
  tags = { Name = "tgw-attach-vpc1" }
}

# Create Customer Gateway using the strongswan EIP (this is the remote / on-prem public IP)
resource "aws_customer_gateway" "strongswan_cgw" {
  bgp_asn    = 65000 #this will be AS for strongswan server's FRR bgp daemon
  ip_address = aws_eip.strongswan_eip.public_ip
  type       = "ipsec.1"
  tags = { Name = "strongswan-cgw" }
}

/*
  Create the Site-to-Site VPN attached to the Transit Gateway
  - static_routes_only = false bc we're using BGP
*/
resource "aws_vpn_connection" "tgw_to_strongswan" {
  transit_gateway_id   = aws_ec2_transit_gateway.tgw.id
  customer_gateway_id  = aws_customer_gateway.strongswan_cgw.id
  type                 = "ipsec.1"
  static_routes_only   = false
  tags = { Name = "tgw-vpn-to-strongswan" }
}

/*
  ROUTING INSIDE VPC1
  - route to TGW for any traffic destined to 10.20.0.0/16 (VPC2)
*/
resource "aws_route_table" "vpc1_private_rt" {
  vpc_id = aws_vpc.vpc1.id
  tags = { Name = "vpc1-private-rt" }
}

resource "aws_route_table_association" "vpc1_private_assoc" {
  subnet_id      = aws_subnet.vpc1_private.id
  route_table_id = aws_route_table.vpc1_private_rt.id
}

# vpc1 route table route to on-prem via TGW
resource "aws_route" "vpc1_to_tgw" {
  route_table_id         = aws_route_table.vpc1_private_rt.id
  destination_cidr_block = aws_vpc.vpc2.cidr_block
  transit_gateway_id     = aws_ec2_transit_gateway.tgw.id
}
