"""
train_model.py
Re-trains the QR malicious-URL classifier on dataset.csv and saves:
  • qr_model.pkl          – the trained GradientBoostingClassifier
  • feature_columns.pkl   – ordered list of feature names expected by the model

Run:  python train_model.py [path/to/dataset.csv]
"""

import sys
import os
import pandas as pd
import joblib
from sklearn.ensemble import GradientBoostingClassifier
from sklearn.model_selection import train_test_split
from sklearn.metrics import accuracy_score, classification_report

BASE_DIR     = os.path.dirname(os.path.abspath(__file__))
DATASET_PATH = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BASE_DIR, "dataset.csv")
MODEL_PATH   = os.path.join(BASE_DIR, "qr_model.pkl")
FEATURE_PATH = os.path.join(BASE_DIR, "feature_columns.pkl")


def train():
    if not os.path.exists(DATASET_PATH):
        print(f"[ERROR] Dataset not found at {DATASET_PATH}")
        sys.exit(1)

    print(f"Loading dataset from {DATASET_PATH} …")
    df = pd.read_csv(DATASET_PATH)

    # Normalise label
    df["label"] = df["label"].apply(
        lambda x: 1 if str(x).lower().strip() == "malicious" else 0
    )

    X = df.drop(columns=["label"])
    y = df["label"]

    print(f"Dataset: {len(df)} rows | benign={int((y==0).sum())}  malicious={int((y==1).sum())}")

    X_train, X_test, y_train, y_test = train_test_split(
        X, y, test_size=0.2, random_state=42, stratify=y
    )

    print("Training GradientBoostingClassifier (XGBoost-equivalent) …")
    clf = GradientBoostingClassifier(
        n_estimators=200,
        max_depth=5,
        learning_rate=0.1,
        subsample=0.8,
        random_state=42,
    )
    clf.fit(X_train, y_train)

    acc = accuracy_score(y_test, clf.predict(X_test))
    print(f"\nTest accuracy: {acc:.4f}\n")
    print(classification_report(y_test, clf.predict(X_test)))

    joblib.dump(clf, MODEL_PATH)
    joblib.dump(list(X.columns), FEATURE_PATH)
    print(f"Saved model      → {MODEL_PATH}")
    print(f"Saved features   → {FEATURE_PATH}")
    print("Done!")


if __name__ == "__main__":
    train()
