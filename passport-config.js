const LocalStrategy = require("passport-local").Strategy;
const bcrypt = require("bcrypt");

function initialize(passport, pool) {
  const authenticateUser = async (email, password, done) => {
    try {
      const [users] = await pool.query("SELECT * FROM Users WHERE email = ?", [
        email,
      ]);
      const user = users[0];

      if (!user) {
        return done(null, false, { message: "No user with that email" });
      }

      if (await bcrypt.compare(password, user.password)) {
        return done(null, user);
      } else {
        return done(null, false, { message: "Incorrect Password" });
      }
    } catch (e) {
      return done(e);
    }
  };

  passport.use(new LocalStrategy({ usernameField: "email" }, authenticateUser));

  passport.serializeUser((user, done) => done(null, user.UserID));

  passport.deserializeUser(async (id, done) => {
    try {
      const [users] = await pool.query("SELECT * FROM Users WHERE UserID = ?", [
        id,
      ]);
      return done(null, users[0]);
    } catch (e) {
      return done(e);
    }
  });
}

module.exports = initialize;
