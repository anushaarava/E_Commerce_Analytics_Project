
import pandas as pd
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
from pathlib import Path

sns.set_theme(style="whitegrid")
pd.set_option("display.max_columns", 50)

RAW = Path("data/raw")
OUT = Path("data/processed")
OUT.mkdir(parents=True, exist_ok=True)

# ------------------------------------------------------------------
# 1. LOAD ALL 9 TABLES
# ------------------------------------------------------------------
customers      = pd.read_csv(RAW / "olist_customers_dataset.csv")
orders         = pd.read_csv(RAW / "olist_orders_dataset.csv")
order_items    = pd.read_csv(RAW / "olist_order_items_dataset.csv")
payments       = pd.read_csv(RAW / "olist_order_payments_dataset.csv")
reviews        = pd.read_csv(RAW / "olist_order_reviews_dataset.csv")
products       = pd.read_csv(RAW / "olist_products_dataset.csv")
sellers        = pd.read_csv(RAW / "olist_sellers_dataset.csv")
geolocation    = pd.read_csv(RAW / "olist_geolocation_dataset.csv")
cat_translation = pd.read_csv(RAW / "product_category_name_translation.csv")

tables = {
    "customers": customers, "orders": orders, "order_items": order_items,
    "payments": payments, "reviews": reviews, "products": products,
    "sellers": sellers, "geolocation": geolocation
}
for name, df in tables.items():
    print(f"{name:15s} -> {df.shape[0]:>7,} rows | {df.shape[1]} cols | "
          f"{df.duplicated().sum()} dup rows | nulls: {df.isnull().sum().sum()}")

# ------------------------------------------------------------------
# 2. CLEANING
# ------------------------------------------------------------------

# --- Orders: parse all timestamp columns ---
date_cols = [c for c in orders.columns if "date" in c or "timestamp" in c]
for c in date_cols:
    orders[c] = pd.to_datetime(orders[c], errors="coerce")

# Explicitly ensure all order datetime columns used in calculations
# are stored as pandas datetime values.
datetime_cols = [
    "order_purchase_timestamp",
    "order_approved_at",
    "order_delivered_carrier_date",
    "order_delivered_customer_date",
    "order_estimated_delivery_date",
]

for c in datetime_cols:
    orders[c] = pd.to_datetime(orders[c], errors="coerce")

# Drop exact duplicate rows across all tables
for name, df in tables.items():
    tables[name] = df.drop_duplicates()

customers, orders, order_items, payments, reviews, products, sellers, geolocation = (
    tables["customers"], tables["orders"], tables["order_items"], tables["payments"],
    tables["reviews"], tables["products"], tables["sellers"], tables["geolocation"]
)

# --- Products: translate category name to English, fix missing dims ---
products = products.merge(cat_translation, on="product_category_name", how="left")
products["product_category_name_english"] = products["product_category_name_english"].fillna("unknown")
for col in ["product_weight_g", "product_length_cm", "product_height_cm", "product_width_cm"]:
    products[col] = products[col].fillna(products[col].median())

# --- Reviews: keep the most recent review per order if duplicated ---
reviews = reviews.sort_values("review_creation_date").drop_duplicates(
    subset="order_id", keep="last"
)

# --- Orders: keep only delivered/valid statuses for delivery-time analysis ---
orders_valid = orders[orders["order_status"] != "unavailable"].copy()

# ------------------------------------------------------------------
# 3. FEATURE ENGINEERING
# ------------------------------------------------------------------

# Delivery performance features
orders_valid["delivery_time_days"] = (
    orders_valid["order_delivered_customer_date"]
    - orders_valid["order_purchase_timestamp"]
).dt.total_seconds() / 86400

orders_valid["estimated_vs_actual_days"] = (
    orders_valid["order_delivered_customer_date"]
    - orders_valid["order_estimated_delivery_date"]
).dt.total_seconds() / 86400  # positive = late delivery

orders_valid["is_late"] = orders_valid["estimated_vs_actual_days"] > 0

orders_valid["purchase_to_approval_hours"] = (
    orders_valid["order_approved_at"] - orders_valid["order_purchase_timestamp"]
).dt.total_seconds() / 3600

orders_valid["order_month"] = orders_valid["order_purchase_timestamp"].dt.to_period("M").astype(str)
orders_valid["order_year"] = orders_valid["order_purchase_timestamp"].dt.year
orders_valid["order_dow"] = orders_valid["order_purchase_timestamp"].dt.day_name()

# Order value: item price + freight, aggregated per order
order_value = order_items.groupby("order_id").agg(
    items_count=("order_item_id", "count"),
    items_price=("price", "sum"),
    freight_value=("freight_value", "sum"),
).reset_index()
order_value["order_total_value"] = order_value["items_price"] + order_value["freight_value"]

# Master fact table: one row per order
fact_orders = (
    orders_valid
    .merge(order_value, on="order_id", how="left")
    .merge(customers, on="customer_id", how="left")
    .merge(payments.groupby("order_id").agg(
        payment_installments=("payment_installments", "max"),
        payment_type=("payment_type", lambda x: x.mode().iloc[0] if not x.mode().empty else "unknown")
    ).reset_index(), on="order_id", how="left")
    .merge(reviews[["order_id", "review_score"]], on="order_id", how="left")
)

# ------------------------------------------------------------------
# 4. RFM SEGMENTATION (Recency, Frequency, Monetary)
# ------------------------------------------------------------------
snapshot_date = fact_orders["order_purchase_timestamp"].max() + pd.Timedelta(days=1)

rfm = fact_orders.groupby("customer_unique_id").agg(
    recency=("order_purchase_timestamp", lambda x: (snapshot_date - x.max()).days),
    frequency=("order_id", "nunique"),
    monetary=("order_total_value", "sum"),
).reset_index()

rfm["r_score"] = pd.qcut(rfm["recency"], 5, labels=[5, 4, 3, 2, 1]).astype(int)
rfm["f_score"] = pd.qcut(rfm["frequency"].rank(method="first"), 5, labels=[1, 2, 3, 4, 5]).astype(int)
rfm["m_score"] = pd.qcut(rfm["monetary"], 5, labels=[1, 2, 3, 4, 5]).astype(int)
rfm["rfm_score"] = rfm["r_score"].astype(str) + rfm["f_score"].astype(str) + rfm["m_score"].astype(str)

def segment_customer(row):
    if row.r_score >= 4 and row.f_score >= 4:
        return "Champions"
    elif row.r_score >= 3 and row.f_score >= 3:
        return "Loyal Customers"
    elif row.r_score >= 4 and row.f_score <= 2:
        return "New Customers"
    elif row.r_score <= 2 and row.f_score >= 3:
        return "At Risk"
    elif row.r_score <= 2 and row.f_score <= 2:
        return "Lost"
    else:
        return "Needs Attention"

rfm["segment"] = rfm.apply(segment_customer, axis=1)

# ------------------------------------------------------------------
# 5. SELLER PERFORMANCE TABLE
# ------------------------------------------------------------------
seller_perf = (
    order_items.merge(orders_valid[["order_id", "is_late", "delivery_time_days"]], on="order_id", how="left")
    .merge(reviews[["order_id", "review_score"]], on="order_id", how="left")
    .groupby("seller_id")
    .agg(
        total_orders=("order_id", "nunique"),
        total_revenue=("price", "sum"),
        avg_review_score=("review_score", "mean"),
        late_rate=("is_late", "mean"),
        avg_delivery_days=("delivery_time_days", "mean"),
    )
    .reset_index()
    .merge(sellers, on="seller_id", how="left")
)

# ------------------------------------------------------------------
# 6. EXPORT CLEANED / MODELED TABLES (feed these into Power BI & SQL)
# ------------------------------------------------------------------
fact_orders.to_csv(OUT / "fact_orders.csv", index=False)
order_items.to_csv(OUT / "dim_order_items.csv", index=False)
products.to_csv(OUT / "dim_products.csv", index=False)
customers.to_csv(OUT / "dim_customers.csv", index=False)
sellers.to_csv(OUT / "dim_sellers.csv", index=False)
rfm.to_csv(OUT / "customer_rfm_segments.csv", index=False)
seller_perf.to_csv(OUT / "seller_performance.csv", index=False)

print("\nCleaned tables exported to data/processed/. Ready for SQL & Power BI.")

# ------------------------------------------------------------------
# 7. EXPLORATORY ANALYSIS (sample plots — extend as needed)
# ------------------------------------------------------------------
fig, axes = plt.subplots(2, 2, figsize=(14, 10))

monthly_rev = fact_orders.groupby("order_month")["order_total_value"].sum().sort_index()
monthly_rev.plot(ax=axes[0, 0], marker="o", color="#2E86AB")
axes[0, 0].set_title("Monthly Revenue Trend")
axes[0, 0].tick_params(axis="x", rotation=45)

fact_orders["review_score"].value_counts().sort_index().plot(
    kind="bar", ax=axes[0, 1], color="#F26419"
)
axes[0, 1].set_title("Review Score Distribution")

rfm["segment"].value_counts().plot(kind="barh", ax=axes[1, 0], color="#6A4C93")
axes[1, 0].set_title("Customer Segments (RFM)")

late_rate_by_month = orders_valid.groupby("order_month")["is_late"].mean().sort_index()
late_rate_by_month.plot(ax=axes[1, 1], marker="o", color="#D7263D")
axes[1, 1].set_title("Late Delivery Rate Over Time")
axes[1, 1].tick_params(axis="x", rotation=45)

plt.tight_layout()
plt.savefig(OUT / "eda_summary.png", dpi=150)
print("EDA summary chart saved to data/processed/eda_summary.png")
