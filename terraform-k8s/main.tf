provider "aws" {
  region = "us-east-1"  # Change to your preferred AWS region
}

resource "aws_vpc" "main" {
  cidr_block = "10.0.0.0/16"

  tags = {
    Name = "k8s-vpc"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
  availability_zone       = "us-east-1a"

  tags = {
    Name = "k8s-subnet"
  }
}

resource "aws_security_group" "k8s_sg" {
  vpc_id = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow SSH from anywhere
  }

  ingress {
    from_port   = 6443
    to_port     = 6443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow Kubernetes API server access
  }

  ingress {
    from_port   = 30000
    to_port     = 32767
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Allow NodePort services
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "k8s-security-group"
  }
}

resource "aws_key_pair" "my_key_pair" {
  key_name   = "my-key-pair"
  public_key = file("~/.ssh/id_ed25519.pub")
}

resource "aws_instance" "k8s_node" {
  ami           = "ami-05b10e08d247fb927"
  instance_type = "t3.medium"
  subnet_id     = aws_subnet.public.id
  vpc_security_group_ids = [aws_security_group.k8s_sg.id]
  key_name = aws_key_pair.my_key_pair.key_name

  user_data = <<-EOF
    #!/bin/bash
    sudo yum update -y
    sudo yum install -y docker git

    # Start and enable Docker
    sudo systemctl start docker
    sudo systemctl enable docker

    # Add ec2-user to Docker group
    sudo usermod -aG docker ec2-user

    # Install kubectl
    curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
    chmod +x kubectl
    sudo mv kubectl /usr/local/bin/

    # Install kind
    curl -Lo ./kind https://kind.sigs.k8s.io/dl/v0.20.0/kind-linux-amd64
    chmod +x kind
    sudo mv kind /usr/local/bin/

    echo "Installation completed!"
  EOF

  tags = {
    Name = "k8s-ec2-instance"
  }
}

output "instance_public_ip" {
  value = aws_instance.k8s_node.public_ip
}
