// Jest setup: Configure R2 environment variables for all tests
process.env.GOOGLE_SERVER_CLIENT_ID =
  process.env.GOOGLE_SERVER_CLIENT_ID || 'test.apps.googleusercontent.com';
process.env.R2_ACCOUNT_ID = process.env.R2_ACCOUNT_ID || 'test-account-id';
process.env.R2_ACCESS_KEY_ID = process.env.R2_ACCESS_KEY_ID || 'test-access-key';
process.env.R2_SECRET_ACCESS_KEY = process.env.R2_SECRET_ACCESS_KEY || 'test-secret-key';
process.env.R2_BUCKET_AVATARS = process.env.R2_BUCKET_AVATARS || 'test-avatars-bucket';
process.env.R2_BUCKET_ACTIVITY_IMAGES = process.env.R2_BUCKET_ACTIVITY_IMAGES || 'test-activity-images-bucket';
