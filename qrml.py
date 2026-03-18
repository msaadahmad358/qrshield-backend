"""
qrml.py  –  URL-based malicious-QR detector
Model: GradientBoostingClassifier trained on dataset.csv (99 % accuracy)
"""

import cv2
from pyzbar.pyzbar import decode
import joblib
import pandas as pd
import re
import requests
import dns.resolver
import tldextract
from urllib.parse import urlparse
import os

# ======================================
# WHOIS API CONFIG
# ======================================
RAPIDAPI_KEY      = "48ae91a537mshe7a9870445933adp1ac93bjsne535f07ca743"
RAPIDAPI_HOST     = "whois-lookup-api.p.rapidapi.com"
RAPIDAPI_ENDPOINT = "https://whois-lookup-api.p.rapidapi.com/domains-age"

# ======================================
# LOAD MODEL  (qr_model.pkl ships alongside this file)
# ======================================
BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
MODEL_PATH   = os.path.join(BASE_DIR, "qr_model.pkl")
FEATURE_PATH = os.path.join(BASE_DIR, "feature_columns.pkl")

model           = joblib.load(MODEL_PATH)
feature_columns = joblib.load(FEATURE_PATH)

# ======================================
# QR DECODER  (image → URL)
# ======================================
def extract_url_from_qr(image_path: str) -> str | None:
    img = cv2.imread(image_path)
    if img is None:
        return None
    for obj in decode(img):
        return obj.data.decode("utf-8")
    return None

# ======================================
# WHOIS  (domain age lookup)
# ======================================
def get_domain_age(domain: str) -> tuple[int, int]:
    """Returns (age_days, whois_available)."""
    headers = {
        "X-RapidAPI-Key":  RAPIDAPI_KEY,
        "X-RapidAPI-Host": RAPIDAPI_HOST,
    }
    try:
        resp = requests.get(
            RAPIDAPI_ENDPOINT,
            headers=headers,
            params={"domains": domain},
            timeout=10,
        )
        data = resp.json()
        if domain in data:
            age = data[domain].get("age_days")
            if age is not None:
                return int(age), 1
    except Exception:
        pass
    return 0, 0

# ======================================
# FEATURE EXTRACTION
# ======================================
def extract_features(url: str) -> dict:
    features: dict = {}
    parsed = urlparse(url)
    ext    = tldextract.extract(url)
    domain = ext.top_domain_under_public_suffix

    # ── Lexical ──────────────────────────────────────────────────
    features["checking_ip_address"] = (
        1 if re.match(r"^\d+\.\d+\.\d+\.\d+", parsed.netloc) else 0
    )
    features["abnormal_url"]        = 0 if parsed.netloc in url else 1
    features["count_dot"]           = url.count(".")
    features["count_at"]            = url.count("@")
    features["find_dir"]            = url.count("/")
    features["no_of_embed"]         = url.count("//") - 1

    shortening_services = [
        "bit.ly", "tinyurl.com", "goo.gl", "t.co",
        "ow.ly", "is.gd", "buff.ly",
    ]
    features["shortening_service"] = (
        1 if any(s in url for s in shortening_services) else 0
    )

    features["count_per"]          = url.count("%")
    features["count_ques"]         = url.count("?")
    features["count_dash"]         = url.count("-")
    features["count_equal"]        = url.count("=")
    features["url_length"]         = len(url)
    features["hostname_length"]    = len(parsed.netloc)

    suspicious_words = [
        "login", "verify", "update", "account",
        "secure", "bank", "confirm",
    ]
    features["suspicious_words"] = (
        1 if any(w in url.lower() for w in suspicious_words) else 0
    )

    features["digit_count"]         = sum(c.isdigit() for c in url)
    features["count_special_chars"] = len(re.findall(r"[^\w]", url))
    features["fd_length"]           = (
        len(parsed.path.split("/")[1]) if len(parsed.path.split("/")) > 1 else 0
    )
    features["tld_length"]          = len(ext.suffix)
    features["uses_https"]          = 1 if parsed.scheme == "https" else 0

    # ── WHOIS ─────────────────────────────────────────────────────
    age, available = get_domain_age(domain)
    features["domain_age_days"] = age
    features["whois_available"] = available

    # ── DNS ───────────────────────────────────────────────────────
    try:
        answers = dns.resolver.resolve(domain, "A")
        features["dns_resolves"]    = 1
        features["num_ip_addresses"] = len(answers)
    except Exception:
        features["dns_resolves"]    = 0
        features["num_ip_addresses"] = 0

    try:
        dns.resolver.resolve(domain, "MX")
        features["has_mx_record"] = 1
    except Exception:
        features["has_mx_record"] = 0

    # ── HTTP ──────────────────────────────────────────────────────
    try:
        response = requests.get(url, timeout=5, allow_redirects=True)
        features["http_status_code"] = response.status_code
        features["redirect_count"]   = len(response.history)
        features["ssl_valid"]        = 1 if url.startswith("https") else 0
    except Exception:
        features["http_status_code"] = -1
        features["redirect_count"]   = 0
        features["ssl_valid"]        = 0

    return features

# ======================================
# PREDICTION
# ======================================
def predict_url(url: str) -> tuple:
    """Returns (prediction: int, malicious_probability: float)."""
    features = extract_features(url)
    df = pd.DataFrame([features]).reindex(columns=feature_columns, fill_value=0)
    prob       = float(model.predict_proba(df)[0][1])
    prediction = int(model.predict(df)[0])
    return prediction, prob

# ======================================
# CLI
# ======================================
if __name__ == "__main__":
    image_path = input("Enter QR image path: ")
    url = extract_url_from_qr(image_path)

    if url:
        print("\nExtracted URL:", url)
        prediction, probability = predict_url(url)
        print("Malicious Probability:", round(probability, 4))
        if probability < 0.30:
            print("✅ BENIGN")
        elif probability < 0.70:
            print("⚠️  SUSPICIOUS")
        else:
            print("🚨 MALICIOUS")
    else:
        print("No QR code detected.")
