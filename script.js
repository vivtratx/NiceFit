const app = document.getElementById("app");

function router() {
  const page = window.location.hash.slice(1) || "home";

  switch (page) {
    case "home":
      app.innerHTML = renderHome();
      break;
    case "products":
      app.innerHTML = renderProducts();
      break;
    case "cart":
      app.innerHTML = renderCart();
      break;
    case "auth":
      app.innerHTML = renderAuth();
      break;
    case "admin":
      app.innerHTML = renderAdmin();
      break;
    default:
      app.innerHTML = renderHome();
  }
}

window.addEventListener("hashchange", router);
window.addEventListener("load", router);
