-- ============================================================
-- 03_scd2_procedures.sql
-- SCD Type 2 stored procedures for dim_customer & dim_product
-- ============================================================

-- ── upsert_dim_customer (SCD Type 2) ─────────────────────────────────────────
CREATE OR REPLACE FUNCTION dw.upsert_dim_customer(
    p_customer_id   VARCHAR,
    p_city          VARCHAR,
    p_state         CHAR(2),
    p_zip           VARCHAR,
    p_lat           NUMERIC,
    p_lng           NUMERIC
)
RETURNS VOID AS $$
DECLARE
    v_hash       VARCHAR(64);
    v_existing   INT;
BEGIN
    -- Compute hash of slowly changing attributes
    v_hash := MD5(COALESCE(p_city,'') || COALESCE(p_state,'') || COALESCE(p_zip,''));

    -- Check if current record already has same hash (no change)
    SELECT COUNT(*) INTO v_existing
    FROM dw.dim_customer
    WHERE customer_id = p_customer_id
      AND is_current  = TRUE
      AND row_hash    = v_hash;

    IF v_existing > 0 THEN
        RETURN;  -- No change, skip
    END IF;

    -- Expire existing current record
    UPDATE dw.dim_customer
    SET    expiry_date = CURRENT_DATE - 1,
           is_current  = FALSE
    WHERE  customer_id = p_customer_id
      AND  is_current  = TRUE;

    -- Insert new current record
    INSERT INTO dw.dim_customer
        (customer_id, customer_city, customer_state, customer_zip_code,
         latitude, longitude, effective_date, expiry_date, is_current, row_hash)
    VALUES
        (p_customer_id, p_city, p_state, p_zip,
         p_lat, p_lng, CURRENT_DATE, '9999-12-31', TRUE, v_hash);
END;
$$ LANGUAGE plpgsql;


-- ── upsert_dim_product (SCD Type 2) ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION dw.upsert_dim_product(
    p_product_id    VARCHAR,
    p_category      VARCHAR,
    p_weight_g      NUMERIC,
    p_length_cm     NUMERIC,
    p_height_cm     NUMERIC,
    p_width_cm      NUMERIC
)
RETURNS VOID AS $$
DECLARE
    v_hash     VARCHAR(64);
    v_existing INT;
BEGIN
    v_hash := MD5(COALESCE(p_category,'') ||
                  COALESCE(p_weight_g::TEXT,'') ||
                  COALESCE(p_length_cm::TEXT,''));

    SELECT COUNT(*) INTO v_existing
    FROM dw.dim_product
    WHERE product_id = p_product_id
      AND is_current = TRUE
      AND row_hash   = v_hash;

    IF v_existing > 0 THEN RETURN; END IF;

    UPDATE dw.dim_product
    SET    expiry_date = CURRENT_DATE - 1,
           is_current  = FALSE
    WHERE  product_id  = p_product_id
      AND  is_current  = TRUE;

    INSERT INTO dw.dim_product
        (product_id, product_category, product_weight_g,
         product_length_cm, product_height_cm, product_width_cm,
         effective_date, expiry_date, is_current, row_hash)
    VALUES
        (p_product_id, p_category, p_weight_g,
         p_length_cm, p_height_cm, p_width_cm,
         CURRENT_DATE, '9999-12-31', TRUE, v_hash);
END;
$$ LANGUAGE plpgsql;
