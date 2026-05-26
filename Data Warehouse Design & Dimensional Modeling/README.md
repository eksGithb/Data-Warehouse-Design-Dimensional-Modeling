# Project 2 — Data Warehouse Design & Dimensional Modeling

**Tools:** SQL · PostgreSQL · Python · Tableau  
**Timeline:** January 2025

---

## Overview

Designed a star-schema data warehouse for a real e-commerce business dataset, modeling fact tables for orders and returns alongside dimension tables for customers, products, time, and geography. Built incremental ETL scripts and implemented Slowly Changing Dimension (SCD) Type 2 logic for product and customer records.

---

## Dataset

**Brazilian E-Commerce Public Dataset by Olist**  
📥 **Download:** https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce

Real commercial data from 100,000 orders placed at Olist Store (2016–2018), anonymized and released publicly. The dataset contains:

| File | Description |
|------|-------------|
| `olist_orders_dataset.csv` | Order header records |
| `olist_order_items_dataset.csv` | Line items per order |
| `olist_order_payments_dataset.csv` | Payment method and value |
| `olist_order_reviews_dataset.csv` | Customer review scores |
| `olist_customers_dataset.csv` | Customer location info |
| `olist_products_dataset.csv` | Product catalog |
| `olist_sellers_dataset.csv` | Seller info |
| `olist_geolocation_dataset.csv` | Brazilian zip-to-lat/lng mapping |
| `product_category_name_translation.csv` | Portuguese → English category names |

After downloading, place all CSVs in the `/data/raw/` folder.

---

## Project Structure

```
2-data-warehouse-modeling/
├── data/
│   ├── raw/          # Place Kaggle CSVs here
│   └── staging/      # Intermediate ETL outputs
├── sql/
│   ├── 01_create_schema.sql       # Star schema DDL
│   ├── 02_create_staging.sql      # Staging tables
│   ├── 03_scd2_procedures.sql     # SCD Type 2 stored procedures
│   └── 04_analytical_queries.sql  # Sample BI queries
├── src/
│   ├── 01_stage_raw_data.py       # Load CSVs → staging tables
│   ├── 02_build_dimensions.py     # Populate dim tables
│   ├── 03_build_facts.py          # Populate fact tables
│   └── 04_incremental_load.py     # Incremental ETL run
├── docs/
│   └── data_model.md              # ERD description and design decisions
└── README.md
```

---

## Setup

### 1. Install dependencies
```bash
pip install pandas numpy sqlalchemy psycopg2-binary tqdm
```

### 2. Create databases
```bash
createdb olist_staging
createdb olist_warehouse
```

### 3. Create schema
```bash
psql -d olist_warehouse -f sql/01_create_schema.sql
psql -d olist_staging  -f sql/02_create_staging.sql
```

### 4. Run ETL pipeline
```bash
python src/01_stage_raw_data.py
python src/02_build_dimensions.py
python src/03_build_facts.py
```

### 5. Run incremental load (simulates day-over-day updates)
```bash
python src/04_incremental_load.py
```

---

## Tableau Connection

Connect Tableau Desktop to PostgreSQL:
- Server: `localhost`
- Port: `5432`
- Database: `olist_warehouse`
- Schema: `dw`

Key views to connect to: `dw.fact_orders`, `dw.dim_customer`, `dw.dim_product`, `dw.dim_date`

---

## References

- Olist dataset: https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce
- Kimball, R. & Ross, M. *The Data Warehouse Toolkit* (Wiley, 3rd ed.)
