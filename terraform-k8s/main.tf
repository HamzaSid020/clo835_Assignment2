terraform {
  backend "s3" {
    bucket = "terraform-state-bucket-clo835"  # Replace with your S3 bucket name
    key    = "terraform.tfstate"           # Path to the state file in the bucket
    region = "us-east-1"                   # AWS region for the bucket
  }
}

# Configure the AWS Provider
provider "aws" {
  region = "us-east-1"  # Change to your preferred AWS region
}

# Create a VPC for the Kubernetes cluster
resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"  # Define the IP range for the VPC

  tags = {
    Name = "k8s-vpc"  # Tag the VPC for easy identification
  }
}

# Create an Internet Gateway and attach it to the VPC
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id  # Attach the IGW to the VPC

  tags = {
    Name = "k8s-igw"  # Tag the IGW for easy identification
  }
}

# Create a public subnet within the VPC
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id  # Associate the subnet with the VPC
  cidr_block              = "10.0.1.0/24"    # Define the IP range for the subnet
  map_public_ip_on_launch = true             # Automatically assign public IPs to instances
  availability_zone       = "us-east-1a"     # Specify the availability zone

  tags = {
    Name = "k8s-subnet"  # Tag the subnet for easy identification
  }
}

# Create a route table for the public subnet
resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.main.id  # Associate the route table with the VPC

  # Route all internet-bound traffic to the Internet Gateway
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = {
    Name = "k8s-public-rt"  # Tag the route table for easy identification
  }
}

# Associate the route table with the public subnet
resource "aws_route_table_association" "public_rt_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public_rt.id
}

# Create a security group for the Kubernetes cluster
resource "aws_security_group" "k8s_sg" {
  vpc_id = aws_vpc.main.id  # Associate the security group with the VPC

  # Allow SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow Kubernetes API server access from anywhere
  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow NodePort services access from anywhere
  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-security-group"  # Tag the security group for easy identification
  }
}

# Create an SSH key pair for instance access
resource "aws_key_pair" "my_key_pair" {
  key_name   = "my-key-pair"  # Name of the key pair
  public_key = file("${path.module}/id_ed25519.pub")  # Path to the public key file
}

# Launch an EC2 instance for the Kubernetes node
resource "aws_instance" "k8s_node" {
  ami           = "ami-05b10e08d247fb927"  # Amazon Linux 2 AMI (us-east-1)
  instance_type = "t3.medium"              # Instance type
  subnet_id     = aws_subnet.public.id     # Launch in the public subnet
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]  # Attach the security group
  key_name      = aws_key_pair.my_key_pair.key_name  # Assign the SSH key pair

  # User data script to install and configure Kubernetes tools
  user_data = <<-EOF
    #!/bin/bash
    # Update the system
    sudo yum update -y

    # Install Docker and Git
    sudo yum install -y docker git

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add the ec2-user to the Docker group
    sudo usermod -aG docker ec2-user

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    # Install kind (Kubernetes in Docker)
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x kind
    sudo mv kind /usr/local/bin/

    echo "Installation completed!"
  EOF

  tags = {
    Name = "k8s-ec2-instance"  # Tag the instance for easy identification
  }
}

# Output the public IP address of the EC2 instance
output "instance_public_ip" {
  value = aws_instance.k8s_node.public_ip  # Display the public IP for SSH access
}