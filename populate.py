import random
from datetime import date, timedelta

import mysql.connector
from faker import Faker

fake = Faker()
random.seed(7)
Faker.seed(7)

DB_CONFIG = dict(
    host="localhost",
    port=3306,
    database="airbnb_booking_db",
    user="root",
    password="",
)

N_HOSTS = 40
N_GUESTS = 120
N_PROPERTIES = 100
BOOKINGS_PER_PROPERTY_RANGE = (2, 6)
REVIEW_PROBABILITY = 0.6

PROPERTY_TYPES = ["Apartment", "House", "Villa", "Cabin", "Cottage", "Studio"]
AMENITIES_POOL = ["WiFi", "Air Conditioning", "Kitchen", "Parking", "Pool",
                   "Washer", "TV", "Heating", "Balcony", "Pet Friendly"]
PAYMENT_METHODS = ["Credit Card", "Debit Card", "UPI", "Net Banking", "PayPal"]
BOOKING_STATUS_WEIGHTS = [("Completed", 0.45), ("Confirmed", 0.25),
                           ("Pending", 0.15), ("Cancelled", 0.15)]


def weighted_status():
    r = random.random()
    acc = 0
    for status, w in BOOKING_STATUS_WEIGHTS:
        acc += w
        if r <= acc:
            return status
    return BOOKING_STATUS_WEIGHTS[-1][0]


def populate_hosts(cur, n):
    ids = []
    for _ in range(n):
        cur.execute(
            """INSERT INTO HOST (Name, Email, Phone, Password, Join_Date)
               VALUES (%s, %s, %s, %s, %s)""",
            (fake.name(), fake.unique.email(), fake.msisdn()[:10],
             fake.password(length=12), fake.date_between(start_date="-3y", end_date="-30d")),
        )
        ids.append(cur.lastrowid)
    return ids


def populate_guests(cur, n):
    ids = []
    for _ in range(n):
        cur.execute(
            """INSERT INTO GUEST (Name, Email, Phone, Password, Join_Date)
               VALUES (%s, %s, %s, %s, %s)""",
            (fake.name(), fake.unique.email(), fake.msisdn()[:10],
             fake.password(length=12), fake.date_between(start_date="-3y", end_date="-15d")),
        )
        ids.append(cur.lastrowid)
    return ids


def populate_properties(cur, n, host_ids):
    ids = []
    for _ in range(n):
        amenities = ", ".join(random.sample(AMENITIES_POOL, k=random.randint(3, 6)))
        cur.execute(
            """INSERT INTO PROPERTY
                   (Host_ID, Title, Description, Location, Price_per_night,
                    Property_Type, Amenities, Availability_Status)
               VALUES (%s, %s, %s, %s, %s, %s, %s, %s)""",
            (
                random.choice(host_ids),
                f"{fake.word().capitalize()} {random.choice(PROPERTY_TYPES)} in {fake.city()}",
                fake.paragraph(nb_sentences=3),
                f"{fake.city()}, {fake.country()}",
                round(random.uniform(25, 400), 2),
                random.choice(PROPERTY_TYPES),
                amenities,
                "Available",
            ),
        )
        ids.append(cur.lastrowid)
    return ids


def populate_bookings_and_payments(cur, property_ids, guest_ids):
    """For each property, lay down a sequence of non-overlapping stays."""
    booking_ids_by_status = {"Completed": []}
    for prop_id in property_ids:
        cursor_date = date.today() - timedelta(days=random.randint(300, 500))
        n_bookings = random.randint(*BOOKINGS_PER_PROPERTY_RANGE)
        for _ in range(n_bookings):
            gap_days = random.randint(2, 20)
            stay_len = random.randint(2, 10)
            check_in = cursor_date + timedelta(days=gap_days)
            check_out = check_in + timedelta(days=stay_len)
            if check_out > date.today() + timedelta(days=180):
                break

            guest_id = random.choice(guest_ids)
            n_guests = random.randint(1, 4)
            cur.execute("SELECT Price_per_night FROM PROPERTY WHERE Property_ID = %s", (prop_id,))
            price = cur.fetchone()[0]
            total = round(float(price) * stay_len, 2)
            status = "Completed" if check_out < date.today() else weighted_status()

            cur.execute(
                """INSERT INTO BOOKING
                       (Guest_ID, Property_ID, CheckIn_Date, CheckOut_Date,
                        No_of_Guests, Total_Amount, Booking_Status)
                   VALUES (%s, %s, %s, %s, %s, %s, %s)""",
                (guest_id, prop_id, check_in, check_out, n_guests, total, status),
            )
            booking_id = cur.lastrowid
            if status == "Completed":
                booking_ids_by_status["Completed"].append((booking_id, guest_id, prop_id))

            pay_status = "Successful" if status in ("Completed", "Confirmed") else (
                "Refunded" if status == "Cancelled" else "Pending"
            )
            cur.execute(
                """INSERT INTO PAYMENT (Booking_ID, Amount, Payment_Method, Payment_Date, Payment_Status)
                   VALUES (%s, %s, %s, %s, %s)""",
                (booking_id, total, random.choice(PAYMENT_METHODS),
                 check_in - timedelta(days=random.randint(1, 5)), pay_status),
            )

            cursor_date = check_out
    return booking_ids_by_status["Completed"]


def populate_reviews(cur, completed_bookings):
    seen_pairs = set()
    for booking_id, guest_id, prop_id in completed_bookings:
        if random.random() > REVIEW_PROBABILITY:
            continue
        if (guest_id, prop_id) in seen_pairs:
            continue
        seen_pairs.add((guest_id, prop_id))
        cur.execute(
            """INSERT INTO REVIEW (Guest_ID, Property_ID, Rating, Comment, Review_Date)
               VALUES (%s, %s, %s, %s, %s)""",
            (guest_id, prop_id, random.randint(1, 5), fake.sentence(nb_words=12),
             fake.date_time_between(start_date="-1y", end_date="now")),
        )


def main():
    conn = mysql.connector.connect(**DB_CONFIG)
    conn.autocommit = False
    try:
        cur = conn.cursor()

        print("Populating HOST...")
        host_ids = populate_hosts(cur, N_HOSTS)

        print("Populating GUEST...")
        guest_ids = populate_guests(cur, N_GUESTS)

        print("Populating PROPERTY...")
        property_ids = populate_properties(cur, N_PROPERTIES, host_ids)

        print("Populating BOOKING + PAYMENT (non-overlapping per property)...")
        completed = populate_bookings_and_payments(cur, property_ids, guest_ids)

        print("Populating REVIEW (only for completed stays)...")
        populate_reviews(cur, completed)

        conn.commit()
        cur.execute("SELECT COUNT(*) FROM BOOKING")
        total_bookings = cur.fetchone()[0]
        print("Done. Rows inserted:")
        print(f"  HOST      : {N_HOSTS}")
        print(f"  GUEST     : {N_GUESTS}")
        print(f"  PROPERTY  : {N_PROPERTIES}")
        print(f"  BOOKING   : {total_bookings} (non-overlapping per property)")
        print("  PAYMENT   : matches BOOKING 1:1")
        print(f"  REVIEW    : {len(completed)} eligible, ~{REVIEW_PROBABILITY:.0%} written")
    except Exception as e:
        conn.rollback()
        print("Error, rolled back:", e)
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
