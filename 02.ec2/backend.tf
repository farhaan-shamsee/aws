terraform {
  backend "s3" {
    bucket = "farhaan-terraform-backend"
    key            = "dev/ec2/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    dynamodb_table = "terraform-state-lock"
  }
}