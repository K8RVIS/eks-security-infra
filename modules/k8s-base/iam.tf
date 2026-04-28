# 1. IAM 정책 
resource "aws_iam_policy" "lbc_policy" {
  name        = "${var.cluster_name}-lbc-policy"
  path        = "/"
  description = "AWS Load Balancer Controller Policy"
  # 실제 정책 내용은 외부 json 파일을 읽어오거나 직접 입력합니다.
  policy      = file("${path.module}/iam_policy.json") 
}

# 2. IAM 역할 및 신뢰 관계
resource "aws_iam_role" "lbc_role" {
  name = "${var.cluster_name}-lbc-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Federated = var.oidc_provider_arn
        }
        Action = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "${replace(var.oidc_provider_url, "https://", "")}:sub": "system:serviceaccount:kube-system:aws-load-balancer-controller"
          }
        }
      }
    ]
  })
}

# 3. 역할에 정책 연결
resource "aws_iam_role_policy_attachment" "lbc_attach" {
  role       = aws_iam_role.lbc_role.name
  policy_arn = aws_iam_policy.lbc_policy.arn
}