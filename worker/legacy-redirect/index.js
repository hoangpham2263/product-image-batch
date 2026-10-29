// The Worker was renamed to product-review-batch-api. This one keeps the old address working: image links in
// CSV files exported before, and app versions that still call the old address, are sent to the new one.
const TARGET = "https://product-review-batch-api.hoangpham2263.workers.dev";
export default {
  fetch(req) {
    const url = new URL(req.url);
    return Response.redirect(TARGET + url.pathname + url.search, 308);
  },
};
