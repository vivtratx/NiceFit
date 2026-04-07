if (process.env.NODE_ENV !== "production") {
  require("dotenv").config();
}

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

// Setting up the routes
app.get("/", checkAuthenticated, (req, res) => {
  res.render("home.ejs", { name: req.user.firstName, user: req.user });
});

app.get("/products", checkAuthenticated, async (req, res) => {
  try {
    const [products] = await pool.query(
      "SELECT ProductID, product, description, category, gender, color, size, price, salePrice, onSale, quantity FROM Inventory WHERE quantity > 0 ORDER BY category, product",
    );
    res.render("products.ejs", {
      name: req.user.firstName,
      user: req.user,
      products,
    });
  } catch (err) {
    console.error("Error fetching products:", err);
    res.render("products.ejs", {
      name: req.user.firstName,
      user: req.user,
      products: [],
      error: "Unable to load products",
    });
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
                sc.quantity,
                (CASE WHEN i.onSale THEN i.salePrice ELSE i.price END * sc.quantity) as itemTotal
            FROM ShopCart sc
            JOIN Inventory i ON sc.ProductID = i.ProductID
            WHERE sc.UserID = ?
        `,
      [userId],
    );

    const total = cartItems.reduce((sum, item) => sum + item.itemTotal, 0);

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

app.listen(3000);
