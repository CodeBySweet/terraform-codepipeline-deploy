# Reference the existing VPC
data "aws_vpc" "existing_vpc" {
  id = "vpc-047a90672a7b63ceb"
}

# Reference the existing subnets
data "aws_subnets" "existing_subnets" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.existing_vpc.id]
  }
}

# Create a security group in the existing VPC
resource "aws_security_group" "my_sg" {
  name        = "my-app-sg"
  description = "Security group for my ECS service"
  vpc_id      = data.aws_vpc.existing_vpc.id

  # Allow inbound HTTP traffic
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Allow inbound HTTPS traffic
  ingress {
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

    # Allow inbound HTTPS traffic
  ingress {
    from_port   = 5000
    to_port     = 5000
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
}

locals {
  subnets         = jsonencode(data.aws_subnets.existing_subnets.ids)
  security_groups = jsonencode([aws_security_group.my_sg.id])
}

# Render the service-definition.json file
resource "local_file" "service_definition" {
  content = templatefile("${path.module}/service-definition.json.tpl", {
    subnets         = local.subnets
    security_groups = local.security_groups
  })
  filename = "${path.module}/service-definition.json"
}

# Declare the ECR repository
resource "aws_ecr_repository" "my_repo" {
  name = "my-app-repo"
}


variable "next_version" {
  description = "Version of the container image"
  type        = string
  default     = "v1"
}

locals {
  image_url = "${aws_ecr_repository.my_repo.repository_url}:${var.next_version}"
}


# Render the task-definition.json file
resource "local_file" "task_definition" {
  content = templatefile("${path.module}/task-definition.json.tpl", {
    image_url = local.image_url
  })
  filename = "${path.module}/task-definition.json"
}

# Create an ECS task definition
resource "aws_ecs_task_definition" "my_task" {
  family                   = "my-app-task"
  container_definitions    = local_file.task_definition.content
  network_mode             = "awsvpc"
  requires_compatibilities = ["FARGATE"]
  cpu                      = "256"
  memory                   = "512"

  execution_role_arn = aws_iam_role.ecs_task_execution_role.arn 
}


# Create an ECS cluster
resource "aws_ecs_cluster" "my_cluster" {
  name = "my-app-cluster"
}

# Create an ECS service
resource "aws_ecs_service" "my_service" {
  name            = "my-app-service"
  cluster         = aws_ecs_cluster.my_cluster.id
  task_definition = aws_ecs_task_definition.my_task.arn
  desired_count   = 1
  launch_type     = "FARGATE"

  # Network configuration with existing subnets and security group
  network_configuration {
    subnets          = data.aws_subnets.existing_subnets.ids
    security_groups  = [aws_security_group.my_sg.id]
    assign_public_ip = true
  }
}