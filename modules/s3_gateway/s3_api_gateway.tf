resource "aws_api_gateway_rest_api" "s3_api_gateway" {
  name        = "s3-edgegw-${var.project}"
  binary_media_types = [
    "multipart/form-data",
  ]

  tags = {
    "owner"   = var.owner
    "project" = var.project
  }
}

# resource "aws_apigatewayv_domain_name" "domain" {
#   domain_name = var.domain
#
#   dynamic "domain_name_configuration" {
#     for_each = var.acm_certificate_arn == null ? [aws_acm_certificate.cert[0].arn] : [var.acm_certificate_arn]
#     content {
#       certificate_arn = domain_name_configuration.value
#       endpoint_configuration {
#         types = ["REGIONAL"]
#       }
#       security_policy = "TLS_1_2"
#     }
#   }
#
#   mutual_tls_authentication {
#     truststore_uri = var.truststore_s3_uri
#   }
#
#   tags = {
#     "owner"   = var.owner
#     "project" = var.project
#   }
#
# }


# Create S3 Read Only Access Policy
resource "aws_iam_policy" "s3_policy" {
  name        = "s3-edgegw-${var.project}-policy"
  description = "Policy for allowing S3 GetObject Actions to ${var.bucket}"

  policy = <<EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "s3:GetObject"
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

# Create API Gateway Role
resource "aws_iam_role" "s3_api_gateyway_role" {
  name = "s3-edgegw-${var.project}-role"

  # Create Trust Policy for API Gateway
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "apigateway.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

# Attach S3 Access Policy to the API Gateway Role
resource "aws_iam_role_policy_attachment" "s3_policy_attach" {
  role       = aws_iam_role.s3_api_gateyway_role.name
  policy_arn = aws_iam_policy.s3_policy.arn
}

resource "aws_api_gateway_resource" "proxy" {
  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  parent_id   = aws_api_gateway_rest_api.s3_api_gateway.root_resource_id
  path_part   = "{proxy+}"
}

resource "aws_api_gateway_method" "proxy" {
  rest_api_id   = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id   = aws_api_gateway_resource.proxy.id
  http_method   = "GET"
  authorization = "NONE"

  request_parameters = {
    "method.request.path.proxy" = true
  }
}

resource "aws_api_gateway_integration" "s3_integration" {
  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method

  # Included because of this issue: https://github.com/hashicorp/terraform/issues/10501
  integration_http_method = "GET"

  type = "AWS"

  # See uri description: https://docs.aws.amazon.com/apigateway/api-reference/resource/integration/
  uri         = "arn:aws:apigateway:${var.bucket_region}:s3:path/${var.bucket}/{proxy}"
  credentials = aws_iam_role.s3_api_gateyway_role.arn

  request_parameters = {
    "integration.request.path.proxy" = "method.request.path.proxy"
  }
}

resource "aws_api_gateway_method_response" "method_response_200" {
  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "200"

  response_models = {
    "application/json" = "Empty"
  }
}


resource "aws_api_gateway_integration_response" "integration_response_200" {
  depends_on = [
    aws_api_gateway_integration.s3_integration
  ]
  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.method_response_200.status_code

  response_templates = {
    "application/json" = ""
  }
}

resource "aws_api_gateway_method_response" "method_response_400" {
  depends_on = [
    aws_api_gateway_integration.s3_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "400"

}

resource "aws_api_gateway_integration_response" "integration_response_400" {
  depends_on = [
    aws_api_gateway_integration.s3_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.method_response_400.status_code

  selection_pattern = "4\\d{2}"
}

resource "aws_api_gateway_method_response" "method_response_500" {
  depends_on = [
    aws_api_gateway_integration.s3_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = "500"

}

resource "aws_api_gateway_integration_response" "integration_response_500" {
  depends_on = [
    aws_api_gateway_integration.s3_integration
  ]

  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id
  resource_id = aws_api_gateway_resource.proxy.id
  http_method = aws_api_gateway_method.proxy.http_method
  status_code = aws_api_gateway_method_response.method_response_500.status_code

  selection_pattern = "5\\d{2}"
}

resource "aws_api_gateway_deployment" "default" {
  depends_on  = [aws_api_gateway_integration.s3_integration]
  rest_api_id = aws_api_gateway_rest_api.s3_api_gateway.id

  stage_description = "default-1"
  stage_name   = "default"
}

# resource "aws_api_gateway_base_path_mapping" "dedicated_domain" {
#   domain_name = aws_api_gateway_domain_name.domain.domain_name
#   stage_name = aws_api_gateway_stage.default.stage_name
#   api_id = aws_api_gateway_rest_api.s3_api_gateway.id
# }
