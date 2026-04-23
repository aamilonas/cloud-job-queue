# Intelligent Job Queue with Auto-Scaling Workers

## Cloud Computing Course — Practical Project

**Student:** Angelo Milonas **Course:** Cloud Computing (FAU) **Project Type:** Hands-on Cloud Computing Project (55% of Total Grade)

cd C:\Users\Angelo\Documents\Projects\cloud-job-queue

we last left off at [[cloud_update]]

[[front end]]
---

## 1. Project Overview

### Objective

Build a cloud-native, event-driven job processing system that demonstrates elastic computing — the core value proposition of the cloud. The system accepts compute-intensive tasks (image processing) via a web API, queues them, and processes them with containerized workers that automatically scale up under load and scale to zero when idle.

### Core Cloud Concepts Demonstrated

- Event-driven architecture (API → Queue → Workers)
- Containerization and container orchestration (Docker, ECS Fargate)
- Auto-scaling based on queue depth metrics
- Serverless compute (Lambda for API layer)
- Managed messaging (SQS)
- Infrastructure-as-code (Terraform)
- Cloud monitoring and observability (CloudWatch)
- Object storage patterns (S3 for inputs/outputs)
- NoSQL database usage (DynamoDB for job tracking)

---

## 2. Architecture

### High-Level Flow

```
User/Frontend
    │
    ▼
API Gateway (REST)
    │
    ▼
Lambda (Job Submission)
    ├──► S3 (store uploaded image)
    └──► SQS Queue (enqueue job message)
              │
              ▼
        ECS Fargate Workers (auto-scaled)
            ├──► S3 (read input, write processed outputs)
            └──► DynamoDB (update job status)
              │
              ▼
        CloudWatch Metrics
            ├──► SQS queue depth
            ├──► ECS task count
            └──► Processing duration / errors

Dashboard Frontend (React on S3 + CloudFront)
    ├──► Polls API Gateway for job statuses
    └──► Displays real-time queue depth & worker count
```

### Component Breakdown

#### A. Frontend (React App on S3)

- Static React app hosted on S3 with CloudFront CDN
- Features:
    - Image upload form (single or batch)
    - Job status tracker (pending → processing → completed → failed)
    - Real-time dashboard showing:
        - Current queue depth
        - Active worker count
        - Processing history chart
    - Results gallery showing original + processed images
    - "Load Test" button that submits N jobs simultaneously

#### B. API Layer (API Gateway + Lambda)

Two Lambda functions behind API Gateway:

1. **Job Submission (`POST /jobs`)**
    
    - Accepts image upload (base64 or multipart)
    - Generates a unique job ID (UUID)
    - Stores original image in S3 at `inputs/{jobId}/original.{ext}`
    - Creates a DynamoDB record: `{ jobId, status: "pending", createdAt, inputKey }`
    - Sends SQS message: `{ jobId, inputKey, operations: ["thumbnail", "grayscale", "blur"] }`
    - Returns `{ jobId, status: "pending" }` to client
2. **Job Status (`GET /jobs/{jobId}` and `GET /jobs`)**
    
    - Queries DynamoDB for job status
    - If completed, returns presigned S3 URLs for processed images
    - `GET /jobs` returns paginated list of all jobs with statuses
3. **System Metrics (`GET /metrics`)**
    
    - Queries CloudWatch for current SQS queue depth
    - Queries ECS for active task count
    - Returns `{ queueDepth, activeWorkers, timestamp }`

#### C. Job Queue (SQS)

- Standard SQS queue for job messages
- Visibility timeout: 120 seconds (enough time for image processing)
- Dead-letter queue (DLQ) for failed messages after 3 retries
- Message format:
    
    ```json
    {  "jobId": "uuid-here",  "inputKey": "inputs/uuid-here/original.jpg",  "operations": ["thumbnail", "grayscale", "blur"],  "submittedAt": "2026-04-03T12:00:00Z"}
    ```
    

#### D. Worker Container (Python on ECS Fargate)

- Dockerized Python application
    
- Long-polls SQS queue for messages
    
- On receiving a job:
    
    1. Downloads image from S3 (`inputKey`)
    2. Performs image transformations using Pillow:
        - **Thumbnail**: Resize to 150x150
        - **Medium**: Resize to 800px wide, maintain aspect ratio
        - **Grayscale**: Convert to grayscale
        - **Blur**: Apply Gaussian blur
        - **Edge Detection**: Apply edge detection filter
    3. Uploads all processed variants to S3 at `outputs/{jobId}/{variant}.jpg`
    4. Updates DynamoDB record: `status: "completed"`, adds output keys and processing duration
    5. Deletes SQS message
- On failure:
    
    1. Logs error to CloudWatch
    2. Does NOT delete SQS message (returns to queue after visibility timeout)
    3. After 3 failures, message goes to DLQ
- **Worker code structure:**
    
    ```
    worker/
    ├── Dockerfile
    ├── requirements.txt
    ├── worker.py          # Main loop: poll SQS, process, update status
    ├── processor.py       # Image transformation logic
    └── config.py          # Environment variable config (queue URL, bucket, table)
    ```
    

#### E. Auto-Scaling Configuration

- **Service**: ECS Fargate Service with desired count = 0 (scale to zero)
- **Scaling Policy**: Target Tracking on CloudWatch metric `ApproximateNumberOfMessagesVisible` from SQS
- **Rules**:
    - Scale up: 1 worker per 5 messages in queue
    - Minimum tasks: 0
    - Maximum tasks: 5
    - Scale-in cooldown: 300 seconds (5 min)
    - Scale-out cooldown: 60 seconds (1 min, react quickly to load)
- **Fargate Task Definition**:
    - 0.25 vCPU, 0.5 GB RAM (smallest available, sufficient for image processing)
    - Image from ECR

#### F. Monitoring & Observability (CloudWatch)

- **Custom Dashboard** with widgets for:
    - SQS `ApproximateNumberOfMessagesVisible` (queue depth over time)
    - SQS `NumberOfMessagesSent` (job submission rate)
    - ECS `RunningTaskCount` (active workers over time)
    - Lambda invocation count and error rate
    - Average job processing duration (custom metric from worker)
- **Alarms**:
    - DLQ depth > 0 → SNS email notification
    - Worker error rate > 10% → SNS email notification

#### G. Infrastructure-as-Code (Terraform)

All infrastructure defined in Terraform:

```
terraform/
├── main.tf              # Provider config
├── variables.tf         # Configurable parameters
├── s3.tf                # S3 bucket for images
├── dynamodb.tf          # Jobs table
├── sqs.tf               # Main queue + DLQ
├── ecr.tf               # Container registry
├── ecs.tf               # Cluster, task def, service, auto-scaling
├── lambda.tf            # Functions + IAM roles
├── api_gateway.tf       # REST API
├── cloudwatch.tf        # Dashboard + alarms
├── outputs.tf           # API URL, bucket name, etc.
└── iam.tf               # All IAM roles and policies
```

---

## 3. Tech Stack Summary

|Component|AWS Service|Purpose|
|---|---|---|
|Frontend|S3 + CloudFront|Static React app hosting|
|API|API Gateway + Lambda|REST endpoints for job mgmt|
|Queue|SQS + DLQ|Decoupled job messaging|
|Workers|ECS Fargate + ECR|Containerized image processing|
|Storage|S3|Image input/output storage|
|Database|DynamoDB|Job status tracking|
|Auto-Scaling|ECS Service Auto Scaling|Scale workers on queue depth|
|Monitoring|CloudWatch|Dashboards, metrics, alarms|
|Alerting|SNS|Email alerts on failures|
|IaC|Terraform|Infrastructure definition|
|CI/CD|GitHub Actions|Build + push Docker image to ECR|

**Worker Language:** Python 3.12 **Image Processing Library:** Pillow (PIL) **Frontend Framework:** React (Vite) **AWS SDK:** boto3 (worker), @aws-sdk (Lambda)

---

## 4. Estimated Cost

|Service|Free Tier / Pricing|Estimated Cost|
|---|---|---|
|Lambda|1M requests/month free|$0.00|
|API Gateway|1M calls/month free (first 12 months)|$0.00|
|S3|5GB free|$0.00|
|DynamoDB|25GB + 25 RCU/WCU free|$0.00|
|SQS|1M requests/month free|$0.00|
|ECR|500MB storage free|$0.00|
|ECS Fargate|~$0.01/hour per task (0.25 vCPU, 0.5GB)|$2-5 total|
|CloudWatch|10 custom metrics + 3 dashboards free|$0.00|
|CloudFront|1TB transfer free (first 12 months)|$0.00|
|SNS|1M publishes free|$0.00|
|**Total**||**$2-5 total**|

Note: If FAU provides AWS Academy credits, total cost is $0.

---

## 5. Development Phases & Timeline

### Phase 1: Foundation (Days 1-2)

- [x] Set up AWS account / configure CLI credentials
- [x] Create Terraform project structure
- [x] Provision S3 bucket, DynamoDB table, SQS queue + DLQ via Terraform
- [x] Test: manually put a message on SQS, verify it appears

### Phase 2: Worker Container (Days 3-4)

- [x] Write Python worker: SQS polling, S3 download/upload, DynamoDB updates
- [x] Write image processor module (Pillow transformations)
- [x] Create Dockerfile, build and test locally
- [x] Push image to ECR
- [x] Deploy ECS Fargate task definition and service via Terraform
- [x] Test: manually enqueue a job, verify worker picks it up and processes it

### Phase 3: API Layer (Days 5-6)

- [x] Write Lambda function for job submission (S3 upload + SQS enqueue + DynamoDB write)
- [x] Write Lambda function for job status retrieval
- [x] Write Lambda function for system metrics
- [x] Configure API Gateway with routes
- [x] Deploy via Terraform
- [x] Test: submit a job via curl/Postman, verify end-to-end flow

### Phase 4: Auto-Scaling (Day 7)

- [x] Configure ECS Service Auto Scaling with target tracking policy
- [x] Set scaling thresholds (5 messages per worker, min 0, max 5)
- [x] Test: submit 20+ jobs, observe workers scaling up
- [x] Test: wait for queue to drain, observe workers scaling down
- [x] Tune cooldown periods as needed

### Phase 5: Frontend Dashboard (Days 8-9)

- [x] Build React app with Vite
- [x] Implement image upload form
- [x] Implement job status tracker with polling
- [x] Implement real-time metrics display (queue depth, worker count)
- [x] Implement results gallery with processed image previews
- [x] Add "Load Test" button for batch submission
- [x] Deploy to S3 + CloudFront via Terraform

### Phase 6: Monitoring & Polish (Day 10)

- [ ] Create CloudWatch dashboard with all key metrics
- [ ] Set up SNS alarms for DLQ and error rates
- [ ] Set up GitHub Actions CI/CD pipeline for Docker builds
- [ ] Write README with architecture diagram
- [ ] End-to-end testing and bug fixes

### Phase 7: Presentation Prep (Days 11-12)

- [ ] Prepare slide deck (architecture diagram, tech stack, scaling demo)
- [ ] Practice live demo flow (see Demo Script below)
- [ ] Prepare backup screenshots/screen recordings in case of live demo failure
- [ ] Write project report

---

## 6. Demo Script (For Professor Presentation)

### Setup (Before Presentation)

- Tear down any running workers (ensure scale-to-zero state)
- Clear DynamoDB table and S3 bucket for a clean demo
- Open three browser tabs:
    1. Frontend dashboard
    2. AWS CloudWatch dashboard
    3. AWS ECS console (showing running tasks)

### Demo Flow

**Act 1: The Architecture (2 min)**

- Show architecture diagram slide
- Walk through each component and explain the cloud service used
- Highlight the auto-scaling mechanism

**Act 2: Single Job (3 min)**

- Submit one image through the frontend
- Show it appear as "pending" in the job tracker
- Switch to ECS console — watch a Fargate task spin up (30-60 sec cold start)
- Switch to CloudWatch — show the queue depth go from 0 to 1
- Switch back to frontend — job moves to "processing" then "completed"
- Show the processed image variants in the results gallery
- Key talking point: "One job triggered one worker. The system went from zero compute to exactly what was needed."

**Act 3: The Scale-Up (4 min)**

- Click the "Load Test" button to submit 25 images simultaneously
- Switch to CloudWatch — queue depth spikes to 25
- Switch to ECS console — watch workers scale from 1 to 5 over the next 1-2 minutes
- Switch to frontend — jobs are being completed in parallel, much faster than single-worker
- Key talking point: "The system detected demand and scaled compute resources automatically. No human intervention required."

**Act 4: The Scale-Down (2 min)**

- Queue is draining, jobs completing
- Show CloudWatch graph: queue depth decreasing as worker count stays high
- Once queue is empty, explain: "In about 5 minutes, the scale-in cooldown will trigger and workers will start terminating."
- Show a pre-recorded clip or screenshot of workers scaling to zero (to save time)
- Key talking point: "When there is no work, we pay for no compute. This is the fundamental promise of the cloud."

**Act 5: Fault Tolerance (2 min)**

- Show the dead-letter queue concept
- Show the SNS alarm configuration
- Explain: "If a job fails 3 times, it goes to the DLQ instead of being lost. An alarm triggers an email notification."
- If time permits: show the Terraform code and explain how the entire infrastructure is reproducible with one command

**Act 6: Q&A (2 min)**

### Backup Plan

- Pre-record the entire demo as a screen recording in case of network issues or AWS outages during presentation
- Have CloudWatch screenshots ready as static backup

---

## 7. File Structure

```
cloud-job-queue/
├── README.md
├── .github/
│   └── workflows/
│       └── deploy-worker.yml       # CI/CD: build + push Docker image
├── terraform/
│   ├── main.tf
│   ├── variables.tf
│   ├── outputs.tf
│   ├── s3.tf
│   ├── dynamodb.tf
│   ├── sqs.tf
│   ├── ecr.tf
│   ├── ecs.tf
│   ├── lambda.tf
│   ├── api_gateway.tf
│   ├── cloudwatch.tf
│   ├── iam.tf
│   └── sns.tf
├── worker/
│   ├── Dockerfile
│   ├── requirements.txt
│   ├── worker.py
│   ├── processor.py
│   └── config.py
├── lambdas/
│   ├── submit_job/
│   │   ├── index.py
│   │   └── requirements.txt
│   ├── get_job/
│   │   └── index.py
│   └── get_metrics/
│       └── index.py
├── frontend/
│   ├── package.json
│   ├── vite.config.js
│   ├── index.html
│   └── src/
│       ├── App.jsx
│       ├── components/
│       │   ├── UploadForm.jsx
│       │   ├── JobTracker.jsx
│       │   ├── MetricsDashboard.jsx
│       │   ├── ResultsGallery.jsx
│       │   └── LoadTestButton.jsx
│       └── api/
│           └── client.js
└── docs/
    ├── architecture-diagram.png
    ├── presentation-slides.pptx
    └── project-report.md
```

---

## 8. Key Talking Points for Grading Criteria

### Technical Proficiency (35 pts)

- **Complexity**: Multi-service architecture with 10+ AWS services working together. Containerization, auto-scaling, event-driven processing, IaC.
- **Implementation**: Proper use of SQS for decoupling, Fargate for elastic compute, DynamoDB for low-latency status tracking, S3 for durable object storage.
- **Innovation**: Scale-to-zero workers with automatic scaling based on real demand metrics. Dead-letter queue for fault tolerance. Full IaC with Terraform.

### Project Management (25 pts)

- **Planning**: Clear 12-day phased timeline with incremental milestones and testable deliverables at each phase.
- **Adaptability**: Built-in flexibility — can adjust scaling thresholds, swap processing tasks, add/remove operations.
- **Completion**: Each phase produces a working increment. Even if later phases are incomplete, the core system functions.

### Application & Problem-Solving (25 pts)

- **Relevance**: Job queues with auto-scaling workers is a foundational cloud pattern used by Netflix, Uber, Slack, and virtually every production cloud system.
- **Problem-Solving**: Solves the real problem of handling variable, unpredictable workloads without over-provisioning or under-provisioning compute resources.

### Presentation & Communication (15 pts)

- **Clarity**: Live demo with clear before/during/after narrative arc.
- **Visuals**: Real-time CloudWatch dashboards, architecture diagrams, live scaling visualization.
- **Q&A**: Deep understanding of each component enables confident handling of technical questions.

---

## 9. Prerequisites & Setup Requirements

- AWS account (free tier eligible or FAU AWS Academy)
- AWS CLI v2 installed and configured
- Terraform installed (v1.5+)
- Docker Desktop installed
- Node.js 18+ (for frontend)
- Python 3.12 (for worker and Lambdas)
- Git + GitHub account (for CI/CD)

---

## 10. Potential Enhancements (If Time Permits)

- Add a WebSocket connection (API Gateway WebSocket) for real-time status updates instead of polling
- Add a cost tracker that estimates the dollar cost of each job based on Fargate runtime
- Implement priority queues (urgent jobs processed first)
- Add authentication (Cognito) for multi-user support
- Implement blue/green deployments for worker container updates
- Add X-Ray tracing for end-to-end request visibility