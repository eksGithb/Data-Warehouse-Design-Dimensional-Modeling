"""
02_build_dimensions.py  +  03_build_facts.py (combined)
---------------------------------------------------------
Transforms staging data → warehouse dimensions and fact tables.
Applies SCD Type 2 logic via PostgreSQL stored procedures.

Run after: 01_stage_raw_data.py and SQL schema setup.
"""

import pandas as pd
import numpy as np
from sqlalchemy import create_engine, text
from datetime import datetime, date
import hashlib

STAGE_DB = "postgresql://postgres:password@localhost:5432/olist_staging"
DW_DB    = "postgresql://postgres:password@localhost:5432/olist_warehouse"
BATCH_ID = datetime.now().strftime("batch_%Y%m%d_%H%M")

stage_eng = create_engine(STAGE_DB)
dw_eng    = create_engine(DW_DB)

def log_audit(table, inserted, updated, skipped, status="success", notes=""):
    with dw_eng.connect() as conn:
        conn.execute(text("""
            INSERT INTO dw.etl_audit_log
                (batch_id, table_name, rows_inserted, rows_updated, rows_skipped, status, notes)
            VALUES (:b, :t, :i, :u, :s, :st, :n)
        """), {"b": BATCH_ID, "t": table, "i": inserted, "u": updated, "s": skipped, "st": status, "n": notes})
        conn.commit()

# ── 1. Populate dim_date ─────────────────────────────────────────────────────
print("Building dim_date (2015-01-01 to 2020-12-31)...")
dates = pd.date_range("2015-01-01", "2020-12-31", freq="D")
dim_date = pd.DataFrame({
    "full_date":     dates,
    "day_of_week":   dates.dayofweek,
    "day_name":      dates.strftime("%A"),
    "day_of_month":  dates.day,
    "day_of_year":   dates.dayofyear,
    "week_of_year":  dates.isocalendar().week.astype(int),
    "month_num":     dates.month,
    "month_name":    dates.strftime("%B"),
    "quarter":       dates.quarter,
    "year":          dates.year,
    "is_weekend":    dates.dayofweek >= 5,
})
dim_date.to_sql("dim_date", dw_eng, schema="dw", if_exists="append",
                index=False, chunksize=1000, method="multi")
log_audit("dw.dim_date", len(dim_date), 0, 0)
print(f"  ✓ {len(dim_date):,} date records inserted")

# ── 2. Populate dim_payment_type ─────────────────────────────────────────────
print("Building dim_payment_type...")
pay = pd.read_sql("SELECT DISTINCT payment_type FROM payments WHERE payment_type IS NOT NULL", stage_eng)
pay.rename(columns={"payment_type": "payment_type"}, inplace=True)
pay.to_sql("dim_payment_type", dw_eng, schema="dw", if_exists="append", index=False)
log_audit("dw.dim_payment_type", len(pay), 0, 0)
print(f"  ✓ {len(pay)} payment types loaded")

# ── 3. Populate dim_seller ───────────────────────────────────────────────────
print("Building dim_seller...")
sellers = pd.read_sql("""
    SELECT DISTINCT
        s.seller_id, s.seller_city, s.seller_state, s.seller_zip_code_prefix::TEXT AS seller_zip_code
    FROM sellers s
""", stage_eng)
sellers.to_sql("dim_seller", dw_eng, schema="dw", if_exists="append", index=False)
log_audit("dw.dim_seller", len(sellers), 0, 0)
print(f"  ✓ {len(sellers):,} sellers loaded")

# ── 4. Populate dim_customer (SCD Type 2 via stored procedure) ───────────────
print("Building dim_customer (SCD Type 2)...")
customers = pd.read_sql("""
    SELECT DISTINCT
        c.customer_id, c.customer_city, c.customer_state,
        c.customer_zip_code_prefix::TEXT AS customer_zip,
        g.geolocation_lat AS lat, g.geolocation_lng AS lng
    FROM customers c
    LEFT JOIN (
        SELECT geolocation_zip_code_prefix, AVG(geolocation_lat) AS geolocation_lat,
               AVG(geolocation_lng) AS geolocation_lng
        FROM geolocation GROUP BY geolocation_zip_code_prefix
    ) g ON g.geolocation_zip_code_prefix::TEXT = c.customer_zip_code_prefix::TEXT
""", stage_eng)

inserted = 0
with dw_eng.connect() as conn:
    for _, row in customers.iterrows():
        conn.execute(text("SELECT dw.upsert_dim_customer(:cid, :city, :state, :zip, :lat, :lng)"), {
            "cid": row.customer_id, "city": row.customer_city, "state": row.customer_state,
            "zip": row.customer_zip, "lat": row.get("lat"), "lng": row.get("lng")
        })
        inserted += 1
    conn.commit()
log_audit("dw.dim_customer", inserted, 0, 0)
print(f"  ✓ {inserted:,} customers upserted (SCD Type 2)")

# ── 5. Populate dim_product (SCD Type 2) ─────────────────────────────────────
print("Building dim_product (SCD Type 2)...")
products = pd.read_sql("""
    SELECT p.product_id, COALESCE(t.string_field_1, p.product_category_name) AS product_category,
           p.product_weight_g, p.product_length_cm, p.product_height_cm, p.product_width_cm
    FROM products p
    LEFT JOIN categories t ON t.string_field_0 = p.product_category_name
""", stage_eng)

inserted = 0
with dw_eng.connect() as conn:
    for _, row in products.iterrows():
        conn.execute(text("SELECT dw.upsert_dim_product(:pid, :cat, :wt, :len, :ht, :wd)"), {
            "pid": row.product_id, "cat": row.product_category,
            "wt": row.get("product_weight_g"), "len": row.get("product_length_cm"),
            "ht": row.get("product_height_cm"), "wd": row.get("product_width_cm")
        })
        inserted += 1
    conn.commit()
log_audit("dw.dim_product", inserted, 0, 0)
print(f"  ✓ {inserted:,} products upserted (SCD Type 2)")

# ── 6. Populate fact_orders ──────────────────────────────────────────────────
print("Building fact_orders...")
facts = pd.read_sql("""
    SELECT
        o.order_id, oi.order_item_id,
        o.customer_id, oi.product_id, oi.seller_id,
        o.order_purchase_timestamp::DATE  AS purchase_date,
        o.order_delivered_customer_date::DATE AS delivered_date,
        oi.price, oi.freight_value,
        p.payment_value, p.payment_installments, p.payment_type,
        r.review_score,
        o.order_status,
        CASE
            WHEN o.order_delivered_customer_date IS NOT NULL
             AND o.order_estimated_delivery_date IS NOT NULL
            THEN (o.order_delivered_customer_date::DATE
                  - o.order_estimated_delivery_date::DATE)
        END AS delivery_days
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    LEFT JOIN (
        SELECT order_id, SUM(payment_value) AS payment_value,
               MAX(payment_installments) AS payment_installments,
               MAX(payment_type) AS payment_type
        FROM payments GROUP BY order_id
    ) p ON p.order_id = o.order_id
    LEFT JOIN (
        SELECT order_id, ROUND(AVG(review_score)) AS review_score
        FROM reviews GROUP BY order_id
    ) r ON r.order_id = o.order_id
""", stage_eng)

# Join to dimension surrogate keys
with dw_eng.connect() as conn:
    cust_map = pd.read_sql("SELECT customer_id, customer_key FROM dw.dim_customer WHERE is_current=TRUE", conn)
    prod_map = pd.read_sql("SELECT product_id, product_key FROM dw.dim_product WHERE is_current=TRUE", conn)
    sell_map = pd.read_sql("SELECT seller_id, seller_key FROM dw.dim_seller", conn)
    date_map = pd.read_sql("SELECT full_date, date_key FROM dw.dim_date", conn)
    pay_map  = pd.read_sql("SELECT payment_type, payment_type_key FROM dw.dim_payment_type", conn)

date_map["full_date"] = pd.to_datetime(date_map["full_date"]).dt.date

facts = (facts
    .merge(cust_map, on="customer_id", how="left")
    .merge(prod_map, on="product_id", how="left")
    .merge(sell_map, on="seller_id", how="left")
    .merge(date_map.rename(columns={"full_date":"purchase_date","date_key":"order_purchase_date_key"}), on="purchase_date", how="left")
    .merge(date_map.rename(columns={"full_date":"delivered_date","date_key":"order_delivered_date_key"}), on="delivered_date", how="left")
    .merge(pay_map, on="payment_type", how="left")
)
facts["etl_batch_id"] = BATCH_ID

keep_cols = [
    "order_id","order_item_id","customer_key","product_key","seller_key",
    "order_purchase_date_key","order_delivered_date_key","payment_type_key",
    "price","freight_value","payment_value","payment_installments",
    "review_score","delivery_days","order_status","etl_batch_id"
]
facts = facts[[c for c in keep_cols if c in facts.columns]].dropna(subset=["customer_key","product_key"])

facts.to_sql("fact_orders", dw_eng, schema="dw", if_exists="append",
             index=False, chunksize=5_000, method="multi")
log_audit("dw.fact_orders", len(facts), 0, 0)
print(f"  ✓ {len(facts):,} order line items loaded into fact_orders")

print(f"\nWarehouse load complete. Batch: {BATCH_ID}")
