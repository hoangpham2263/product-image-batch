// The Worker is now tools-hub-api. This one runs under each old name (product-images-api, product-review-batch-api)
// so old addresses keep working: image links in CSV files exported before, and app versions that still call them.
const TARGET = "https://tools-hub-api.hoangpham2263.workers.dev";
export default {
  fetch(req) {
    const url = new URL(req.url);
    return Response.redirect(TARGET + url.pathname + url.search, 308);
  },
};
