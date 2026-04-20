if (process.env.NODE_ENV !== "production") {
  require("dotenv").config();
}
const fs = require("fs");
const path = require("path");
const express = require("express");
const app = express();
const bcrypt = require("bcrypt");
const passport = require("passport");
const flash = require("express-flash");
const session = require("express-session");
const methodOverride = require("method-override");
const pool = require("./lib/db");

const GENDERS = ["Men", "Women", "Unisex", "Kids"];

function normalizeImageURL(raw) {
  const s = (raw || "").trim();
  if (!s) return null;
  if (s.startsWith("http://") || s.startsWith("https://")) return s;
  if (s.startsWith("/")) return s;
  return "/" + s.replace(/^\/+/, "");
}

function parseInventoryBody(body) {
  const product = (body.product || "").trim();
  const description = (body.description || "").trim() || null;
  const category = (body.category || "").trim() || null;
  let gender = (body.gender || "Unisex").trim();
  if (!GENDERS.includes(gender)) gender = "Unisex";
  const color = (body.color || "").trim() || null;
  const size = (body.size || "").trim() || null;
  const price = Number(body.price);
  const quantity = Math.max(0, parseInt(body.quantity, 10) || 0);
  const onSale = body.onSale === "1" || body.onSale === "on";
  let salePrice = null;
  if (
    onSale &&
    body.salePrice != null &&
    String(body.salePrice).trim() !== ""
  ) {
    const sp = Number(body.salePrice);
    if (!Number.isNaN(sp)) salePrice = sp;
  }
  const imageURL = normalizeImageURL(body.imageURL);

  return {
    product,
    description,
    category,
    gender,
    color,
    size,
    price,
    quantity,
    onSale: onSale ? 1 : 0,
    salePrice,
    imageURL,
  };
}

const initializePassport = require("./passport-config");
initializePassport(passport, pool);

// Users now stored in database

app.set("view engine", "ejs");
app.use(express.static("public"));
app.use(express.urlencoded({ extended: false }));
app.use(express.json());
app.use(flash());
app.use(
  session({
    secret: process.env.SESSION_SECRET,
    resave: false,
    saveUninitialized: false,
  }),
);
app.use(passport.initialize());
app.use(passport.session());
app.use(methodOverride("_method"));
app.use("/images", express.static("images"));

// Setting up the routes
app.get("/", checkAuthenticated, async (req, res) => {
  try {
    const [categories] = await pool.query(`
      SELECT category, COUNT(DISTINCT product) AS itemCount
      FROM Inventory
      GROUP BY category
      ORDER BY category
    `);

    const [rawProducts] = await pool.query(`
      SELECT 
        MIN(ProductID) AS ProductID,
        product,
        MIN(description) AS description,
        category,
        MIN(price) AS price,
        MAX(onSale) AS onSale,
        MIN(salePrice) AS salePrice,
        SUM(quantity) AS quantity,
        MIN(imageURL) AS imageURL
      FROM Inventory
      WHERE quantity > 0
      GROUP BY product, category
      ORDER BY MAX(onSale) DESC, product ASC
    `);

    const products = rawProducts
      .filter((item) => {
        if (!item.imageURL) return false;

        // imageURL trong DB đang có dạng "/images/xxx.jpg"
        const fileName = path.basename(item.imageURL);
        const imagePath = path.join(__dirname, "images", fileName);

        return fs.existsSync(imagePath);
      })
      .slice(0, 12); // chỉ lấy 12 sản phẩm đầu có ảnh thật

    res.render("home.ejs", {
      name: req.user.firstName,
      user: req.user,
      categories,
      products,
    });
  } catch (err) {
    console.error("Error loading home page:", err);
    res.render("home.ejs", {
      name: req.user.firstName,
      user: req.user,
      categories: [],
      products: [],
    });
  }
});

app.get("/test-db", async (req, res) => {
  try {
    const [rows] = await pool.query("SELECT COUNT(*) AS total FROM Inventory");
    res.send(rows);
  } catch (err) {
    console.error(err);
    res.send("DB error");
  }
});

// changed implementation for sorting
app.get("/products", checkAuthenticated, async (req, res) => {
  try {
    const { search, sortPrice, sortStock } = req.query;

    // only show things in stock
    let query = "SELECT * FROM Inventory WHERE 1=1";
    let params = [];

    // for searching
    if (search) {
      query += " AND (product LIKE ? OR description LIKE ?)";
      const searchTerm = `%${search}%`;
      params.push(searchTerm, searchTerm);
    }

    let orderClauses = [];

    // sorting by availability
    if (sortStock === "high") {
      orderClauses.push("quantity DESC");
    } else if (sortStock === "low") {
      orderClauses.push("quantity ASC");
    }

    // sorting by price
    if (sortPrice === "ASC" || sortPrice === "DESC") {
      orderClauses.push(`price ${sortPrice}`);
    }

    if (orderClauses.length > 0) {
      query += " ORDER BY " + orderClauses.join(", ");
    } else {
      query += " ORDER BY product ASC";
    }

    const [products] = await pool.query(query, params);

    res.render("products.ejs", {
      name: req.user.firstName,
      user: req.user,
      products,
      query: req.query,
    });
  } catch (err) {
    console.error("Error fetching products:", err);
    res.status(500).send("Database Error");
  }
});

app.get("/product/:id", checkAuthenticated, async (req, res) => {
    const productId = req.params.id;
    try {
        const [rows] = await pool.query("SELECT * FROM Inventory WHERE ProductID = ?", [productId]);

        if (rows.length > 0) {
            res.render("product-detail.ejs", { product: rows[0], user: req.user });
        } else {
            res.status(404).send("Product not found");
        }
    } catch (err) {
        console.error(err);
        res.redirect("/products");
    }
});

app.get("/cart", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;
    const [cartItems] = await pool.query(
      `
        SELECT 
            sc.cartID,
            sc.ProductID,
            i.product,
            i.price,
            i.salePrice,
            i.onSale,
            i.color,
            i.size,
            i.imageURL,
            sc.quantity,
            (CASE WHEN i.onSale THEN i.salePrice ELSE i.price END * sc.quantity) AS itemTotal
        FROM ShopCart sc
        JOIN Inventory i ON sc.ProductID = i.ProductID
        WHERE sc.UserID = ?
    `,
      [userId],
    );
    // converting item.itemTotal into a number
    const total = cartItems.reduce(
      (sum, item) => sum + (Number(item.itemTotal) || 0),
      0,
    );

    res.render("cart.ejs", {
      name: req.user.firstName,
      user: req.user,
      cartItems,
      total,
    });
  } catch (err) {
    console.error("Error fetching cart:", err);
    res.render("cart.ejs", {
      name: req.user.firstName,
      user: req.user,
      cartItems: [],
      total: 0,
      error: "Unable to load cart",
    });
  }
});

app.post("/cart/add", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;
    const { productId, quantity } = req.body;

    // Check if item already in cart
    const [existing] = await pool.query(
      "SELECT * FROM ShopCart WHERE UserID = ? AND ProductID = ?",
      [userId, productId],
    );

    if (existing.length > 0) {
      // Update quantity
      await pool.query(
        "UPDATE ShopCart SET quantity = quantity + ? WHERE UserID = ? AND ProductID = ?",
        [quantity, userId, productId],
      );
    } else {
      // Add new item
      await pool.query(
        "INSERT INTO ShopCart (UserID, ProductID, quantity) VALUES (?, ?, ?)",
        [userId, productId, quantity],
      );
    }

    res.redirect("/cart");
  } catch (err) {
    console.error("Error adding to cart:", err);
    res.redirect("/cart");
  }
});

app.post("/cart/update-qty", async (req, res) => {
  const { cartID, amount } = req.body;

  console.log(`Updating Cart ID ${cartID} by ${amount}`);

  try {
    const sql = "UPDATE ShopCart SET quantity = quantity + ? WHERE cartID = ?";

    await pool.query(sql, [amount, cartID]);

    res.redirect("/cart");
  } catch (err) {
    console.error("Database error:", err);
    res.status(500).json({ success: false, error: "Database update failed" });
  }
});

app.post("/cart/apply-discount", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;
    const { discountCode } = req.body;

    const [cartItems] = await pool.query(
      `
      SELECT 
        sc.cartID,
        sc.ProductID,
        i.product,
        i.price,
        i.salePrice,
        i.onSale,
        i.color,
        i.size,
        i.imageURL,
        sc.quantity,
        (CASE WHEN i.onSale THEN i.salePrice ELSE i.price END * sc.quantity) AS itemTotal
      FROM ShopCart sc
      JOIN Inventory i ON sc.ProductID = i.ProductID
      WHERE sc.UserID = ?
      `,
      [userId],
    );

    const subtotal = cartItems.reduce(
      (sum, item) => sum + (Number(item.itemTotal) || 0),
      0,
    );

    let discountAmount = 0;
    let discountMessage = "Invalid or expired discount code.";

    const [codes] = await pool.query(
      `
      SELECT *
      FROM DiscountCodes
      WHERE code = ?
        AND isActive = 1
        AND (expiresAt IS NULL OR expiresAt > NOW())
        AND (usageLimit IS NULL OR usageCount < usageLimit)
      `,
      [discountCode],
    );

    if (codes.length > 0) {
      const code = codes[0];

      req.session.discountCode = code.code;

      if (code.discountType === "percent") {
        discountAmount = subtotal * (Number(code.discountValue) / 100);
      } else if (code.discountType === "flat") {
        discountAmount = Math.min(Number(code.discountValue), subtotal);
      }

      discountMessage = `Discount code "${code.code}" applied successfully.`;
    }

    const discountedSubtotal = Math.max(subtotal - discountAmount, 0);
    const tax = discountedSubtotal * 0.0825;
    const total = discountedSubtotal + tax;

    res.render("cart.ejs", {
      name: req.user.firstName,
      user: req.user,
      cartItems,
      total: discountedSubtotal,
      discountAmount,
      tax,
      finalTotal: total,
      discountMessage,
    });
  } catch (err) {
    console.error("Error applying discount:", err);
    res.redirect("/cart");
  }
});

app.post("/cart/remove/:cartId", checkAuthenticated, async (req, res) => {
  try {
    const { cartId } = req.params;
    const userId = req.user.UserID;

    await pool.query("DELETE FROM ShopCart WHERE cartID = ? AND UserID = ?", [
      cartId,
      userId,
    ]);

    res.redirect("/cart");
  } catch (err) {
    console.error("Error removing from cart:", err);
    res.redirect("/cart");
  }
});

app.get("/admin", checkAuthenticated, async (req, res) => {
  try {
    // Check if user is admin
    if (req.user.role !== "admin") {
      return res.render("admin.ejs", {
        user: req.user,
        message: "Access denied.",
      });
    }

    const { statusFilter, sortBy, sortDir } = req.query;
    let orderQuery = `
            SELECT 
                o.orderID,
                o.customerID,
                u.firstName,
                u.lastName,
                o.orderDate,
                o.status,
                o.orderTotal
            FROM Orders o
            LEFT JOIN Users u ON o.customerID = u.UserID
            WHERE 1=1
        `;

    // Apply status filter
    if (statusFilter && statusFilter !== "all") {
      orderQuery += ` AND o.status = '${statusFilter}'`;
    }

    // Apply sorting
    let sortColumn = "o.orderDate";
    if (sortBy === "customer") sortColumn = "u.firstName";
    else if (sortBy === "total") sortColumn = "o.orderTotal";

    const direction = sortDir === "ASC" ? "ASC" : "DESC";
    orderQuery += ` ORDER BY ${sortColumn} ${direction} LIMIT 20`;

    const [orders] = await pool.query(orderQuery);

    // Fetch discount codes
    const [discounts] = await pool.query(`
      SELECT * FROM DiscountCodes ORDER BY createdAt DESC
    `);

    // Fetch users
    const [users] = await pool.query(`
      SELECT UserID, firstName, lastName, email, role FROM Users ORDER BY firstName
    `);

    const [inventory] = await pool.query(`
      SELECT * FROM Inventory
      ORDER BY category, product, color, size, ProductID
    `);

    res.render("admin.ejs", {
      name: req.user.firstName,
      user: req.user,
      orders,
      discounts: discounts || [],
      users: users || [],
      inventory: inventory || [],
      genders: GENDERS,
      query: req.query,
    });
  } catch (err) {
    console.error("Error fetching admin data:", err);
    res.render("admin.ejs", {
      name: req.user.firstName,
      user: req.user,
      orders: [],
      discounts: [],
      users: [],
      inventory: [],
      genders: GENDERS,
      query: {},
      error: "Unable to load admin data",
    });
  }
});

app.get("/login", checkNotAuthenticated, (req, res) => {
  res.render("login.ejs");
});

app.post(
  "/login",
  checkNotAuthenticated,
  passport.authenticate("local", {
    successRedirect: "/",
    failureRedirect: "/login",
    failureFlash: true,
  }),
);

app.get("/register", checkNotAuthenticated, (req, res) => {
  res.render("register.ejs");
});

app.post("/register", checkNotAuthenticated, async (req, res) => {
  try {
    const hashedPassword = await bcrypt.hash(req.body.password, 10);
    const nameParts = req.body.name.trim().split(" ");
    const firstName = nameParts[0];
    const lastName = nameParts.slice(1).join(" ") || "";

    await pool.query(
      "INSERT INTO Users (firstName, lastName, userName, password, email, role) VALUES (?, ?, ?, ?, ?, 'customer')",
      [firstName, lastName, req.body.email, hashedPassword, req.body.email],
    );

    res.redirect("/login");
  } catch (err) {
    console.error("Registration error:", err);
    res.redirect("/register");
  }
});

// For logout
app.delete("/logout", (req, res) => {
  req.logOut((err) => {
    if (err) {
      return next(err);
    }
    res.redirect("/login");
  });
});

// Create inventory SKU
app.post("/admin/inventory/create", checkAuthenticated, async (req, res) => {
  console.log("POST /admin/inventory body:", req.body);
  try {
    if (req.user.role !== "admin") {
      return res.redirect("/admin");
    }

    const row = parseInventoryBody(req.body);
    if (!row.product || Number.isNaN(row.price) || row.price < 0) {
      return res.redirect("/admin");
    }

    await pool.query(
      `INSERT INTO Inventory
        (product, description, category, gender, color, size, price, quantity, onSale, salePrice, imageURL)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      [
        row.product,
        row.description,
        row.category,
        row.gender,
        row.color,
        row.size,
        row.price,
        row.quantity,
        row.onSale,
        row.salePrice,
        row.imageURL,
      ],
    );

    res.redirect("/admin");
  } catch (err) {
    console.error("Error creating inventory:", err);
    res.redirect("/admin");
  }
});

// Edit inventory form
app.get(
  "/admin/inventory/item/:productId/edit",
  checkAuthenticated,
  async (req, res) => {
    try {
      if (req.user.role !== "admin") {
        return res.redirect("/admin");
      }

      const productId = parseInt(req.params.productId, 10);
      if (Number.isNaN(productId)) {
        return res.redirect("/admin");
      }

      const [rows] = await pool.query(
        "SELECT * FROM Inventory WHERE ProductID = ? LIMIT 1",
        [productId],
      );

      const item = rows[0];
      if (!item) {
        return res.redirect("/admin");
      }

      res.render("inventory-edit.ejs", {
        name: req.user.firstName,
        user: req.user,
        item,
        genders: GENDERS,
      });
    } catch (err) {
      console.error("Error loading inventory edit:", err);
      res.redirect("/admin");
    }
  },
);

// Update inventory SKU
app.put(
  "/admin/inventory/item/:productId",
  checkAuthenticated,
  async (req, res) => {
    try {
      if (req.user.role !== "admin") {
        return res.redirect("/admin");
      }

      const productId = parseInt(req.params.productId, 10);
      if (Number.isNaN(productId)) {
        return res.redirect("/admin");
      }

      const row = parseInventoryBody(req.body);
      if (!row.product || Number.isNaN(row.price) || row.price < 0) {
        return res.redirect(`/admin/inventory/item/${productId}/edit`);
      }

      const [result] = await pool.query(
        `UPDATE Inventory SET
        product = ?,
        description = ?,
        category = ?,
        gender = ?,
        color = ?,
        size = ?,
        price = ?,
        quantity = ?,
        onSale = ?,
        salePrice = ?,
        imageURL = ?
       WHERE ProductID = ?`,
        [
          row.product,
          row.description,
          row.category,
          row.gender,
          row.color,
          row.size,
          row.price,
          row.quantity,
          row.onSale,
          row.salePrice,
          row.imageURL,
          productId,
        ],
      );

      if (result.affectedRows === 0) {
        return res.redirect("/admin");
      }

      res.redirect("/admin");
    } catch (err) {
      console.error("Error updating inventory:", err);
      res.redirect("/admin");
    }
  },
);
// Delete inventory SKU
app.delete(
  "/admin/inventory/item/:productId",
  checkAuthenticated,
  async (req, res) => {
    try {
      if (req.user.role !== "admin") return res.redirect("/admin");

      const productId = parseInt(req.params.productId, 10);
      if (Number.isNaN(productId)) return res.redirect("/admin");

      await pool.query("DELETE FROM Inventory WHERE ProductID = ?", [
        productId,
      ]);
      res.redirect("/admin");
    } catch (err) {
      console.error("Error deleting inventory:", err);
      res.redirect("/admin");
    }
  },
);

// Create discount code
app.post("/admin/discounts", checkAuthenticated, async (req, res) => {
  try {
    if (req.user.role !== "admin") {
      return res.redirect("/admin");
    }

    const { code, discountType, discountValue, usageLimit, expiresAt } =
      req.body;

    await pool.query(
      `INSERT INTO DiscountCodes (code, discountType, discountValue, usageLimit, expiresAt, isActive, usageCount, createdAt)
       VALUES (?, ?, ?, ?, ?, 1, 0, NOW())`,
      [
        code,
        discountType,
        discountValue,
        usageLimit || null,
        expiresAt || null,
      ],
    );

    res.redirect("/admin");
  } catch (err) {
    console.error("Error creating discount code:", err);
    res.redirect("/admin");
  }
});

// Delete discount code
app.delete(
  "/admin/discounts/:discountId",
  checkAuthenticated,
  async (req, res) => {
    try {
      if (req.user.role !== "admin") {
        return res.redirect("/admin");
      }

      const { discountId } = req.params;

      await pool.query("DELETE FROM DiscountCodes WHERE discountID = ?", [
        discountId,
      ]);

      res.redirect("/admin");
    } catch (err) {
      console.error("Error deleting discount code:", err);
      res.redirect("/admin");
    }
  },
);

// Update user role
app.post("/admin/users/:userId/role", checkAuthenticated, async (req, res) => {
  try {
    if (req.user.role !== "admin") {
      return res.redirect("/admin");
    }

    const { userId } = req.params;
    const { role } = req.body;

    await pool.query("UPDATE Users SET role = ? WHERE UserID = ?", [
      role,
      userId,
    ]);

    res.redirect("/admin");
  } catch (err) {
    console.error("Error updating user role:", err);
    res.redirect("/admin");
  }
});

// Delete user
app.delete("/admin/users/:userId", checkAuthenticated, async (req, res) => {
  try {
    if (req.user.role !== "admin") {
      return res.redirect("/admin");
    }

    const { userId } = req.params;

    await pool.query("DELETE FROM Users WHERE UserID = ?", [userId]);
    // Also delete their related data (cart, orders, etc.) if needed

    res.redirect("/admin");
  } catch (err) {
    console.error("Error deleting user:", err);
    res.redirect("/admin");
  }
});

function checkAuthenticated(req, res, next) {
  if (req.isAuthenticated()) {
    return next();
  }
  res.redirect("/login");
}

function checkNotAuthenticated(req, res, next) {
  if (req.isAuthenticated()) {
    return res.redirect("/");
  }
  next();
}

app.get("/checkout", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;

    const [cartItems] = await pool.query(
      `
      SELECT 
        sc.cartID,
        sc.ProductID,
        i.product,
        i.price,
        i.salePrice,
        i.onSale,
        i.color,
        i.size,
        i.imageURL,
        sc.quantity,
        (CASE WHEN i.onSale THEN i.salePrice ELSE i.price END * sc.quantity) AS itemTotal
      FROM ShopCart sc
      JOIN Inventory i ON sc.ProductID = i.ProductID
      WHERE sc.UserID = ?
      `,
      [userId],
    );

    const subtotal = cartItems.reduce(
      (sum, item) => sum + (Number(item.itemTotal) || 0),
      0,
    );

    const appliedCode = req.session.discountCode || null;
    let discountAmount = 0;

    if (appliedCode) {
        const [discountResults] = await pool.query(
            "SELECT discountType, discountValue FROM DiscountCodes WHERE code = ? AND isActive = 1", 
            [appliedCode]
        );

        if (discountResults.length > 0) {
            const d = discountResults[0];
            const val = Number(d.discountValue);

            if (d.discountType === 'percent') {
                discountAmount = subtotal * (val / 100);
            } else {
                discountAmount = val;
            }
        }
    }

    const discountedSubtotal = Math.max(0, subtotal - discountAmount);
    const tax = discountedSubtotal * 0.0825;
    const total = discountedSubtotal + tax;

    console.log("Session Code:", req.session.discountCode);
    console.log("Subtotal:", subtotal);
    console.log("Calculated Discount:", discountAmount);

    res.render("checkout.ejs", {
      name: req.user.firstName,
      user: req.user,
      cartItems,
      subtotal,
      discountAmount,
      tax,
      total,
      appliedCode: req.session.discountCode || ""
    });
  } catch (err) {
    console.error("Error loading checkout:", err);
    res.redirect("/cart");
  }
});

app.post("/checkout/place-order", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;
    const discountCode = req.body.discountCode || null;

    await pool.query("SET @p_orderID = 0");
    await pool.query("SET @p_message = ''");

    await pool.query("CALL sp_PlaceOrder(?, ?, @p_orderID, @p_message)", [
      userId,
      discountCode,
    ]);

    const [result] = await pool.query(
      "SELECT @p_orderID AS orderID, @p_message AS message",
    );

    const orderID = result[0].orderID;
    const message = result[0].message;

    if (!orderID || Number(orderID) < 0) {
      return res.redirect("/cart");
    }
    
    req.session.discountCode = null;
    res.redirect(`/thank-you?orderID=${orderID}`);
  } catch (err) {
    console.error("Error placing order:", err);
    res.redirect("/checkout");
  }
});

app.get("/thank-you", checkAuthenticated, (req, res) => {
  const orderID = req.query.orderID;

  res.render("thank-you.ejs", {
    name: req.user.firstName,
    user: req.user,
    orderID,
  });
});

app.get("/orders", checkAuthenticated, async (req, res) => {
  try {
    const userId = req.user.UserID;

    const [orders] = await pool.query(
      `SELECT orderID, orderDate, status, subtotal, taxAmount, discountAmount, orderTotal
       FROM Orders
       WHERE customerID = ?
       ORDER BY orderDate DESC`,
      [userId],
    );

    const ordersWithItems = orders.map((o) => ({ ...o, items: [] }));

    if (orders.length > 0) {
      const ids = orders.map((o) => o.orderID);
      const placeholders = ids.map(() => "?").join(",");
      const [items] = await pool.query(
        `SELECT oi.orderID, oi.quantity, oi.priceAtPurchase, i.product, i.imageURL
         FROM OrderItems oi
         JOIN Inventory i ON i.ProductID = oi.productID
         WHERE oi.orderID IN (${placeholders})
         ORDER BY oi.itemID ASC`,
        ids,
      );

      const byOrderId = new Map(ordersWithItems.map((o) => [o.orderID, o]));
      for (const row of items) {
        const order = byOrderId.get(row.orderID);
        if (order) {
          order.items.push({
            product: row.product,
            quantity: row.quantity,
            priceAtPurchase: row.priceAtPurchase,
            imageURL: row.imageURL,
          });
        }
      }
    }

    res.render("orders.ejs", {
      name: req.user.firstName,
      user: req.user,
      orders: ordersWithItems,
    });
  } catch (err) {
    console.error("Error loading orders:", err);
    res.status(500).render("orders.ejs", {
      name: req.user.firstName,
      user: req.user,
      orders: [],
      error: "We could not load your orders. Please try again later.",
    });
  }
});

app.listen(3000);
