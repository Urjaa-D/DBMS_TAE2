DROP TABLE IF EXISTS REVIEW;
DROP TABLE IF EXISTS PAYMENT;
DROP TABLE IF EXISTS BOOKING;
DROP TABLE IF EXISTS PROPERTY;
DROP TABLE IF EXISTS GUEST;
DROP TABLE IF EXISTS HOST;

CREATE TABLE HOST (
    Host_ID     INT AUTO_INCREMENT PRIMARY KEY,
    Name        VARCHAR(100) NOT NULL,
    Email       VARCHAR(100) NOT NULL,
    Phone       VARCHAR(15)  NOT NULL,
    Password    VARCHAR(255) NOT NULL,
    Join_Date   DATE NOT NULL DEFAULT (CURRENT_DATE)
) ENGINE=InnoDB;

ALTER TABLE HOST
    ADD CONSTRAINT uq_host_email UNIQUE (Email);

ALTER TABLE HOST
    ADD CONSTRAINT chk_host_email_format
    CHECK (Email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');

ALTER TABLE HOST
    ADD CONSTRAINT chk_host_phone_format
    CHECK (Phone REGEXP '^[+]?[0-9]{10,15}$');

CREATE TABLE GUEST (
    Guest_ID    INT AUTO_INCREMENT PRIMARY KEY,
    Name        VARCHAR(100) NOT NULL,
    Email       VARCHAR(100) NOT NULL,
    Phone       VARCHAR(15)  NOT NULL,
    Password    VARCHAR(255) NOT NULL,
    Join_Date   DATE NOT NULL DEFAULT (CURRENT_DATE)
) ENGINE=InnoDB;

ALTER TABLE GUEST
    ADD CONSTRAINT uq_guest_email UNIQUE (Email);

ALTER TABLE GUEST
    ADD CONSTRAINT chk_guest_email_format
    CHECK (Email REGEXP '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}$');

ALTER TABLE GUEST
    ADD CONSTRAINT chk_guest_phone_format
    CHECK (Phone REGEXP '^[+]?[0-9]{10,15}$');

CREATE TABLE PROPERTY (
    Property_ID          INT AUTO_INCREMENT PRIMARY KEY,
    Host_ID              INT NOT NULL,
    Title                VARCHAR(150) NOT NULL,
    Description          TEXT,
    Location             VARCHAR(150) NOT NULL,
    Price_per_night      DECIMAL(10,2) NOT NULL,
    Property_Type        VARCHAR(50) NOT NULL,
    Amenities            VARCHAR(255),
    Availability_Status  VARCHAR(20) NOT NULL DEFAULT 'Available'
) ENGINE=InnoDB;

ALTER TABLE PROPERTY
    ADD CONSTRAINT chk_property_price_positive
    CHECK (Price_per_night > 0);

ALTER TABLE PROPERTY
    ADD CONSTRAINT chk_property_type
    CHECK (Property_Type IN ('Apartment', 'House', 'Villa', 'Cabin', 'Cottage', 'Studio'));

ALTER TABLE PROPERTY
    ADD CONSTRAINT chk_property_availability
    CHECK (Availability_Status IN ('Available', 'Booked', 'Under Maintenance', 'Inactive'));

ALTER TABLE PROPERTY
    ADD CONSTRAINT fk_property_host
    FOREIGN KEY (Host_ID) REFERENCES HOST (Host_ID)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;

CREATE TABLE BOOKING (
    Booking_ID       INT AUTO_INCREMENT PRIMARY KEY,
    Guest_ID         INT NOT NULL,
    Property_ID      INT NOT NULL,
    CheckIn_Date     DATE NOT NULL,
    CheckOut_Date    DATE NOT NULL,
    No_of_Guests     INT NOT NULL DEFAULT 1,
    Total_Amount     DECIMAL(10,2) NOT NULL,
    Booking_Status   VARCHAR(20) NOT NULL DEFAULT 'Pending',
    Created_At       TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

ALTER TABLE BOOKING
    ADD CONSTRAINT chk_booking_dates
    CHECK (CheckOut_Date > CheckIn_Date);

ALTER TABLE BOOKING
    ADD CONSTRAINT chk_booking_guests_positive
    CHECK (No_of_Guests > 0);

ALTER TABLE BOOKING
    ADD CONSTRAINT chk_booking_amount_positive
    CHECK (Total_Amount > 0);

ALTER TABLE BOOKING
    ADD CONSTRAINT chk_booking_status
    CHECK (Booking_Status IN ('Pending', 'Confirmed', 'Completed', 'Cancelled'));

ALTER TABLE BOOKING
    ADD CONSTRAINT fk_booking_guest
    FOREIGN KEY (Guest_ID) REFERENCES GUEST (Guest_ID)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;

ALTER TABLE BOOKING
    ADD CONSTRAINT fk_booking_property
    FOREIGN KEY (Property_ID) REFERENCES PROPERTY (Property_ID)
    ON UPDATE CASCADE
    ON DELETE RESTRICT;

CREATE TABLE PAYMENT (
    Payment_ID       INT AUTO_INCREMENT PRIMARY KEY,
    Booking_ID       INT NOT NULL,
    Amount           DECIMAL(10,2) NOT NULL,
    Payment_Method   VARCHAR(30) NOT NULL,
    Payment_Date     DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
    Payment_Status   VARCHAR(20) NOT NULL DEFAULT 'Pending'
) ENGINE=InnoDB;

ALTER TABLE PAYMENT
    ADD CONSTRAINT uq_payment_booking UNIQUE (Booking_ID);

ALTER TABLE PAYMENT
    ADD CONSTRAINT chk_payment_amount_positive
    CHECK (Amount > 0);

ALTER TABLE PAYMENT
    ADD CONSTRAINT chk_payment_method
    CHECK (Payment_Method IN ('Credit Card', 'Debit Card', 'UPI', 'Net Banking', 'PayPal'));

ALTER TABLE PAYMENT
    ADD CONSTRAINT chk_payment_status
    CHECK (Payment_Status IN ('Pending', 'Successful', 'Failed', 'Refunded'));

ALTER TABLE PAYMENT
    ADD CONSTRAINT fk_payment_booking
    FOREIGN KEY (Booking_ID) REFERENCES BOOKING (Booking_ID)
    ON UPDATE CASCADE
    ON DELETE CASCADE;

CREATE TABLE REVIEW (
    Review_ID     INT AUTO_INCREMENT PRIMARY KEY,
    Guest_ID      INT NOT NULL,
    Property_ID   INT NOT NULL,
    Rating        TINYINT NOT NULL,
    Comment       TEXT,
    Review_Date   DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP
) ENGINE=InnoDB;

ALTER TABLE REVIEW
    ADD CONSTRAINT chk_review_rating_range
    CHECK (Rating BETWEEN 1 AND 5);

ALTER TABLE REVIEW
    ADD CONSTRAINT fk_review_guest
    FOREIGN KEY (Guest_ID) REFERENCES GUEST (Guest_ID)
    ON UPDATE CASCADE
    ON DELETE CASCADE;

ALTER TABLE REVIEW
    ADD CONSTRAINT fk_review_property
    FOREIGN KEY (Property_ID) REFERENCES PROPERTY (Property_ID)
    ON UPDATE CASCADE
    ON DELETE CASCADE;

CREATE INDEX idx_property_host        ON PROPERTY (Host_ID);
CREATE INDEX idx_booking_guest        ON BOOKING (Guest_ID);
CREATE INDEX idx_booking_property     ON BOOKING (Property_ID);
CREATE INDEX idx_booking_status       ON BOOKING (Booking_Status);
CREATE INDEX idx_payment_status       ON PAYMENT (Payment_Status);
CREATE INDEX idx_review_guest         ON REVIEW (Guest_ID);
CREATE INDEX idx_review_property      ON REVIEW (Property_ID);
