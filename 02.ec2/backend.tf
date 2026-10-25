terraform {
  backend "s3" {
    bucket = "farhaan-terraform-backend"
    key            = "ec2/terraform.tfstate"
    region         = "ap-south-1"
    encrypt        = true
    use_lockfile   = true
  }
}