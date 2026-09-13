# Data Analyst Assignment Submission — Xeno

This repository contains my assignment submission for the **Xeno Data Analyst** role. The objective was to reconcile Finance's `target_base` metric for **Merchant 501** during **October 2026** by analyzing communication logs and campaign hierarchies.

---

## What I Did (Step-by-Step)

To bridge the gap between raw communication log records and the verified metric, I investigated the dataset top-down and validated it bottom-up:

1. **Step 0: Baseline Gross Send Count (Result: 30)**  
   Queried all campaign communication records (`communication_type = '2'`) for Merchant 501 in October 2026. This naive baseline gave **30 send attempts**.

2. **Step 1: Filter for Delivered Sends Only (Result: 26)**  
   Filtered on `delivery_status = 900`. This excluded 4 soft-failed sends (status 1100 for customers C2, C3, and D1). Although these attempts consumed billing credits, they never actually reached customers and cannot count toward reached audience.

3. **Step 2: Enforce Campaign Lifecycle Governance (Result: 22)**  
   Checked campaign creation and processing statuses. To qualify for official reporting, a campaign must be fully signed off (`creation_status IN ('approved', 'aborted', 'resumed', 'stopped')`) and processed (`processing_status = 'processed'`).  
   - I discovered Campaign 9004 ran ahead of approval bookkeeping (`creation_status = 'approval_awaiting'`).  
   - Excluding its 4 delivered sends reduced the count to **22**.

4. **Step 3: Audit Retry-Chain Deduplication (Result: 22)**  
   For retry chains (Campaign families 9001 and 9201), Finance counts *distinct customers reached* across the entire parent-child hierarchy (`COUNT(DISTINCT customer_id)`).  
   - I audited delivery logs for customers C1–C10 and D1–D5.  
   - Since earlier attempts failed and only retries succeeded, each customer had exactly one successful delivery. There were zero redundant deliveries within retry chains, confirming 10 + 5 = **15 unique reached customers**.

5. **Step 4: Verify Standalone Campaign Behavior (Result: 22)**  
   Campaign 9101 is standalone (no parent, no retries). Customer C20 received two deliveries 10 days apart (Oct 10 and Oct 20).  
   - Unlike retry chains, repeat sends under a standalone campaign represent deliberate audience re-targeting events where every send counts (`COUNT(*)`).  
   - All **7 sends** legitimately qualify without deduplication.

6. **Final Validation:**  
   Both the top-down filtering query and an independent bottom-up recursive CTE arrive at the exact same figure: **22 qualifying sends** (10 from the 9001 chain + 7 standalone from 9101 + 5 from the 9201 chain).

---

## Repository Structure

```text
├── README.md                      # Assignment overview and summary (this file)
├── notebooks/
│   └── methodology.ipynb          # Step-by-step analysis, interactive SQL, and explanations
├── Answer/
│   ├── final_query.sql            # Clean, production-ready SQL queries (Top-down & Recursive CTE)
│   ├── reconciliation_bridge.pdf  # Clean 4-column reconciliation table (Step, Description, Result, Reason)
│   └── observations.pdf           # Key surprises and edge cases discovered in the data
└── data/
    ├── comm_log.db                # SQLite database with campaign and communication_log tables
    ├── campaign.csv               # Raw campaign table export
    ├── communication_log.csv      # Raw communication log table export
    └── README.md                  # Original data dictionary and schema documentation (untouched)
```

### Key Deliverables in `Answer/`
- **[`final_query.sql`](file:///s:/Data%20Analyst%20Assignment-20260913T041541Z-1-001/Data%20Analyst%20Assignment/Answer/final_query.sql)**: Contains two executable SQL queries:
  1. *Query 1 (Top-Down CTE)*: Progressively applies the business filters to return the target base.
  2. *Query 2 (Bottom-Up Recursive CTE)*: Traverses parent-child retry chains, applies the appropriate aggregation rule (distinct customers for retries vs. total sends for standalone), and provides a per-family breakdown.
- **[`reconciliation_bridge.pdf`](file:///s:/Data%20Analyst%20Assignment-20260913T041541Z-1-001/Data%20Analyst%20Assignment/Answer/reconciliation_bridge.pdf)**: A single, clean 4-column reconciliation table detailing each step, its count, and the exact business rationale.
- **[`observations.pdf`](file:///s:/Data%20Analyst%20Assignment-20260913T041541Z-1-001/Data%20Analyst%20Assignment/Answer/observations.pdf)**: Notes on surprising patterns uncovered during exploration (e.g., dual meaning of duplicate customers, pipeline running ahead of approval, branching retry trees).

### Methodology in `notebooks/`
- **[`notebooks/methodology.ipynb`](file:///s:/Data%20Analyst%20Assignment-20260913T041541Z-1-001/Data%20Analyst%20Assignment/notebooks/methodology.ipynb)**: Detailed analytical walkthrough containing:
  - Initial exploratory queries and findings.
  - Detailed cell-by-cell execution of the reconciliation bridge.
  - Recursive CTE campaign tree resolution.
  - Verification checks for all customer duplicates.

---

## How to Run & Verify

### 1. Running the Jupyter Notebook
To run through the end-to-end analysis and see interactive outputs:
```bash
jupyter notebook notebooks/methodology.ipynb
```
*(Dependencies: Python 3.8+, `sqlite3`, `pandas`, `ipython`)*

### 2. Running the SQL Queries Directly
You can run `Answer/final_query.sql` against the SQLite database from your terminal:
```bash
sqlite3 data/comm_log.db < Answer/final_query.sql
```
This will output the top-down counts (`30 -> 26 -> 22`) followed by the per-family breakdown (`9001: 10`, `9101: 7`, `9201: 5`).
