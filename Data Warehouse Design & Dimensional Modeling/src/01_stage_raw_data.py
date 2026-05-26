"""
01_stage_raw_data.py
---------------------
Loads all Olist raw CSVs into PostgreSQL staging schema.

Dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
Place all CSVs in /data/raw/ before running.
"""

import pandas as pd
import os
from sqlalchemy import create_engine, text
from datetime import datetime

STAGE_DB   = "postgresql://postgres:password@localhost:5432/olist_staging"
RAW_DIR    = os.path.join(os.path.dirname(__file__), "../data/raw")
BATCH_ID   = datetime.now().strftime("batch_%Y%m%d_%H%M")

FILES = {
    "orders":       "olist_orders_dataset.csv",
    "order_items":  "olist_order_items_dataset.csv",
    "payments":     "olist_order_payments_dataset.csv",
    "reviews":      "olist_order_reviews_dataset.csv",
    "customers":    "olist_customers_dataset.csv",
    "products":     "olist_products_dataset.csv",
    "sellers":      "olist_sellers_dataset.csv",
    "geolocation":  "olist_geolocation_dataset.csv",
    "categories":   "product_category_name_translation.csv",
}

engine = create_engine(STAGE_DB)

for table_name, filename in FILES.items():
    path = os.path.join(RAW_DIR, filename)
    if not os.path.exists(path):
        print(f"  SKIP (not found): {filename}")
        continue

    print(f"Loading {filename} → staging.{table_name} ...")
    df = pd.read_csv(path, low_memory=False)
    df["etl_batch_id"] = BATCH_ID
    df["etl_loaded_at"] = datetime.now()

    df.to_sql(table_name, engine, schema="public", if_exists="replace",
              index=False, chunksize=5_000, method="multi")
    print(f"  ✓ {len(df):,} rows loaded")

print(f"\nAll staging loads complete. Batch: {BATCH_ID}")
