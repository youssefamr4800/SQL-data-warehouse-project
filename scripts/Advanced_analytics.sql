-- 1. Changes over time

-- Analyze sales performance over time
SELECT YEAR(order_date) AS year,
       SUM(sales_amount) AS total_sales,
       COUNT(DISTINCT customer_key) AS total_customer,
       SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY YEAR(order_date)
ORDER BY YEAR(order_date);

SELECT DATETRUNC(MONTH ,order_date) AS month,
       SUM(sales_amount) AS total_sales,
       COUNT(DISTINCT customer_key) AS total_customer,
       SUM(quantity) AS total_quantity
FROM gold.fact_sales
WHERE order_date IS NOT NULL
GROUP BY DATETRUNC(MONTH ,order_date)
ORDER BY DATETRUNC(MONTH ,order_date);


---------------------------------------------------------------------------
-- 2. Cumulative Analysis

/* Calculate the total sales per month and
 the running total sales over time */
WITH month_total_sales AS (
    SELECT DATETRUNC(MONTH, order_date) AS order_date,
           SUM(sales_amount) AS totsl_sales
    FROM gold.fact_sales
    WHERE order_date IS NOT NULL
    GROUP BY DATETRUNC(MONTH, order_date)
)
SELECT order_date,
       totsl_sales,
       SUM(totsl_sales) OVER (PARTITION BY YEAR(order_date) ORDER BY order_date) AS running_total
FROM month_total_sales;


--------------------------------------------------------------
-- 3. Performance Analysis

/* Analyze the yearly performance of products by comparing their sales
to both the average sales performance of the product and the previous year's sales */
WITH yearly_product_sales AS (
    SELECT
        YEAR(f.order_date) AS order_year,
        p.product_name,
        SUM(f.sales_amount) AS current_sales
    FROM gold.fact_sales f
    LEFT JOIN gold.dim_products p
        ON f.product_key = p.product_key
    WHERE f.order_date IS NOT NULL
    GROUP BY 
        YEAR(f.order_date),
        p.product_name
)
SELECT
    order_year,
    product_name,
    current_sales,
    AVG(current_sales) OVER (PARTITION BY product_name) AS avg_sales,
    current_sales - AVG(current_sales) OVER (PARTITION BY product_name) AS diff_avg,
    CASE 
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) > 0 THEN 'Above Avg'
        WHEN current_sales - AVG(current_sales) OVER (PARTITION BY product_name) < 0 THEN 'Below Avg'
        ELSE 'Avg'
    END AS avg_change,
    -- Year-over-Year Analysis
    LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS py_sales,
    current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) AS diff_py,
    CASE 
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) > 0 THEN 'Increase'
        WHEN current_sales - LAG(current_sales) OVER (PARTITION BY product_name ORDER BY order_year) < 0 THEN 'Decrease'
        ELSE 'No Change'
    END AS py_change
FROM yearly_product_sales
ORDER BY product_name, order_year;



-------------------------------------------------------------------------------------------
-- 4. Part-To-Whole Analysis

-- Which categories contribute the most to overall sales?

WITH category_sales AS (
    SELECT dp.category,
       SUM(fs.sales_amount) AS total_sales
    FROM gold.fact_sales fs
    LEFT JOIN gold.dim_products dp
    ON fs.product_key = dp.product_key
    GROUP BY dp.category
)
SELECT category,
       total_sales,
       SUM(total_sales) OVER () AS overall_sales,
       CONCAT(ROUND(CAST(total_sales AS FLOAT) / SUM(total_sales) OVER () * 100, 2), '%') AS percentage_of_total
FROM category_sales
ORDER BY total_sales DESC;

-------------------------------------------------------------------------------------
-- 5. Data segmentation

-- Segment products into cost range and count how many products fall into each segment.

WITH product_segments AS (
     SELECT product_key,
     product_name,
     cost,
     CASE
         WHEN cost < 100 THEN 'Below 100'
         WHEN cost BETWEEN 100 AND 500 THEN '100-500'
         WHEN cost BETWEEN 500 AND 1000 THEN '500-1000'
         ELSE 'Above 1000'
         END AS cost_range
    FROM gold.dim_products
)
SELECT cost_range,
       COUNT(cost_range) AS total_products
FROM product_segments
GROUP BY cost_range
ORDER BY total_products DESC;


/*
 Will be Added later
 */

WITH customer_spending AS (
    SELECT dc.customer_key,
       SUM(fs.sales_amount) AS total_spending,
       MIN(fs.order_date) AS first_order,
       MAX(fs.order_date) AS last_order,
       DATEDIFF(MONTH, MIN(fs.order_date), MAX(fs.order_date)) AS life_Span
    FROM gold.fact_sales fs
    LEFT JOIN gold.dim_customers dc
    ON fs.customer_key = dc.customer_key
    GROUP BY dc.customer_key
),
    customer_segment AS (
    SELECT customer_key,
        CASE
           WHEN life_Span >= 12 AND total_spending > 5000 THEN 'VIP'
           WHEN life_Span >= 12 AND total_spending <= 5000 THEN 'Regular'
           ELSE 'New'
        END AS customer_segment
    FROM customer_spending
)
SELECT customer_segment,
       COUNT(customer_key) AS total_customer_segment
FROM customer_segment
GROUP BY customer_segment
ORDER BY total_customer_segment DESC;


--------------------------------------------------------------------------------------------
-- 6. Reporting

CREATE VIEW gold.report_customers AS
WITH base_query AS (
    SELECT fc.order_number,
           fc.product_key,
           fc.order_date,
           fc.sales_amount,
           fc.quantity,
           dc.customer_key,
           dc.customer_number,
           CONCAT(dc.first_name, ' ', dc.last_name) AS customer_name,
           DATEDIFF(YEAR, dc.birth_date, GETDATE()) AS age
    FROM gold.fact_sales fc
    LEFT JOIN gold.dim_customers dc
    ON fc.customer_key = dc.customer_key
    WHERE order_date IS NOT NULL
),
    customer_aggregation AS (
    SELECT customer_key,
           customer_number,
           customer_name,
           age,
           COUNT(DISTINCT order_number) AS total_orders,
           SUM(sales_amount) AS total_sales,
           SUM(quantity) AS total_quantity,
           COUNT(DISTINCT product_key) AS total_products,
           MAX(order_date) AS last_order_date,
           DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS life_Span
    FROM base_query
    GROUP BY customer_key, customer_number, customer_name, age
)
SELECT customer_key,
       customer_number,
       customer_name,
       age,
       CASE
           WHEN age < 20 THEN 'Under 20'
           WHEN age BETWEEN 20 AND 29 THEN '20-29'
           WHEN age BETWEEN 30 AND 39 THEN '30-39'
           WHEN age BETWEEN 40 AND 49 THEN '40-49'
           ELSE '50 and above'
       END AS age_group,
       CASE
           WHEN life_Span >= 12 AND total_sales > 5000 THEN 'VIP'
           WHEN life_Span >= 12 AND total_sales <= 5000 THEN 'Regular'
           ELSE 'New'
       END AS customer_segment,
       last_order_date,
       DATEDIFF(MONTH, last_order_date, GETDATE()) AS recency,
       total_orders,
       total_sales,
       total_quantity,
       total_products,
       life_Span,
       CASE
           WHEN total_orders = 0 THEN 0
           ELSE total_sales / total_orders
       END AS avg_order_value,
       CASE
           WHEN life_Span = 0 THEN total_sales
           ELSE total_sales / life_Span
       END AS avg_monthly_spend
FROM customer_aggregation;


CREATE VIEW gold.report_products AS
WITH base_query AS (
    SELECT fs.order_number,
           fs.order_date,
           fs.customer_key,
           fs.sales_amount,
           fs.quantity,
           dp.product_key,
           dp.product_name,
           dp.category,
           dp.subcategory,
           dp.cost
    FROM gold.fact_sales fs
    LEFT JOIN gold.dim_products dp
    ON fs.product_key = dp.product_key
    WHERE order_date IS NOT NULL
),
    customer_aggregation AS (
    SELECT product_key,
           product_name,
           category,
           subcategory,
           cost,
           COUNT(DISTINCT order_number) AS total_orders,
           SUM(sales_amount) AS total_sales,
           SUM(quantity) AS quantity_sold,
           COUNT(DISTINCT customer_key) AS total_customers,
           MAX(order_date) AS last_sale_order,
           DATEDIFF(MONTH, MIN(order_date), MAX(order_date)) AS life_Span,
           ROUND(AVG(CAST(sales_amount AS FLOAT) / NULLIF(quantity, 0)), 1) AS avg_selling_price
    FROM base_query
    GROUP BY product_key, product_name, category, subcategory, cost
)
SELECT product_key,
       product_name,
       category,
       subcategory,
       cost,
       CASE
           WHEN total_sales > 50000 THEN 'High-Performance'
           WHEN total_sales >= 10000 THEN 'Mid-Range'
           ELSE 'Low-Performance'
       END AS product_segment,
       last_sale_order,
       DATEDIFF(MONTH, last_sale_order, GETDATE()) AS recency,
       total_orders,
       total_sales,
       quantity_sold,
       total_customers,
       life_Span,
       avg_selling_price,
       CASE
           WHEN total_orders = 0 THEN 0
           ELSE total_sales / total_orders
       END AS avg_order_revenue,
       CASE
           WHEN life_Span = 0 THEN total_sales
           ELSE total_sales / life_Span
       END AS avg_monthly_revenue
FROM customer_aggregation;


SELECT * FROM gold.report_customers;
SELECT * FROM gold.report_products;
