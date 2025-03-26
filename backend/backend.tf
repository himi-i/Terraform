# MySQL RDS 인스턴스 생성

  resource "aws_db_instance" "terraform_db" {
  allocated_storage    = 20
  db_name             = "terraformdb"
  engine              = "mysql"
  engine_version      = "8.0"
  instance_class      = "db.t3.medium"
  username            = "admin"
  password            = "password"  # 비밀번호는 환경 변수나 AWS Secrets Manager로 관리해야 합니다.
  parameter_group_name = "default.mysql8.0"
  skip_final_snapshot = true
  publicly_accessible = false
  multi_az            = false
  storage_type        = "gp2"
  region              = "ap-northeast-2"

  tags = {
    Name = "Terraform-MySQL-DB"
  }
}


# S3 버킷 생성
resource "aws_s3_bucket" "terraform_state" { 
  bucket = "terraform13579"
  force_destroy = true
}


# MySQL 테이블을 사용하여 상태 잠금 관리
resource "null_resource" "create_lock_table" {
  depends_on = [aws_db_instance.terraform_db]

  provisioner "local-exec" {
    command = <<EOT
      mysql -h ${aws_db_instance.terraform_db.endpoint} -u admin -p${aws_db_instance.terraform_db.password} -e "
      CREATE DATABASE IF NOT EXISTS terraform_state;
      USE terraform_state;
      CREATE TABLE IF NOT EXISTS locks (
        LockID VARCHAR(255) PRIMARY KEY,
        Version INT
      );
    "
  }
}


# S3 버킷에 대한 버전 관리 활성화
resource "aws_s3_bucket_versioning" "enabled" { 
  bucket = aws_s3_bucket.terraform_state.id 
  versioning_configuration {
    status = "Enabled"
  }
}

# S3 버킷에 대한 서버 측 암호화 설정
resource "aws_s3_bucket_server_side_encryption_configuration" "default" { 
  bucket = aws_s3_bucket.terraform_state.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# S3 버킷 공개 접근 차단
resource "aws_s3_bucket_public_access_block" "public_access" {
  bucket = aws_s3_bucket.terraform_state.id
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}

# S3 버킷 정책 설정
resource "aws_s3_bucket_policy" "terraform_state_policy" {
  bucket = aws_s3_bucket.terraform_state.id
  policy = <<POLICY
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": "*",
      "Action": [
        "s3:GetBucketPolicy",
        "s3:ListBucket",
        "s3:GetObject",
        "s3:PutObject"
      ],
      "Resource": [
        "arn:aws:s3:::terraform13579",
        "arn:aws:s3:::terraform13579/*"
      ]
    }
  ]
}
POLICY
}

# Terraform Backend 설정을 MySQL과 S3 사용하도록 설정
terraform {
  backend "s3" {
    bucket = "terraform13579"  # S3 버킷 이름
    key    = "stage/terraform/terraform.tfstate"
    region = "ap-northeast-2"
  }

  backend "mysql" {
    host     = aws_db_instance.terraform_db.endpoint
    port     = 3306
    username = "admin"
    password = "yourpassword"  # 비밀번호를 환경 변수나 AWS Secrets Manager로 관리해야 합니다
    database = "terraform_state"
    table    = "locks"
  }
  
}