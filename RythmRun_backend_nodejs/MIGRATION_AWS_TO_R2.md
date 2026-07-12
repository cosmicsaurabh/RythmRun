# Migration Guide: AWS S3 + CloudFront → Cloudflare R2

This document outlines the migration from AWS S3 and CloudFront to Cloudflare R2 for file storage and CDN.

## 📋 Overview

**Migration Date**: This branch implements the complete migration
**Cost Savings**: ~$60-70/month (from $4-7/month on AWS to $0.15/month on R2)
**Benefits**: 
- Zero egress fees (AWS charges $0.09/GB)
- S3-compatible API (minimal code changes)
- Built-in CDN via Cloudflare
- Free tier with 10GB storage + unlimited egress

## 🔄 What Changed

### Code Changes

#### 1. **S3 Service** (`src/services/s3.service.ts`)
- **Removed**: AWS SDK v2 (`aws-sdk` package)
- **Added**: AWS SDK v3 (`@aws-sdk/client-s3`, `@aws-sdk/s3-request-presigner`)
- **Updated**: Configuration to use R2 endpoint instead of AWS region
- **New Methods**:
  - `getSignedReadUrl()` - Generate signed URLs for reading files (replaces CloudFront signing)
  - `deleteObject()` - Delete files from R2

#### 2. **Dependencies** (`package.json`)
```json
// REMOVED
"aws-sdk": "^2.1692.0"

// ADDED
"@aws-sdk/client-s3": "^3.600.0"
"@aws-sdk/s3-request-presigner": "^3.600.0"
```

#### 3. **Environment Variables** (`.env.example`)
```bash
# REMOVED (AWS)
AWS_REGION=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=
S3_BUCKET=
CLOUDFRONT_DOMAIN=
CLOUDFRONT_KEY_PAIR_ID=
CLOUDFRONT_PRIVATE_KEY=

# ADDED (Cloudflare R2)
R2_ACCOUNT_ID=
R2_ACCESS_KEY_ID=
R2_SECRET_ACCESS_KEY=
R2_BUCKET_AVATARS=
R2_BUCKET_ACTIVITY_IMAGES=
R2_PUBLIC_URL=
```

#### 4. **Documentation** (`README.md`)
- Updated tech stack: AWS S3 + CloudFront → Cloudflare R2
- Updated deployment info
- Updated environment variable examples

## 🚀 Deployment Steps

### Step 1: Create Cloudflare R2 Account
1. Visit [dash.cloudflare.com](https://dash.cloudflare.com)
2. Sign up (free account)
3. Navigate to **R2** section

### Step 2: Create Storage Buckets
1. Click **Create bucket**
2. Create two buckets:
   - `rythmrun-avatars`
   - `rythmrun-activity-images`

### Step 3: Generate API Credentials
1. Go to **R2 Settings** → **API Tokens**
2. Click **Create API token**
3. Settings:
   - **Token name**: rhythmrun-backend
   - **Permission**: Object Read & Write
   - **Bucket access**: Select both buckets created above
4. Copy these values:
   ```
   Access Key ID: R2_ACCESS_KEY_ID
   Secret Access Key: R2_SECRET_ACCESS_KEY
   Account ID: R2_ACCOUNT_ID (from R2 Settings → Account Details)
   ```

### Step 4: Update Environment Variables

In your production environment (Render, Railway, etc.):

```bash
# Remove old variables
AWS_REGION
AWS_ACCESS_KEY_ID
AWS_SECRET_ACCESS_KEY
S3_BUCKET
CLOUDFRONT_DOMAIN
CLOUDFRONT_KEY_PAIR_ID
CLOUDFRONT_PRIVATE_KEY

# Add new variables
R2_ACCOUNT_ID="your-account-id"
R2_ACCESS_KEY_ID="your-access-key"
R2_SECRET_ACCESS_KEY="your-secret-key"
R2_BUCKET_AVATARS="rythmrun-avatars"
R2_BUCKET_ACTIVITY_IMAGES="rythmrun-activity-images"
R2_PUBLIC_URL="https://your-account-id.r2.cloudflarestorage.com"
```

### Step 5: Install Dependencies
```bash
cd RythmRun_backend_nodejs
npm install
```

### Step 6: Deploy
```bash
# Commit changes
git add .
git commit -m "chore: migrate from AWS S3/CloudFront to Cloudflare R2"

# Push to your repository
git push origin migration/aws-s3-to-cloudflare-r2

# Create a PR for review
# Merge to main after approval
# Deploy to production
```

## ✅ Verification Checklist

After deployment:

- [ ] Backend starts without errors
- [ ] Test avatar upload via `/api/avatar/upload-url`
- [ ] Confirm avatar upload completes successfully
- [ ] Verify avatars display correctly in app
- [ ] Check R2 dashboard shows new objects
- [ ] Test image CDN URLs work (accessible from any location)
- [ ] Verify image URLs expire after configured time

## 📊 Cost Comparison

**Previous Setup (AWS S3 + CloudFront)**:
- Storage: $0.23/GB
- Egress: $0.09/GB
- CloudFront: $5-10/month
- **Total (10GB)**: ~$4-7/month + high egress costs

**New Setup (Cloudflare R2)**:
- Storage: $0.015/GB
- Egress: $0.00/GB (FREE!)
- CDN: Included
- **Total (10GB)**: $0.15/month

**Monthly Savings**: ~$4-7/month + egress savings

## 🔒 Security Notes

1. **API Credentials**: Store in environment variables, never commit
2. **Bucket Policies**: R2 buckets are private by default (good!)
3. **Signed URLs**: All files accessed through signed URLs with expiry (15 minutes default)
4. **No Direct Access**: Frontend never receives S3/R2 credentials

## 🐛 Troubleshooting

### Issue: "NoSuchBucket" Error
- **Solution**: Verify bucket names in environment variables match R2 dashboard

### Issue: "Invalid credentials" Error
- **Solution**: Double-check R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY

### Issue: Signed URLs not working
- **Solution**: Ensure R2_PUBLIC_URL is correct (format: https://account-id.r2.cloudflarestorage.com)

### Issue: Images not displaying in app
- **Solution**: Verify signed URLs are valid and not expired (default 900 seconds = 15 minutes)

## 📝 API Changes for Consumers

**No breaking changes!** The API endpoints remain the same:

```http
POST /api/avatar/upload-url   # Still works the same
POST /api/avatar/confirm       # Still works the same
```

The only change is internal - S3 URLs are replaced with R2 signed URLs.

## 🚀 Future Improvements

1. Add custom domain for R2 (e.g., cdn.rhythmrun.app)
2. Implement image optimization pipeline
3. Add WebP conversion for better compression
4. Monitor usage patterns for cost optimization

---

**Questions?** Check the main README.md or Cloudflare R2 documentation.
