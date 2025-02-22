# Backend config to store tfstate in an S3 bucket

terraform {
  backend "s3" {
    bucket = "sctp-ce9-tfstate"
    key    = "huang-ce9-activity2-10.tfstate"
    region = "us-east-1"
    encrypt = true
  }
}