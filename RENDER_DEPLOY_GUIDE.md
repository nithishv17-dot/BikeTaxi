# Render Deployment Instructions: Monorepo Deployment (Backend & Frontend)

This guide explains how to host both the **Express Backend** and **Flutter Web Frontend** on **Render**.

---

## 1. Backend Service Setup (Node.js + WebSockets)
Follow these steps to host your backend on Render:

1. **Create a new Web Service** on Render.
2. Connect your GitHub repository.
3. Configure the following settings:
   * **Name**: `bike-taxi-backend`
   * **Root Directory**: `backend` *(This isolates build commands to the backend folder)*
   * **Build Command**: `npm install`
   * **Start Command**: `node server.js`
   * **Instance Type**: `Free`
4. Add the necessary Environment Variables:
   * `MONGODB_URI` = `your_mongodb_connection_string`
   * `JWT_SECRET` = `your_jwt_secret_token`

---

## 2. Frontend Service Setup (Flutter Web Static Site)
Since Flutter compiles to a static bundle of HTML/CSS/JS files, you can deploy it as a **Static Site** on Render for free.

1. **Create a Static Site** on Render.
2. Connect your GitHub repository.
3. Configure the following settings:
   * **Name**: `bike-taxi-frontend`
   * **Root Directory**: `frontend/bike_taxi_app` *(Tells Render where the Flutter project is)*
   * **Build Command**: `flutter build web --release` *(Compiles the Flutter application)*
   * **Publish Directory**: `build/web` *(Render will host the contents of this folder)*
   * **Instance Type**: `Free`

---

## 3. Important Configuration Sync
After creating the Web Service, copy the generated backend URL (e.g. `https://bike-taxi-backend.onrender.com`).
* Go to `frontend/bike_taxi_app/lib/services/api_service.dart` (or wherever your API endpoint URL is configured) and update the base URL to point to your new Render Backend URL.
* Re-commit and push the changes. Render will automatically rebuild and deploy both services!
