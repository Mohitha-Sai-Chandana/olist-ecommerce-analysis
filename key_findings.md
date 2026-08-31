# Key Findings — Olist E-Commerce Analysis

All figures below were calculated independently in SQL (`sql/olist_analysis.sql`) and cross-checked against the Power BI dashboard's DAX measures before being finalized.

## Headline finding

**96.88% of customers made only one purchase during the observed period.**

Given the limited observation window, this shouldn't be read as proof of lifetime behavior — but it's a strong signal that retention, not just acquisition, is likely this marketplace's biggest growth lever.

---

## Revenue

1. **Genuine, completed revenue is R$15,419,773.75 — not the R$16,008,872.12 shown by raw payment totals.** The R$589K gap comes from 774 orders present in the payments table but missing from the order-items table — predominantly `cancelled` or `unavailable` orders (verified via a LEFT JOIN coverage check and an order-status breakdown). A handful of these were in non-terminal statuses (e.g., `shipped`) and checked individually; the count was negligible (1–2 orders), confirming the gap reflects genuine lost business rather than orders still in transit when the data was extracted.
2. **Revenue is concentrated in a small number of product categories.** These should be prioritized for inventory planning and promotional focus.
3. **Seller revenue is highly uneven** — a small group of top sellers drives a disproportionate share of total revenue. This is a concentration risk: supporting high performers while actively growing the mid-tier seller base would reduce dependency on a handful of accounts.
4. **São Paulo dominates seller revenue and order volume.** Because so much marketplace activity is concentrated in one state, any operational disruption there (logistics, fulfillment, seller issues) would have an outsized effect on overall performance.

### Regional pattern (cross-cutting)

Freight cost, delivery time, and customer concentration all move together by region. States farther from São Paulo — the marketplace's operational center — show higher average freight, longer average delivery times, and fewer customers overall. This is presented as one structural regional pattern, not three unrelated findings — and specifically **as a correlation, not a proven causal claim**: no distance-from-hub variable was calculated, so "distance causes delay" was deliberately not asserted.

---

## Orders

1. **Average delivered order value is R$159.83**, calculated at the order level (not item level) to avoid underestimating spend on multi-item orders.
2. **Customers buy an average of 1.14 items per order.** Most purchases are single-item — multi-item baskets are the exception. This points to cross-sell and bundling as an underused lever.
3. Order volume grew steadily through most of the observed period before stabilizing, consistent with a maturing marketplace moving out of its early growth phase.

---

## Delivery

1. **Average delivery time is approximately 12 days.**
2. **Only 8.11% of delivered orders arrived after the estimated delivery date** — the logistics network is generally meeting the expectations it sets with customers.
3. Delivery time varies substantially by region, tying directly into the regional pattern above — remote states see materially longer average delivery windows than São Paulo and nearby states.

---

## Customers

1. **~96.88% one-time purchase rate** (see headline finding above).
2. Customer base is heavily concentrated in a handful of states, mirroring the seller/revenue concentration and reinforcing the regional dependency risk.
3. **Recommendation:** retention is likely the highest-leverage growth opportunity. Converting even a modest share of one-time buyers into repeat customers would likely outperform acquisition-focused spend, since retention is typically cheaper to sustain. This is a suggested direction, not a proven conclusion from this dataset alone.

---

## Reviews

1. **Average review score is ~4.0 out of 5** — customer satisfaction is generally positive.
2. Satisfaction varies by product category, suggesting product type itself shapes customer experience, independent of price or shipping.
3. **Methodological note:** seller ratings are only meaningful with enough reviews behind them. Sellers with fewer than 10 reviews were excluded from ranking comparisons, to avoid one lucky or unlucky review producing a misleading 5.0 or 1.0 average.

---

## Freight

1. Freight cost varies substantially by product category and by customer location — both product characteristics (size/weight) and shipping distance play a role.
2. **Freight cost has only a weak correlation with review score** (tested directly via a Pearson correlation coefficient computed in SQL). Shipping cost alone doesn't appear to be a major driver of customer satisfaction — delivery speed, product quality, and service experience likely matter more. This is a correlation, not a causal claim.

---

## Sellers

1. A small number of sellers account for a disproportionate share of both orders and revenue — consistent with the revenue concentration finding above.
2. Sellers with consistently poor ratings (and a sufficient review count, ≥10) can be identified for targeted support or stricter marketplace standards.

---

## Business recommendations

1. **Invest in retention over pure acquisition.** Targeted re-engagement campaigns for one-time buyers, given retention is typically cheaper to sustain than acquiring new customers.
2. **Formalize account management for top-performing sellers**, to reduce dependency risk on a small number of accounts.
3. **Monitor underperforming sellers more closely**, using review score and delivery performance data, for targeted intervention or stricter standards.
4. These recommendations are directional, based on patterns observed in this dataset's limited time window — they are not proven conclusions and would benefit from further testing (e.g., an A/B test of a retention campaign) before being acted on at scale.
