provider "aws" {
  alias   = "us-east-1"
  region  = "us-east-1"
}

resource "aws_s3_bucket" "documents" {
  bucket = "${var.bucket}"
}

resource "aws_s3_bucket_ownership_controls" "documents" {
  bucket = aws_s3_bucket.documents.id
  rule {
    object_ownership = "BucketOwnerPreferred"
  }
}

resource "aws_s3_bucket_acl" "documents" {
  depends_on = [aws_s3_bucket_ownership_controls.documents]

  bucket = aws_s3_bucket.documents.id
  acl    = "private"
}

resource "aws_s3_bucket_public_access_block" "documents" {
  bucket = aws_s3_bucket.documents.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_route53_zone" "documents" {
  name    = "docs.hrndz.dev"
  comment = "Document Signing Test Domain"
}

resource "aws_route53_record" "docs-ns" {
  zone_id = "Z024618413F1C2414DAWK"
  name    = "docs.hrndz.dev"
  type    = "NS"
  ttl     = "30"
  records = aws_route53_zone.documents.name_servers
}

resource "aws_acm_certificate" "apex" {
  provider          = aws.us-east-1
  domain_name       = aws_route53_zone.documents.name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "apex-certificate-validation" {
  provider = aws.us-east-1
  for_each = {
    for dvo in aws_acm_certificate.apex.domain_validation_options : dvo.domain_name => {
      name   = dvo.resource_record_name
      record = dvo.resource_record_value
      type   = dvo.resource_record_type
    }
  }

  allow_overwrite = true
  name            = each.value.name
  records         = [each.value.record]
  ttl             = 300
  type            = each.value.type
  zone_id         = aws_route53_zone.documents.zone_id
}

resource "aws_acm_certificate_validation" "apex-certificate" {
  provider                = aws.us-east-1
  certificate_arn         = aws_acm_certificate.apex.arn
  validation_record_fqdns = [for record in aws_route53_record.apex-certificate-validation : record.fqdn]
}

resource "aws_cloudfront_origin_access_identity" "documents-identity" {
  comment = "Cloudfront identity for access to S3 Bucket"
}


resource "aws_cloudfront_distribution" "documents" {
  aliases = [aws_acm_certificate.apex.domain_name]
  origin {
    domain_name = aws_s3_bucket.documents.bucket_regional_domain_name
    origin_id   = "s3"

    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.documents-identity.cloudfront_access_identity_path
  }
 }

 enabled         = true
 is_ipv6_enabled = true
 comment         = "Distribution of signed S3 objects"

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"] # reads only
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "s3"
    compress         = true

      trusted_key_groups = [
        aws_cloudfront_key_group.documents-signing-key-group.id
      ]

    forwarded_values {
      query_string = false

      cookies {
        forward = "none"
      }
    }

    viewer_protocol_policy = "redirect-to-https"
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  price_class = "PriceClass_100"

  restrictions {
    geo_restriction {
      restriction_type = "whitelist"
      locations        = ["US", "CA"]
    }
  }

  tags = {
    Name = aws_acm_certificate.apex.domain_name # So it looks nice in the console
  }

  # https://docs.aws.amazon.com/AmazonCloudFront/latest/DeveloperGuide/secure-connections-supported-viewer-protocols-ciphers.html
  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate.apex.arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  depends_on = [
    aws_acm_certificate_validation.apex-certificate
  ]
}

resource "aws_s3_bucket_policy" "documents" {
  bucket = aws_s3_bucket.documents.id
  # policy = data.aws_iam_policy_document.documents-cloudfront-policy.json
  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal" : {
                "AWS": ["${aws_cloudfront_origin_access_identity.documents-identity.iam_arn}"]
            },
            "Action": [
                "s3:GetObject",
                "s3:ListBucket"
            ],
            "Resource": [
                "arn:aws:s3:::${var.bucket}/*",
                "arn:aws:s3:::${var.bucket}"
            ]
        }
    ]
}
EOF
}

resource "aws_route53_record" "documents-a" {
  zone_id = aws_route53_zone.documents.zone_id
  name    = aws_acm_certificate.apex.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.documents.domain_name
    zone_id                = aws_cloudfront_distribution.documents.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_route53_record" "documents-aaaa" {
  zone_id = aws_route53_zone.documents.zone_id
  name    = aws_acm_certificate.apex.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.documents.domain_name
    zone_id                = aws_cloudfront_distribution.documents.hosted_zone_id
    evaluate_target_health = true
  }
}

resource "aws_cloudfront_key_group" "documents-signing-key-group" {
  comment = "Valid Document Signing Keys"
  items = [
    aws_cloudfront_public_key.hhrndz-docs-signing-key-20230926.id
  ]
  name = "document-keys"
}

# convert public key to PKCS8 format (expected).
# Will take PEM, but stores internally differently
# resulting in a perma-diff
resource "aws_cloudfront_public_key" "hhrndz-docs-signing-key-20230926" {
  name        = "hhrndz-docs-signing-key-20230926"
  comment     = "Docs Link Public Key 20230926"
  encoded_key = <<EOT
-----BEGIN PUBLIC KEY-----
MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEAoOrXuO8Ko+PD0T0bk44g
KxStwOWtT4xcGgUMr5JAC5oSnLpyDuznQbMgy6NlFdPJKqr46b4gg4OKqnz1CJPh
uBKPCoRpSTvBolZNZ4AzEcN+rmruWRzir94fPgtysLYe7fsbg9AF3ZzI2dUOgbSM
S+CNAaR2xNvANTM5XVSJDjJWdwfKOLb0lZBULVwKXVlvtaL8t6O6x/z6/wQzFLwU
i48kn/iKEqgvdXND2kLQoz8JGNlb1sC8Kn01abT12seczE6PpKfvLE8SrKhf/4jR
QwLPia5t9seUYFHp+3Jaxi32xDzvaQ18KaB35KZ4jVJpFchr4pIVQ6fGmimxdnLB
owIDAQAB
-----END PUBLIC KEY-----
EOT
}

resource "aws_iam_role" "lambda_role" {
  name = "lambda_execution_role"
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
      }
    ]
  })
}

resource "aws_iam_role_policy" "lambda_policy" {
  name = "lambda_policy"
  role = aws_iam_role.lambda_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Effect = "Allow"
        Resource = "*"
      },
      {
        Action = "lambda:*"
        Effect = "Allow"
        Resource = "*"
      }
    ]
  })
}

resource "aws_lambda_function" "cf_fetcher" {
    function_name = "get_nuget_lambda"
    role = aws_iam_role.lambda_role.arn
    handler       = "get_nuget_lambda"


    filename = "lambda_function.zip"
    source_code_hash = "NGZkM2YwZGE1NmMzMWZkOGQxMWFkNjIzN2I3YzI5YTIxMjJiMzg2OTRhYWNmOTM1ZDM4NmE5NzMxZmQyOWZmMiAgbGFtYmRhX2Z1bmN0aW9uLnppcAo="

    runtime = "go1.x"

    timeout = 10
}

# HTTP API
resource "aws_apigatewayv2_api" "api" {
	name          = "api-cf-s3nuget"
	protocol_type = "HTTP"
	target        = aws_lambda_function.cf_fetcher.arn
}

# Permission
resource "aws_lambda_permission" "apigw" {
	action        = "lambda:InvokeFunction"
	function_name = aws_lambda_function.cf_fetcher.arn
	principal     = "apigateway.amazonaws.com"

	source_arn = "${aws_apigatewayv2_api.api.execution_arn}/*/*"
}

# module "s3_gateway" {
#   source = "./modules/s3_gateway"
#
#   bucket = "hnotes"
#   owner = "hh"
#   domain = "hnotes"
#   project = "hnotes"
# }
