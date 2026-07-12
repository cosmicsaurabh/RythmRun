// Jest setup: Configure R2 environment variables for all tests
process.env.R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID || 'test-account-id';
process.env.R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID || 'test-access-key';
process.env.R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY || 'test-secret-key';
process.env.R2_BUCKET_AVATARS = process.env.R2_BUCKET_AVATARS || 'test-avatars-bucket';
process.env.R2_BUCKET_ACTIVITY_IMAGES = process.env.R2_BUCKET_ACTIVITY_IMAGES || 'test-activity-images-bucket';
process.env.R2_PUBLIC_URL = process.env.R2_PUBLIC_URL || 'https://test-account-id.r2.cloudflarestorage.com';
