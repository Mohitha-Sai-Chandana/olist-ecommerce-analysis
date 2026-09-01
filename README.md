# Olist E-Commerce Marketplace Analysis

End-to-end analysis of Olist, a Brazilian e-commerce marketplace, using SQL for data profiling and validation and Power BI (DAX) for modeling and visualization. Every headline number in the dashboard was independently calculated and verified in SQL before being rebuilt in the data model — the two are meant to be read together as one validated analysis, not two separate exercises.

## Headline finding

**96.88% of customers make only one purchase.**

This is the single most striking pattern in the dataset. Given the limited observation window, this shouldn't be read as proof of lifetime behavior — but it's a strong signal that retention, not just acquisition, is likely this marketplace's biggest growth lever.

## What's in this repo

```
├── sql/
│   └── olist_analysis.sql              # Full diagnostic and analytical SQL script
├── power-bi/
│   └── olist_dashboard.pbix            # 4-page Power BI dashboard
├── insights/
│   ├── key_findings.md                 # Full written findings, by topic
│   └── debugging_log.md                # Data modeling & DAX problems, root causes, and fixes
└── screenshots/
    ├── page1_revenue_reconciliation.png
    ├── page2_regional_delivery.png
    ├── page3_unit_economics.png
    └── page4_retention.png
```

## Dashboard structure

The dashboard is organized as four pages, each built around one specific business question rather than a loose topic grouping.

### Page 1 — Revenue Reconciliation & Category Performance
Reconciles gross payment totals against actual completed revenue, and shows what's driving the number.

![Revenue Reconciliation & Category Performance](screenshots/page1_revenue_reconciliation.png)

### Page 2 — Regional & Delivery Performance
How freight cost, delivery time, and order volume vary by state, plus overall SLA (delivery-promise) compliance.

![Regional & Delivery Performance](screenshots/page2_regional_delivery.png)

### Page 3 — Unit Economics & Transaction Dynamics
Order value, basket size distribution, and seller revenue concentration.

![Unit Economics & Transaction Dynamics](screenshots/page3_unit_economics.png)

### Page 4 — Retention & Customer Behavior
The one-time-purchase headline finding, with business recommendations.

![Retention & Customer Behavior](screenshots/page4_retention.png)

## Methodology notes

A few things worth calling out specifically, since they reflect real decisions made during the analysis rather than default choices:

- **Revenue reconciliation.** Raw payment totals (R$16.01M) overstate actual completed revenue by roughly R$589K. This gap was traced to 774 orders present in the payments table but absent from the order-items table — predominantly `cancelled` or `unavailable` orders. A left-join coverage check, an order-status breakdown of the mismatched orders, and a manual check of the one reverse-direction mismatch (an item-only order missing its payment record) were used to confirm the gap was genuine lost business rather than a timing artifact. The validated figure, R$15.42M, restricts to `delivered` orders only and is calculated from item value (price + freight), not raw payments.
- **Customer identity.** Olist's `customer_id` is unique per *order*, not per person — using it directly for repeat-purchase analysis would make every customer look like a one-time buyer by definition. `customer_unique_id` was used throughout for anything measuring real customer behavior.
- **Regional pattern, not a causal claim.** Freight cost, delivery time, and customer volume move together by state. This is presented as a correlational pattern, not a proven "distance causes delay" claim — no distance-from-hub variable was calculated, so the dashboard doesn't overstate what the data actually shows.
- **Review reliability.** Seller-level review scores are only meaningful with enough reviews behind them. Sellers with fewer than 10 reviews were excluded from ranking comparisons, to avoid one lucky or unlucky review producing a misleading 5.0 or 1.0 average.
- **Customer scoring (Recency, Frequency, Monetary).** Percentile-based, deterministic scoring — not machine-learning clustering — was built and validated for individual customers during development. A summary chart of customer counts by segment was ultimately not shippable: materializing it as a stored table triggered an out-of-memory error on the available hardware, and Power BI's chart Axis wells don't accept measures directly. Rather than force a fragile workaround, this was scoped out of the final dashboard; the full technical detail, including the root cause, is in [`insights/debugging_log.md`](insights/debugging_log.md).

## Key insights

**Revenue**
- Revenue is concentrated in a small number of product categories, which should be prioritized for inventory and promotional focus.
- A small group of top sellers drives a disproportionate share of total revenue — a concentration risk worth actively managing (support top performers, grow the mid-tier seller base).
- São Paulo dominates both seller revenue and order volume; any operational disruption there would have an outsized effect on the whole marketplace.

**Orders & delivery**
- Average delivered order value is R$159.83; customers buy an average of 1.14 items per order — most purchases are single-item, suggesting cross-sell and bundling are underused levers.
- Average delivery time is ~12 days, with only 8.11% of delivered orders arriving after the estimated delivery date.
- Freight cost, delivery time, and customer concentration move together by region — one structural story about distance from the fulfillment center, not three unrelated findings.

**Customers**
- 96.88% one-time purchase rate (see headline finding).
- Retention is likely the highest-leverage growth opportunity — converting even a modest share of one-time buyers into repeat customers would likely outperform acquisition-focused spend, since retention is typically cheaper to sustain. This is a suggested direction, not a proven conclusion from this dataset alone.

**Reviews & freight**
- Average review score is ~4.0/5; satisfaction varies by product category.
- Freight cost has only a weak correlation with review score (tested directly via a Pearson correlation coefficient computed in SQL) — shipping cost alone doesn't appear to be a major driver of customer satisfaction.

Full write-up, by topic: [`insights/key_findings.md`](key_findings.md)

## Tools

SQL Server · Power BI · DAX

## Notes on the process

The SQL analysis and the Power BI dashboard were built somewhat independently, then cross-checked against each other — every core figure in the dashboard (revenue, one-time-purchase rate, average delivery time, SLA compliance, average order value) matches the corresponding SQL query result. Several real modeling bugs were found and fixed along the way, including a backwards relationship cardinality between customers and orders, and a filter-context leak in a percentile-scoring DAX measure (`VALUES` vs `ALL`). The full debugging history — including the one problem that was worked around rather than solved — is kept intentionally in [`insights/debugging_log.md`](insights/debugging_log.md), since the diagnostic process is part of demonstrating the underlying understanding.
