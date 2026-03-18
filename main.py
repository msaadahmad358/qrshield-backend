# main.py  –  QRShield FastAPI backend
# Hosted at: https://flutterdeveloper.online/mlapi
# Uvicorn launch:
#   uvicorn main:app --host 0.0.0.0 --port 8000 --root-path /mlapi
#
# Nginx snippet (add inside your flutterdeveloper.online server block):
#   location /mlapi/ {
#       proxy_pass         http://127.0.0.1:8000/;
#       proxy_set_header   Host $host;
#       proxy_set_header   X-Real-IP $remote_addr;
#       proxy_read_timeout 120s;
#   }

import io
import os
import numpy as np
from PIL import Image, ImageOps, ImageFilter
import time

from fastapi import FastAPI, UploadFile, File
from fastapi.responses import HTMLResponse, JSONResponse
from fastapi.middleware.cors import CORSMiddleware
from fastapi.templating import Jinja2Templates
from fastapi.requests import Request
from pydantic import BaseModel

from pyzbar.pyzbar import decode as pyzbar_decode
import cv2

import qrdl
import qrml

# ── App with root_path so docs/openapi work behind /mlapi proxy ──
app = FastAPI(
    title="QRShield API",
    version="1.0.0",
    root_path="/mlapi",         # matches Nginx proxy prefix
)

# ── CORS: allow Flutter web + mobile ─────────────────────────────
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],        # tighten in production if desired
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

templates = Jinja2Templates(directory="templates")

DEBUG     = False
DEBUG_DIR = "qr_debug"
os.makedirs(DEBUG_DIR, exist_ok=True)

print("Loading DL model...")
dl_model = qrdl.load_model()
print("DL model loaded.")


# ─────────────────────────────────────────────
# Debug helper
# ─────────────────────────────────────────────
def save_debug(img_pil, name):
    if not DEBUG:
        return
    path = os.path.join(DEBUG_DIR, f"{int(time.time()*1000)}_{name}.png")
    try:
        img_pil.save(path)
    except Exception as e:
        print("[DEBUG] save failed:", e)


# ─────────────────────────────────────────────
# Low-level decoders
# ─────────────────────────────────────────────
def try_pyzbar(pil_image):
    try:
        decoded = pyzbar_decode(pil_image)
        for obj in decoded:
            try:
                return obj.data.decode("utf-8")
            except Exception:
                return obj.data.decode(errors="ignore")
    except Exception:
        pass
    return None


def try_opencv_qr(pil_image):
    try:
        arr = np.array(pil_image.convert("RGB"))[:, :, ::-1]
        detector = cv2.QRCodeDetector()
        data, points, _ = detector.detectAndDecode(arr)
        if data and len(data.strip()) > 0:
            return data
    except Exception:
        pass
    return None


# ─────────────────────────────────────────────
# Preprocessing helpers
# ─────────────────────────────────────────────
def upscale_image(pil_image, scale):
    w, h = pil_image.size
    return pil_image.resize((int(w * scale), int(h * scale)), Image.LANCZOS)


def adaptive_threshold_cv(pil_image):
    arr = np.array(pil_image.convert("L"))
    try:
        thresh = cv2.adaptiveThreshold(
            arr, 255, cv2.ADAPTIVE_THRESH_GAUSSIAN_C, cv2.THRESH_BINARY, 21, 10
        )
        return Image.fromarray(thresh)
    except Exception:
        return pil_image


def denoise_cv(pil_image):
    arr = np.array(pil_image.convert("RGB"))
    try:
        dst = cv2.fastNlMeansDenoisingColored(
            arr, None, h=10, hColor=10, templateWindowSize=7, searchWindowSize=21
        )
        return Image.fromarray(dst)
    except Exception:
        return pil_image


def gamma_correction(pil_image, gamma):
    inv = 1.0 / gamma
    lut = np.array([pow(x / 255.0, inv) * 255 for x in range(256)]).clip(0, 255).astype("uint8")
    return pil_image.point(lambda i: lut[i])


# ─────────────────────────────────────────────
# Robust decode
# ─────────────────────────────────────────────
def robust_decode(pil_image):
    save_debug(pil_image, "orig")
    r = try_pyzbar(pil_image)
    if r: return r, "pyzbar:orig"
    r = try_opencv_qr(pil_image)
    if r: return r, "opencv:orig"

    scales    = [1, 1.5, 2, 3]
    rotations = [0, 90, 180, 270]
    pre_funcs = [
        lambda x: x,
        lambda x: ImageOps.autocontrast(x),
        lambda x: x.filter(ImageFilter.UnsharpMask(radius=1, percent=150, threshold=3)),
        lambda x: denoise_cv(ImageOps.autocontrast(x)),
        lambda x: adaptive_threshold_cv(ImageOps.autocontrast(x)),
        lambda x: gamma_correction(ImageOps.autocontrast(x), 0.8),
        lambda x: gamma_correction(ImageOps.autocontrast(x), 1.2),
    ]

    for scale in scales:
        scaled = pil_image if scale == 1 else upscale_image(pil_image, scale)
        for rot in rotations:
            cand = scaled.rotate(rot, expand=True) if rot != 0 else scaled
            for i, pf in enumerate(pre_funcs):
                try_img = pf(cand)
                r = try_pyzbar(try_img)
                if r: return r, f"pyzbar:scale{scale}_rot{rot}_pre{i}"
                r = try_opencv_qr(try_img)
                if r: return r, f"opencv:scale{scale}_rot{rot}_pre{i}"

    try:
        base = pil_image.convert("L")
        arr  = np.array(base)
        for k in [3, 5, 7]:
            try:
                b = cv2.medianBlur(arr, k)
                _, thr = cv2.threshold(b, 0, 255, cv2.THRESH_BINARY + cv2.THRESH_OTSU)
                r = try_pyzbar(Image.fromarray(thr))
                if r: return r, f"pyzbar:otsu_k{k}"
                r = try_opencv_qr(Image.fromarray(thr))
                if r: return r, f"opencv:otsu_k{k}"
            except Exception:
                continue
    except Exception:
        pass

    return None, "not_decoded"


# ─────────────────────────────────────────────
# Fusion & decision
# ─────────────────────────────────────────────
def adaptive_fusion(ml_prob, dl_prob):
    if ml_prob < 0.30:
        w_ml, w_dl, mode = 0.95, 0.05, "ML Dominant (Benign)"
    elif ml_prob < 0.70:
        w_ml, w_dl, mode = 0.80, 0.20, "Balanced (Suspicious)"
    else:
        w_ml, w_dl, mode = 0.95, 0.05, "ML Dominant (Malicious)"
    return round(w_ml * ml_prob + w_dl * dl_prob, 6), mode


def risk_decision(score):
    if score < 0.25:  return "SAFE"
    if score < 0.60:  return "SUSPICIOUS"
    return "MALICIOUS"


# ─────────────────────────────────────────────
# Main pipeline
# ─────────────────────────────────────────────
def analyze_qr(image: Image.Image) -> dict:
    result = {
        "decoded_url":    None,
        "ml_probability": 0.0,
        "dl_probability": 0.0,
        "fusion_score":   0.0,
        "fusion_mode":    "",
        "status":         "UNKNOWN",
        "error":          None,
        "note":           None,
    }
    try:
        image     = image.convert("RGB")
        temp_path = "temp_scan.png"
        image.save(temp_path, format="PNG")

        dl_label, dl_prob = qrdl.predict_image(dl_model, temp_path)
        result["dl_probability"] = round(float(dl_prob), 6)

        decoded, method = robust_decode(image)
        if decoded:
            result["decoded_url"] = decoded
            result["note"]        = f"decoded_by={method}"
            url = decoded if decoded.startswith(("http://", "https://")) else "https://" + decoded
            try:
                _, ml_prob = qrml.predict_url(url)
                result["ml_probability"] = round(float(ml_prob), 6)
            except Exception as e:
                result["note"] += f"; ml_error={e}"

            fusion_score, fusion_mode = adaptive_fusion(
                result["ml_probability"], result["dl_probability"]
            )
            result["fusion_score"] = fusion_score
            result["fusion_mode"]  = fusion_mode
            result["status"]       = risk_decision(fusion_score)
        else:
            result["fusion_score"] = round(float(dl_prob), 6)
            result["fusion_mode"]  = "DL Only (No URL)"
            result["status"]       = "DISTORTED_QR" if dl_prob > 0 else "UNKNOWN"
            result["note"]         = "No URL decoded; DL-only result."

    except Exception as e:
        result["error"] = str(e)

    return result


# ─────────────────────────────────────────────
# Endpoints
# ─────────────────────────────────────────────
@app.get("/", response_class=HTMLResponse)
async def home(request: Request):
    return templates.TemplateResponse("index.html", {"request": request})


@app.get("/health")
async def health():
    """Simple health-check for uptime monitoring."""
    return {"status": "ok", "service": "QRShield API"}


@app.post("/scan")
async def scan_qr(file: UploadFile = File(...)):
    try:
        contents = await file.read()
        image    = Image.open(io.BytesIO(contents))
        return analyze_qr(image)
    except Exception as e:
        return JSONResponse(status_code=500, content={
            "decoded_url": None, "ml_probability": 0.0,
            "dl_probability": 0.0, "fusion_score": 0.0,
            "fusion_mode": "", "status": "ERROR",
            "error": str(e), "note": "Failed to process uploaded image.",
        })


class URLRequest(BaseModel):
    url: str


@app.post("/scan_url")
async def scan_url(req: URLRequest):
    try:
        url = req.url
        if not url.startswith(("http://", "https://")):
            url = "https://" + url

        _, ml_prob   = qrml.predict_url(url)
        fusion_score = float(ml_prob)
        status       = risk_decision(fusion_score)

        return {
            "decoded_url":    url,
            "ml_probability": round(float(ml_prob), 6),
            "dl_probability": 0.0,
            "fusion_score":   round(fusion_score, 6),
            "fusion_mode":    "ML Only",
            "status":         status,
            "error":          None,
            "note":           "Manual URL lookup",
        }
    except Exception as e:
        return JSONResponse(status_code=500, content={
            "decoded_url": getattr(req, "url", ""),
            "ml_probability": 0.0, "dl_probability": 0.0,
            "fusion_score": 0.0, "fusion_mode": "",
            "status": "ERROR", "error": str(e),
            "note": "Failed to process manual URL.",
        })
