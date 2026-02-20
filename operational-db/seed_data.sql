-- =============================================================
-- Seed Data — Operational OLTP Loan Management System
-- Realistic enterprise data for demonstrations and testing
-- =============================================================

SET search_path TO operational, public;

-- =============================================================
-- LOAN PRODUCTS
-- =============================================================
INSERT INTO loan_products (product_name, product_type, min_amount, max_amount, min_tenure_months, max_tenure_months) VALUES
  ('Personal Express Loan',   'personal',  5000.00,     500000.00,   3,  60),
  ('SME Business Loan',       'business',  50000.00,    5000000.00,  6,  84),
  ('Home Mortgage',           'mortgage',  500000.00,   50000000.00, 60, 360),
  ('Auto Financing',          'auto',      50000.00,    3000000.00,  12, 72),
  ('Education Loan',          'education', 10000.00,    800000.00,   6,  48);

-- =============================================================
-- CUSTOMERS
-- =============================================================
INSERT INTO customers (full_name, email, phone, national_id, date_of_birth, city, segment) VALUES
  ('Alice Njoroge',      'alice.njoroge@mail.co.ke',   '+254700111001', '12345678', '1988-04-12', 'Nairobi',  'retail'),
  ('Brian Otieno',       'brian.otieno@mail.co.ke',    '+254700111002', '23456789', '1985-07-23', 'Mombasa',  'retail'),
  ('Catherine Wanjiru',  'catherine.w@mail.co.ke',     '+254700111003', '34567890', '1990-01-05', 'Kisumu',   'retail'),
  ('David Kamau',        'david.kamau@mail.co.ke',     '+254700111004', '45678901', '1978-09-30', 'Nakuru',   'sme'),
  ('Esther Achieng',     'esther.a@mail.co.ke',        '+254700111005', '56789012', '1992-03-17', 'Nairobi',  'retail'),
  ('Francis Mwangi',     'francis.mwangi@mail.co.ke',  '+254700111006', '67890123', '1975-11-08', 'Eldoret',  'sme'),
  ('Grace Mutua',        'grace.mutua@mail.co.ke',     '+254700111007', '78901234', '1995-06-22', 'Thika',    'retail'),
  ('Hassan Abdi',        'hassan.abdi@mail.co.ke',     '+254700111008', '89012345', '1983-02-14', 'Mombasa',  'corporate'),
  ('Ivy Chebet',         'ivy.chebet@mail.co.ke',      '+254700111009', '90123456', '1989-08-01', 'Nairobi',  'retail'),
  ('James Omondi',       'james.omondi@mail.co.ke',    '+254700111010', '01234567', '1980-12-19', 'Kisumu',   'sme'),
  ('Karen Adhiambo',     'karen.adhiambo@mail.co.ke',  '+254700111011', '11223344', '1993-05-11', 'Nairobi',  'retail'),
  ('Leon Mutuku',        'leon.mutuku@mail.co.ke',     '+254700111012', '22334455', '1987-10-27', 'Machakos', 'sme'),
  ('Mary Wambui',        'mary.wambui@mail.co.ke',     '+254700111013', '33445566', '1976-03-03', 'Nairobi',  'corporate'),
  ('Nelson Karanja',     'nelson.karanja@mail.co.ke',  '+254700111014', '44556677', '1991-07-16', 'Nyeri',    'retail'),
  ('Olivia Auma',        'olivia.auma@mail.co.ke',     '+254700111015', '55667788', '1984-01-29', 'Kisumu',   'retail');

-- =============================================================
-- LOANS
-- =============================================================
INSERT INTO loans (customer_id, product_id, amount, interest_rate, tenure_months, status, disbursed_at, maturity_date, outstanding_balance, loan_officer, branch_code) VALUES
  (1,  1, 150000.00,  14.50, 24, 'active',    '2024-01-15 08:00:00+03', '2026-01-15', 95000.00,    'Joseph Kariuki',  'NBI-001'),
  (2,  1, 80000.00,   15.00, 12, 'repaid',    '2023-06-01 09:00:00+03', '2024-06-01', 0.00,        'Amina Said',      'MBA-001'),
  (3,  2, 500000.00,  12.00, 36, 'active',    '2024-03-20 10:00:00+03', '2027-03-20', 380000.00,   'Peter Maina',     'KSM-001'),
  (4,  2, 2000000.00, 11.50, 60, 'active',    '2023-11-01 08:30:00+03', '2028-11-01', 1650000.00,  'Joseph Kariuki',  'NKR-001'),
  (5,  1, 50000.00,   16.00, 6,  'repaid',    '2023-09-01 08:00:00+03', '2024-03-01', 0.00,        'Amina Said',      'NBI-001'),
  (6,  2, 750000.00,  12.50, 48, 'active',    '2024-02-01 09:00:00+03', '2028-02-01', 620000.00,   'Peter Maina',     'ELD-001'),
  (7,  1, 30000.00,   17.00, 3,  'defaulted', '2023-04-01 08:00:00+03', '2023-07-01', 15000.00,    'Joseph Kariuki',  'THK-001'),
  (8,  3, 8000000.00, 10.00, 240,'active',    '2022-06-15 08:00:00+03', '2042-06-15', 7500000.00,  'Amina Said',      'MBA-001'),
  (9,  4, 1200000.00, 13.00, 60, 'active',    '2024-04-10 09:00:00+03', '2029-04-10', 1100000.00,  'Peter Maina',     'NBI-002'),
  (10, 2, 900000.00,  12.00, 48, 'active',    '2024-01-05 08:00:00+03', '2028-01-05', 810000.00,   'Joseph Kariuki',  'KSM-001'),
  (11, 5, 200000.00,  13.50, 36, 'active',    '2024-05-01 10:00:00+03', '2027-05-01', 185000.00,   'Amina Said',      'NBI-002'),
  (12, 2, 1500000.00, 11.00, 60, 'active',    '2023-07-01 08:00:00+03', '2028-07-01', 1200000.00,  'Peter Maina',     'MCH-001'),
  (13, 3, 15000000.00, 9.50, 300,'active',    '2020-01-01 08:00:00+03', '2045-01-01', 13500000.00, 'Joseph Kariuki',  'NBI-001'),
  (14, 1, 100000.00,  14.00, 18, 'repaid',    '2022-10-01 09:00:00+03', '2024-04-01', 0.00,        'Amina Said',      'NYR-001'),
  (15, 1, 60000.00,   16.50, 12, 'active',    '2024-06-01 08:00:00+03', '2025-06-01', 45000.00,    'Peter Maina',     'KSM-002');

-- =============================================================
-- PAYMENTS
-- =============================================================
-- Loan 1 (Alice — active, 24m)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (1, 7200.00, 5500.00, 1700.00, 'mpesa',         'MPRef001A', '2024-02-15'),
  (1, 7200.00, 5600.00, 1600.00, 'mpesa',         'MPRef002A', '2024-03-15'),
  (1, 7200.00, 5700.00, 1500.00, 'bank_transfer', 'BTRef003A', '2024-04-15'),
  (1, 7200.00, 5800.00, 1400.00, 'mpesa',         'MPRef004A', '2024-05-15'),
  (1, 7200.00, 5900.00, 1300.00, 'mpesa',         'MPRef005A', '2024-06-15');

-- Loan 2 (Brian — repaid)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (2, 7200.00, 6000.00, 1200.00, 'mpesa', 'MPRef001B', '2023-07-01'),
  (2, 7200.00, 6100.00, 1100.00, 'mpesa', 'MPRef002B', '2023-08-01'),
  (2, 7200.00, 6200.00, 1000.00, 'mpesa', 'MPRef003B', '2023-09-01'),
  (2, 7200.00, 6300.00,  900.00, 'mpesa', 'MPRef004B', '2023-10-01'),
  (2, 7200.00, 6400.00,  800.00, 'mpesa', 'MPRef005B', '2023-11-01'),
  (2, 7200.00, 6500.00,  700.00, 'mpesa', 'MPRef006B', '2023-12-01'),
  (2, 7200.00, 6600.00,  600.00, 'mpesa', 'MPRef007B', '2024-01-01'),
  (2, 7200.00, 6700.00,  500.00, 'mpesa', 'MPRef008B', '2024-02-01'),
  (2, 7200.00, 6800.00,  400.00, 'mpesa', 'MPRef009B', '2024-03-01'),
  (2, 7200.00, 6900.00,  300.00, 'mpesa', 'MPRef010B', '2024-04-01'),
  (2, 7200.00, 7000.00,  200.00, 'mpesa', 'MPRef011B', '2024-05-01'),
  (2, 7000.00, 6900.00,  100.00, 'mpesa', 'MPRef012B', '2024-06-01');

-- Loan 3 (Catherine — SME, active)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (3, 17000.00, 12000.00, 5000.00, 'bank_transfer', 'BTRef001C', '2024-04-20'),
  (3, 17000.00, 12200.00, 4800.00, 'bank_transfer', 'BTRef002C', '2024-05-20'),
  (3, 17000.00, 12400.00, 4600.00, 'bank_transfer', 'BTRef003C', '2024-06-20');

-- Loan 4 (David — SME business)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (4, 44000.00, 32000.00, 12000.00, 'bank_transfer', 'BTRef001D', '2023-12-01'),
  (4, 44000.00, 32500.00, 11500.00, 'bank_transfer', 'BTRef002D', '2024-01-01'),
  (4, 44000.00, 33000.00, 11000.00, 'bank_transfer', 'BTRef003D', '2024-02-01'),
  (4, 44000.00, 33500.00, 10500.00, 'bank_transfer', 'BTRef004D', '2024-03-01'),
  (4, 44000.00, 34000.00, 10000.00, 'bank_transfer', 'BTRef005D', '2024-04-01'),
  (4, 44000.00, 34500.00,  9500.00, 'bank_transfer', 'BTRef006D', '2024-05-01');

-- Loan 8 (Hassan — corporate mortgage)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (8, 72000.00, 5000.00, 67000.00, 'bank_transfer', 'BTRef001H', '2022-07-15'),
  (8, 72000.00, 5100.00, 66900.00, 'bank_transfer', 'BTRef002H', '2022-08-15'),
  (8, 72000.00, 5200.00, 66800.00, 'bank_transfer', 'BTRef003H', '2022-09-15'),
  (8, 72000.00, 5300.00, 66700.00, 'bank_transfer', 'BTRef004H', '2022-10-15');

-- Loan 12 (Leon — SME)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (12, 33000.00, 24000.00, 9000.00, 'online', 'ONRef001L', '2023-08-01'),
  (12, 33000.00, 24200.00, 8800.00, 'online', 'ONRef002L', '2023-09-01'),
  (12, 33000.00, 24400.00, 8600.00, 'online', 'ONRef003L', '2023-10-01'),
  (12, 33000.00, 24600.00, 8400.00, 'online', 'ONRef004L', '2023-11-01'),
  (12, 33000.00, 24800.00, 8200.00, 'online', 'ONRef005L', '2023-12-01');

-- Loan 13 (Mary — corporate mortgage)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (13, 135000.00, 10000.00, 125000.00, 'bank_transfer', 'BTRef001M', '2020-02-01'),
  (13, 135000.00, 10100.00, 124900.00, 'bank_transfer', 'BTRef002M', '2020-03-01'),
  (13, 135000.00, 10200.00, 124800.00, 'bank_transfer', 'BTRef003M', '2020-04-01');

-- Loan 14 (Nelson — repaid)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (14, 6400.00, 5000.00, 1400.00, 'mpesa', 'MPRef001N', '2022-11-01'),
  (14, 6400.00, 5100.00, 1300.00, 'mpesa', 'MPRef002N', '2022-12-01'),
  (14, 6400.00, 5200.00, 1200.00, 'mpesa', 'MPRef003N', '2023-01-01'),
  (14, 6400.00, 5300.00, 1100.00, 'mpesa', 'MPRef004N', '2023-02-01'),
  (14, 6400.00, 5400.00, 1000.00, 'mpesa', 'MPRef005N', '2023-03-01'),
  (14, 6400.00, 5500.00,  900.00, 'mpesa', 'MPRef006N', '2023-04-01'),
  (14, 6400.00, 5600.00,  800.00, 'mpesa', 'MPRef007N', '2023-05-01'),
  (14, 6400.00, 5700.00,  700.00, 'mpesa', 'MPRef008N', '2023-06-01'),
  (14, 6400.00, 5800.00,  600.00, 'mpesa', 'MPRef009N', '2023-07-01'),
  (14, 6300.00, 5900.00,  400.00, 'mpesa', 'MPRef010N', '2023-08-01');

-- Loan 15 (Olivia — active)
INSERT INTO payments (loan_id, amount, principal_portion, interest_portion, payment_method, reference_number, payment_date) VALUES
  (15, 5500.00, 4500.00, 1000.00, 'mpesa', 'MPRef001O', '2024-07-01'),
  (15, 5500.00, 4600.00,  900.00, 'mpesa', 'MPRef002O', '2024-08-01');
