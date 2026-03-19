# 🛡️ QRShield API Backend

A powerful FastAPI-based backend for real-time QR code analysis, combining Deep Learning (DL) for image distortion detection and Machine Learning (ML) for malicious URL classification.

## 🚀 Overview

QRShield provides a robust API for scanning QR codes and detecting potential security risks. The system uses a two-stage fusion model approach:
- **Computer Vision (Robust Decoding)**: Employs multiple preprocessing techniques (upscaling, rotations, denoising, adaptive thresholding) with `pyzbar` and `OpenCV` to extract URLs even from low-quality images.
- **Deep Learning (Distortion Analysis)**: A ResNet-18 based model that identifies if a QR code has been physically tampered with or distorted.
- **Machine Learning (URL Classification)**: A Gradient Boosting classifier that analyzes lexical, DNS, and WHOIS features of the extracted URL to determine its safety.

---

## 🛠️ Architecture & Tech Stack

- **Framework**: `FastAPI` (Python)
- **Image Processing**: `Pillow`, `OpenCV`
- **QR Decoding**: `pyzbar`, `cv2.QRCodeDetector`
- **ML/DL**: `PyTorch` (DL), `Scikit-learn` (ML)
- **Database/Storage**: (Stateless API)
- **Web Server**: `Uvicorn`

---

## 📡 API Endpoints

| Method | Endpoint | Description |
| :--- | :--- | :--- |
| `GET` | `/health` | Service health status. |
| `POST` | `/scan` | Upload a QR image file for full analysis. |
| `POST` | `/scan_url` | Analyze a direct URL for malicious indicators. |
| `GET` | `/docs` | Interactive Swagger API documentation. |

---

## ⚙️ Configuration (Environment Variables)

The following environment variables can be used to configure the service:

| Variable | Default | Description |
| :--- | :--- | :--- |
| `PORT` | `8000` | Port for the Uvicorn server. |
| `ROOT_PATH` | `/mlapi` | Path prefix when hosted behind a proxy. |
| `RAPIDAPI_KEY` | `...` | Key for WHOIS domain age lookups. |

---

## 🌐 Hosting & Deployment

The API is designed to be hosted behind an Nginx reverse proxy.

### 1. Launch with Uvicorn
You can run the application directly using Uvicorn:
```bash
uvicorn main:app --host 0.0.0.0 --port 8000
```
*Note: The `ROOT_PATH` is handled internally via environment variables or defaults to `/mlapi`.*

### 2. Nginx Configuration
Add the following snippet inside your server block to proxy requests to the API:

```nginx
location /mlapi/ {
    proxy_pass         http://127.0.0.1:8000/;
    proxy_set_header   Host $host;
    proxy_set_header   X-Real-IP $remote_addr;
    proxy_set_header   X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header   X-Forwarded-Proto $scheme;
    proxy_read_timeout 120s;
}
```

### 3. Procfile (Paas like Heroku)
A `Procfile` is included for easy deployment:
```text
web: uvicorn main:app --host 0.0.0.0 --port $PORT
```

---

## 💻 Local Development

1. **Clone the repository**:
   ```bash
   git clone <repo-url>
   cd qrshield-backend
   ```

2. **Set up a virtual environment**:
   ```bash
   python3 -m venv venv
   source venv/bin/activate  # On macOS/Linux
   # or
   venv\Scripts\activate     # On Windows
   ```

3. **Install dependencies**:
   ```bash
   pip install -r requirements.txt
   ```

4. **Run the server**:
   ```bash
   uvicorn main:app --reload
   ```

5. **Access the UI**:
   Open `http://127.0.0.1:8000/` in your browser to see the API status dashboard.

---

## 🧪 Model Files
Ensure the following files are present in the root directory:
- `best_qr_model.pth` (DL Model)
- `qr_model.pkl` (ML Model)
- `feature_columns.pkl` (Feature list)

---