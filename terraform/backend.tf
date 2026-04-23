terraform {
  backend "s3" {
    bucket         = "safle-app-cicd"
    key            = "ecs-app/terraform.tfstate"
    region         = "ap-south-1"
    dynamodb_table = "safle_app_cicd"
  }
}