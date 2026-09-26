# E-Commerce Analytics Dashboard | Olist Brazilian E-Commerce

End-to-end analytics project on a 9-table relational e-commerce dataset —
covering data cleaning, SQL analysis, customer segmentation, and a 4-page
Power BI dashboard.

## Dataset Overview
**Source:** [Olist Brazilian E-Commerce Public Dataset (Kaggle)](https://www.kaggle.com/datasets/olistbr/brazilian-ecommerce)
**Time period:** September 4, 2016 – October 17, 2018

| Table | Rows | Description |
|---|---|---|
| `olist_orders_dataset.csv` | 99,441 | Core order records with status and timestamps |
| `olist_order_items_dataset.csv` | 112,650 | One row per product line item within an order |
| `olist_customers_dataset.csv` | 99,441 | Customer records (99,441 `customer_id`, 96,096 unique `customer_unique_id`) |
| `olist_order_payments_dataset.csv` | 103,886 | Payment transactions (orders can have multiple) |
| `olist_order_reviews_dataset.csv` | 99,224 | Customer review scores and comments |
| `olist_products_dataset.csv` | 32,951 | Product catalog with category and dimensions |
| `olist_sellers_dataset.csv` | 3,095 | Seller records with location |
| `olist_geolocation_dataset.csv` | 1,000,163 | Zip-code-to-lat/lng mapping |
| `product_category_name_translation.csv` | ~71 | Portuguese-to-English category names |

**verified facts about the raw data:**
- Customers span **4,119 distinct cities** across **27 states**
- Only **96,096 of 99,441** customer records are unique people — about **3.4%** of customers made a repeat purchase, the rest are one-time buyers (this is the real starting point for your repeat-purchase-rate metric)
- 4 payment types: credit card, boleto, voucher, debit card

## Key Insights

**Revenue & Sales**
- Total revenue across the analyzed period: **$15.84M** from **99K orders**, 
  at an average order value of **$160.31**
- Credit card is the dominant payment method, accounting for **78.34%** of 
  revenue ($12.54M), followed by boleto at **17.92%** ($2.87M)
- Top revenue category is **Health & Beauty** ($1.4M), followed by 
  **Watches/Gifts** ($1.3M) and **Bed, Bath & Table** ($1.2M) — the top 3 
  categories alone generate roughly $3.9M of the $15.84M total

**Customers**
- **96K unique customers**, but only a **3% repeat purchase rate** — the 
  business is overwhelmingly driven by one-time buyers, which is the single 
  biggest growth lever in this dataset
- Average customer lifetime value: **$165.83**
- RFM segmentation splits customers into: **At Risk (23K)**, **Loyal 
  Customers (19K)**, **Champions (15K)**, **New Customers (15K)**, 
  **Lost (15K)**, and **Needs Attention (8K)** — At Risk is the single 
  largest segment, larger than Champions, signaling a retention problem 
  worth prioritizing over acquisition

**Delivery & Logistics**
- Average delivery time: **12.5 days**, with an average order-approval 
  time of **12.56 hours**
- Overall late-delivery rate: **7.92%**
- Slowest-shipping categories are **Office Furniture (20.8 days)**, 
  **Christmas Supplies (15.7 days)**, and **Fashion Shoes (15.4 days)** — 
  nearly double the fastest categories, suggesting a fulfillment bottleneck 
  specific to bulky/seasonal goods

**Sellers**
- **3,095 sellers** on the platform; top seller generated **$229.47K** in 
  revenue
- Average seller review score: **3.97**, slightly below the platform-wide 
  average review score of **4.10** — sellers are dragging overall 
  satisfaction down relative to the buyer experience


## Dashboard Preview
![Executive Overview]("D:\data_analyst_projects\e_commerce_project\powerbi\Screenshot 2026-09-26 144307.png")
![Customer Segmentation]("D:\data_analyst_projects\e_commerce_project\powerbi\Screenshot 2026-09-26 144503.png")
![Logistics]("D:\data_analyst_projects\e_commerce_project\powerbi\Screenshot 2026-09-26 144523.png")
![Seller Performance]("D:\data_analyst_projects\e_commerce_project\powerbi\Screenshot 2026-09-26 144545.png")

## Tech Stack
- **Python** (pandas, numpy, matplotlib, seaborn) — data cleaning, feature engineering, EDA
- **MySQL** — relational modeling, CTEs, window functions (RANK, NTILE, LAG), RFM segmentation, cohort analysis
- **Power BI** — star-schema data model, DAX measures, 4-page interactive dashboard

## Project Structure
```
ecommerce-analytics-project/
├── README.md
├── python/
│   └── 01_data_cleaning_eda.py
├── sql/
│   └── 02_sql_analysis_queries_mysql.sql
├── powerbi/
│   ├── ecommerce_dashboard.pbix
│   └── screenshots/
```


## Author
Anusha Arava