-- ============================================================
-- 01_create_schema.sql
-- Star Schema DDL for Olist E-Commerce Data Warehouse
-- Database: olist_warehouse | Schema: dw
-- ============================================================

CREATE SCHEMA IF NOT EXISTS dw;

-- ── Dimension: Date ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.dim_date (
    date_key        SERIAL PRIMARY KEY,
    full_date       DATE        NOT NULL UNIQUE,
    day_of_week     SMALLINT,
    day_name        VARCHAR(10),
    day_of_month    SMALLINT,
    day_of_year     SMALLINT,
    week_of_year    SMALLINT,
    month_num       SMALLINT,
    month_name      VARCHAR(10),
    quarter         SMALLINT,
    year            SMALLINT,
    is_weekend      BOOLEAN,
    is_holiday      BOOLEAN DEFAULT FALSE
);

-- ── Dimension: Customer (SCD Type 2) ────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.dim_customer (
    customer_key        SERIAL PRIMARY KEY,
    customer_id         VARCHAR(50)  NOT NULL,   -- natural key
    customer_city       VARCHAR(100),
    customer_state      CHAR(2),
    customer_zip_code   VARCHAR(10),
    latitude            NUMERIC(9,6),
    longitude           NUMERIC(9,6),
    -- SCD Type 2 metadata
    effective_date      DATE         NOT NULL DEFAULT CURRENT_DATE,
    expiry_date         DATE         NOT NULL DEFAULT '9999-12-31',
    is_current          BOOLEAN      NOT NULL DEFAULT TRUE,
    row_hash            VARCHAR(64)  -- MD5 of slowly changing attributes
);

CREATE INDEX IF NOT EXISTS idx_dim_customer_id  ON dw.dim_customer(customer_id);
CREATE INDEX IF NOT EXISTS idx_dim_customer_cur ON dw.dim_customer(is_current);

-- ── Dimension: Product (SCD Type 2) ─────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.dim_product (
    product_key             SERIAL PRIMARY KEY,
    product_id              VARCHAR(50)  NOT NULL,
    product_category        VARCHAR(100),
    product_name_length     SMALLINT,
    product_description_len INT,
    product_photos_qty      SMALLINT,
    product_weight_g        NUMERIC(10,2),
    product_length_cm       NUMERIC(8,2),
    product_height_cm       NUMERIC(8,2),
    product_width_cm        NUMERIC(8,2),
    -- SCD Type 2 metadata
    effective_date          DATE         NOT NULL DEFAULT CURRENT_DATE,
    expiry_date             DATE         NOT NULL DEFAULT '9999-12-31',
    is_current              BOOLEAN      NOT NULL DEFAULT TRUE,
    row_hash                VARCHAR(64)
);

CREATE INDEX IF NOT EXISTS idx_dim_product_id  ON dw.dim_product(product_id);

-- ── Dimension: Seller ────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.dim_seller (
    seller_key      SERIAL PRIMARY KEY,
    seller_id       VARCHAR(50)  NOT NULL UNIQUE,
    seller_city     VARCHAR(100),
    seller_state    CHAR(2),
    seller_zip_code VARCHAR(10)
);

-- ── Dimension: Payment Method ────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.dim_payment_type (
    payment_type_key SERIAL PRIMARY KEY,
    payment_type     VARCHAR(30) NOT NULL UNIQUE
);

-- ── Fact: Orders ─────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.fact_orders (
    order_key               BIGSERIAL PRIMARY KEY,
    order_id                VARCHAR(50)   NOT NULL,
    order_item_id           SMALLINT      NOT NULL,       -- line item within order
    -- Foreign keys
    customer_key            INT           NOT NULL REFERENCES dw.dim_customer(customer_key),
    product_key             INT           NOT NULL REFERENCES dw.dim_product(product_key),
    seller_key              INT           NOT NULL REFERENCES dw.dim_seller(seller_key),
    order_purchase_date_key INT           NOT NULL REFERENCES dw.dim_date(date_key),
    order_delivered_date_key INT                   REFERENCES dw.dim_date(date_key),
    payment_type_key        INT                   REFERENCES dw.dim_payment_type(payment_type_key),
    -- Measures
    price                   NUMERIC(10,2) NOT NULL,
    freight_value           NUMERIC(10,2),
    payment_value           NUMERIC(10,2),
    payment_installments    SMALLINT,
    review_score            SMALLINT,
    delivery_days           INT,           -- derived: delivered - estimated
    -- Order status
    order_status            VARCHAR(20),
    -- Audit
    etl_loaded_at           TIMESTAMP     NOT NULL DEFAULT NOW(),
    etl_batch_id            VARCHAR(30)
);

CREATE INDEX IF NOT EXISTS idx_fact_orders_customer ON dw.fact_orders(customer_key);
CREATE INDEX IF NOT EXISTS idx_fact_orders_product  ON dw.fact_orders(product_key);
CREATE INDEX IF NOT EXISTS idx_fact_orders_date     ON dw.fact_orders(order_purchase_date_key);
CREATE INDEX IF NOT EXISTS idx_fact_orders_status   ON dw.fact_orders(order_status);

-- ── Fact: Returns / Cancellations ────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.fact_returns (
    return_key          BIGSERIAL PRIMARY KEY,
    order_id            VARCHAR(50) NOT NULL,
    customer_key        INT         REFERENCES dw.dim_customer(customer_key),
    product_key         INT         REFERENCES dw.dim_product(product_key),
    cancel_date_key     INT         REFERENCES dw.dim_date(date_key),
    original_price      NUMERIC(10,2),
    review_score        SMALLINT,
    cancellation_reason VARCHAR(50) DEFAULT 'customer_request',
    etl_loaded_at       TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- ── ETL audit log ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS dw.etl_audit_log (
    log_id          BIGSERIAL PRIMARY KEY,
    batch_id        VARCHAR(30)  NOT NULL,
    table_name      VARCHAR(60)  NOT NULL,
    rows_inserted   INT          DEFAULT 0,
    rows_updated    INT          DEFAULT 0,
    rows_skipped    INT          DEFAULT 0,
    status          VARCHAR(20)  DEFAULT 'success',
    run_at          TIMESTAMP    NOT NULL DEFAULT NOW(),
    notes           TEXT
);
