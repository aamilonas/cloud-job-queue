# Cloud Job Queue

Event-driven, auto-scaling job processing system built on AWS.

**Stack:** SQS, ECS Fargate, Lambda, API Gateway, DynamoDB, S3, CloudWatch, Terraform

**Status:** Complete — all phases delivered.

## Phase Status

- [x] Phase 1: Foundation (S3, DynamoDB, SQS, DLQ)
- [x] Phase 2: Worker container (ECS Fargate)
- [x] Phase 3: API layer (Lambda + API Gateway)
- [x] Phase 4: Auto-scaling
- [x] Phase 5: Frontend
- [x] Phase 6: Monitoring

## Deploy

```powershell
cd terraform
terraform init
terraform plan
terraform apply
```
