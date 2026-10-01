-- =====================================================================
-- Airbnb Property Booking & Reservation Management Database
-- DBMS TAE 2 | queries.sql (MySQL 8.0)
-- Covers: joins (inner/outer/self), correlated subqueries, aggregates,
-- 1 stored procedure, 2 triggers, 2 views, 2 EXPLAIN ANALYZE benchmarks
-- =====================================================================

-- =====================================================================
-- SECTION 1: MULTI-TABLE JOINS
-- =====================================================================

-- 1a. INNER JOIN — every booking with its guest, property, and host
SELECT g.Name AS guest, p.Title AS property, h.Name AS host,
       b.CheckIn_Date, b.CheckOut_Date, b.Booking_Status
FROM BOOKING b
INNER JOIN GUEST g    ON b.Guest_ID = g.Guest_ID
INNER JOIN PROPERTY p ON b.Property_ID = p.Property_ID
INNER JOIN HOST h     ON p.Host_ID = h.Host_ID
ORDER BY b.CheckIn_Date DESC
LIMIT 20;

-- 1b. OUTER JOIN (LEFT) — every property, including ones never booked
SELECT p.Title, p.Location, COUNT(b.Booking_ID) AS total_bookings
FROM PROPERTY p
LEFT JOIN BOOKING b ON p.Property_ID = b.Property_ID
GROUP BY p.Property_ID, p.Title, p.Location
ORDER BY total_bookings ASC;

-- 1c. OUTER JOIN (LEFT, direction reversed with RIGHT semantics) —
--     every host, including ones whose properties have zero reviews
SELECT h.Name AS host, p.Title AS property, r.Rating
FROM PROPERTY p
LEFT JOIN HOST h  ON h.Host_ID = p.Host_ID
LEFT JOIN REVIEW r ON r.Property_ID = p.Property_ID
WHERE r.Review_ID IS NULL
ORDER BY h.Name;

-- 1d. SELF JOIN — pairs of guests who booked the SAME property
--     (peer discovery: b1 and b2 are two aliases of BOOKING)
SELECT DISTINCT g1.Name AS guest_a, g2.Name AS guest_b, p.Title AS property
FROM BOOKING b1
JOIN BOOKING b2 ON b1.Property_ID = b2.Property_ID AND b1.Guest_ID < b2.Guest_ID
JOIN GUEST g1 ON g1.Guest_ID = b1.Guest_ID
JOIN GUEST g2 ON g2.Guest_ID = b2.Guest_ID
JOIN PROPERTY p ON p.Property_ID = b1.Property_ID
ORDER BY p.Title
LIMIT 20;

-- 1e. SELF JOIN — hosts who own more than one property, paired up
--     (join PROPERTY to itself via two aliases sharing the same Host_ID)
SELECT h.Name AS host, pr1.Title AS property_a, pr2.Title AS property_b
FROM PROPERTY pr1
JOIN PROPERTY pr2 ON pr1.Host_ID = pr2.Host_ID AND pr1.Property_ID < pr2.Property_ID
JOIN HOST h ON h.Host_ID = pr1.Host_ID
ORDER BY h.Name
LIMIT 20;

-- =====================================================================
-- SECTION 2: CORRELATED SUBQUERIES + AGGREGATES (GROUP BY / HAVING)
-- =====================================================================

-- 2a. Correlated subquery — guests whose booking count exceeds the
--     average number of bookings per guest
SELECT g.Guest_ID, g.Name,
       (SELECT COUNT(*) FROM BOOKING b WHERE b.Guest_ID = g.Guest_ID) AS booking_count
FROM GUEST g
WHERE (SELECT COUNT(*) FROM BOOKING b WHERE b.Guest_ID = g.Guest_ID) >
      (SELECT AVG(cnt) FROM (SELECT COUNT(*) AS cnt FROM BOOKING GROUP BY Guest_ID) sub)
ORDER BY booking_count DESC;

-- 2b. Correlated subquery — the highest-earning property for each host
--     (top property per host by total completed-booking revenue)
SELECT h.Name AS host, p.Title AS property,
       (SELECT COALESCE(SUM(b.Total_Amount), 0) FROM BOOKING b
        WHERE b.Property_ID = p.Property_ID AND b.Booking_Status = 'Completed') AS revenue
FROM PROPERTY p
JOIN HOST h ON h.Host_ID = p.Host_ID
WHERE (SELECT COALESCE(SUM(b.Total_Amount), 0) FROM BOOKING b
       WHERE b.Property_ID = p.Property_ID AND b.Booking_Status = 'Completed') =
      (SELECT MAX(rev) FROM (
           SELECT p2.Property_ID,
                  (SELECT COALESCE(SUM(b2.Total_Amount), 0) FROM BOOKING b2
                   WHERE b2.Property_ID = p2.Property_ID AND b2.Booking_Status = 'Completed') AS rev
           FROM PROPERTY p2 WHERE p2.Host_ID = p.Host_ID
       ) host_max)
ORDER BY revenue DESC;

-- 2c. Aggregate + GROUP BY / HAVING — properties with an average rating
--     below 3, at least 3 reviews (candidates for host follow-up)
SELECT p.Title, COUNT(r.Review_ID) AS review_count, ROUND(AVG(r.Rating), 2) AS avg_rating
FROM PROPERTY p
JOIN REVIEW r ON r.Property_ID = p.Property_ID
GROUP BY p.Property_ID, p.Title
HAVING COUNT(r.Review_ID) >= 3 AND AVG(r.Rating) < 3
ORDER BY avg_rating ASC;

-- 2d. Aggregate + GROUP BY / HAVING — hosts earning more than 50,000 in
--     successful payments (top-performing hosts report)
SELECT h.Name AS host, COUNT(DISTINCT b.Booking_ID) AS completed_bookings,
       SUM(pay.Amount) AS total_revenue
FROM HOST h
JOIN PROPERTY p ON p.Host_ID = h.Host_ID
JOIN BOOKING b ON b.Property_ID = p.Property_ID
JOIN PAYMENT pay ON pay.Booking_ID = b.Booking_ID
WHERE pay.Payment_Status = 'Successful'
GROUP BY h.Host_ID, h.Name
HAVING SUM(pay.Amount) > 50000
ORDER BY total_revenue DESC;

-- =====================================================================
-- SECTION 3: STORED PROCEDURE — operational transaction
-- Creates a booking AND its mandatory 1:1 payment record atomically,
-- exactly the "book a property + record payment" transaction from TAE 1.
-- =====================================================================
DELIMITER $$

CREATE PROCEDURE create_booking_with_payment(
    IN p_guest_id     INT,
    IN p_property_id  INT,
    IN p_checkin      DATE,
    IN p_checkout     DATE,
    IN p_no_of_guests INT,
    IN p_method       VARCHAR(30)
)
BEGIN
    DECLARE v_price DECIMAL(10,2);
    DECLARE v_total DECIMAL(10,2);
    DECLARE v_booking_id INT;

    IF NOT EXISTS (SELECT 1 FROM GUEST WHERE Guest_ID = p_guest_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Guest does not exist';
    END IF;
    IF NOT EXISTS (SELECT 1 FROM PROPERTY WHERE Property_ID = p_property_id) THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Property does not exist';
    END IF;

    SELECT Price_per_night INTO v_price FROM PROPERTY WHERE Property_ID = p_property_id;
    SET v_total = v_price * DATEDIFF(p_checkout, p_checkin);

    START TRANSACTION;

    INSERT INTO BOOKING (Guest_ID, Property_ID, CheckIn_Date, CheckOut_Date,
                          No_of_Guests, Total_Amount, Booking_Status)
    VALUES (p_guest_id, p_property_id, p_checkin, p_checkout, p_no_of_guests, v_total, 'Pending');

    SET v_booking_id = LAST_INSERT_ID();

    INSERT INTO PAYMENT (Booking_ID, Amount, Payment_Method, Payment_Status)
    VALUES (v_booking_id, v_total, p_method, 'Pending');

    COMMIT;

    SELECT v_booking_id AS new_booking_id, v_total AS total_amount;
END$$

DELIMITER ;

-- Example call:
-- CALL create_booking_with_payment(12, 7, '2026-11-10', '2026-11-14', 2, 'UPI');

-- =====================================================================
-- SECTION 4: TRIGGERS — automated business rules from TAE 1
-- =====================================================================

-- 4a. Enforce "a property cannot have overlapping bookings for the same
--     dates" — a cross-row rule that only a trigger (not a CHECK) can express.
DELIMITER $$

CREATE TRIGGER trg_prevent_overlap
BEFORE INSERT ON BOOKING
FOR EACH ROW
BEGIN
    DECLARE v_conflicts INT;

    SELECT COUNT(*) INTO v_conflicts
    FROM BOOKING b
    WHERE b.Property_ID = NEW.Property_ID
      AND b.Booking_Status IN ('Pending', 'Confirmed', 'Completed')
      AND NEW.CheckIn_Date < b.CheckOut_Date
      AND NEW.CheckOut_Date > b.CheckIn_Date;

    IF v_conflicts > 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Overlapping booking: this property is already booked for part of the requested date range';
    END IF;
END$$

DELIMITER ;

-- 4b. Enforce "a guest can submit a review only after completing a
--     booking for that property" + keep PROPERTY.Availability_Status in
--     sync whenever a booking is confirmed or cancelled (dynamic audit
--     of status changes via a companion audit table).
CREATE TABLE IF NOT EXISTS BOOKING_STATUS_AUDIT (
    Audit_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Booking_ID  INT NOT NULL,
    Old_Status  VARCHAR(20),
    New_Status  VARCHAR(20),
    Changed_At  TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DELIMITER $$

CREATE TRIGGER trg_review_requires_completed_stay
BEFORE INSERT ON REVIEW
FOR EACH ROW
BEGIN
    DECLARE v_stayed INT;

    SELECT COUNT(*) INTO v_stayed
    FROM BOOKING b
    WHERE b.Guest_ID = NEW.Guest_ID
      AND b.Property_ID = NEW.Property_ID
      AND b.Booking_Status = 'Completed';

    IF v_stayed = 0 THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Guest can only review a property after a completed booking there';
    END IF;
END$$

CREATE TRIGGER trg_booking_status_audit
BEFORE UPDATE ON BOOKING
FOR EACH ROW
BEGIN
    IF NEW.Booking_Status <> OLD.Booking_Status THEN
        INSERT INTO BOOKING_STATUS_AUDIT (Booking_ID, Old_Status, New_Status)
        VALUES (OLD.Booking_ID, OLD.Booking_Status, NEW.Booking_Status);

        IF NEW.Booking_Status = 'Confirmed' THEN
            UPDATE PROPERTY SET Availability_Status = 'Booked' WHERE Property_ID = NEW.Property_ID;
        ELSEIF NEW.Booking_Status = 'Cancelled' THEN
            UPDATE PROPERTY SET Availability_Status = 'Available' WHERE Property_ID = NEW.Property_ID;
        END IF;
    END IF;
END$$

DELIMITER ;

-- =====================================================================
-- SECTION 5: VIEWS for business reporting
-- =====================================================================

-- 5a. Host revenue & performance report
CREATE OR REPLACE VIEW vw_host_performance AS
SELECT h.Host_ID,
       h.Name,
       COUNT(DISTINCT p.Property_ID) AS total_properties,
       COUNT(DISTINCT CASE WHEN b.Booking_Status = 'Completed' THEN b.Booking_ID END) AS completed_bookings,
       COALESCE(SUM(CASE WHEN pay.Payment_Status = 'Successful' THEN pay.Amount ELSE 0 END), 0) AS total_revenue,
       ROUND(AVG(r.Rating), 2) AS avg_property_rating
FROM HOST h
LEFT JOIN PROPERTY p ON p.Host_ID = h.Host_ID
LEFT JOIN BOOKING b ON b.Property_ID = p.Property_ID
LEFT JOIN PAYMENT pay ON pay.Booking_ID = b.Booking_ID
LEFT JOIN REVIEW r ON r.Property_ID = p.Property_ID
GROUP BY h.Host_ID, h.Name;

-- 5b. Property booking & review health report
CREATE OR REPLACE VIEW vw_property_health AS
SELECT p.Property_ID,
       p.Title,
       p.Location,
       p.Availability_Status,
       COUNT(DISTINCT b.Booking_ID) AS total_bookings,
       COUNT(DISTINCT CASE WHEN b.Booking_Status = 'Cancelled' THEN b.Booking_ID END) AS cancelled_bookings,
       ROUND(AVG(r.Rating), 2) AS avg_rating,
       COUNT(DISTINCT r.Review_ID) AS review_count
FROM PROPERTY p
LEFT JOIN BOOKING b ON b.Property_ID = p.Property_ID
LEFT JOIN REVIEW r ON r.Property_ID = p.Property_ID
GROUP BY p.Property_ID, p.Title, p.Location, p.Availability_Status;

-- Usage:
-- SELECT * FROM vw_host_performance ORDER BY total_revenue DESC LIMIT 10;
-- SELECT * FROM vw_property_health ORDER BY avg_rating DESC LIMIT 10;

-- =====================================================================
-- SECTION 6: PERFORMANCE TUNING — EXPLAIN ANALYZE before/after indexing
-- =====================================================================

-- ---- Benchmark Query A: check property availability for a date range
-- (mirrors the TAE 1 transaction: "search properties based on ...
--  availability" and the overlap check the trigger performs)

-- BEFORE: only the single-column idx_booking_property exists
EXPLAIN ANALYZE
SELECT Booking_ID, CheckIn_Date, CheckOut_Date, Booking_Status
FROM BOOKING
WHERE Property_ID = 15
  AND Booking_Status IN ('Pending', 'Confirmed', 'Completed')
  AND CheckIn_Date < '2026-12-20'
  AND CheckOut_Date > '2026-12-10';

-- Composite index matching the exact overlap-check filter pattern
CREATE INDEX idx_booking_property_dates
    ON BOOKING (Property_ID, Booking_Status, CheckIn_Date, CheckOut_Date);

-- AFTER: planner should switch from a full table/range scan to a
-- narrow index range scan on the composite index
EXPLAIN ANALYZE
SELECT Booking_ID, CheckIn_Date, CheckOut_Date, Booking_Status
FROM BOOKING
WHERE Property_ID = 15
  AND Booking_Status IN ('Pending', 'Confirmed', 'Completed')
  AND CheckIn_Date < '2026-12-20'
  AND CheckOut_Date > '2026-12-10';

-- ---- Benchmark Query B: guest booking history report
-- (mirrors "generate booking history ... reports")

-- BEFORE: idx_booking_guest exists (single column) but ORDER BY still sorts
EXPLAIN ANALYZE
SELECT Booking_ID, Property_ID, CheckIn_Date, Booking_Status
FROM BOOKING
WHERE Guest_ID = 42
ORDER BY CheckIn_Date DESC;

-- Composite index covers both the filter and the sort
CREATE INDEX idx_booking_guest_checkin
    ON BOOKING (Guest_ID, CheckIn_Date DESC);

-- AFTER: planner should use the composite index and skip a separate sort
EXPLAIN ANALYZE
SELECT Booking_ID, Property_ID, CheckIn_Date, Booking_Status
FROM BOOKING
WHERE Guest_ID = 42
ORDER BY CheckIn_Date DESC;
