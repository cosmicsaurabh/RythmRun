# RythmRun Backend

This is the backend API for the RythmRun fitness application, built with Node.js, Express, and TypeScript.

## Technology Used

- **Runtime**: Node.js 22.x
- **Framework**: Express.js
- **Language**: TypeScript
- **Database**: PostgreSQL
- **ORM**: Prisma
- **Authentication**: JWT (JSON Web Tokens)
- **Password Hashing**: bcrypt
- **File Uploads**: Direct-to-S3 signed uploads with CloudFront reads

## API Features & Endpoints

This section details the currently implemented features and their corresponding API endpoints.

### 👤 User & Authentication

- **`POST /api/users/register`**: Register a new user.
- **`POST /api/users/login`**: Authenticate a user and receive a JWT.
- **`GET /api/users/profile`**: Fetch the authenticated user's profile.
- **`PUT /api/users/profile`**: Update the authenticated user's profile information.
- **`POST /api/users/profile-picture`**: Upload or update a user's profile picture.

### 🏃 Activity Management

- **`POST /api/activities`**: Create a new fitness activity.
- **`GET /api/activities`**: Retrieve a list of activities (e.g., for a feed).
- **`GET /api/activities/:id`**: Get details for a specific activity.
- **`PUT /api/activities/:id`**: Update an existing activity.
- **`DELETE /api/activities/:id`**: Delete an activity.

### 👥 Social Features

- **Friends**

  - **`GET /api/friends`**: Get the user's list of friends.
  - **`POST /api/friends/request`**: Send a friend request to another user.

- **Interactions**
  - **`POST /api/activities/:activityId/likes`**: Like or unlike an activity.
  - **`POST /api/activities/:activityId/comments`**: Post a new comment on an activity.

## Project Structure

```
src/
├── controllers/     # Handles API requests and responses
├── services/        # Contains the business logic
├── routes/          # Defines the API endpoints
├── middleware/      # For authentication and validation
├── models/          # DTOs and type definitions
├── config/          # Application configuration
└── prisma/          # Database schema and migrations
```

## How to Run

Use Node.js 22.x; `package.json` declares this runtime line because current AWS SDK v3 packages require a supported Node release. Deployment tooling must enforce the declaration.

1.  **Install Dependencies**

    ```bash
    npm install --no-audit
    ```

2.  **Set Up Environment**

    - Create a `.env` file in this directory.
    - Add your `DATABASE_URL` to the `.env` file:
      ```
      DATABASE_URL="postgresql://USER:PASSWORD@HOST:PORT/DATABASE"
      ```

3.  **Run Database Migrations**

    ```bash
    npx prisma migrate dev
    ```

4.  **Start the Server**
    ```bash
    npm run dev
    ```

The API will be running on `http://localhost:3000`.
