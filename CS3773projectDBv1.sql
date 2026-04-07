
--  JS CONNECTION (Node.js / Express):
--    npm install mysql2
--    ─────────────────────────────────────────────────────────
--    const mysql = require('mysql2/promise');
--    const pool  = mysql.createPool({
--      host    : 'YOUR_SERVER_IP',
--      port    : 3306,
--      user    : 'app_user',
--      password: 'YOUR_PASSWORD',
--      database: 'shopping_site',
--      waitForConnections: true,
--      connectionLimit   : 10
--    });
--    ─────────────────────────────────────────────────────────

CREATE DATABASE IF NOT EXISTS shopping_site
  CHARACTER SET utf8mb4
  COLLATE utf8mb4_unicode_ci;

USE shopping_site;

SET FOREIGN_KEY_CHECKS = 0;
SET SQL_MODE = 'STRICT_TRANS_TABLES,NO_ZERO_IN_DATE,ERROR_FOR_DIVISION_BY_ZERO';


-- 1. Users

CREATE TABLE IF NOT EXISTS Users (
  UserID      INT UNSIGNED              NOT NULL AUTO_INCREMENT,
  firstName   VARCHAR(50)               NOT NULL,
  lastName    VARCHAR(50)               NOT NULL,
  userName    VARCHAR(50)               NOT NULL,
  password    VARCHAR(255)              NOT NULL  COMMENT 'bcrypt hash only — never plaintext',
  email       VARCHAR(100)                  NULL,
  phone       VARCHAR(20)                   NULL  DEFAULT '(123) 456-7890',
  address     VARCHAR(200)                  NULL  DEFAULT '12345 Avenue',
  state       VARCHAR(50)                   NULL  DEFAULT 'Texas',
  zipCode     CHAR(10)                      NULL  DEFAULT '00000',
  dob         DATE                          NULL,
  role        ENUM('customer','admin')  NOT NULL  DEFAULT 'customer',
  createdAt   DATETIME                  NOT NULL  DEFAULT CURRENT_TIMESTAMP,
  updatedAt   DATETIME                  NOT NULL  DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (UserID),
  UNIQUE KEY uq_userName (userName),
  UNIQUE KEY uq_email    (email)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Customer and administrator accounts';



-- 2. Inventory

CREATE TABLE IF NOT EXISTS Inventory (
  ProductID   INT UNSIGNED                              NOT NULL AUTO_INCREMENT,
  product     VARCHAR(150)                              NOT NULL  COMMENT 'Style name',
  description TEXT                                          NULL,
  category    VARCHAR(100)                                  NULL  COMMENT 'Tops / Bottoms / Dresses / Outerwear / etc.',
  gender      ENUM('Men','Women','Unisex','Kids')       NOT NULL  DEFAULT 'Unisex',
  color       VARCHAR(50)                                   NULL,
  size        VARCHAR(10)                                   NULL  COMMENT 'XS/S/M/L/XL/XXL or shoe size',
  price       DECIMAL(10,2)                             NOT NULL,
  quantity    INT UNSIGNED                              NOT NULL  DEFAULT 0,
  onSale      TINYINT(1)                                NOT NULL  DEFAULT 0  COMMENT '0=regular, 1=on sale',
  salePrice   DECIMAL(10,2)                                 NULL,
  imageURL    VARCHAR(500)                                  NULL,
  createdAt   DATETIME                                  NOT NULL  DEFAULT CURRENT_TIMESTAMP,
  updatedAt   DATETIME                                  NOT NULL  DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (ProductID),
  KEY idx_product   (product),
  KEY idx_category  (category),
  KEY idx_gender    (gender),
  KEY idx_price     (price),
  KEY idx_quantity  (quantity),
  KEY idx_color     (color)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Clothing SKUs — one row per style + size + color variant';



-- 3. DiscountCodes

CREATE TABLE IF NOT EXISTS DiscountCodes (
  discountID    INT UNSIGNED               NOT NULL AUTO_INCREMENT,
  code          VARCHAR(50)                NOT NULL,
  discountType  ENUM('percent','flat')     NOT NULL DEFAULT 'percent',
  discountValue DECIMAL(10,2)              NOT NULL COMMENT 'Percent 0-100 or flat dollar amount',
  usageLimit    INT UNSIGNED                   NULL COMMENT 'NULL = unlimited',
  usageCount    INT UNSIGNED               NOT NULL DEFAULT 0,
  expiresAt     DATETIME                       NULL,
  isActive      TINYINT(1)                 NOT NULL DEFAULT 1,
  createdAt     DATETIME                   NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (discountID),
  UNIQUE KEY uq_code (code)
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Promotional discount and coupon codes';


-- 4. ShopCart

CREATE TABLE IF NOT EXISTS ShopCart (
  cartID      INT UNSIGNED NOT NULL AUTO_INCREMENT,
  userID      INT UNSIGNED NOT NULL,
  productID   INT UNSIGNED NOT NULL,
  quantity    INT UNSIGNED NOT NULL DEFAULT 1,
  addedAt     DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (cartID),
  UNIQUE KEY uq_user_product (userID, productID),
  KEY idx_cart_user    (userID),
  KEY idx_cart_product (productID),

  CONSTRAINT fk_cart_user
    FOREIGN KEY (userID)    REFERENCES Users(UserID)
    ON DELETE CASCADE ON UPDATE CASCADE,

  CONSTRAINT fk_cart_product
    FOREIGN KEY (productID) REFERENCES Inventory(ProductID)
    ON DELETE CASCADE ON UPDATE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Active shopping carts — one row per user + SKU';


-- 5. Orders

CREATE TABLE IF NOT EXISTS Orders (
  orderID        INT UNSIGNED NOT NULL AUTO_INCREMENT,
  customerID     INT UNSIGNED NOT NULL,
  discountID     INT UNSIGNED     NULL,
  subtotal       DECIMAL(10,2) NOT NULL,
  taxAmount      DECIMAL(10,2) NOT NULL COMMENT '8.25% applied after discount',
  discountAmount DECIMAL(10,2) NOT NULL DEFAULT 0.00,
  orderTotal     DECIMAL(10,2) NOT NULL,
  orderDate      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP,
  status         ENUM('placed','processing','shipped','delivered','cancelled')
                               NOT NULL DEFAULT 'placed',
  updatedAt      DATETIME      NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,

  PRIMARY KEY (orderID),
  KEY idx_order_customer (customerID),
  KEY idx_order_date     (orderDate),
  KEY idx_order_total    (orderTotal),
  KEY idx_order_status   (status),

  CONSTRAINT fk_order_customer
    FOREIGN KEY (customerID) REFERENCES Users(UserID)
    ON DELETE RESTRICT ON UPDATE CASCADE,

  CONSTRAINT fk_order_discount
    FOREIGN KEY (discountID) REFERENCES DiscountCodes(discountID)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Order headers';


-- 
-- 6. OrderItems
-- 
CREATE TABLE IF NOT EXISTS OrderItems (
  itemID          INT UNSIGNED  NOT NULL AUTO_INCREMENT,
  orderID         INT UNSIGNED  NOT NULL,
  productID       INT UNSIGNED  NOT NULL,
  quantity        INT UNSIGNED  NOT NULL,
  priceAtPurchase DECIMAL(10,2) NOT NULL COMMENT 'Price snapshot — immune to future price changes',

  PRIMARY KEY (itemID),
  KEY idx_oi_order   (orderID),
  KEY idx_oi_product (productID),

  CONSTRAINT fk_oi_order
    FOREIGN KEY (orderID)   REFERENCES Orders(orderID)
    ON DELETE CASCADE ON UPDATE CASCADE,

  CONSTRAINT fk_oi_product
    FOREIGN KEY (productID) REFERENCES Inventory(ProductID)
    ON DELETE RESTRICT ON UPDATE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Line items per order';


-- 
-- 7. PaymentInfo
-- 
CREATE TABLE IF NOT EXISTS PaymentInfo (
  paymentID       INT UNSIGNED NOT NULL AUTO_INCREMENT,
  userID          INT UNSIGNED NOT NULL,
  orderID         INT UNSIGNED     NULL,
  paymentType     VARCHAR(50)  NOT NULL COMMENT 'credit / debit / paypal / etc.',
  cardLast4       CHAR(4)          NULL,
  approved        TINYINT(1)   NOT NULL DEFAULT 0,
  transactionDate DATETIME     NOT NULL DEFAULT CURRENT_TIMESTAMP,

  PRIMARY KEY (paymentID),
  KEY idx_pay_user  (userID),
  KEY idx_pay_order (orderID),

  CONSTRAINT fk_pay_user
    FOREIGN KEY (userID)  REFERENCES Users(UserID)
    ON DELETE RESTRICT ON UPDATE CASCADE,

  CONSTRAINT fk_pay_order
    FOREIGN KEY (orderID) REFERENCES Orders(orderID)
    ON DELETE SET NULL ON UPDATE CASCADE
) ENGINE=InnoDB
  DEFAULT CHARSET=utf8mb4
  COLLATE=utf8mb4_unicode_ci
  COMMENT='Payment records linked to users and orders';


SET FOREIGN_KEY_CHECKS = 1;


-- ================================================================
--  ACID STORED PROCEDURES

DELIMITER $$

-- 
-- SP 1: Register a new user
-- 
DROP PROCEDURE IF EXISTS sp_RegisterUser$$
CREATE PROCEDURE sp_RegisterUser(
  IN  p_firstName VARCHAR(50),
  IN  p_lastName  VARCHAR(50),
  IN  p_userName  VARCHAR(50),
  IN  p_password  VARCHAR(255),
  IN  p_email     VARCHAR(100),
  OUT p_newUserID INT,
  OUT p_message   VARCHAR(200)
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_newUserID = -1;
    SET p_message   = 'Registration failed: username or email already exists.';
  END;

  START TRANSACTION;
    INSERT INTO Users (firstName, lastName, userName, password, email)
    VALUES (p_firstName, p_lastName, p_userName, p_password, p_email);
    SET p_newUserID = LAST_INSERT_ID();
  COMMIT;
  SET p_message = 'User registered successfully.';
END$$


-- 
-- SP 2: Add or update a cart item (upsert with stock check)
-- 
DROP PROCEDURE IF EXISTS sp_UpsertCartItem$$
CREATE PROCEDURE sp_UpsertCartItem(
  IN  p_userID    INT UNSIGNED,
  IN  p_productID INT UNSIGNED,
  IN  p_quantity  INT UNSIGNED,
  OUT p_message   VARCHAR(200)
)
BEGIN
  DECLARE v_stock INT UNSIGNED DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_message = 'Cart update failed — please try again.';
  END;

  START TRANSACTION;
    SELECT quantity INTO v_stock
      FROM Inventory
     WHERE ProductID = p_productID
     FOR UPDATE;

    IF v_stock < p_quantity THEN
      ROLLBACK;
      SET p_message = CONCAT('Only ', v_stock, ' units available.');
    ELSE
      INSERT INTO ShopCart (userID, productID, quantity)
      VALUES (p_userID, p_productID, p_quantity)
      ON DUPLICATE KEY UPDATE quantity = p_quantity;
      COMMIT;
      SET p_message = 'Cart updated.';
    END IF;
END$$


-- 
-- SP 3: Place an order
--   • Validates discount code (if supplied)
--   • Calculates subtotal → discount → 8.25% tax → total
--   • Decrements inventory per item
--   • Writes Orders + OrderItems atomically
--   • Clears the cart on success

DROP PROCEDURE IF EXISTS sp_PlaceOrder$$
CREATE PROCEDURE sp_PlaceOrder(
  IN  p_userID       INT UNSIGNED,
  IN  p_discountCode VARCHAR(50),
  OUT p_orderID      INT,
  OUT p_message      VARCHAR(200)
)
sp_PlaceOrder:BEGIN
  DECLARE v_discountID   INT UNSIGNED  DEFAULT NULL;
  DECLARE v_discountType VARCHAR(10)   DEFAULT 'percent';
  DECLARE v_discountVal  DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_subtotal     DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_discountAmt  DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_taxAmount    DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_orderTotal   DECIMAL(10,2) DEFAULT 0.00;
  DECLARE v_cartCount    INT           DEFAULT 0;

  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_orderID = -1;
    SET p_message  = 'Order failed — all changes have been rolled back.';
  END;

  START TRANSACTION;

    -- 1. Cart must not be empty
    SELECT COUNT(*) INTO v_cartCount
      FROM ShopCart WHERE userID = p_userID;

    IF v_cartCount = 0 THEN
      ROLLBACK;
      SET p_orderID = -1;
      SET p_message  = 'Cart is empty.';
      LEAVE sp_PlaceOrder;
    END IF;

   SELECT i.quantity INTO @_lock_dummy
      FROM ShopCart sc
      JOIN Inventory i ON i.ProductID = sc.productID
     WHERE sc.userID = p_userID
     LIMIT 1
     FOR UPDATE;

    IF EXISTS (
      SELECT 1
        FROM ShopCart sc
        JOIN Inventory i ON i.ProductID = sc.productID
       WHERE sc.userID   = p_userID
         AND i.quantity  < sc.quantity
    ) THEN
      ROLLBACK;
      SET p_orderID = -1;
      SET p_message  = 'One or more items are out of stock.';
      LEAVE sp_PlaceOrder;
    END IF;

    IF p_discountCode IS NOT NULL AND p_discountCode != '' THEN
      SELECT discountID, discountType, discountValue
        INTO v_discountID, v_discountType, v_discountVal
        FROM DiscountCodes
       WHERE code       = p_discountCode
         AND isActive   = 1
         AND (expiresAt  IS NULL OR expiresAt  > NOW())
         AND (usageLimit IS NULL OR usageCount < usageLimit);

      IF v_discountID IS NULL THEN
        ROLLBACK;
        SET p_orderID = -1;
        SET p_message  = 'Invalid or expired discount code.';
        LEAVE sp_PlaceOrder;
      END IF;

      UPDATE DiscountCodes
         SET usageCount = usageCount + 1
       WHERE discountID = v_discountID;
    END IF;

    -- 5. Subtotal — use sale price when item is on sale
    SELECT SUM(sc.quantity * IF(i.onSale = 1 AND i.salePrice IS NOT NULL, i.salePrice, i.price))
      INTO v_subtotal
      FROM ShopCart sc
      JOIN Inventory i ON i.ProductID = sc.productID
     WHERE sc.userID = p_userID;

    -- 6. Apply discount
    IF v_discountType = 'percent' THEN
      SET v_discountAmt = ROUND(v_subtotal * (v_discountVal / 100), 2);
    ELSE
      SET v_discountAmt = LEAST(v_discountVal, v_subtotal);
    END IF;

    -- 7. Tax at 8.25%
    SET v_taxAmount  = ROUND((v_subtotal - v_discountAmt) * 0.0825, 2);
    SET v_orderTotal = ROUND((v_subtotal - v_discountAmt) + v_taxAmount, 2);

    -- 8. Insert order header
    INSERT INTO Orders (customerID, discountID, subtotal, taxAmount, discountAmount, orderTotal)
    VALUES (p_userID, v_discountID, v_subtotal, v_taxAmount, v_discountAmt, v_orderTotal);
    SET p_orderID = LAST_INSERT_ID();

    -- 9. Insert line items and decrement inventory in one pass
    INSERT INTO OrderItems (orderID, productID, quantity, priceAtPurchase)
    SELECT p_orderID,
           sc.productID,
           sc.quantity,
           IF(i.onSale = 1 AND i.salePrice IS NOT NULL, i.salePrice, i.price)
      FROM ShopCart sc
      JOIN Inventory i ON i.ProductID = sc.productID
     WHERE sc.userID = p_userID;

    UPDATE Inventory i
      JOIN ShopCart  sc ON sc.productID = i.ProductID
       SET i.quantity = i.quantity - sc.quantity
     WHERE sc.userID  = p_userID;

    -- 10. Clear the cart
    DELETE FROM ShopCart WHERE userID = p_userID;

  COMMIT;
  SET p_message = CONCAT('Order #', p_orderID, ' placed successfully.');
END$$


-- 
-- SP 4: Admin — update an existing inventory item
-- 
DROP PROCEDURE IF EXISTS sp_UpdateInventoryItem$$
CREATE PROCEDURE sp_UpdateInventoryItem(
  IN  p_productID   INT UNSIGNED,
  IN  p_product     VARCHAR(150),
  IN  p_description TEXT,
  IN  p_category    VARCHAR(100),
  IN  p_gender      ENUM('Men','Women','Unisex','Kids'),
  IN  p_color       VARCHAR(50),
  IN  p_size        VARCHAR(10),
  IN  p_price       DECIMAL(10,2),
  IN  p_quantity    INT UNSIGNED,
  IN  p_onSale      TINYINT(1),
  IN  p_salePrice   DECIMAL(10,2),
  IN  p_imageURL    VARCHAR(500),
  OUT p_message     VARCHAR(200)
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_message = 'Inventory update failed.';
  END;

  START TRANSACTION;
    UPDATE Inventory
       SET product     = p_product,
           description = p_description,
           category    = p_category,
           gender      = p_gender,
           color       = p_color,
           size        = p_size,
           price       = p_price,
           quantity    = p_quantity,
           onSale      = p_onSale,
           salePrice   = IF(p_onSale = 1, p_salePrice, NULL),
           imageURL    = p_imageURL
     WHERE ProductID   = p_productID;

    IF ROW_COUNT() = 0 THEN
      ROLLBACK;
      SET p_message = 'Product not found.';
    ELSE
      COMMIT;
      SET p_message = 'Product updated.';
    END IF;
END$$


-- 
-- SP 5: Admin — add a brand-new inventory SKU
-- 
DROP PROCEDURE IF EXISTS sp_AddInventoryItem$$
CREATE PROCEDURE sp_AddInventoryItem(
  IN  p_product     VARCHAR(150),
  IN  p_description TEXT,
  IN  p_category    VARCHAR(100),
  IN  p_gender      ENUM('Men','Women','Unisex','Kids'),
  IN  p_color       VARCHAR(50),
  IN  p_size        VARCHAR(10),
  IN  p_price       DECIMAL(10,2),
  IN  p_quantity    INT UNSIGNED,
  IN  p_onSale      TINYINT(1),
  IN  p_salePrice   DECIMAL(10,2),
  IN  p_imageURL    VARCHAR(500),
  OUT p_productID   INT,
  OUT p_message     VARCHAR(200)
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_productID = -1;
    SET p_message   = 'Failed to add item.';
  END;

  START TRANSACTION;
    INSERT INTO Inventory
      (product, description, category, gender, color, size,
       price, quantity, onSale, salePrice, imageURL)
    VALUES
      (p_product, p_description, p_category, p_gender, p_color, p_size,
       p_price, p_quantity, p_onSale, IF(p_onSale = 1, p_salePrice, NULL), p_imageURL);
    SET p_productID = LAST_INSERT_ID();
  COMMIT;
  SET p_message = CONCAT('Item "', p_product, '" added with ID ', p_productID, '.');
END$$


-- 
-- SP 6: Admin — create a discount code
-- 
DROP PROCEDURE IF EXISTS sp_CreateDiscountCode$$
CREATE PROCEDURE sp_CreateDiscountCode(
  IN  p_code       VARCHAR(50),
  IN  p_type       ENUM('percent','flat'),
  IN  p_value      DECIMAL(10,2),
  IN  p_limit      INT UNSIGNED,
  IN  p_expiresAt  DATETIME,
  OUT p_discountID INT,
  OUT p_message    VARCHAR(200)
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_discountID = -1;
    SET p_message    = 'Discount code creation failed — code may already exist.';
  END;

  START TRANSACTION;
    INSERT INTO DiscountCodes (code, discountType, discountValue, usageLimit, expiresAt)
    VALUES (UPPER(TRIM(p_code)), p_type, p_value, p_limit, p_expiresAt);
    SET p_discountID = LAST_INSERT_ID();
  COMMIT;
  SET p_message = CONCAT('Code "', UPPER(TRIM(p_code)), '" created.');
END$$


-- 
-- SP 7: Admin — modify a user account
-- 
DROP PROCEDURE IF EXISTS sp_UpdateUser$$
CREATE PROCEDURE sp_UpdateUser(
  IN  p_userID    INT UNSIGNED,
  IN  p_firstName VARCHAR(50),
  IN  p_lastName  VARCHAR(50),
  IN  p_email     VARCHAR(100),
  IN  p_phone     VARCHAR(20),
  IN  p_address   VARCHAR(200),
  IN  p_state     VARCHAR(50),
  IN  p_zipCode   CHAR(10),
  IN  p_role      ENUM('customer','admin'),
  OUT p_message   VARCHAR(200)
)
BEGIN
  DECLARE EXIT HANDLER FOR SQLEXCEPTION
  BEGIN
    ROLLBACK;
    SET p_message = 'User update failed.';
  END;

  START TRANSACTION;
    UPDATE Users
       SET firstName = p_firstName,
           lastName  = p_lastName,
           email     = p_email,
           phone     = p_phone,
           address   = p_address,
           state     = p_state,
           zipCode   = p_zipCode,
           role      = p_role
     WHERE UserID    = p_userID;

    IF ROW_COUNT() = 0 THEN
      ROLLBACK;
      SET p_message = 'User not found.';
    ELSE
      COMMIT;
      SET p_message = 'User updated.';
    END IF;
END$$

DELIMITER ;


-- 
--  VIEWS
-- 

-- Full order history (admin dashboard — sort by date/customer/total)
CREATE OR REPLACE VIEW vw_OrderHistory AS
SELECT
  o.orderID,
  CONCAT(u.firstName, ' ', u.lastName) AS customerName,
  u.email,
  o.subtotal,
  o.discountAmount,
  o.taxAmount,
  o.orderTotal,
  o.status,
  o.orderDate,
  dc.code AS discountCode
FROM Orders o
JOIN  Users         u  ON u.UserID     = o.customerID
LEFT JOIN DiscountCodes dc ON dc.discountID = o.discountID;


-- Active (open) orders only
CREATE OR REPLACE VIEW vw_ActiveOrders AS
SELECT * FROM vw_OrderHistory
WHERE status NOT IN ('delivered','cancelled');


-- Storefront inventory — shows effective price, supports search & sort
CREATE OR REPLACE VIEW vw_Inventory AS
SELECT
  ProductID,
  product,
  description,
  category,
  gender,
  color,
  size,
  price                                                        AS regularPrice,
  onSale,
  IF(onSale = 1 AND salePrice IS NOT NULL, salePrice, price)  AS effectivePrice,
  quantity,
  imageURL
FROM Inventory
ORDER BY category, product, gender, size;


-- 
--  SEED DATA
-- 

-- 
-- Users  (1 admin + 2 sample customers)
-- 
INSERT INTO Users (firstName, lastName, userName, password, email, role) VALUES
  ('Vivian',  'User',  'admin',  '$2b$12$placeholder_hash_admin',  'admin@store.com',    'admin'),
  ('Andrea',   'G', 'AG', '$2b$12$placeholder_hash_jane',   'andrea@example.com',   'customer'),
  ('Jacob', 'Lopez', 'JLO', '$2b$12$placeholder_hash_carlos', 'jacob@example.com', 'customer');


-- 
-- Inventory — Clothing store SKUs

INSERT INTO Inventory
  (product, description, category, gender, color, size, price, quantity, onSale, salePrice, imageURL)
VALUES

-- ── WOMEN'S TOPS ────────────────────────────────────────────────
('Oversized Linen Shirt',  'Relaxed fit, 100% linen, roll-up sleeves',    'Tops', 'Women', 'White',      'XS', 39.99,  40, 0, NULL,  '/images/w-linen-shirt-white-xs.jpg'),
('Oversized Linen Shirt',  'Relaxed fit, 100% linen, roll-up sleeves',    'Tops', 'Women', 'White',      'S',  39.99,  55, 0, NULL,  '/images/w-linen-shirt-white-s.jpg'),
('Oversized Linen Shirt',  'Relaxed fit, 100% linen, roll-up sleeves',    'Tops', 'Women', 'White',      'M',  39.99,  60, 0, NULL,  '/images/w-linen-shirt-white-m.jpg'),
('Oversized Linen Shirt',  'Relaxed fit, 100% linen, roll-up sleeves',    'Tops', 'Women', 'Sage Green', 'S',  39.99,  45, 0, NULL,  '/images/w-linen-shirt-sage-s.jpg'),
('Oversized Linen Shirt',  'Relaxed fit, 100% linen, roll-up sleeves',    'Tops', 'Women', 'Sage Green', 'M',  39.99,  50, 0, NULL,  '/images/w-linen-shirt-sage-m.jpg'),
('Ribbed Crop Tank',       'Stretch ribbed jersey, cropped length',       'Tops', 'Women', 'Black',      'XS', 14.99,  80, 0, NULL,  '/images/w-ribbed-tank-black-xs.jpg'),
('Ribbed Crop Tank',       'Stretch ribbed jersey, cropped length',       'Tops', 'Women', 'Black',      'S',  14.99,  90, 0, NULL,  '/images/w-ribbed-tank-black-s.jpg'),
('Ribbed Crop Tank',       'Stretch ribbed jersey, cropped length',       'Tops', 'Women', 'Black',      'M',  14.99,  85, 0, NULL,  '/images/w-ribbed-tank-black-m.jpg'),
('Ribbed Crop Tank',       'Stretch ribbed jersey, cropped length',       'Tops', 'Women', 'Cream',      'XS', 14.99,  70, 0, NULL,  '/images/w-ribbed-tank-cream-xs.jpg'),
('Ribbed Crop Tank',       'Stretch ribbed jersey, cropped length',       'Tops', 'Women', 'Cream',      'S',  14.99,  75, 0, NULL,  '/images/w-ribbed-tank-cream-s.jpg'),
('Satin Slip Blouse',      'V-neck satin, adjustable straps',             'Tops', 'Women', 'Dusty Rose', 'S',  34.99,  35, 1, 24.99, '/images/w-satin-blouse-rose-s.jpg'),
('Satin Slip Blouse',      'V-neck satin, adjustable straps',             'Tops', 'Women', 'Dusty Rose', 'M',  34.99,  30, 1, 24.99, '/images/w-satin-blouse-rose-m.jpg'),
('Satin Slip Blouse',      'V-neck satin, adjustable straps',             'Tops', 'Women', 'Champagne',  'S',  34.99,  40, 1, 24.99, '/images/w-satin-blouse-champ-s.jpg'),
('Satin Slip Blouse',      'V-neck satin, adjustable straps',             'Tops', 'Women', 'Champagne',  'M',  34.99,  35, 1, 24.99, '/images/w-satin-blouse-champ-m.jpg'),
('Floral Print Blouse',    'Woven fabric, tie neck, floral print',        'Tops', 'Women', 'Multi',      'XS', 29.99,  50, 0, NULL,  '/images/w-floral-blouse-xs.jpg'),
('Floral Print Blouse',    'Woven fabric, tie neck, floral print',        'Tops', 'Women', 'Multi',      'S',  29.99,  55, 0, NULL,  '/images/w-floral-blouse-s.jpg'),
('Floral Print Blouse',    'Woven fabric, tie neck, floral print',        'Tops', 'Women', 'Multi',      'M',  29.99,  50, 0, NULL,  '/images/w-floral-blouse-m.jpg'),

-- ── WOMEN'S BOTTOMS ─────────────────────────────────────────────
('High-Waist Wide-Leg Trousers', 'Flowy wide-leg, elasticated waist',    'Bottoms', 'Women', 'Camel',      'XS', 49.99, 40, 0, NULL,  '/images/w-wideleg-camel-xs.jpg'),
('High-Waist Wide-Leg Trousers', 'Flowy wide-leg, elasticated waist',    'Bottoms', 'Women', 'Camel',      'S',  49.99, 45, 0, NULL,  '/images/w-wideleg-camel-s.jpg'),
('High-Waist Wide-Leg Trousers', 'Flowy wide-leg, elasticated waist',    'Bottoms', 'Women', 'Black',      'S',  49.99, 50, 0, NULL,  '/images/w-wideleg-black-s.jpg'),
('High-Waist Wide-Leg Trousers', 'Flowy wide-leg, elasticated waist',    'Bottoms', 'Women', 'Black',      'M',  49.99, 55, 0, NULL,  '/images/w-wideleg-black-m.jpg'),
('Straight-Leg Jeans',     'Mid-rise, 5-pocket, stretch denim',          'Bottoms', 'Women', 'Light Wash', 'S',  44.99, 60, 0, NULL,  '/images/w-jeans-light-s.jpg'),
('Straight-Leg Jeans',     'Mid-rise, 5-pocket, stretch denim',          'Bottoms', 'Women', 'Light Wash', 'M',  44.99, 65, 0, NULL,  '/images/w-jeans-light-m.jpg'),
('Straight-Leg Jeans',     'Mid-rise, 5-pocket, stretch denim',          'Bottoms', 'Women', 'Dark Wash',  'S',  44.99, 60, 0, NULL,  '/images/w-jeans-dark-s.jpg'),
('Straight-Leg Jeans',     'Mid-rise, 5-pocket, stretch denim',          'Bottoms', 'Women', 'Dark Wash',  'M',  44.99, 55, 0, NULL,  '/images/w-jeans-dark-m.jpg'),
('Mini Pleated Skirt',     'A-line pleated, zip back closure',            'Bottoms', 'Women', 'Beige',      'XS', 29.99, 45, 1, 19.99, '/images/w-miniskirt-beige-xs.jpg'),
('Mini Pleated Skirt',     'A-line pleated, zip back closure',            'Bottoms', 'Women', 'Beige',      'S',  29.99, 50, 1, 19.99, '/images/w-miniskirt-beige-s.jpg'),
('Mini Pleated Skirt',     'A-line pleated, zip back closure',            'Bottoms', 'Women', 'Black',      'S',  29.99, 55, 1, 19.99, '/images/w-miniskirt-black-s.jpg'),
('Mini Pleated Skirt',     'A-line pleated, zip back closure',            'Bottoms', 'Women', 'Black',      'M',  29.99, 50, 1, 19.99, '/images/w-miniskirt-black-m.jpg'),

-- ── WOMEN'S DRESSES ─────────────────────────────────────────────
('Wrap Midi Dress',        'Surplice wrap, midi length, flutter sleeves', 'Dresses', 'Women', 'Terracotta', 'XS', 59.99, 30, 0, NULL,  '/images/w-wrap-terra-xs.jpg'),
('Wrap Midi Dress',        'Surplice wrap, midi length, flutter sleeves', 'Dresses', 'Women', 'Terracotta', 'S',  59.99, 35, 0, NULL,  '/images/w-wrap-terra-s.jpg'),
('Wrap Midi Dress',        'Surplice wrap, midi length, flutter sleeves', 'Dresses', 'Women', 'Navy Print', 'S',  59.99, 40, 0, NULL,  '/images/w-wrap-navy-s.jpg'),
('Wrap Midi Dress',        'Surplice wrap, midi length, flutter sleeves', 'Dresses', 'Women', 'Navy Print', 'M',  59.99, 38, 0, NULL,  '/images/w-wrap-navy-m.jpg'),
('Knit Mini Dress',        'Ribbed knit, sleeveless, bodycon fit',        'Dresses', 'Women', 'Black',      'XS', 44.99, 40, 0, NULL,  '/images/w-knit-dress-black-xs.jpg'),
('Knit Mini Dress',        'Ribbed knit, sleeveless, bodycon fit',        'Dresses', 'Women', 'Black',      'S',  44.99, 45, 0, NULL,  '/images/w-knit-dress-black-s.jpg'),
('Knit Mini Dress',        'Ribbed knit, sleeveless, bodycon fit',        'Dresses', 'Women', 'Olive',      'S',  44.99, 35, 0, NULL,  '/images/w-knit-dress-olive-s.jpg'),
('Printed Maxi Dress',     'Tiered hem, smocked bodice, woven fabric',    'Dresses', 'Women', 'Floral',     'S',  69.99, 25, 1, 49.99, '/images/w-maxi-floral-s.jpg'),
('Printed Maxi Dress',     'Tiered hem, smocked bodice, woven fabric',    'Dresses', 'Women', 'Floral',     'M',  69.99, 28, 1, 49.99, '/images/w-maxi-floral-m.jpg'),
('Printed Maxi Dress',     'Tiered hem, smocked bodice, woven fabric',    'Dresses', 'Women', 'Floral',     'L',  69.99, 20, 1, 49.99, '/images/w-maxi-floral-l.jpg'),

-- ── WOMEN'S OUTERWEAR ───────────────────────────────────────────
('Oversized Blazer',           'Relaxed single-button, woven fabric',        'Outerwear', 'Women', 'Ecru',    'S',  89.99, 25, 0, NULL,  '/images/w-blazer-ecru-s.jpg'),
('Oversized Blazer',           'Relaxed single-button, woven fabric',        'Outerwear', 'Women', 'Ecru',    'M',  89.99, 30, 0, NULL,  '/images/w-blazer-ecru-m.jpg'),
('Oversized Blazer',           'Relaxed single-button, woven fabric',        'Outerwear', 'Women', 'Black',   'S',  89.99, 30, 0, NULL,  '/images/w-blazer-black-s.jpg'),
('Oversized Blazer',           'Relaxed single-button, woven fabric',        'Outerwear', 'Women', 'Black',   'M',  89.99, 35, 0, NULL,  '/images/w-blazer-black-m.jpg'),
('Faux-Leather Biker Jacket',  'Zip front, quilted lining, belt waist',      'Outerwear', 'Women', 'Black',   'S',  99.99, 20, 1, 74.99, '/images/w-biker-black-s.jpg'),
('Faux-Leather Biker Jacket',  'Zip front, quilted lining, belt waist',      'Outerwear', 'Women', 'Black',   'M',  99.99, 22, 1, 74.99, '/images/w-biker-black-m.jpg'),
('Teddy Coat',                 'Faux-sherpa, double-breasted, belt tie',     'Outerwear', 'Women', 'Cream',   'S', 119.99, 18, 0, NULL,  '/images/w-teddy-cream-s.jpg'),
('Teddy Coat',                 'Faux-sherpa, double-breasted, belt tie',     'Outerwear', 'Women', 'Cream',   'M', 119.99, 20, 0, NULL,  '/images/w-teddy-cream-m.jpg'),
('Teddy Coat',                 'Faux-sherpa, double-breasted, belt tie',     'Outerwear', 'Women', 'Caramel', 'S', 119.99, 15, 0, NULL,  '/images/w-teddy-caramel-s.jpg'),

-- ── MEN'S TOPS ──────────────────────────────────────────────────
('Slim-Fit Oxford Shirt',  'Poplin cotton, button-down collar',             'Tops', 'Men', 'White',      'S',  34.99, 50, 0, NULL,  '/images/m-oxford-white-s.jpg'),
('Slim-Fit Oxford Shirt',  'Poplin cotton, button-down collar',             'Tops', 'Men', 'White',      'M',  34.99, 60, 0, NULL,  '/images/m-oxford-white-m.jpg'),
('Slim-Fit Oxford Shirt',  'Poplin cotton, button-down collar',             'Tops', 'Men', 'White',      'L',  34.99, 55, 0, NULL,  '/images/m-oxford-white-l.jpg'),
('Slim-Fit Oxford Shirt',  'Poplin cotton, button-down collar',             'Tops', 'Men', 'Sky Blue',   'S',  34.99, 45, 0, NULL,  '/images/m-oxford-blue-s.jpg'),
('Slim-Fit Oxford Shirt',  'Poplin cotton, button-down collar',             'Tops', 'Men', 'Sky Blue',   'M',  34.99, 50, 0, NULL,  '/images/m-oxford-blue-m.jpg'),
('Essential Crew-Neck Tee','100% cotton, relaxed fit, ribbed collar',       'Tops', 'Men', 'Black',      'S',  12.99,100, 0, NULL,  '/images/m-tee-black-s.jpg'),
('Essential Crew-Neck Tee','100% cotton, relaxed fit, ribbed collar',       'Tops', 'Men', 'Black',      'M',  12.99,120, 0, NULL,  '/images/m-tee-black-m.jpg'),
('Essential Crew-Neck Tee','100% cotton, relaxed fit, ribbed collar',       'Tops', 'Men', 'Black',      'L',  12.99,110, 0, NULL,  '/images/m-tee-black-l.jpg'),
('Essential Crew-Neck Tee','100% cotton, relaxed fit, ribbed collar',       'Tops', 'Men', 'White',      'M',  12.99,115, 0, NULL,  '/images/m-tee-white-m.jpg'),
('Essential Crew-Neck Tee','100% cotton, relaxed fit, ribbed collar',       'Tops', 'Men', 'White',      'L',  12.99,105, 0, NULL,  '/images/m-tee-white-l.jpg'),
('Graphic Print Tee',      'Oversized, heavyweight cotton, front graphic',  'Tops', 'Men', 'Black',      'M',  19.99, 70, 0, NULL,  '/images/m-graphic-black-m.jpg'),
('Graphic Print Tee',      'Oversized, heavyweight cotton, front graphic',  'Tops', 'Men', 'Black',      'L',  19.99, 65, 0, NULL,  '/images/m-graphic-black-l.jpg'),
('Graphic Print Tee',      'Oversized, heavyweight cotton, front graphic',  'Tops', 'Men', 'Stone',      'M',  19.99, 60, 0, NULL,  '/images/m-graphic-stone-m.jpg'),
('Linen Blend Shirt',      'Regular fit, Cuban collar, linen blend',        'Tops', 'Men', 'Ecru',       'S',  39.99, 40, 1, 27.99, '/images/m-linen-ecru-s.jpg'),
('Linen Blend Shirt',      'Regular fit, Cuban collar, linen blend',        'Tops', 'Men', 'Ecru',       'M',  39.99, 45, 1, 27.99, '/images/m-linen-ecru-m.jpg'),
('Linen Blend Shirt',      'Regular fit, Cuban collar, linen blend',        'Tops', 'Men', 'Dusty Blue', 'M',  39.99, 40, 1, 27.99, '/images/m-linen-blue-m.jpg'),
('Linen Blend Shirt',      'Regular fit, Cuban collar, linen blend',        'Tops', 'Men', 'Dusty Blue', 'L',  39.99, 35, 1, 27.99, '/images/m-linen-blue-l.jpg'),

-- ── MEN'S BOTTOMS ───────────────────────────────────────────────
('Slim-Fit Chinos',        'Stretch cotton, tapered leg, 5-pocket',         'Bottoms', 'Men', 'Khaki',      'S',  49.99, 55, 0, NULL,  '/images/m-chino-khaki-s.jpg'),
('Slim-Fit Chinos',        'Stretch cotton, tapered leg, 5-pocket',         'Bottoms', 'Men', 'Khaki',      'M',  49.99, 60, 0, NULL,  '/images/m-chino-khaki-m.jpg'),
('Slim-Fit Chinos',        'Stretch cotton, tapered leg, 5-pocket',         'Bottoms', 'Men', 'Khaki',      'L',  49.99, 50, 0, NULL,  '/images/m-chino-khaki-l.jpg'),
('Slim-Fit Chinos',        'Stretch cotton, tapered leg, 5-pocket',         'Bottoms', 'Men', 'Navy',       'M',  49.99, 55, 0, NULL,  '/images/m-chino-navy-m.jpg'),
('Slim-Fit Chinos',        'Stretch cotton, tapered leg, 5-pocket',         'Bottoms', 'Men', 'Olive',      'M',  49.99, 50, 0, NULL,  '/images/m-chino-olive-m.jpg'),
('Slim-Fit Jeans',         'Slim tapered, mid-rise, stretch denim',         'Bottoms', 'Men', 'Dark Wash',  'S',  54.99, 55, 0, NULL,  '/images/m-jeans-dark-s.jpg'),
('Slim-Fit Jeans',         'Slim tapered, mid-rise, stretch denim',         'Bottoms', 'Men', 'Dark Wash',  'M',  54.99, 65, 0, NULL,  '/images/m-jeans-dark-m.jpg'),
('Slim-Fit Jeans',         'Slim tapered, mid-rise, stretch denim',         'Bottoms', 'Men', 'Dark Wash',  'L',  54.99, 60, 0, NULL,  '/images/m-jeans-dark-l.jpg'),
('Slim-Fit Jeans',         'Slim tapered, mid-rise, stretch denim',         'Bottoms', 'Men', 'Light Wash', 'M',  54.99, 55, 0, NULL,  '/images/m-jeans-light-m.jpg'),
('Cargo Trousers',         'Relaxed fit, multi-pocket, drawstring waist',   'Bottoms', 'Men', 'Olive',      'M',  59.99, 40, 1, 39.99, '/images/m-cargo-olive-m.jpg'),
('Cargo Trousers',         'Relaxed fit, multi-pocket, drawstring waist',   'Bottoms', 'Men', 'Olive',      'L',  59.99, 38, 1, 39.99, '/images/m-cargo-olive-l.jpg'),
('Cargo Trousers',         'Relaxed fit, multi-pocket, drawstring waist',   'Bottoms', 'Men', 'Black',      'M',  59.99, 45, 1, 39.99, '/images/m-cargo-black-m.jpg'),
('Cargo Trousers',         'Relaxed fit, multi-pocket, drawstring waist',   'Bottoms', 'Men', 'Black',      'L',  59.99, 42, 1, 39.99, '/images/m-cargo-black-l.jpg'),

-- ── MEN'S OUTERWEAR ─────────────────────────────────────────────
('Harrington Jacket',      'Classic check lining, zip front',               'Outerwear', 'Men', 'Tan',          'S',  79.99, 30, 0, NULL,  '/images/m-harrington-tan-s.jpg'),
('Harrington Jacket',      'Classic check lining, zip front',               'Outerwear', 'Men', 'Tan',          'M',  79.99, 35, 0, NULL,  '/images/m-harrington-tan-m.jpg'),
('Harrington Jacket',      'Classic check lining, zip front',               'Outerwear', 'Men', 'Black',        'M',  79.99, 35, 0, NULL,  '/images/m-harrington-black-m.jpg'),
('Harrington Jacket',      'Classic check lining, zip front',               'Outerwear', 'Men', 'Black',        'L',  79.99, 30, 0, NULL,  '/images/m-harrington-black-l.jpg'),
('Puffer Jacket',          'Recycled fill, stand collar, zip pockets',      'Outerwear', 'Men', 'Black',        'M',  99.99, 25, 1, 69.99, '/images/m-puffer-black-m.jpg'),
('Puffer Jacket',          'Recycled fill, stand collar, zip pockets',      'Outerwear', 'Men', 'Black',        'L',  99.99, 28, 1, 69.99, '/images/m-puffer-black-l.jpg'),
('Puffer Jacket',          'Recycled fill, stand collar, zip pockets',      'Outerwear', 'Men', 'Forest Green', 'M',  99.99, 20, 1, 69.99, '/images/m-puffer-green-m.jpg'),
('Wool-Blend Overcoat',    'Double-breasted, notch lapel, wool blend',      'Outerwear', 'Men', 'Camel',        'M', 149.99, 15, 0, NULL,  '/images/m-overcoat-camel-m.jpg'),
('Wool-Blend Overcoat',    'Double-breasted, notch lapel, wool blend',      'Outerwear', 'Men', 'Camel',        'L', 149.99, 18, 0, NULL,  '/images/m-overcoat-camel-l.jpg'),
('Wool-Blend Overcoat',    'Double-breasted, notch lapel, wool blend',      'Outerwear', 'Men', 'Charcoal',     'M', 149.99, 14, 0, NULL,  '/images/m-overcoat-charcoal-m.jpg'),

-- ── UNISEX KNITWEAR ─────────────────────────────────────────────
('Chunky Knit Sweater',    'Oversized, drop shoulder, ribbed hem',          'Knitwear', 'Unisex', 'Oatmeal',  'S',  59.99, 45, 0, NULL, '/images/u-chunky-oat-s.jpg'),
('Chunky Knit Sweater',    'Oversized, drop shoulder, ribbed hem',          'Knitwear', 'Unisex', 'Oatmeal',  'M',  59.99, 50, 0, NULL, '/images/u-chunky-oat-m.jpg'),
('Chunky Knit Sweater',    'Oversized, drop shoulder, ribbed hem',          'Knitwear', 'Unisex', 'Charcoal', 'S',  59.99, 40, 0, NULL, '/images/u-chunky-char-s.jpg'),
('Chunky Knit Sweater',    'Oversized, drop shoulder, ribbed hem',          'Knitwear', 'Unisex', 'Charcoal', 'M',  59.99, 45, 0, NULL, '/images/u-chunky-char-m.jpg'),
('Merino Turtleneck',      'Fine-knit merino wool, slim fit',               'Knitwear', 'Unisex', 'Camel',    'S',  69.99, 30, 0, NULL, '/images/u-turtleneck-camel-s.jpg'),
('Merino Turtleneck',      'Fine-knit merino wool, slim fit',               'Knitwear', 'Unisex', 'Camel',    'M',  69.99, 35, 0, NULL, '/images/u-turtleneck-camel-m.jpg'),
('Merino Turtleneck',      'Fine-knit merino wool, slim fit',               'Knitwear', 'Unisex', 'Black',    'S',  69.99, 40, 0, NULL, '/images/u-turtleneck-black-s.jpg'),
('Merino Turtleneck',      'Fine-knit merino wool, slim fit',               'Knitwear', 'Unisex', 'Black',    'M',  69.99, 45, 0, NULL, '/images/u-turtleneck-black-m.jpg'),
('Zip-Up Hoodie',          'French terry cotton, kangaroo pocket',          'Knitwear', 'Unisex', 'Black',    'S',  44.99, 60, 0, NULL, '/images/u-hoodie-black-s.jpg'),
('Zip-Up Hoodie',          'French terry cotton, kangaroo pocket',          'Knitwear', 'Unisex', 'Black',    'M',  44.99, 70, 0, NULL, '/images/u-hoodie-black-m.jpg'),
('Zip-Up Hoodie',          'French terry cotton, kangaroo pocket',          'Knitwear', 'Unisex', 'Black',    'L',  44.99, 65, 0, NULL, '/images/u-hoodie-black-l.jpg'),
('Zip-Up Hoodie',          'French terry cotton, kangaroo pocket',          'Knitwear', 'Unisex', 'Grey Marl','M',  44.99, 65, 0, NULL, '/images/u-hoodie-grey-m.jpg'),

-- ── UNISEX ACTIVEWEAR ───────────────────────────────────────────
('Jogger Sweatpants',       'Fleece-lined, tapered, elastic cuffs',         'Activewear', 'Unisex', 'Black',      'S',  34.99, 70, 0, NULL, '/images/u-jogger-black-s.jpg'),
('Jogger Sweatpants',       'Fleece-lined, tapered, elastic cuffs',         'Activewear', 'Unisex', 'Black',      'M',  34.99, 80, 0, NULL, '/images/u-jogger-black-m.jpg'),
('Jogger Sweatpants',       'Fleece-lined, tapered, elastic cuffs',         'Activewear', 'Unisex', 'Black',      'L',  34.99, 75, 0, NULL, '/images/u-jogger-black-l.jpg'),
('Jogger Sweatpants',       'Fleece-lined, tapered, elastic cuffs',         'Activewear', 'Unisex', 'Grey Marl',  'M',  34.99, 75, 0, NULL, '/images/u-jogger-grey-m.jpg'),
('Performance Leggings',    'High-waist, 4-way stretch, hidden pocket',     'Activewear', 'Women', 'Black',       'XS', 29.99, 80, 0, NULL, '/images/w-leggings-black-xs.jpg'),
('Performance Leggings',    'High-waist, 4-way stretch, hidden pocket',     'Activewear', 'Women', 'Black',       'S',  29.99, 90, 0, NULL, '/images/w-leggings-black-s.jpg'),
('Performance Leggings',    'High-waist, 4-way stretch, hidden pocket',     'Activewear', 'Women', 'Black',       'M',  29.99, 85, 0, NULL, '/images/w-leggings-black-m.jpg'),
('Performance Leggings',    'High-waist, 4-way stretch, hidden pocket',     'Activewear', 'Women', 'Dusty Mauve', 'S',  29.99, 60, 0, NULL, '/images/w-leggings-mauve-s.jpg'),

-- ── ACCESSORIES ─────────────────────────────────────────────────
('Canvas Tote Bag',        'Heavy-duty canvas, internal zip pocket',        'Accessories', 'Unisex', 'Natural', 'One Size', 19.99, 100, 0, NULL,  '/images/u-tote-natural.jpg'),
('Canvas Tote Bag',        'Heavy-duty canvas, internal zip pocket',        'Accessories', 'Unisex', 'Black',   'One Size', 19.99,  90, 0, NULL,  '/images/u-tote-black.jpg'),
('Knit Beanie',            'Ribbed knit, turn-up brim',                     'Accessories', 'Unisex', 'Black',   'One Size', 14.99,  80, 0, NULL,  '/images/u-beanie-black.jpg'),
('Knit Beanie',            'Ribbed knit, turn-up brim',                     'Accessories', 'Unisex', 'Oatmeal', 'One Size', 14.99,  75, 0, NULL,  '/images/u-beanie-oatmeal.jpg'),
('Knit Beanie',            'Ribbed knit, turn-up brim',                     'Accessories', 'Unisex', 'Camel',   'One Size', 14.99,  70, 0, NULL,  '/images/u-beanie-camel.jpg'),
('Woven Belt',             'Faux-leather, pin-buckle, 3.5cm width',         'Accessories', 'Unisex', 'Brown',   'S/M',      12.99,  60, 0, NULL,  '/images/u-belt-brown-sm.jpg'),
('Woven Belt',             'Faux-leather, pin-buckle, 3.5cm width',         'Accessories', 'Unisex', 'Black',   'S/M',      12.99,  65, 0, NULL,  '/images/u-belt-black-sm.jpg'),
('Woven Belt',             'Faux-leather, pin-buckle, 3.5cm width',         'Accessories', 'Unisex', 'Black',   'L/XL',     12.99,  55, 0, NULL,  '/images/u-belt-black-lxl.jpg'),
('Chain Shoulder Bag',     'Faux leather, adjustable chain strap',          'Accessories', 'Women',  'Black',   'One Size', 39.99,  40, 1, 27.99, '/images/w-chainbag-black.jpg'),
('Chain Shoulder Bag',     'Faux leather, adjustable chain strap',          'Accessories', 'Women',  'Tan',     'One Size', 39.99,  35, 1, 27.99, '/images/w-chainbag-tan.jpg'),

-- ── FOOTWEAR ────────────────────────────────────────────────────
('Chunky Platform Boots',  'Faux leather upper, lace-up, block heel',       'Footwear', 'Women', 'Black', '6',  79.99, 20, 0, NULL,  '/images/w-platform-black-6.jpg'),
('Chunky Platform Boots',  'Faux leather upper, lace-up, block heel',       'Footwear', 'Women', 'Black', '7',  79.99, 25, 0, NULL,  '/images/w-platform-black-7.jpg'),
('Chunky Platform Boots',  'Faux leather upper, lace-up, block heel',       'Footwear', 'Women', 'Black', '8',  79.99, 22, 0, NULL,  '/images/w-platform-black-8.jpg'),
('Canvas Sneakers',        'Low-top, rubber sole, lace-up',                 'Footwear', 'Unisex','White', '7',  34.99, 40, 0, NULL,  '/images/u-sneaker-white-7.jpg'),
('Canvas Sneakers',        'Low-top, rubber sole, lace-up',                 'Footwear', 'Unisex','White', '8',  34.99, 45, 0, NULL,  '/images/u-sneaker-white-8.jpg'),
('Canvas Sneakers',        'Low-top, rubber sole, lace-up',                 'Footwear', 'Unisex','White', '9',  34.99, 40, 0, NULL,  '/images/u-sneaker-white-9.jpg'),
('Canvas Sneakers',        'Low-top, rubber sole, lace-up',                 'Footwear', 'Unisex','Black', '8',  34.99, 50, 0, NULL,  '/images/u-sneaker-black-8.jpg'),
('Canvas Sneakers',        'Low-top, rubber sole, lace-up',                 'Footwear', 'Unisex','Black', '9',  34.99, 45, 0, NULL,  '/images/u-sneaker-black-9.jpg'),
('Derby Leather Shoes',    'Smooth faux leather, brogue detailing',         'Footwear', 'Men',   'Black', '9',  69.99, 20, 1, 49.99, '/images/m-derby-black-9.jpg'),
('Derby Leather Shoes',    'Smooth faux leather, brogue detailing',         'Footwear', 'Men',   'Black', '10', 69.99, 22, 1, 49.99, '/images/m-derby-black-10.jpg'),
('Derby Leather Shoes',    'Smooth faux leather, brogue detailing',         'Footwear', 'Men',   'Tan',   '9',  69.99, 18, 1, 49.99, '/images/m-derby-tan-9.jpg'),
('Derby Leather Shoes',    'Smooth faux leather, brogue detailing',         'Footwear', 'Men',   'Tan',   '10', 69.99, 20, 1, 49.99, '/images/m-derby-tan-10.jpg');


-- ----------------------------------------------------------------
-- Discount Codes
-- ----------------------------------------------------------------
INSERT INTO DiscountCodes (code, discountType, discountValue, usageLimit, expiresAt) VALUES
  ('WELCOME10',   'percent', 10.00,  NULL, NULL),
  ('NEWSEASON20', 'percent', 20.00,  500,  DATE_ADD(NOW(), INTERVAL 60  DAY)),
  ('SAVE5',       'flat',     5.00,  200,  DATE_ADD(NOW(), INTERVAL 90  DAY)),
  ('FLASH50',     'percent', 50.00,   50,  DATE_ADD(NOW(), INTERVAL 7   DAY)),
  ('FREESHIP',    'flat',     8.99,  NULL, DATE_ADD(NOW(), INTERVAL 120 DAY));
