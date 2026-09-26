
-- ------------------------------------------------------------------
-- 0. TABLE CREATION (run once, then import the CSVs into these)
-- ------------------------------------------------------------------
CREATE DATABASE IF NOT EXISTS olist;
USE olist;

CREATE TABLE customers (
    customer_id              VARCHAR(64) PRIMARY KEY,
    customer_unique_id       VARCHAR(64),
    customer_zip_code_prefix VARCHAR(16),
    customer_city            VARCHAR(128),
    customer_state           VARCHAR(8)
);

CREATE TABLE orders (
    order_id                       VARCHAR(64) PRIMARY KEY,
    customer_id                    VARCHAR(64),
    order_status                   VARCHAR(32),
    order_purchase_timestamp       DATETIME,
    order_approved_at              DATETIME,
    order_delivered_carrier_date   DATETIME,
    order_delivered_customer_date  DATETIME,
    order_estimated_delivery_date  DATETIME,
    FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

CREATE TABLE order_items (
    order_id            VARCHAR(64),
    order_item_id       INT,
    product_id          VARCHAR(64),
    seller_id           VARCHAR(64),
    shipping_limit_date DATETIME,
    price               DECIMAL(10,2),
    freight_value       DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE payments (
    order_id             VARCHAR(64),
    payment_sequential   INT,
    payment_type         VARCHAR(32),
    payment_installments INT,
    payment_value        DECIMAL(10,2),
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE reviews (
    review_id               VARCHAR(64),
    order_id                VARCHAR(64),
    review_score            INT,
    review_comment_title    VARCHAR(255),
    review_comment_message  TEXT,
    review_creation_date    DATETIME,
    review_answer_timestamp DATETIME,
    FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE products (
    product_id                  VARCHAR(64) PRIMARY KEY,
    product_category_name       VARCHAR(128),
    product_name_lenght         INT,
    product_description_lenght  INT,
    product_photos_qty          INT,
    product_weight_g            DECIMAL(10,2),
    product_length_cm           DECIMAL(10,2),
    product_height_cm           DECIMAL(10,2),
    product_width_cm            DECIMAL(10,2)
);

CREATE TABLE sellers (
    seller_id              VARCHAR(64) PRIMARY KEY,
    seller_zip_code_prefix VARCHAR(16),
    seller_city            VARCHAR(128),
    seller_state            VARCHAR(8)
);

CREATE TABLE category_translation (
    product_category_name         VARCHAR(128) PRIMARY KEY,
    product_category_name_english VARCHAR(128)
);


-- ==================================================================
-- 1. REVENUE & GROWTH ANALYSIS
-- ==================================================================

-- 1a. Monthly revenue, order count and average order value with MoM growth
WITH monthly AS (
    SELECT
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS order_month,
        COUNT(DISTINCT o.order_id)                           AS total_orders,
        SUM(oi.price + oi.freight_value)                     AS total_revenue
    FROM orders o
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('unavailable', 'canceled')
    GROUP BY order_month
)
SELECT
    order_month,
    total_orders,
    ROUND(total_revenue, 2) AS total_revenue,
    ROUND(total_revenue / NULLIF(total_orders, 0), 2) AS avg_order_value,
    ROUND(
        (total_revenue - LAG(total_revenue) OVER (ORDER BY order_month))
        / NULLIF(LAG(total_revenue) OVER (ORDER BY order_month), 0) * 100, 2
    ) AS mom_growth_pct
FROM monthly
ORDER BY order_month;


-- 1b. Revenue by product category (English name), ranked
SELECT
    ct.product_category_name_english          AS category,
    COUNT(DISTINCT oi.order_id)                AS orders,
    ROUND(SUM(oi.price), 2)                    AS revenue,
    RANK() OVER (ORDER BY SUM(oi.price) DESC)  AS revenue_rank
FROM order_items oi
JOIN products p ON p.product_id = oi.product_id
JOIN category_translation ct ON ct.product_category_name = p.product_category_name
GROUP BY ct.product_category_name_english
ORDER BY revenue DESC;


-- ==================================================================
-- 2. CUSTOMER ANALYSIS — RFM SEGMENTATION IN PURE SQL
-- ==================================================================
WITH customer_orders AS (
    SELECT
        c.customer_unique_id,
        o.order_id,
        o.order_purchase_timestamp,
        (oi.price + oi.freight_value) AS order_value
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    JOIN order_items oi ON oi.order_id = o.order_id
    WHERE o.order_status NOT IN ('unavailable', 'canceled')
),
rfm_base AS (
    SELECT
        customer_unique_id,
        MAX(order_purchase_timestamp) AS last_order_date,
        COUNT(DISTINCT order_id)      AS frequency,
        SUM(order_value)              AS monetary,
        DATEDIFF(
            (SELECT MAX(order_purchase_timestamp) FROM customer_orders),
            MAX(order_purchase_timestamp)
        ) AS recency
    FROM customer_orders
    GROUP BY customer_unique_id
),
rfm_scored AS (
    SELECT
        *,
        NTILE(5) OVER (ORDER BY recency ASC)   AS r_score,   -- most recent = highest score
        NTILE(5) OVER (ORDER BY frequency ASC) AS f_score,
        NTILE(5) OVER (ORDER BY monetary ASC)  AS m_score
    FROM rfm_base
)
SELECT
    *,
    CASE
        WHEN r_score >= 4 AND f_score >= 4 THEN 'Champions'
        WHEN r_score >= 3 AND f_score >= 3 THEN 'Loyal Customers'
        WHEN r_score >= 4 AND f_score <= 2 THEN 'New Customers'
        WHEN r_score <= 2 AND f_score >= 3 THEN 'At Risk'
        WHEN r_score <= 2 AND f_score <= 2 THEN 'Lost'
        ELSE 'Needs Attention'
    END AS segment
FROM rfm_scored
ORDER BY monetary DESC;


-- ==================================================================
-- 3. COHORT RETENTION ANALYSIS
-- ==================================================================
WITH first_purchase AS (
    SELECT
        c.customer_unique_id,
        DATE_FORMAT(MIN(o.order_purchase_timestamp), '%Y-%m-01') AS cohort_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    GROUP BY c.customer_unique_id
),
orders_with_cohort AS (
    SELECT
        c.customer_unique_id,
        fp.cohort_month,
        DATE_FORMAT(o.order_purchase_timestamp, '%Y-%m-01') AS order_month
    FROM orders o
    JOIN customers c ON c.customer_id = o.customer_id
    JOIN first_purchase fp ON fp.customer_unique_id = c.customer_unique_id
),
cohort_activity AS (
    SELECT
        cohort_month,
        order_month,
        (YEAR(order_month) - YEAR(cohort_month)) * 12
          + (MONTH(order_month) - MONTH(cohort_month)) AS month_number,
        COUNT(DISTINCT customer_unique_id) AS active_customers
    FROM orders_with_cohort
    GROUP BY cohort_month, order_month
),
cohort_size AS (
    SELECT cohort_month, active_customers AS cohort_customers
    FROM cohort_activity
    WHERE month_number = 0
)
SELECT
    ca.cohort_month,
    ca.month_number,
    ca.active_customers,
    cs.cohort_customers,
    ROUND(ca.active_customers / cs.cohort_customers * 100, 2) AS retention_pct
FROM cohort_activity ca
JOIN cohort_size cs ON cs.cohort_month = ca.cohort_month
ORDER BY ca.cohort_month, ca.month_number;


-- ==================================================================
-- 4. DELIVERY / LOGISTICS PERFORMANCE
-- ==================================================================

-- 4a. Late delivery rate and avg delay by state
SELECT
    c.customer_state,
    COUNT(*) AS total_orders,
    ROUND(AVG(TIMESTAMPDIFF(SECOND, o.order_purchase_timestamp, o.order_delivered_customer_date)) / 86400, 1) AS avg_delivery_days,
    ROUND(AVG(
        CASE WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 1 ELSE 0 END
    ) * 100, 2) AS late_delivery_pct
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY c.customer_state
ORDER BY late_delivery_pct DESC;

-- 4b. Impact of late delivery on review score
SELECT
    CASE
        WHEN o.order_delivered_customer_date > o.order_estimated_delivery_date THEN 'Late'
        ELSE 'On Time'
    END AS delivery_status,
    ROUND(AVG(r.review_score), 2) AS avg_review_score,
    COUNT(*) AS order_count
FROM orders o
JOIN reviews r ON r.order_id = o.order_id
WHERE o.order_delivered_customer_date IS NOT NULL
GROUP BY delivery_status;


-- ==================================================================
-- 5. SELLER PERFORMANCE LEADERBOARD (window functions)
-- ==================================================================
SELECT
    s.seller_id,
    s.seller_state,
    COUNT(DISTINCT oi.order_id)                     AS total_orders,
    ROUND(SUM(oi.price), 2)                         AS total_revenue,
    ROUND(AVG(r.review_score), 2)                   AS avg_review_score,
    DENSE_RANK() OVER (ORDER BY SUM(oi.price) DESC) AS revenue_rank,
    NTILE(4) OVER (ORDER BY SUM(oi.price) DESC)     AS revenue_quartile
FROM order_items oi
JOIN sellers s ON s.seller_id = oi.seller_id
LEFT JOIN reviews r ON r.order_id = oi.order_id
GROUP BY s.seller_id, s.seller_state
HAVING COUNT(DISTINCT oi.order_id) >= 5
ORDER BY total_revenue DESC;


-- ==================================================================
-- 6. PAYMENT BEHAVIOR ANALYSIS
-- ==================================================================
SELECT
    payment_type,
    COUNT(*) AS transactions,
    ROUND(AVG(payment_installments), 1) AS avg_installments,
    ROUND(SUM(payment_value), 2) AS total_value,
    ROUND(SUM(payment_value) * 100.0 / SUM(SUM(payment_value)) OVER (), 2) AS pct_of_total_value
FROM payments
GROUP BY payment_type
ORDER BY total_value DESC;


-- ==================================================================
-- 7. CUSTOMER LIFETIME VALUE (running total per customer)
-- ==================================================================
SELECT
    c.customer_unique_id,
    o.order_purchase_timestamp,
    (oi.price + oi.freight_value) AS order_value,
    SUM(oi.price + oi.freight_value) OVER (
        PARTITION BY c.customer_unique_id
        ORDER BY o.order_purchase_timestamp
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) AS running_ltv
FROM orders o
JOIN customers c ON c.customer_id = o.customer_id
JOIN order_items oi ON oi.order_id = o.order_id
ORDER BY c.customer_unique_id, o.order_purchase_timestamp;
