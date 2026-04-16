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

const initializePassport = require("./passport-config");
initializePassport(passport, pool);

// Users now stored in database



app.set("view engine", "ejs");
app.use(express.static("public"));
app.use(express.urlencoded({ extended: false }));
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
app.use(express.json());
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
        let query = "SELECT * FROM Inventory WHERE quantity > 0";
        let params = [];

        // for searching
        if (search) {
            query += " AND (product LIKE ? OR description LIKE ?)";
            const searchTerm = `%${search}%`;
            params.push(searchTerm, searchTerm);
        }

        let orderClauses = [];
        
        // sorting by availability
        if (sortStock === 'high') {
            orderClauses.push("quantity DESC");
        } else if (sortStock === 'low') {
            orderClauses.push("quantity ASC");
        }

        // sorting by price
        if (sortPrice === 'ASC' || sortPrice === 'DESC') {
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
            query: req.query
        });

    } catch (err) {
        console.error("Error fetching products:", err);
        res.status(500).send("Database Error");
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
    const total = cartItems.reduce((sum, item) => sum + (Number(item.itemTotal) || 0), 0);

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

app.post('/cart/update-qty', async (req, res) => {
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
      [userId]
    );

    const subtotal = cartItems.reduce(
      (sum, item) => sum + (Number(item.itemTotal) || 0),
      0
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
      [discountCode]
    );

    if (codes.length > 0) {
      const code = codes[0];

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
      discountMessage
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
    // For now, just show a placeholder. In a real app, you'd check user.role === 'admin'
    const [orders] = await pool.query(`
            SELECT 
                o.orderID,
                o.customerID,
                u.firstName,
                u.lastName,
                o.orderDate,
                o.status,
                o.total
            FROM Orders o
            LEFT JOIN Users u ON o.customerID = u.UserID
            ORDER BY o.orderDate DESC
            LIMIT 20
        `);

    res.render("admin.ejs", {
      name: req.user.firstName,
      user: req.user,
      orders,
    });
  } catch (err) {
    console.error("Error fetching admin data:", err);
    res.render("admin.ejs", {
      name: req.user.name,
      user: req.user,
      orders: [],
      error: "Unable to load orders",
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
      [userId]
    );

    const subtotal = cartItems.reduce(
      (sum, item) => sum + (Number(item.itemTotal) || 0),
      0
    );
    const tax = subtotal * 0.0825;
    const total = subtotal + tax;

    res.render("checkout.ejs", {
      name: req.user.firstName,
      user: req.user,
      cartItems,
      subtotal,
      tax,
      total
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

    await pool.query(
      "CALL sp_PlaceOrder(?, ?, @p_orderID, @p_message)",
      [userId, discountCode]
    );

    const [result] = await pool.query(
      "SELECT @p_orderID AS orderID, @p_message AS message"
    );

    const orderID = result[0].orderID;
    const message = result[0].message;

    if (!orderID || Number(orderID) < 0) {
      return res.redirect("/cart");
    }

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
    orderID
  });
});

app.listen(3000);

