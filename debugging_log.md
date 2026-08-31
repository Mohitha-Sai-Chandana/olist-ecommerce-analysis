# Debugging Log — Data Modeling & DAX Problems

This document records the real problems hit while building the Power BI side of this project, how each was diagnosed and fixed, and what the final model actually contains. It's kept as a genuine debugging/methodology record rather than a polished summary, since the diagnostic process is part of demonstrating the underlying understanding — including the one problem that was ultimately worked around rather than solved.

---

## Part 1: Data Modeling Problems

### 1.1 Date/Time vs Date mismatch breaking the revenue trend line
**Symptom:** A line chart of Total Revenue by Year-Month showed almost all revenue collapsed into a single "(Blank)" category, with only one real data point.

**Root cause:** `orders[order_purchase_timestamp]` was typed as **Date/Time** (includes hours/minutes/seconds), while the custom Date table's `Date` column was pure **Date**. Power BI relationships need matching granularity — a timestamp like `2018-06-07 10:06:19` doesn't match a date value of `2018-06-07`, so almost every row failed to join to the Date table.

**Fix:** Changed `order_purchase_timestamp`'s data type from Date/Time to Date in Power Query, at the source.

**Lesson:** "Looks the same" formatting in the UI doesn't mean the same underlying data type. Always check the actual Data Type property, not just how a column displays.

---

### 1.2 Grain mismatch: `payment_value` sliced by category
**Symptom:** A bar chart of Total Revenue by product category showed the exact same total revenue figure repeated for every single category bar.

**Root cause:** The `Total Revenue` measure summed `order_payments[payment_value]`, which exists at the **order** level (one row per payment). Category lives at the **order_items/product** level. Payments aren't split by item or category in the raw data, so filtering by category had no way to reach or restrict the payments table — the chart just showed the full, unfiltered total every time.

**Fix:** Created a second measure, `Total Revenue (Items)`, based on `order_items[price] + order_items[freight_value]` — genuinely item/category-level data — and used that measure for anything sliced by category, product, or seller. Kept the payment-based measure only for order-level, non-category-sliced totals.

**Lesson:** "Revenue" isn't one universal number — which table it's summed from determines what it can correctly be broken down by. Check the grain of the slicing dimension against the grain of the measure's source table before building.

---

### 1.3 Missing `customers ↔ orders` relationship entirely
**Symptom:** Every chart sliced by `customer_state` (avg delivery time, avg freight cost, total orders) showed the exact same value for every single state.

**Root cause:** The `customers` table had a relationship to `geolocation`, but no relationship at all to `orders` — it had simply never been built.

**Fix:** Manually created the relationship (`customers[customer_id]` to `orders[customer_id]`).

**Side effect:** This introduced an ambiguous-path warning, since two routes now existed from `order_items` to `geolocation` (via `customers`, and via `sellers`). Resolved by setting `sellers ↔ geolocation` to inactive, keeping `customers ↔ geolocation` active.

**Lesson:** A relationship existing elsewhere in the model diagram doesn't mean every table you'd expect to be connected actually is.

---

### 1.4 Wrong cardinality: `customers ↔ orders` initially built backwards
**Symptom:** After manually drawing the relationship, Power BI's auto-detected cardinality showed `customers` as "many" and `orders` as "one" — reversed from expectation — and manually editing it threw a duplicate-value error.

**Root cause investigation:** `customer_id` was confirmed unique in **both** `customers` and `orders` — Olist generates a fresh `customer_id` per order, even for repeat customers. The genuinely duplicated column is `customer_unique_id`, which identifies the real person.

**Fix:** Since `customer_id` is unique on both sides, the correct relationship type is **1-to-1**, with cross-filter direction set to **Both**.

**Lesson:** Don't assume a relationship type based on what it "sounds like." Check the actual grain of each table — `customers` and `orders` were effectively the same grain here (one row per order), just split into two tables.

---

### 1.5 `customer_id` vs `customer_unique_id`
Recurring distinction throughout the project. `customer_id` is unique per **order**; `customer_unique_id` identifies the actual **person** and repeats across their orders. `customer_unique_id` was used for all repeat-purchase and customer-behavior analysis; `customer_id` was kept only for the join to `orders`.

---

## Part 2: DAX Problems

### 2.1 Calculated column placed in an empty table
**Symptom:** A new column (`Items In Order`) showed 0 rows and produced nothing on any chart.

**Root cause:** The column was created while `measures_table` (an empty placeholder table used to hold measures) was selected, instead of the real data table. Calculated columns compute once per row of their home table — an empty table has no rows to compute against.

**Fix:** Recreated the column with `order_items` explicitly selected first.

**Lesson:** Measures can live anywhere; calculated columns cannot. A calculated column's home table determines what data it's actually calculated against.

---

### 2.2 `Items In Order` — basket-size histogram
```dax
Items In Order =
CALCULATE(
    COUNTROWS(order_items),
    ALLEXCEPT(order_items, order_items[order_id])
)
```
- `ALLEXCEPT(order_items, order_items[order_id])` removes every filter on `order_items` except the one on `order_id` — so for the row being calculated, the count is restricted to "only rows sharing this same order_id."
- Net effect, per row: how many items were in this row's order. Every row in the same order ends up with the same value.

```dax
Order Count by Basket Size = DISTINCTCOUNT(order_items[order_id])
```
Used as the chart's Values field, counting distinct orders (not item-rows), so a 3-item order isn't triple-counted.

Chart setup: Bar chart, Axis = `Items In Order` (column), Values = `Order Count by Basket Size` (measure).

---

### 2.3 Revenue Waterfall — manual reference table
Power BI's native Waterfall visual needs a category column to step through; nothing in the raw data represents "waterfall steps," so a small manual table was built.

```dax
Revenue Waterfall =
DATATABLE(
    "Category", STRING,
    "SortOrder", INTEGER,
    {
        {"Raw Payment Total", 1},
        {"Cancelled/Unfulfilled Orders", 2},
        {"Delivered Revenue", 3}
    }
)
```
`DATATABLE` hand-types a small table directly into a formula. `SortOrder` exists purely so the three steps display left-to-right in logical order rather than alphabetically.

```dax
Waterfall Value =
SWITCH(
    SELECTEDVALUE('Revenue Waterfall'[Category]),
    "Raw Payment Total", [Raw Payment Total],
    "Cancelled/Unfulfilled Orders", -[Revenue Leakage],
    "Delivered Revenue", [Total Revenue (Items)],
    BLANK()
)
```
`SELECTEDVALUE` returns whichever category the chart is currently rendering; `SWITCH` returns the matching measure. The middle step is returned as a negative number so the waterfall visually drops rather than rises.

Supporting measures:
```dax
Raw Payment Total = SUM(order_payments[payment_value])
Revenue Leakage = [Raw Payment Total] - [Total Revenue (Items)]
```

---

### 2.4 `VALUES` vs `ALL` — a percentile-scoring context leak
**Symptom:** A `Recency Score` measure, intended to rank each customer 1–5 by percentile position, returned the same score (5) for every customer — including customers with obviously poor recency (770+ days since last purchase).

**First (broken) version** used `VALUES(customers[customer_unique_id])` inside a temporary table built with `ADDCOLUMNS`, to calculate percentile thresholds.

**Diagnosis:** A debug measure returning the percentile threshold values as text, placed inside the same per-customer table, showed that for a customer with Recency = 773, the computed thresholds were *also* 773 — the "all customers" table inside the formula was actually only containing that one customer.

**Root cause:** `VALUES(...)`, evaluated inside row context (a table visual with `customer_unique_id` as a row), respects the *existing* filter from that row — it returned a table of just the current customer, not the full customer base. The percentile calculation compared each customer only to themselves, so every comparison trivially passed and every score defaulted to 5.

**Fix:** Replaced `VALUES(...)` with `ALL(customers[customer_unique_id])`, which explicitly strips existing filters, forcing the calculation to use the full, unfiltered customer list regardless of row context.

**Working structure (illustrative — see Part 3 for the model's final state):**
```dax
Recency Score =
VAR CurrentRecency = [Customer Recency]
VAR RecencyTable =
    ADDCOLUMNS(
        ALL(customers[customer_unique_id]),
        "RecencyVal", [Customer Recency]
    )
VAR P20 = PERCENTILEX.INC(RecencyTable, [RecencyVal], 0.2)
VAR P40 = PERCENTILEX.INC(RecencyTable, [RecencyVal], 0.4)
VAR P60 = PERCENTILEX.INC(RecencyTable, [RecencyVal], 0.6)
VAR P80 = PERCENTILEX.INC(RecencyTable, [RecencyVal], 0.8)
RETURN
SWITCH(
    TRUE(),
    CurrentRecency <= P20, 5,
    CurrentRecency <= P40, 4,
    CurrentRecency <= P60, 3,
    CurrentRecency <= P80, 2,
    1
)
```
Scoring direction is reversed for Recency specifically (lower days = better), opposite of Frequency and Monetary (higher = better).

**Lesson:** `VALUES` respects filters already in place; `ALL` strips them. Any formula that needs to compare one row against "everyone, regardless of context" requires `ALL` — using `VALUES` inside row-level context can silently shrink "everyone" down to just the current row.

---

### 2.5 Out-of-memory crash building a full customer-level RFM table
**Symptom:** Attempting to build a stored summary table (`SUMMARIZE` over `customers`, computing Recency/Frequency/Monetary values and their percentile scores as six columns per customer) ran for several minutes, then failed with: *"There's not enough memory to complete this operation."*

**Root cause:** Each of the three score measures independently rebuilds a full ~96,000-row temporary table every time it's evaluated (the `ADDCOLUMNS(ALL(...), ...)` pattern from 2.4). `SUMMARIZE` forces all six columns to be calculated and physically stored for all ~96,000 customers at once — meaning three separate ~96K-row temporary tables were being rebuilt, per customer, for 96,000 customers. The cost compounds multiplicatively rather than staying linear, and exceeded available RAM.

**Resolution:** The stored-table approach was abandoned. A chart summarizing customer counts per RFM segment was not built as a result — this is a genuine, unresolved limitation of the approach on the available hardware, not something worked around. The individual score measures (2.4) worked correctly and cheaply when evaluated live, one customer at a time, inside a Table visual with row context; that is not the same as being safe to force into a single pre-materialized table at scale.

**Lesson:** Measures that are individually cheap when evaluated once can become extremely expensive when an operation forces them to be recalculated for every row of a large table simultaneously. A pattern that works fine live, on demand, inside a visual is not automatically safe to bake into a stored table at scale.

---

### 2.6 Measures cannot be dropped onto a chart's Axis field
**Symptom:** Dragging a text-returning segment measure into a Bar/Column chart's Axis well was rejected outright, or silently redirected to the Tooltips well instead.

**Root cause:** Axis wells on standard chart types expect columns (real, stored category values) — they cannot group by a measure, which only ever returns one calculated value at a time and has no fixed list of categories for Power BI to enumerate ahead of time.

**Lesson:** Whether a chart type's field wells accept measures or only columns depends on the specific well and chart type — worth testing on a small scale before investing in a specific chart design.

---

## Part 3: Final state of the model

**RFM scoring — what's actually in the file today.** `Customer Recency`, `Customer Frequency`, and `Customer Monetary` (the underlying per-customer metrics, not the percentile scores) remain in the model. The percentile-based `Recency Score` / `Frequency Score` / `Monetary Score` measures described in 2.4, along with `RFM Total Score` and `RFM Segment`, were built, debugged, and validated correctly during development — then deliberately removed from the final model once it became clear they had no working visual home (2.5, 2.6) and the dashboard's Page 4 was redesigned around the validated one-time-purchase-rate finding instead. They are not present in the current `.pbix` file; this log documents the technique, not the current state of the Fields pane.

**Retained, in the final model:**
- Revenue, order, delivery, and freight measures (Sections 1.2, 2.3)
- The Revenue Waterfall table and its supporting measures (2.3)
- `Items In Order` and `Order Count by Basket Size` (2.2)
- `Total Unique Customers`, `One-Time Customers`, `% One-Time Purchase Rate`, `Repeat Customers`
- All relationships as corrected in Part 1

---

## Summary — what was decided against, and why

| Feature | Decision | Reason |
|---|---|---|
| Distance-from-São Paulo as a calculated variable | Not built | Would have required a Haversine distance calculation; kept the regional pattern honestly correlational instead of implying unproven causation |
| RFM segment count/bar chart | Dropped | `SUMMARIZE`-based stored table caused an out-of-memory crash; measures can't populate a chart Axis directly |
| RFM scoring measures in the final model | Removed | Built and validated during development, but had no working visual output after 2.5/2.6 — kept out of the final file rather than left unused |
| Churn flag measure (90-day rule) | Dropped | Lower priority than fixing the core RFM measures; the validated 96.88% one-time-purchase rate already carries the retention narrative |
| Seller on-time shipping % | Dropped early | Would have required restoring `shipping_limit_date`, previously removed during data cleanup; judged not essential to the seller-performance story |
