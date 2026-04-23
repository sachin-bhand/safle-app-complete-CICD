resource "aws_vpc" "safle-app-vpc"{
  cidr_block= "10.0.0.0/16"
  enable_dns_hostnames = true
  enable_dns_support = true
}      

resource "aws_subnet" "public-subnet-1" {
  vpc_id     = aws_vpc.safle-app-vpc.id
  availability_zone= "ap-south-1a"
  cidr_block = "10.0.1.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-1"
  }
  
}

resource "aws_subnet" "public-subnet-2" {
  vpc_id     = aws_vpc.safle-app-vpc.id
  availability_zone= "ap-south-1b"
  cidr_block = "10.0.2.0/24"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet-2"
  }
  
}

resource "aws_subnet" "private-subnet-1" {
  vpc_id     = aws_vpc.safle-app-vpc.id
  availability_zone = "ap-south-1a"
  cidr_block = "10.0.3.0/24"

  tags = {
    Name = "private-subnet-1"
  }
}

resource "aws_subnet" "private-subnet-2" {
  vpc_id     = aws_vpc.safle-app-vpc.id
  availability_zone = "ap-south-1b"
  cidr_block = "10.0.4.0/24"

  tags = {
    Name = "private-subnet-2"
  }
}

resource "aws_internet_gateway" "safle-igw" {
  vpc_id = aws_vpc.safle-app-vpc.id
  tags = {
    Name = "safle-igw"
  }
}

# add bastion host for ssh
resource "aws_instance" "bastion" {
  ami           = data.aws_ami.ecs_optimized.id
  instance_type = "t3.micro"
  subnet_id     = aws_subnet.public-subnet-1.id
  security_groups = [aws_security_group.safle-sg.id]

  tags = {
    Name = "bastion-host"
  }
}

resource "aws_eip" "safle-eip" {
  domain = "vpc"
}

resource "aws_nat_gateway" "safle-ngw"{
    allocation_id= aws_eip.safle-eip.id
    subnet_id= aws_subnet.public-subnet-1.id
    depends_on = [aws_internet_gateway.safle-igw]

    tags={
        Name= "safle-ngw"
    }
}


resource "aws_route_table" "public_route" {
  vpc_id = aws_vpc.safle-app-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.safle-igw.id
  }
  tags = {
    Name = "public_route"
  }
}


resource "aws_route_table" "private_route" {
  vpc_id = aws_vpc.safle-app-vpc.id

  route {
    cidr_block = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.safle-ngw.id
  }
  tags = {
    Name = "private_route"
  }
}



resource "aws_route_table_association" "public-association" {
  subnet_id      = aws_subnet.public-subnet-1.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table_association" "public2-association" {
  subnet_id      = aws_subnet.public-subnet-2.id
  route_table_id = aws_route_table.public_route.id
}

resource "aws_route_table_association" "private-association" {
  subnet_id      = aws_subnet.private-subnet-1.id
  route_table_id = aws_route_table.private_route.id
}

resource "aws_route_table_association" "private2-association" {
  subnet_id      = aws_subnet.private-subnet-2.id
  route_table_id = aws_route_table.private_route.id
}

resource "aws_ecr_repository" "safle-app" {
  name                 = "safle-app"
  image_tag_mutability = "MUTABLE"
  force_delete = true

  image_scanning_configuration {
    scan_on_push = true
  }
}


resource "aws_ecs_cluster" "safle-cluster" {
  name = "safle-cluster"
  tags = {
    Name = "safle-cluster"
  }
}

resource "aws_iam_role" "ecs_custom_role" {
  name = "ecs-custom-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = ["ecs.amazonaws.com", "ec2.amazonaws.com"]
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "ecs_custom_policy" {
  name        = "ecs-custom-policy"
  description = "Custom policy for ECS, ECR, EC2, CloudWatch Logs"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [


      {
        Effect = "Allow"
        Action = [
          "ec2:Describe*"
        ]
        Resource = "*"
      },

      {
        Effect = "Allow"
        Action = [
          "ecr:GetAuthorizationToken",
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:DescribeRepositories",
          "ecr:ListImages"
        ]
        Resource = "*"
      },

    
      {
        Effect = "Allow"
        Action = [
          "ecs:CreateCluster",
          "ecs:RegisterContainerInstance",
          "ecs:Describe*",
          "ecs:List*",
          "ecs:TagResource"
        ]
        Resource = "*"
      }

    ]
  })
}

data "aws_iam_policy_document" "ecs_cloudwatch_full" {
  statement {
    actions = [
      "logs:CreateLogGroup",
      "logs:CreateLogStream",
      "logs:PutLogEvents",
      "logs:DescribeLogStreams",
      "cloudwatch:PutMetricData",
      "cloudwatch:GetMetricData",
      "cloudwatch:ListMetrics"
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "ecs_cloudwatch_policy" {
  name        = "ECSCloudWatchFullAccess"
  description = "Allows ECS to manage logs and metrics"
  policy      = data.aws_iam_policy_document.ecs_cloudwatch_full.json
}




resource "aws_iam_role_policy_attachment" "attach_policy" {
  role       = aws_iam_role.ecs_custom_role.name
  policy_arn = aws_iam_policy.ecs_custom_policy.arn

}


resource "aws_iam_role_policy_attachment" "ecs_task_execution_role_policy" {
  role       = aws_iam_role.ecs_task_execution_role.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonECSTaskExecutionRolePolicy"
}




resource "aws_iam_role" "ecs_task_execution_role" {
  name = "ecs_task_execution_role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Action = "sts:AssumeRole"
      Effect = "Allow"
      Principal = {
        Service = "ecs-tasks.amazonaws.com"
      }
    }]
  })
}




resource "aws_iam_role" "ecs_instance_role_1" {
  name = "ecsInstanceRole01"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [{
      Effect = "Allow",
      Principal = {
        Service = ["ec2.amazonaws.com", "ecs.amazonaws.com"]
      },
      Action = "sts:AssumeRole"
    }]
  })
}



resource "aws_iam_role_policy_attachment" "ecs_instance_role_attach" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceforEC2Role"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ssm" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_ecr" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "ecs_instance_cw_agent" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}
resource "aws_iam_role_policy_attachment" "ecs_instance_ec2_container_service_role" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AmazonEC2ContainerServiceRole"
}

# attach admin policy to role
resource "aws_iam_role_policy_attachment" "ecs_instance_admin" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

resource "aws_ecs_task_definition" "app_task" {
  family = "my-ec2-task-family"

  requires_compatibilities = ["EC2"]
  depends_on = [aws_cloudwatch_log_group.ecs_logs]

  container_definitions = jsonencode([
    {
      name      = "my-app-container"
      image     = "${aws_ecr_repository.safle-app.repository_url}:latest"
      cpu       = 256 
      memory    = 512 
      essential = true
      portMappings = [
        {
          containerPort = 3000
          hostPort      = 0
        }
      ]
      logConfiguration = {
        logDriver = "awslogs"
        options = {
          "awslogs-group" : "/ecs/my-ec2-task",
          "awslogs-region" : "ap-south-1", 
          "awslogs-stream-prefix" : "ecs",
          "awslogs-create-group"  :"true"
        }
      }
    }
  ])

  execution_role_arn  = aws_iam_role.ecs_task_execution_role.arn
  network_mode        = "bridge" 
}


resource "aws_cloudwatch_log_group" "ecs_logs" {
  name = "/ecs/my-ec2-task"
}

resource "aws_iam_role_policy_attachment" "logs_policy" {
  role       = aws_iam_role.ecs_instance_role_1.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchLogsFullAccess"
}


resource "aws_lb_target_group" "app_tg" {
  name        = "app-target-group"
  port        = 3000
  protocol    = "HTTP"
  vpc_id      = aws_vpc.safle-app-vpc.id
  target_type = "instance" 

  health_check {
    path                = "/"
    interval            =30
    timeout             =10
    healthy_threshold   = 2
    unhealthy_threshold = 10
  }
}


resource "aws_autoscaling_attachment" "asg_attachment" {
  autoscaling_group_name = aws_autoscaling_group.safle-asg.id
  lb_target_group_arn    = aws_lb_target_group.app_tg.arn
}


resource "aws_security_group" "safle-sg" {
  vpc_id      = aws_vpc.safle-app-vpc.id
  tags = {
    Name = "safle-sg"
  }
  lifecycle {
    create_before_destroy = true
  }

  ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

ingress {
  from_port   = 0
  to_port     = 0
  protocol    = "-1"
  cidr_blocks = ["0.0.0.0/0"]
}

  
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }



  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
  }


  egress {
    from_port        = 5432
    to_port          = 5432
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
  }
}

resource "aws_lb" "safle-alb" {
  name               = "safle-alb"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.safle-sg.id]
  subnets            = [aws_subnet.public-subnet-1.id,aws_subnet.public-subnet-2.id]
  enable_deletion_protection = false
}

resource "aws_lb_listener" "http" {
  load_balancer_arn = aws_lb.safle-alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.app_tg.arn
  }
}

resource "aws_iam_instance_profile" "ecs_instance_profile" {
  name = "ecs-instance-profile_new"
  role = aws_iam_role.ecs_instance_role_1.name
}

data "aws_ami" "ecs_optimized" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn2-ami-ecs-hvm-*-x86_64-ebs"]
  }

  owners = ["amazon"]
}


resource "aws_launch_template" "safle_template" {
  name_prefix   = "ec2-cluster-"
  image_id      = data.aws_ami.ecs_optimized.id

  instance_type = "t3.micro"

  key_name = "saflekey"

  iam_instance_profile {
    name = aws_iam_instance_profile.ecs_instance_profile.name
  }
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "optional"
  }

user_data = base64encode(<<-EOF
#!/bin/bash
echo ECS_CLUSTER=safle-cluster >> /etc/ecs/ecs.config
systemctl stop ecs
systemctl start ecs
EOF
)

 vpc_security_group_ids = [aws_security_group.safle-sg.id]
    
  
  
  depends_on = [aws_ecs_cluster.safle-cluster]

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_autoscaling_group" "safle-asg" {
  desired_capacity    = 0
  max_size            = 5
  min_size            = 0
  vpc_zone_identifier = [aws_subnet.private-subnet-1.id, aws_subnet.private-subnet-2.id]# List of subnet IDs

  launch_template {
    id      = aws_launch_template.safle_template.id
    version = "$Latest"
  }

  tag {
    key                 = "AmazonECSManaged"
    value               = "true"
    propagate_at_launch = true
  }
}








resource "aws_ecs_capacity_provider" "safle" {
  name = "safle-capacity-provider"

  auto_scaling_group_provider {
    auto_scaling_group_arn = aws_autoscaling_group.safle-asg.arn

    managed_scaling {
      status = "ENABLED"
      target_capacity = 100
    }
  }
  depends_on = [
    aws_autoscaling_group.safle-asg
  ]
}

resource "aws_ecs_cluster_capacity_providers" "safle" {
  cluster_name = aws_ecs_cluster.safle-cluster.name

 capacity_providers = [
    aws_ecs_capacity_provider.safle.name
  ]
 default_capacity_provider_strategy {
  capacity_provider = aws_ecs_capacity_provider.safle.name
  weight            = 1
}

  depends_on = [
    aws_ecs_capacity_provider.safle
  ]
}



resource "aws_ecs_service" "app_service" {
  name            = "my-ec2-service"
  cluster         = aws_ecs_cluster.safle-cluster.id
  task_definition = aws_ecs_task_definition.app_task.arn
  desired_count   = 0

  capacity_provider_strategy {
    capacity_provider = aws_ecs_capacity_provider.safle.name
    weight            = 1
    base              = 1
  }

  load_balancer {
    target_group_arn = aws_lb_target_group.app_tg.arn
    container_name   = "my-app-container" 
    container_port   = 3000                
  }

  # Ensure the listener is created before the service tries to register
  depends_on = [aws_lb_listener.http]
}
