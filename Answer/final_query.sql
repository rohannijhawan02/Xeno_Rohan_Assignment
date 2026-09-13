-- ============================================================
-- Target Base Reconciliation — Merchant 501, October 2026
-- Run against: data/comm_log.db
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- QUERY 1: Top-Down Reconciliation (Steps 0–2 as CTE)
-- ────────────────────────────────────────────────────────────
--
-- Starts with all raw communication-log rows and progressively
-- applies the three reporting filters:
--   Step 0 → Count all campaign sends
--   Step 1 → Keep only successful deliveries (delivery_status = 900)
--   Step 2 → Exclude non-reportable campaigns (creation_status check)
--
-- The final CTE output IS the target_base answer.

WITH

-- Step 0: All campaign sends for merchant 501, Oct 2026
step0_all_rows AS (
    SELECT *
    FROM communication_log
    WHERE merchant_id = 501
      AND communication_type = '2'
      AND sent_time >= '2026-10-01'
      AND sent_time <  '2026-11-01'
),

-- Step 1: Keep only successful deliveries
step1_delivered AS (
    SELECT *
    FROM step0_all_rows
    WHERE delivery_status = 900
),

-- Step 2: Keep only sends from reportable campaigns
step2_reportable AS (
    SELECT l.*
    FROM step1_delivered AS l
    JOIN campaign AS c
        ON c.id = l.communication_id
    WHERE c.creation_status IN ('approved', 'aborted', 'resumed', 'stopped')
      AND c.processing_status = 'processed'
)

SELECT
    (SELECT COUNT(*) FROM step0_all_rows)    AS step0_all_rows,
    (SELECT COUNT(*) FROM step1_delivered)    AS step1_delivered,
    (SELECT COUNT(*) FROM step2_reportable)   AS step2_target_base;

-- Expected result:
--   step0_all_rows = 30
--   step1_delivered = 26
--   step2_target_base = 22


-- ────────────────────────────────────────────────────────────
-- QUERY 2: Bottom-Up Verification (Recursive CTE)
-- ────────────────────────────────────────────────────────────
--
-- Implements the Finance business definition:
--   • Retry chain → COUNT(DISTINCT customer_id) per chain root
--   • Standalone campaign → COUNT(*) (every send is its own event)
--
-- Uses a recursive CTE to walk the campaign.parent_id chain
-- and resolve each campaign to its root.

WITH RECURSIVE campaign_roots AS (

    /* Base: campaigns with no parent are their own root */
    SELECT
        id AS campaign_id,
        id AS root_id
    FROM campaign
    WHERE parent_id IS NULL

    UNION ALL

    /* Recursive: follow the retry chain */
    SELECT
        c.id AS campaign_id,
        cr.root_id
    FROM campaign AS c
    JOIN campaign_roots AS cr
        ON c.parent_id = cr.campaign_id
),

eligible_sends AS (

    SELECT
        l.communication_id,
        l.customer_id,
        cr.root_id,

        CASE
            WHEN c.parent_id IS NULL
             AND NOT EXISTS (
                 SELECT 1
                 FROM campaign AS child
                 WHERE child.parent_id = c.id
             )
            THEN 1
            ELSE 0
        END AS is_standalone

    FROM communication_log AS l

    JOIN campaign AS c
        ON c.id = l.communication_id

    JOIN campaign_roots AS cr
        ON cr.campaign_id = c.id

    WHERE l.merchant_id = 501
      AND l.communication_type = '2'
      AND l.sent_time >= '2026-10-01'
      AND l.sent_time <  '2026-11-01'
      AND l.delivery_status = 900

      AND c.creation_status IN (
          'approved',
          'aborted',
          'resumed',
          'stopped'
      )
      AND c.processing_status = 'processed'
),

family_counts AS (

    SELECT
        root_id,

        CASE
            WHEN MAX(is_standalone) = 1
                THEN COUNT(*)
            ELSE COUNT(DISTINCT customer_id)
        END AS qualifying_sends

    FROM eligible_sends
    GROUP BY root_id
)

-- Per-family breakdown
SELECT root_id, qualifying_sends
FROM family_counts
ORDER BY root_id;

-- Expected result:
--   root_id    qualifying_sends
--   --------   ----------------
--   9001       10
--   9101        7
--   9201        5

-- Final total (change the last SELECT to):
-- SELECT SUM(qualifying_sends) AS target_base FROM family_counts;
-- → target_base = 22
