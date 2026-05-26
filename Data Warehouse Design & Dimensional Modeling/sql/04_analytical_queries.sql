-- ============================================================
-- 04_analytical_queries.sql
-- Sample BI queries for Tableau / reporting layer
-- ============================================================

-- ── Monthly Revenue Trend ─────────────────────────────────────────────────────
SELECT
    d.year,
    d.month_name,
    d.month_num,
    SUM(f.price)          AS gross_revenue,
    SUM(f.freight_value)  AS total_freight,
    SUM(f.payment_value)  AS total_payment_collected,
    COUNT(DISTINCT f.order_id) AS order_count,
    COUNT(*)              AS line_items
FROM dw.fact_orders f
JOIN dw.dim_date    d ON f.order_purchase_date_key = d.date_key
WHERE f.order_status NOT IN ('canceled', 'unavailable')
GROUP BY d.year, d.month_name, d.month_num
ORDER BY d.year, d.month_num;


-- ── Revenue by Product Category (Top 20) ─────────────────────────────────────
SELECT
    p.product_category,
    COUNT(DISTINCT f.order_id)   AS orders,
    SUM(f.price)                 AS revenue,
    ROUND(AVG(f.review_score),2) AS avg_review,
    ROUND(AVG(f.delivery_days),1) AS avg_delivery_days
FROM dw.fact_orders f
JOIN dw.dim_product p ON f.product_key = p.product_key AND p.is_current = TRUE
WHERE f.order_status = 'delivered'
GROUP BY p.product_category
ORDER BY revenue DESC
LIMIT 20;


-- ── Customer State Revenue Heatmap ───────────────────────────────────────────
SELECT
    c.customer_state,
    COUNT(DISTINCT f.order_id)       AS orders,
    COUNT(DISTINCT f.customer_key)   AS unique_customers,
    SUM(f.price)                     AS revenue,
    ROUND(AVG(f.review_score), 2)    AS avg_satisfaction
FROM dw.fact_orders f
JOIN dw.dim_customer c ON f.customer_key = c.customer_key AND c.is_current = TRUE
WHERE f.order_status = 'delivered'
GROUP BY c.customer_state
ORDER BY revenue DESC;


-- ── Delivery Performance: On-Time vs Late ────────────────────────────────────
SELECT
    CASE
        WHEN f.delivery_days <= 0 THEN 'Early'
        WHEN f.delivery_days <= 3 THEN 'On Time'
        WHEN f.delivery_days <= 7 THEN 'Slightly Late'
        ELSE 'Late (7+ days)'
    END AS delivery_bucket,
    COUNT(*) AS orders,
    ROUND(AVG(f.review_score),2) AS avg_review
FROM dw.fact_orders f
WHERE f.order_status = 'delivered'
  AND f.delivery_days IS NOT NULL
GROUP BY delivery_bucket
ORDER BY avg_review DESC;


-- ── SCD Type 2 Audit: Products with Multiple Versions ────────────────────────
SELECT
    product_id,
    COUNT(*) AS versions,
    MIN(effective_date) AS first_seen,
    MAX(effective_date) AS last_changed
FROM dw.dim_product
GROUP BY product_id
HAVING COUNT(*) > 1
ORDER BY versions DESC;


-- ── ETL Audit Summary ─────────────────────────────────────────────────────────
SELECT
    batch_id,
    table_name,
    rows_inserted,
    rows_updated,
    rows_skipped,
    status,
    run_at
FROM dw.etl_audit_log
ORDER BY run_at DESC
LIMIT 50;
