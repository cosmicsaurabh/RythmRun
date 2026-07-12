# Migration Guide: AWS S3 + CloudFront → Cloudflare R2

This document outlines the migration from AWS S3 and CloudFront to Cloudflare R2 for file storage and CDN.

## 📋 Overview

**Cost Savings**: ~$60-70/month reduction
- **Previous**: AWS S3 ($0.23/GB) + CloudFront ($5-10/month) + Egress fees ($0.09/GB)
- **New**: Cloudflare R2 ($0.015/GB storage + FREE egress)

**Benefits**: 
- Zero egress fees (AWS charges $0.09/GB)
- S3-compatible API (minimal code changes)
- Built-in CDN via Cloudflare
- Free tier: 10GB storage + unlimited bandwidth

## 🔄 Code Changes Made

### 1. S3 Service (`src/services/s3.service.ts`)
- **Removed**: CloudFront signing logic and dependencies
- **Updated**: S3 client to use R2 endpoint
- **New**: Uses R2 credentials (Account ID, Access Key, Secret Key)
- **Changed**: `getActivityImageReadUrl()` now async, returns R2 signed URLs instead of CloudFront URLs

### 2. Dependencies (`package.json`)
- **Removed**: `@aws-sdk/cloudfront-signer` (no longer needed)
- **Kept**: AWS SDK v3 packages (S3-compatible with R2)

### 3. Environment Variables (`.env.example`)
- **Removed**: AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, S3_BUCKET, CLOUDFRONT_DOMAIN, CLOUDFRONT_KEY_PAIR_ID, CLOUDFRONT_PRIVATE_KEY
- **Added**: R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY, R2_BUCKET_AVATARS, R2_BUCKET_ACTIVITY_IMAGES, R2_PUBLIC_URL

### 4. Documentation (`README.md`)
- Updated all references from AWS S3/CloudFront to Cloudflare R2
- Updated architecture diagrams
- Updated configuration sections

## 🚀 Deployment Steps

### Step 1: Create Cloudflare R2 Account
1. Visit [dash.cloudflare.com](https://dash.cloudflare.com)
2. Sign up (free account - no credit card required for free tier)
3. Navigate to **R2** section

### Step 2: Create Two Storage Buckets
1. Click **Create bucket**
2. Create bucket 1:
   - Name: `rythmrun-avatars`
   - Region: Any (recommended: closest to your users)
3. Create bucket 2:
   - Name: `rythmrun-activity-images`
   - Region: Same as above

### Step 3: Generate R2 API Credentials
1. Go to **R2 Settings** → **API Tokens**
2. Click **Create API token**
3. Configure:
   - **Token name**: `rhythmrun-backend`
   - **Permission**: `Object Read & Write`
   - **Bucket access**: Select both buckets from Step 2
   - **No TTL** or set appropriate expiry
4. Copy these values (shown only once):
   ```
   Access Key ID = R2_ACCESS_KEY_ID
   Secret Access Key = R2_SECRET_ACCESS_KEY
   ```

### Step 4: Get Account ID
1. Go to **R2 Settings** → **Account Details**
2. Copy your **Account ID**

### Step 5: Update Environment Variables

**Local Development** (`.env`):
```bash
R2_ACCOUNT_ID="your-account-id-here"
R2_ACCESS_KEY_ID="your-access-key-here"
R2_SECRET_ACCESS_KEY="your-secret-key-here"
R2_BUCKET_AVATARS="rythmrun-avatars"
R2_BUCKET_ACTIVITY_IMAGES="rythmrun-activity-images"
R2_PUBLIC_URL="https://your-account-id.r2.cloudflarestorage.com"
```

**Production** (Render/Railway dashboard):
Same as above - add to environment variables in deployment settings.

### Step 6: Install Dependencies
```bash
cd RythmRun_backend_nodejs
npm install
```

### Step 7: Deploy
```bash
# Merge this branch to main
git checkout main
git merge migration/aws-to-cloudflare-r2

# Push and deploy
git push origin main
# Deploy via your CI/CD pipeline (Render, Railway, etc.)
```

## ✅ Verification Checklist

After deployment, test the following:

- [ ] Backend starts without errors
- [ ] Test avatar upload via `/api/avatar/upload-url`
- [ ] Avatar upload completes successfully via `/api/avatar/confirm`
- [ ] Check R2 dashboard - new avatars appear in `rythmrun-avatars` bucket
- [ ] Test activity image upload (if implemented)
- [ ] Verify images display correctly in app
- [ ] Check that signed URLs work and have correct expiry time (15 minutes default)
- [ ] Verify images are accessible from multiple locations/networks

## 📊 How It Works Now

### Avatar Upload Flow
1. Frontend requests upload URL from `/api/avatar/upload-url`
2. Backend generates R2 presigned POST URL (valid for 5 minutes)
3. Frontend uploads directly to R2 via presigned URL
4. Frontend confirms upload via `/api/avatar/confirm`
5. Backend stores avatar key in user profile

### Image Delivery Flow
1. When returning image URLs, backend calls `getActivityImageReadUrl()`
2. Backend generates R2 presigned GET URL (valid for 15 minutes)
3. Frontend receives signed URL in API response
4. Frontend displays image via signed URL
5. URL automatically expires after 15 minutes

## 🔒 Security Notes

1. **API Credentials**: Store only in environment variables
2. **Never commit credentials** to git or .env file
3. **Presigned URLs**: All files accessed through signed URLs with automatic expiry
4. **No Direct Access**: Frontend never receives raw R2 credentials
5. **Bucket Privacy**: R2 buckets are private by default
6. **Signed URL Expiry**: Default 900 seconds (15 minutes) prevents unauthorized access

## 🐛 Troubleshooting

| Issue | Solution |
|-------|----------|
| "NoSuchBucket" error | Verify bucket names match R2 dashboard exactly |
| "Invalid credentials" error | Double-check R2_ACCOUNT_ID, R2_ACCESS_KEY_ID, R2_SECRET_ACCESS_KEY |
| Signed URLs not working | Ensure R2_PUBLIC_URL format is correct: `https://account-id.r2.cloudflarestorage.com` |
| Images not displaying in app | Verify signed URLs haven't expired (default 15 minutes) |
| Permission denied errors | Check API token has "Object Read & Write" permission for selected buckets |

## 💾 Data Migration (Optional)

If you have existing images in AWS S3:

```bash
# 1. Export from S3
aws s3 sync s3://rythmrun-profile-pictures-lore ./local-images/

# 2. Upload to R2
aws s3 sync ./local-images s3://rythmrun-avatars \
  --endpoint-url https://your-account-id.r2.cloudflarestorage.com \
  --access-key your-r2-access-key \
  --secret-key your-r2-secret-key
```

But since you don't have existing production images, you can skip this step.

## 📝 API Changes

**No breaking changes!** APIs remain identical:
- `POST /api/avatar/upload-url` - Still returns presigned upload URL
- `POST /api/avatar/confirm` - Still confirms upload
- `GET /api/activities` - Still returns signed image URLs

The only change is internal: URLs now come from R2 instead of CloudFront.

## 🚀 Future Improvements

1. Add custom domain for R2 (e.g., `cdn.rhythmrun.app`)
2. Implement image optimization (resize, compression)
3. Add WebP format support for better compression
4. Monitor R2 usage dashboard for cost optimization

## 📚 References

- [Cloudflare R2 Documentation](https://developers.cloudflare.com/r2/)
- [R2 S3 API Compatibility](https://developers.cloudflare.com/r2/api/s3/api/)
- [Presigned URLs in R2](https://developers.cloudflare.com/r2/examples/presigned-urls/)

---

**Questions?** Check the main README.md or Cloudflare R2 documentation linked above.
