
DROP DATABASE IF EXISTS uk_ecommerce_portfolio;
CREATE DATABASE uk_ecommerce_portfolio;
USE uk_ecommerce_portfolio;

-- =========================================================
-- 1) DIMENSION TABLES
-- =========================================================

CREATE TABLE categories (
    category_id INT PRIMARY KEY,
    category_code VARCHAR(10),
    category_name VARCHAR(100),
    category_name_raw VARCHAR(100)
);

CREATE TABLE marketing_channels (
    channel_id INT PRIMARY KEY,
    channel_name VARCHAR(100),
    channel_group VARCHAR(50)
);

CREATE TABLE customers (
    customer_id INT PRIMARY KEY,
    first_name VARCHAR(100),
    last_name VARCHAR(100),
    email VARCHAR(255),
    signup_date DATE,
    city VARCHAR(100),
    region VARCHAR(100),
    country VARCHAR(50),
    acquisition_channel_id INT,
    customer_type VARCHAR(50),
    is_duplicate_seed TINYINT,
    CONSTRAINT fk_customers_channel
        FOREIGN KEY (acquisition_channel_id) REFERENCES marketing_channels(channel_id)
);

CREATE TABLE products (
    product_id INT PRIMARY KEY,
    sku VARCHAR(50),
    product_name VARCHAR(255),
    brand VARCHAR(100),
    category_id INT,
    cost_gbp DECIMAL(10,2),
    list_price_gbp DECIMAL(10,2),
    is_active TINYINT,
    avg_rating_seed DECIMAL(3,1),
    weight_kg DECIMAL(8,2),
    launch_date DATE,
    CONSTRAINT fk_products_category
        FOREIGN KEY (category_id) REFERENCES categories(category_id)
);

-- =========================================================
-- 2) FACT / TRANSACTION TABLES
-- =========================================================

CREATE TABLE orders (
    order_id INT PRIMARY KEY,
    customer_id INT,
    order_date DATE,
    order_status VARCHAR(50),
    channel_id INT,
    ship_city VARCHAR(100),
    ship_region VARCHAR(100),
    total_units INT,
    subtotal_gbp DECIMAL(12,2),
    discount_gbp DECIMAL(12,2),
    shipping_fee_gbp DECIMAL(10,2),
    order_total_gbp DECIMAL(12,2),
    CONSTRAINT fk_orders_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id),
    CONSTRAINT fk_orders_channel
        FOREIGN KEY (channel_id) REFERENCES marketing_channels(channel_id)
);

CREATE TABLE order_items (
    order_item_id INT PRIMARY KEY,
    order_id INT,
    product_id INT,
    quantity INT,
    unit_price_gbp DECIMAL(10,2),
    discount_gbp DECIMAL(10,2),
    line_total_gbp DECIMAL(12,2),
    CONSTRAINT fk_order_items_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_order_items_product
        FOREIGN KEY (product_id) REFERENCES products(product_id)
);

CREATE TABLE payments (
    payment_id INT PRIMARY KEY,
    order_id INT,
    payment_date DATETIME,
    payment_method VARCHAR(50),
    payment_status VARCHAR(50),
    amount_paid_gbp DECIMAL(12,2),
    refund_amount_gbp DECIMAL(12,2),
    CONSTRAINT fk_payments_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE shipments (
    shipment_id INT PRIMARY KEY,
    order_id INT,
    carrier VARCHAR(50),
    shipped_date DATE,
    delivered_date DATE,
    delivery_service VARCHAR(50),
    shipment_status VARCHAR(50),
    CONSTRAINT fk_shipments_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id)
);

CREATE TABLE returns (
    return_id INT PRIMARY KEY,
    order_id INT,
    order_item_id INT,
    return_date DATE,
    return_reason VARCHAR(100),
    refund_gbp DECIMAL(12,2),
    return_status VARCHAR(50),
    CONSTRAINT fk_returns_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_returns_order_item
        FOREIGN KEY (order_item_id) REFERENCES order_items(order_item_id)
);

CREATE TABLE reviews (
    review_id INT PRIMARY KEY,
    order_id INT,
    product_id INT,
    customer_id INT,
    rating INT,
    review_title VARCHAR(255),
    review_text TEXT,
    review_date DATE,
    CONSTRAINT fk_reviews_order
        FOREIGN KEY (order_id) REFERENCES orders(order_id),
    CONSTRAINT fk_reviews_product
        FOREIGN KEY (product_id) REFERENCES products(product_id),
    CONSTRAINT fk_reviews_customer
        FOREIGN KEY (customer_id) REFERENCES customers(customer_id)
);

-- =========================================================
-- 4) PERFORMANCE SUPPORT: INDEXES
-- =========================================================

CREATE INDEX idx_orders_customer_date ON orders(customer_id, order_date);
CREATE INDEX idx_orders_channel_date ON orders(channel_id, order_date);
CREATE INDEX idx_order_items_order ON order_items(order_id);
CREATE INDEX idx_order_items_product ON order_items(product_id);
CREATE INDEX idx_payments_order_status ON payments(order_id, payment_status);
CREATE INDEX idx_shipments_order ON shipments(order_id);
CREATE INDEX idx_returns_order_item ON returns(order_id, order_item_id);
CREATE INDEX idx_reviews_order_product ON reviews(order_id, product_id);

-- =========================================================
-- 5) RAW DATA PROFILING / QUALITY CHECKS
-- =========================================================

-- 5.1 Row counts by table
SELECT 'customers' AS table_name, COUNT(*) AS row_count FROM customers
UNION ALL SELECT 'products', COUNT(*) FROM products
UNION ALL SELECT 'categories', COUNT(*) FROM categories
UNION ALL SELECT 'marketing_channels', COUNT(*) FROM marketing_channels
UNION ALL SELECT 'orders', COUNT(*) FROM orders
UNION ALL SELECT 'order_items', COUNT(*) FROM order_items
UNION ALL SELECT 'payments', COUNT(*) FROM payments
UNION ALL SELECT 'shipments', COUNT(*) FROM shipments
UNION ALL SELECT 'returns', COUNT(*) FROM returns
UNION ALL SELECT 'reviews', COUNT(*) FROM reviews;

-- 5.2 Duplicate-looking customers based on normalised email
SELECT
    LOWER(TRIM(email)) AS email_norm,
    COUNT(*) AS duplicate_count
FROM customers
GROUP BY LOWER(TRIM(email))
HAVING COUNT(*) > 1
ORDER BY duplicate_count DESC, email_norm;

-- 5.3 Category naming inconsistencies
SELECT category_id, category_name, category_name_raw
FROM categories
WHERE TRIM(LOWER(category_name)) <> TRIM(LOWER(category_name_raw));

-- 5.4 Missing value scan
SELECT
    SUM(CASE WHEN city IS NULL OR TRIM(city) = '' THEN 1 ELSE 0 END) AS customers_missing_city,
    SUM(CASE WHEN email IS NULL OR TRIM(email) = '' THEN 1 ELSE 0 END) AS customers_missing_email
FROM customers;

SELECT
    SUM(CASE WHEN payment_method IS NULL OR TRIM(payment_method) = '' THEN 1 ELSE 0 END) AS payments_missing_method
FROM payments;

SELECT
    SUM(CASE WHEN review_text IS NULL OR TRIM(review_text) = '' THEN 1 ELSE 0 END) AS reviews_missing_text
FROM reviews;

-- 5.5 Order / payment reconciliation issues
SELECT
    p.order_id,
    p.amount_paid_gbp,
    p.refund_amount_gbp,
    o.order_total_gbp,
    p.payment_status
FROM payments p
JOIN orders o
    ON p.order_id = o.order_id
WHERE p.refund_amount_gbp > p.amount_paid_gbp
   OR (p.payment_status = 'Failed' AND p.amount_paid_gbp > 0);

-- 5.6 Shipping sequence issues
SELECT
    s.shipment_id,
    s.order_id,
    o.order_date,
    s.shipped_date,
    s.delivered_date
FROM shipments s
JOIN orders o
    ON s.order_id = o.order_id
WHERE s.shipped_date < o.order_date
   OR (s.delivered_date IS NOT NULL AND s.delivered_date < s.shipped_date);

-- 5.7 Discount logic exceptions
SELECT
    order_item_id,
    order_id,
    quantity,
    unit_price_gbp,
    discount_gbp
FROM order_items
WHERE discount_gbp > quantity * unit_price_gbp;

-- =========================================================
-- 6) CLEANING / STANDARDISATION LAYER
-- Build reusable views instead of overwriting raw tables.
-- =========================================================

CREATE OR REPLACE VIEW vw_categories_clean AS
SELECT
    category_id,
    category_code,
    TRIM(
        CASE
            WHEN LOWER(TRIM(category_name_raw)) = 'home and kitchen' THEN 'Home & Kitchen'
            WHEN LOWER(TRIM(category_name_raw)) = 'fashion' THEN 'Fashion'
            WHEN LOWER(TRIM(category_name_raw)) = 'beauty' THEN 'Beauty'
            WHEN LOWER(TRIM(category_name_raw)) = 'books and stationery' THEN 'Books & Stationery'
            ELSE category_name
        END
    ) AS category_name_clean
FROM categories;

CREATE OR REPLACE VIEW vw_customers_dedup AS
WITH email_ranked AS (
    SELECT
        c.*,
        LOWER(TRIM(email)) AS email_norm,
        ROW_NUMBER() OVER (
            PARTITION BY LOWER(TRIM(email))
            ORDER BY is_duplicate_seed ASC, signup_date ASC, customer_id ASC
        ) AS rn
    FROM customers c
)
SELECT *
FROM email_ranked
WHERE rn = 1;

CREATE OR REPLACE VIEW vw_order_quality_flags AS
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_status,
    o.channel_id,
    o.order_total_gbp,
    p.payment_status,
    p.amount_paid_gbp,
    p.refund_amount_gbp,
    s.shipped_date,
    s.delivered_date,
    CASE WHEN p.refund_amount_gbp > p.amount_paid_gbp THEN 1 ELSE 0 END AS refund_mismatch_flag,
    CASE WHEN s.shipped_date < o.order_date THEN 1 ELSE 0 END AS negative_ship_lag_flag,
    CASE WHEN s.delivered_date IS NOT NULL AND s.shipped_date IS NOT NULL AND s.delivered_date < s.shipped_date THEN 1 ELSE 0 END AS delivery_sequence_flag,
    CASE WHEN o.order_status = 'Cancelled' AND COALESCE(p.payment_status, '') = 'Paid' THEN 1 ELSE 0 END AS cancelled_but_paid_flag
FROM orders o
LEFT JOIN payments p
    ON o.order_id = p.order_id
LEFT JOIN shipments s
    ON o.order_id = s.order_id;

CREATE OR REPLACE VIEW vw_orders_clean AS
SELECT
    o.order_id,
    CASE
        WHEN d.customer_id IS NOT NULL THEN d.customer_id
        ELSE o.customer_id
    END AS customer_id_clean,
    o.order_date,
    o.order_status,
    o.channel_id,
    TRIM(o.ship_city) AS ship_city_clean,
    TRIM(o.ship_region) AS ship_region_clean,
    o.total_units,
    o.subtotal_gbp,
    o.discount_gbp,
    o.shipping_fee_gbp,
    o.order_total_gbp,
    COALESCE(p.payment_status, 'Unknown') AS payment_status,
    COALESCE(p.amount_paid_gbp, 0) AS amount_paid_gbp,
    COALESCE(p.refund_amount_gbp, 0) AS refund_amount_gbp,
    CASE
        WHEN COALESCE(p.payment_status, '') = 'Failed' THEN 0
        ELSE o.order_total_gbp - COALESCE(p.refund_amount_gbp, 0)
    END AS net_revenue_gbp,
    CASE
        WHEN q.refund_mismatch_flag = 1
          OR q.negative_ship_lag_flag = 1
          OR q.delivery_sequence_flag = 1
        THEN 1 ELSE 0
    END AS needs_review_flag
FROM orders o
LEFT JOIN payments p
    ON o.order_id = p.order_id
LEFT JOIN vw_order_quality_flags q
    ON o.order_id = q.order_id
LEFT JOIN vw_customers_dedup d
    ON o.customer_id = d.customer_id;

CREATE OR REPLACE VIEW vw_order_items_enriched AS
SELECT
    oi.order_item_id,
    oi.order_id,
    oi.product_id,
    oi.quantity,
    oi.unit_price_gbp,
    oi.discount_gbp,
    oi.line_total_gbp,
    p.product_name,
    p.brand,
    p.cost_gbp,
    vc.category_name_clean AS category_name,
    (oi.line_total_gbp - p.cost_gbp * oi.quantity) AS gross_profit_proxy_gbp
FROM order_items oi
JOIN products p
    ON oi.product_id = p.product_id
JOIN vw_categories_clean vc
    ON p.category_id = vc.category_id;

CREATE OR REPLACE VIEW vw_order_customer_sequence AS
SELECT
    o.*,
    ROW_NUMBER() OVER (
        PARTITION BY customer_id_clean
        ORDER BY order_date, order_id
    ) AS customer_order_sequence
FROM vw_orders_clean o;

-- Q1. Top 15 highest-value orders
SELECT
    order_id,
    customer_id,
    order_date,
    order_total_gbp
FROM orders
ORDER BY order_total_gbp DESC
LIMIT 15;

-- Q2. Orders by status
SELECT
    order_status,
    COUNT(*) AS orders
FROM orders
GROUP BY order_status
ORDER BY orders DESC;

-- Q3. Revenue by month
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS order_month,
    COUNT(*) AS orders,
    ROUND(SUM(order_total_gbp), 2) AS gross_revenue_gbp
FROM orders
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY order_month;

-- Q4. Average order value by region
SELECT
    ship_region,
    ROUND(AVG(order_total_gbp), 2) AS avg_order_value_gbp
FROM orders
GROUP BY ship_region
ORDER BY avg_order_value_gbp DESC;


-- Q5. Top categories by revenue and gross profit proxy
SELECT
    e.category_name,
    ROUND(SUM(e.line_total_gbp), 2) AS revenue_gbp,
    SUM(e.quantity) AS units_sold,
    ROUND(SUM(e.gross_profit_proxy_gbp), 2) AS gross_profit_proxy_gbp
FROM vw_order_items_enriched e
GROUP BY e.category_name
ORDER BY revenue_gbp DESC;

-- Q6. Customer revenue summary
SELECT
    c.customer_id,
    CONCAT(c.first_name, ' ', c.last_name) AS customer_name,
    COUNT(DISTINCT o.order_id) AS orders,
    ROUND(SUM(o.net_revenue_gbp), 2) AS net_revenue_gbp
FROM vw_customers_dedup c
JOIN vw_orders_clean o
    ON c.customer_id = o.customer_id_clean
GROUP BY c.customer_id, CONCAT(c.first_name, ' ', c.last_name)
ORDER BY net_revenue_gbp DESC
LIMIT 20;

-- Q7. Orders with above-average order value
SELECT
    order_id,
    customer_id,
    order_total_gbp
FROM orders
WHERE order_total_gbp > (
    SELECT AVG(order_total_gbp)
    FROM orders
)
ORDER BY order_total_gbp DESC;

-- Q8. Return rate by category
SELECT
    e.category_name,
    COUNT(DISTINCT r.return_id) AS returns_count,
    COUNT(DISTINCT e.order_item_id) AS sold_order_items,
    ROUND(COUNT(DISTINCT r.return_id) / NULLIF(COUNT(DISTINCT e.order_item_id), 0), 4) AS return_rate
FROM vw_order_items_enriched e
LEFT JOIN returns r
    ON e.order_item_id = r.order_item_id
GROUP BY e.category_name
ORDER BY return_rate DESC, returns_count DESC;

-- Q9. Month-over-month net revenue with growth %
WITH monthly_sales AS (
    SELECT
        DATE_FORMAT(order_date, '%Y-%m') AS order_month,
        ROUND(SUM(net_revenue_gbp), 2) AS net_revenue_gbp
    FROM vw_orders_clean
    GROUP BY DATE_FORMAT(order_date, '%Y-%m')
)
SELECT
    order_month,
    net_revenue_gbp,
    ROUND(
        100 * (net_revenue_gbp - LAG(net_revenue_gbp) OVER (ORDER BY order_month))
        / NULLIF(LAG(net_revenue_gbp) OVER (ORDER BY order_month), 0),
        2
    ) AS mom_growth_pct
FROM monthly_sales
ORDER BY order_month;

-- Q10. Repeat purchase rate by acquisition channel
WITH customer_orders AS (
    SELECT
        c.customer_id,
        mc.channel_name,
        COUNT(DISTINCT o.order_id) AS order_count
    FROM vw_customers_dedup c
    LEFT JOIN vw_orders_clean o
        ON c.customer_id = o.customer_id_clean
    LEFT JOIN marketing_channels mc
        ON c.acquisition_channel_id = mc.channel_id
    GROUP BY c.customer_id, mc.channel_name
)
SELECT
    channel_name,
    COUNT(*) AS customers,
    ROUND(AVG(CASE WHEN order_count > 1 THEN 1 ELSE 0 END), 4) AS repeat_purchase_rate
FROM customer_orders
GROUP BY channel_name
ORDER BY repeat_purchase_rate DESC;

-- Q11. RFM-style customer segmentation
WITH customer_metrics AS (
    SELECT
        customer_id_clean AS customer_id,
        MIN(order_date) AS first_order_date,
        MAX(order_date) AS last_order_date,
        COUNT(DISTINCT order_id) AS frequency,
        SUM(net_revenue_gbp) AS monetary
    FROM vw_orders_clean
    GROUP BY customer_id_clean
),
rfm_base AS (
    SELECT
        customer_id,
        DATEDIFF('2025-12-31', last_order_date) AS recency_days,
        frequency,
        monetary,
        NTILE(4) OVER (ORDER BY DATEDIFF('2025-12-31', last_order_date) DESC) AS recency_quartile,
        NTILE(4) OVER (ORDER BY frequency ASC) AS frequency_quartile,
        NTILE(4) OVER (ORDER BY monetary ASC) AS monetary_quartile
    FROM customer_metrics
),
rfm_scored AS (
    SELECT
        customer_id,
        recency_days,
        frequency,
        monetary,
        (5 - recency_quartile) + frequency_quartile + monetary_quartile AS rfm_score
    FROM rfm_base
)
SELECT
    CASE
        WHEN rfm_score >= 10 THEN 'Champions'
        WHEN rfm_score >= 8 THEN 'Loyal'
        WHEN rfm_score >= 6 THEN 'Promising'
        ELSE 'At-Risk'
    END AS customer_segment,
    COUNT(*) AS customers,
    ROUND(AVG(monetary), 2) AS avg_customer_value_gbp,
    ROUND(SUM(monetary), 2) AS total_value_gbp
FROM rfm_scored
GROUP BY customer_segment
ORDER BY total_value_gbp DESC;

-- Q12. Customer purchase cadence: days between orders
WITH ordered_events AS (
    SELECT
        customer_id_clean,
        order_id,
        order_date,
        LAG(order_date) OVER (
            PARTITION BY customer_id_clean
            ORDER BY order_date, order_id
        ) AS previous_order_date
    FROM vw_orders_clean
)
SELECT
    customer_id_clean,
    order_id,
    order_date,
    previous_order_date,
    DATEDIFF(order_date, previous_order_date) AS days_since_previous_order
FROM ordered_events
WHERE previous_order_date IS NOT NULL
ORDER BY days_since_previous_order DESC, customer_id_clean;

-- Q13. Top products by revenue share
WITH product_revenue AS (
    SELECT
        product_id,
        product_name,
        ROUND(SUM(line_total_gbp), 2) AS revenue_gbp
    FROM vw_order_items_enriched
    GROUP BY product_id, product_name
),
ranked AS (
    SELECT
        product_id,
        product_name,
        revenue_gbp,
        ROUND(
            100 * revenue_gbp / SUM(revenue_gbp) OVER (),
            2
        ) AS revenue_share_pct,
        DENSE_RANK() OVER (ORDER BY revenue_gbp DESC) AS revenue_rank
    FROM product_revenue
)
SELECT *
FROM ranked
WHERE revenue_rank <= 15
ORDER BY revenue_rank;

-- Q14. Cohort-lite monthly first-order retention
WITH first_orders AS (
    SELECT
        customer_id_clean,
        MIN(DATE_FORMAT(order_date, '%Y-%m-01')) AS cohort_month
    FROM vw_orders_clean
    GROUP BY customer_id_clean
),
activity AS (
    SELECT
        o.customer_id_clean,
        DATE_FORMAT(o.order_date, '%Y-%m-01') AS activity_month
    FROM vw_orders_clean o
    GROUP BY o.customer_id_clean, DATE_FORMAT(o.order_date, '%Y-%m-01')
)
SELECT
    f.cohort_month,
    TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month) AS months_since_first_purchase,
    COUNT(DISTINCT a.customer_id_clean) AS active_customers
FROM first_orders f
JOIN activity a
    ON f.customer_id_clean = a.customer_id_clean
GROUP BY f.cohort_month,
         TIMESTAMPDIFF(MONTH, f.cohort_month, a.activity_month)
ORDER BY f.cohort_month, months_since_first_purchase;

-- =========================================================
-- 10) OPERATIONS / DELIVERY / REVIEWS
-- =========================================================

-- Q15. Shipping speed KPIs
SELECT
    ROUND(AVG(DATEDIFF(s.shipped_date, o.order_date)), 2) AS avg_days_to_ship,
    ROUND(AVG(DATEDIFF(s.delivered_date, s.shipped_date)), 2) AS avg_days_in_transit,
    ROUND(AVG(CASE WHEN DATEDIFF(s.shipped_date, o.order_date) > 3 THEN 1 ELSE 0 END), 4) AS late_dispatch_rate
FROM shipments s
JOIN orders o
    ON s.order_id = o.order_id;

-- Q16. Relationship between shipping delay and review score
WITH review_delivery AS (
    SELECT
        r.review_id,
        r.rating,
        CASE
            WHEN DATEDIFF(s.shipped_date, o.order_date) <= 1 THEN '0-1 days'
            WHEN DATEDIFF(s.shipped_date, o.order_date) <= 3 THEN '2-3 days'
            WHEN DATEDIFF(s.shipped_date, o.order_date) <= 7 THEN '4-7 days'
            ELSE '8+ days'
        END AS ship_lag_bucket
    FROM reviews r
    JOIN shipments s
        ON r.order_id = s.order_id
    JOIN orders o
        ON r.order_id = o.order_id
)
SELECT
    ship_lag_bucket,
    COUNT(*) AS reviews,
    ROUND(AVG(rating), 2) AS avg_rating
FROM review_delivery
GROUP BY ship_lag_bucket
ORDER BY FIELD(ship_lag_bucket, '0-1 days', '2-3 days', '4-7 days', '8+ days');

-- Q17. Return reasons ranked
SELECT
    return_reason,
    COUNT(*) AS returns_count,
    ROUND(SUM(refund_gbp), 2) AS refund_value_gbp,
    DENSE_RANK() OVER (ORDER BY COUNT(*) DESC) AS return_reason_rank
FROM returns
GROUP BY return_reason
ORDER BY return_reason_rank;

-- =========================================================
-- 11) CHANNEL / FUNNEL / EXECUTIVE KPI QUERIES
-- =========================================================

-- Q18. Channel efficiency
SELECT
    mc.channel_name,
    COUNT(DISTINCT o.order_id) AS orders,
    COUNT(DISTINCT o.customer_id_clean) AS customers,
    ROUND(SUM(o.order_total_gbp), 2) AS gross_revenue_gbp,
    ROUND(SUM(o.net_revenue_gbp), 2) AS net_revenue_gbp,
    ROUND(AVG(o.order_total_gbp), 2) AS avg_order_value_gbp
FROM vw_orders_clean o
JOIN marketing_channels mc
    ON o.channel_id = mc.channel_id
GROUP BY mc.channel_name
ORDER BY net_revenue_gbp DESC;

-- Q19. Executive KPI dashboard query
SELECT
    COUNT(DISTINCT order_id) AS total_orders,
    COUNT(DISTINCT customer_id_clean) AS active_customers,
    ROUND(SUM(order_total_gbp), 2) AS gross_revenue_gbp,
    ROUND(SUM(net_revenue_gbp), 2) AS net_revenue_gbp,
    ROUND(AVG(order_total_gbp), 2) AS avg_order_value_gbp,
    ROUND(AVG(CASE WHEN customer_order_sequence > 1 THEN 1 ELSE 0 END), 4) AS repeat_order_share
FROM vw_order_customer_sequence;

-- =========================================================
-- 12) ANOMALY / FRAUD-LITE CHECKS
-- =========================================================

-- Q20. Orders above the 99th percentile
WITH order_threshold AS (
    SELECT
        PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY order_total_gbp) OVER () AS p99_order_total
    FROM orders
    LIMIT 1
)
SELECT
    o.order_id,
    o.customer_id,
    o.order_date,
    o.order_total_gbp
FROM orders o
CROSS JOIN order_threshold t
WHERE o.order_total_gbp >= t.p99_order_total
ORDER BY o.order_total_gbp DESC;

-- MySQL does not support PERCENTILE_CONT in all installations.
-- Use NTILE(100) over ORDER BY order_total_gbp and filter tile = 100.

WITH ranked_orders AS (
    SELECT
        order_id,
        customer_id,
        order_date,
        order_total_gbp,
        NTILE(100) OVER (ORDER BY order_total_gbp) AS percentile_bucket
    FROM orders
)
SELECT *
FROM ranked_orders
WHERE percentile_bucket = 100
ORDER BY order_total_gbp DESC;

-- Q21. Orders needing manual review
SELECT *
FROM vw_order_quality_flags
WHERE refund_mismatch_flag = 1
   OR negative_ship_lag_flag = 1
   OR delivery_sequence_flag = 1
   OR cancelled_but_paid_flag = 1
ORDER BY order_date, order_id;

-- Q22. Potential duplicate orders
WITH order_signature AS (
    SELECT
        customer_id,
        order_date,
        ROUND(order_total_gbp, 2) AS order_total_gbp,
        COUNT(*) AS duplicate_count
    FROM orders
    GROUP BY customer_id, order_date, ROUND(order_total_gbp, 2)
)
SELECT *
FROM order_signature
WHERE duplicate_count > 1
ORDER BY duplicate_count DESC, order_date;

-- =========================================================
-- 13) OPTIONAL REUSABLE VIEW FOR REPORTING
-- =========================================================

CREATE OR REPLACE VIEW vw_monthly_kpis AS
SELECT
    DATE_FORMAT(order_date, '%Y-%m') AS order_month,
    COUNT(DISTINCT order_id) AS orders,
    COUNT(DISTINCT customer_id_clean) AS active_customers,
    ROUND(SUM(order_total_gbp), 2) AS gross_revenue_gbp,
    ROUND(SUM(net_revenue_gbp), 2) AS net_revenue_gbp,
    ROUND(AVG(order_total_gbp), 2) AS avg_order_value_gbp
FROM vw_orders_clean
GROUP BY DATE_FORMAT(order_date, '%Y-%m')
ORDER BY order_month;

SELECT * FROM vw_monthly_kpis;
