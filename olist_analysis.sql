/* ============================================================
   OLIST E-COMMERCE ANALYSIS — SQL SCRIPT
   SQL Server. Diagnostic, data quality, and analytical queries.
   ============================================================ */


/* ============================================================
   SECTION 1: CHECK EXISTING TABLE / COLUMN INFO
   ============================================================ */

SELECT DB_NAME() AS current_database;

SELECT TABLE_NAME
FROM INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE'
ORDER BY TABLE_NAME;

SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH, IS_NULLABLE
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'olist_orders_dataset';  -- change table name as needed


/* ============================================================
   SECTION 2: PRIMARY KEYS
   - geolocation      -> surrogate key (duplicates existed)
   - order_items      -> composite key (order_id + order_item_id)
   - order_payments   -> composite key (order_id + payment_sequential)
   ============================================================ */

-- 2A. Surrogate key (geolocation)
ALTER TABLE olist_geolocation_dataset
ADD geolocation_id INT IDENTITY(1,1) NOT NULL;

ALTER TABLE olist_geolocation_dataset
ADD CONSTRAINT PK_olist_geolocation PRIMARY KEY (geolocation_id);

-- 2B. Composite key (order_items)
SELECT order_id, order_item_id, COUNT(*)
FROM olist_order_items_dataset
GROUP BY order_id, order_item_id
HAVING COUNT(*) > 1;  -- confirm the pair is unique before constraining

ALTER TABLE olist_order_items_dataset
ALTER COLUMN order_id NVARCHAR(50) NOT NULL;

ALTER TABLE olist_order_items_dataset
ALTER COLUMN order_item_id TINYINT NOT NULL;

ALTER TABLE olist_order_items_dataset
ADD CONSTRAINT PK_olist_order_items_dataset PRIMARY KEY (order_id, order_item_id);

-- 2C. Composite key (order_payments): order_id, payment_sequential — same pattern as 2B


/* ============================================================
   SECTION 3: DATA QUALITY CHECKS
   ============================================================ */

-- 3A. NULLs in specific columns
SELECT
    SUM(CASE WHEN order_id IS NULL THEN 1 ELSE 0 END) AS order_id_nulls,
    SUM(CASE WHEN customer_id IS NULL THEN 1 ELSE 0 END) AS customer_id_nulls,
    COUNT(*) AS total_rows
FROM olist_orders_dataset;

-- 3C. Auto-generate a null check for every column in a table
-- (run this, copy the query_text output, strip trailing UNION ALL, add ';', run it)
SELECT 'SELECT ''' + COLUMN_NAME + ''' AS column_name, COUNT(*) AS null_count FROM olist_orders_dataset WHERE '
    + COLUMN_NAME + ' IS NULL UNION ALL' AS query_text
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'olist_orders_dataset';

-- 3D. Blank/whitespace-only values (text columns only)
SELECT COUNT(*) AS blank_count
FROM olist_orders_dataset
WHERE LTRIM(RTRIM(order_status)) = '';

-- 3E. Auto-generate a blank check for all text columns in a table
SELECT
    'SELECT ''' + COLUMN_NAME + ''' AS column_name, COUNT(*) AS blank_count FROM olist_order_payments_dataset WHERE LTRIM(RTRIM('
    + COLUMN_NAME + ')) = '''' UNION ALL' AS query_text
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'olist_order_payments_dataset'
  AND DATA_TYPE IN ('nvarchar', 'varchar', 'char', 'nchar', 'text');

-- 3F. Duplicate rows (by key columns)
SELECT geolocation_lat, geolocation_lng, COUNT(*) AS cnt
FROM olist_geolocation_dataset
GROUP BY geolocation_lat, geolocation_lng
HAVING COUNT(*) > 1
ORDER BY cnt DESC;

-- 3G. Distinct values with counts
SELECT order_status, COUNT(*) AS count
FROM olist_orders_dataset
GROUP BY order_status
ORDER BY count DESC;

SELECT payment_type, COUNT(*) AS count
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY count DESC;


/* ============================================================
   SECTION 4: BACKUP (before any destructive changes)
   ============================================================ */

SELECT * INTO olist_geolocation_dataset_backup FROM olist_geolocation_dataset;


/* ============================================================
   SECTION 5: OPTIONAL — REMOVE DUPLICATE ROWS
   (Only if duplicates are genuine errors, not legitimate repeats)
   ============================================================ */

WITH duplicates AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY geolocation_lat, geolocation_lng ORDER BY (SELECT NULL)) AS rn
    FROM olist_geolocation_dataset
)
DELETE FROM duplicates WHERE rn > 1;


/* ============================================================
   SECTION 6: DATA PROFILING
   ============================================================ */

-- Auto-generate MIN/MAX/AVG/STDEV for all numeric columns in a table
SELECT STRING_AGG(
    'MIN(' + COLUMN_NAME + ') AS min_' + COLUMN_NAME + ', ' +
    'MAX(' + COLUMN_NAME + ') AS max_' + COLUMN_NAME + ', ' +
    'AVG(CAST(' + COLUMN_NAME + ' AS FLOAT)) AS avg_' + COLUMN_NAME + ', ' +
    'STDEV(' + COLUMN_NAME + ') AS stdev_' + COLUMN_NAME
    , ', ') AS query_text
FROM INFORMATION_SCHEMA.COLUMNS
WHERE TABLE_NAME = 'olist_order_items_dataset'
  AND DATA_TYPE IN ('int', 'float', 'decimal', 'numeric', 'tinyint', 'smallint', 'bigint', 'money');
-- Note: AVG() on integer types truncates to a whole number unless cast to FLOAT/DECIMAL first.

-- Investigate zero-value payment installments
SELECT payment_installments, payment_type
FROM olist_order_payments_dataset
WHERE payment_installments = 0;

SELECT order_id, payment_installments, payment_type
FROM olist_order_payments_dataset
WHERE payment_type = 'credit_card'
  AND payment_installments = 0;
-- Finding: 2 records with payment_installments = 0 on credit_card payments — treated as an
-- isolated data entry/ETL anomaly, immaterial to the overall analysis.


/* ============================================================
   SECTION 7: REVENUE
   ============================================================ */

-- 7.1 Total revenue — compare payments total vs item-value total
SELECT SUM(payment_value) AS SUM_PAYMENT_VALUE
FROM olist_order_payments_dataset;
-- Result: 16,008,872.12

SELECT SUM(price) + SUM(freight_value) AS SUM_PRICE
FROM olist_order_items_dataset;
-- Result: 15,843,553.24  (gap of ~165,318.88 vs payments total — investigated below)

-- Coverage mismatch check
SELECT COUNT(DISTINCT order_id) AS payment_orders FROM olist_order_payments_dataset;   -- 99,440
SELECT COUNT(DISTINCT order_id) AS item_orders FROM olist_order_items_dataset;          -- 98,666

-- Orders with a payment but no items (774 orders)
SELECT DISTINCT p.order_id
FROM olist_order_payments_dataset p
LEFT JOIN olist_order_items_dataset i ON p.order_id = i.order_id
WHERE i.order_id IS NULL;

-- Reverse check: orders with items but no payment (1 order)
SELECT DISTINCT i.order_id
FROM olist_order_items_dataset i
LEFT JOIN olist_order_payments_dataset p ON i.order_id = p.order_id
WHERE p.order_id IS NULL;

-- Order status of the 774 mismatched (payment-only) orders
SELECT o.order_id, o.order_status
FROM olist_orders_dataset o
WHERE o.order_id IN (
    SELECT DISTINCT p.order_id
    FROM olist_order_payments_dataset p
    LEFT JOIN olist_order_items_dataset i ON p.order_id = i.order_id
    WHERE i.order_id IS NULL
);
-- Finding: predominantly 'cancelled' or 'unavailable' — genuine lost business, not a timing
-- artifact. (A small remainder in non-terminal statuses, e.g. 'shipped', was checked and found
-- negligible — 1-2 orders.)

-- Value of the single item-only order missing its payment record (found to be 'delivered')
SELECT order_id, ROUND(SUM(price) + SUM(freight_value), 2) AS order_value
FROM olist_order_items_dataset
WHERE order_id = '<order_id>'
GROUP BY order_id;
-- Result: 143.46 — negligible, already included in the item-value total, no adjustment needed.

-- 7.1 (final) Validated revenue — delivered orders only, item value basis
SELECT ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
WHERE o.order_status = 'delivered';
-- Result: 15,419,773.75  <-- validated "Total Revenue" figure used throughout the analysis

-- 7.2 Revenue by product category
SELECT p.product_category_name,
    ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_products_dataset p ON i.product_id = p.product_id
WHERE o.order_status = 'delivered'
GROUP BY p.product_category_name
ORDER BY total_revenue DESC;

-- 7.3 Revenue by seller / seller state
SELECT s.seller_id,
    ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_sellers_dataset s ON i.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_id
ORDER BY total_revenue DESC;

SELECT s.seller_state,
    ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_sellers_dataset s ON i.seller_id = s.seller_id
WHERE o.order_status = 'delivered'
GROUP BY s.seller_state
ORDER BY total_revenue DESC;

-- 7.4 Top products by revenue
SELECT TOP 10 p.product_category_name,
    ROUND(SUM(i.price) + SUM(i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_products_dataset p ON i.product_id = p.product_id
WHERE o.order_status = 'delivered'
GROUP BY p.product_category_name
ORDER BY total_revenue DESC;


/* ============================================================
   SECTION 8: ORDERS
   ============================================================ */

-- 8.1 Orders by month
SELECT
    YEAR(order_purchase_timestamp) AS order_year,
    MONTH(order_purchase_timestamp) AS order_month,
    COUNT(*) AS total_orders
FROM olist_orders_dataset
GROUP BY YEAR(order_purchase_timestamp), MONTH(order_purchase_timestamp)
ORDER BY order_year, order_month;

-- 8.2 Orders by day of week
SELECT
    DATENAME(WEEKDAY, order_purchase_timestamp) AS day_column,
    COUNT(*) AS count_total
FROM olist_orders_dataset
GROUP BY DATENAME(WEEKDAY, order_purchase_timestamp)
ORDER BY
    CASE DATENAME(WEEKDAY, order_purchase_timestamp)
        WHEN 'sunday' THEN 1
        WHEN 'monday' THEN 2
        WHEN 'tuesday' THEN 3
        WHEN 'wednesday' THEN 4
        WHEN 'thursday' THEN 5
        WHEN 'friday' THEN 6
        WHEN 'saturday' THEN 7
    END;

-- 8.3 Average order value (correct, per-order basis — not per item row)
SELECT
    ROUND(SUM(i.price + i.freight_value) / COUNT(DISTINCT i.order_id), 2) AS avg_per_order
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON o.order_id = i.order_id
WHERE order_status = 'delivered';
-- Result: 159.83

-- 8.4 Average items per order (cast to FLOAT to avoid integer-division truncation)
SELECT
    ROUND(CAST(COUNT(i.order_id) AS FLOAT) / COUNT(DISTINCT i.order_id), 2) AS avg_per_order
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON o.order_id = i.order_id
WHERE order_status = 'delivered';
-- Result: 1.14


/* ============================================================
   SECTION 9: CUSTOMERS
   ============================================================ */

-- 9.1 Customers by state / city
SELECT customer_state, COUNT(DISTINCT customer_id) AS total
FROM olist_customers_dataset
GROUP BY customer_state
ORDER BY total DESC;

SELECT TOP 10 customer_city, COUNT(DISTINCT customer_id) AS total
FROM olist_customers_dataset
GROUP BY customer_city
ORDER BY total DESC;

-- 9.2 Repeat customers (customer_unique_id — NOT customer_id, which is unique per order)
SELECT c.customer_unique_id, COUNT(order_id) AS total_orders
FROM olist_orders_dataset o
JOIN olist_customers_dataset c ON c.customer_id = o.customer_id
GROUP BY customer_unique_id
HAVING COUNT(order_id) > 1
ORDER BY total_orders DESC;

-- 9.3 One-time purchasers, most recent first
SELECT c.customer_unique_id,
    COUNT(o.order_id) AS order_count,
    MAX(o.order_purchase_timestamp) AS last_purchase_time
FROM olist_customers_dataset c
JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
GROUP BY c.customer_unique_id
HAVING COUNT(o.order_id) = 1
ORDER BY last_purchase_time DESC;
-- Finding: 93,099 of 96,096 customers (96.88%) are one-time purchasers.


/* ============================================================
   SECTION 10: DELIVERY
   ============================================================ */

-- 10.1 Average delivery time
SELECT AVG(DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date)) AS delivery_time
FROM olist_orders_dataset
WHERE order_delivered_customer_date IS NOT NULL;
-- Result: 12

-- 10.2 Late delivery percentage
SELECT
    ROUND(
        (SELECT CAST(COUNT(*) AS FLOAT)
         FROM olist_orders_dataset
         WHERE order_delivered_customer_date IS NOT NULL
           AND order_delivered_customer_date > order_estimated_delivery_date)
        /
        (SELECT CAST(COUNT(*) AS FLOAT)
         FROM olist_orders_dataset
         WHERE order_delivered_customer_date IS NOT NULL)
        * 100, 4) AS late_delivery_percentage;
-- Result: 8.1129

-- 10.3 Delivery time by state
SELECT customer_state,
    ROUND(AVG(DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date)), 2) AS avg_delivery_time
FROM olist_customers_dataset c
JOIN olist_orders_dataset o ON c.customer_id = o.customer_id
WHERE order_delivered_customer_date IS NOT NULL
GROUP BY customer_state
ORDER BY avg_delivery_time DESC;

-- 10.4 Delivery time by product category
SELECT p.product_category_name,
    ROUND(AVG(DATEDIFF(DAY, order_purchase_timestamp, order_delivered_customer_date)), 2) AS avg_delivery_time
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_products_dataset p ON p.product_id = i.product_id
WHERE order_delivered_customer_date IS NOT NULL
  AND product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY avg_delivery_time DESC;


/* ============================================================
   SECTION 11: REVIEWS
   ============================================================ */

-- 11.1 Average review score
SELECT ROUND(AVG(review_score), 2) AS avg_review_score
FROM olist_order_reviews_dataset;
-- Result: 4.0

-- 11.2 Review score by category
SELECT p.product_category_name, ROUND(AVG(review_score), 4) AS avg_review_score
FROM olist_order_reviews_dataset r
JOIN olist_order_items_dataset i ON i.order_id = r.order_id
JOIN olist_products_dataset p ON p.product_id = i.product_id
WHERE p.product_category_name IS NOT NULL
GROUP BY p.product_category_name
ORDER BY avg_review_score DESC;

-- 11.3 Review score by seller — reliability-filtered (>= 10 reviews)
-- Naive version (unreliable — a seller with 1 lucky review can outrank a seller with 500 solid ones):
SELECT i.seller_id, ROUND(AVG(review_score), 4) AS avg_review_score
FROM olist_order_reviews_dataset r
JOIN olist_order_items_dataset i ON i.order_id = r.order_id
WHERE i.seller_id IS NOT NULL
GROUP BY i.seller_id
ORDER BY avg_review_score DESC;

-- Corrected version — HAVING filters on the aggregate, WHERE cannot:
SELECT i.seller_id, ROUND(AVG(review_score), 4) AS avg_review_score,
    COUNT(DISTINCT r.order_id) AS number_of_orders
FROM olist_order_reviews_dataset r
JOIN olist_order_items_dataset i ON i.order_id = r.order_id
WHERE i.seller_id IS NOT NULL
GROUP BY i.seller_id
HAVING COUNT(DISTINCT r.order_id) >= 10
ORDER BY avg_review_score DESC;


/* ============================================================
   SECTION 12: PAYMENTS
   ============================================================ */

-- 12.1 Payment method distribution
SELECT payment_type, COUNT(payment_type) AS number
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY number DESC;

-- 12.2 Average installments by payment type (cast to FLOAT — see integer-division note)
SELECT payment_type, ROUND(AVG(CAST(payment_installments AS FLOAT)), 2) AS avg_installments
FROM olist_order_payments_dataset
GROUP BY payment_type
ORDER BY avg_installments DESC;

-- 12.3 Revenue by payment type
-- Naive version — WRONG: joining payments directly to items cross-multiplies rows
-- (an order with 2 items and 2 payment rows produces 4 joined rows, duplicating item value).
SELECT payment_type, SUM(CAST(i.price + i.freight_value AS FLOAT)) AS revenue
FROM olist_order_payments_dataset p
JOIN olist_order_items_dataset i ON i.order_id = p.order_id
JOIN olist_orders_dataset o ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY payment_type
ORDER BY revenue DESC;

-- Corrected version — aggregate items to one total per order FIRST, then join to payments
SELECT p.payment_type, ROUND(SUM(order_totals.item_total), 2) AS revenue
FROM olist_order_payments_dataset p
JOIN (
    SELECT i.order_id, SUM(i.price + i.freight_value) AS item_total
    FROM olist_order_items_dataset i
    JOIN olist_orders_dataset o ON i.order_id = o.order_id
    WHERE o.order_status = 'delivered'
    GROUP BY i.order_id
) AS order_totals ON p.order_id = order_totals.order_id
GROUP BY p.payment_type
ORDER BY revenue DESC;


/* ============================================================
   SECTION 13: FREIGHT
   ============================================================ */

-- 13.1 Highest freight categories
SELECT p.product_category_name, AVG(CAST(i.freight_value AS FLOAT)) AS avg_freight_value
FROM olist_order_items_dataset i
JOIN olist_products_dataset p ON i.product_id = p.product_id
GROUP BY p.product_category_name
ORDER BY avg_freight_value DESC;

-- 13.2 Freight by state
SELECT c.customer_state, AVG(CAST(i.freight_value AS FLOAT)) AS avg_freight_value
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
JOIN olist_customers_dataset c ON o.customer_id = c.customer_id
GROUP BY c.customer_state
ORDER BY avg_freight_value DESC;

-- 13.3 Freight vs. review score — Pearson correlation coefficient, computed directly in SQL
SELECT
    (COUNT(*) * SUM(CAST(i.freight_value AS FLOAT) * CAST(r.review_score AS FLOAT))
     - SUM(CAST(i.freight_value AS FLOAT)) * SUM(CAST(r.review_score AS FLOAT)))
    /
    (SQRT(COUNT(*) * SUM(POWER(CAST(i.freight_value AS FLOAT), 2)) - POWER(SUM(CAST(i.freight_value AS FLOAT)), 2))
     * SQRT(COUNT(*) * SUM(POWER(CAST(r.review_score AS FLOAT), 2)) - POWER(SUM(CAST(r.review_score AS FLOAT)), 2)))
    AS correlation_freight_review_score
FROM olist_order_items_dataset i
JOIN olist_order_reviews_dataset r ON i.order_id = r.order_id
WHERE i.freight_value IS NOT NULL AND r.review_score IS NOT NULL;
-- Finding: weak correlation — freight cost alone is not a major driver of review score.


/* ============================================================
   SECTION 14: SELLERS
   ============================================================ */

-- 14.1 Top sellers by orders
SELECT i.seller_id, COUNT(DISTINCT i.order_id) AS total_orders
FROM olist_order_items_dataset i
GROUP BY i.seller_id
ORDER BY total_orders DESC;

-- 14.2 Top sellers by revenue
SELECT i.seller_id, ROUND(SUM(i.price + i.freight_value), 2) AS total_revenue
FROM olist_order_items_dataset i
JOIN olist_orders_dataset o ON i.order_id = o.order_id
WHERE o.order_status = 'delivered'
GROUP BY i.seller_id
ORDER BY total_revenue DESC;

-- 14.3 Sellers with poor ratings (reliability-filtered, >= 10 reviews, avg score < 3)
SELECT i.seller_id,
    COUNT(DISTINCT r.order_id) AS review_count,
    ROUND(AVG(CAST(r.review_score AS FLOAT)), 2) AS avg_review_score
FROM olist_order_items_dataset i
JOIN olist_order_reviews_dataset r ON i.order_id = r.order_id
GROUP BY i.seller_id
HAVING COUNT(DISTINCT r.order_id) >= 10
   AND AVG(CAST(r.review_score AS FLOAT)) < 3
ORDER BY avg_review_score ASC;
