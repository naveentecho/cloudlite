output "ec2_public_ip" {
  value = aws_instance.app.public_ip
}

output "s3_bucket_name" {
  value = aws_s3_bucket.static.bucket
}

output "dynamodb_table_name" {
  value = aws_dynamodb_table.sessions.name
}