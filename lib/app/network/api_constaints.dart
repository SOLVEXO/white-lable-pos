class ApiConstants {
  // Phase 6 (white-label build/identity separation): each app (buyer, POS)
  // can independently target dev/staging/prod without touching this shared
  // file — pass `--dart-define=API_BASE_URL=...` to `flutter run`/`build`.
  // Omitting it keeps today's behavior (staging) unchanged for both apps.
  static const String baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'https://api.solvexo.store',
  );

  static const String apiPrefix = "$baseUrl/api";

  // ============ White-Label Branding (Phase 4) ============
  // ⚠️ Backend does NOT implement this endpoint yet — requested from the
  // backend team as part of the white-label transformation. Expected shape:
  // GET, public or JWT-optional, response `{ success, data: { appName,
  // marketplaceName, logoUrl, primaryColor, secondaryColor, accentColor,
  // featureFlags: { [key: string]: boolean } } }`. Until it exists,
  // `BrandingRepository` calls this, gets a 404, and silently falls back to
  // `BrandingConfigModel.defaults()` — see that class's doc comment.
  static const String brandingConfig = "$apiPrefix/branding/config";

  // Timeouts
  static const int connectTimeout = 30000; // 30 seconds
  static const int receiveTimeout = 30000;

  // ============ Auth Endpoints ============
  // The buyer app dropped its email/password UI in favor of Google Sign-In
  // only (Phase 10) — but the backend endpoints themselves are still live
  // (verified directly against staging: POST /auth/login with a bad
  // password returns a real 401 "Invalid email or password", not a 404).
  // POS uses both: Google Sign-In and email/password, always with
  // role: 'seller'.
  static const String socialLogin = '$apiPrefix/auth/social-login';
  static const String login = '$apiPrefix/auth/login';
  static const String register = '$apiPrefix/auth/register';
  static const String verifyOtp = '$apiPrefix/auth/verifyOtp';
  static const String getMe = "$apiPrefix/auth/getprofile";
  static const String logout = "$apiPrefix/auth/logout";

  static const String faqs = '$apiPrefix/faqs';
  static const String contactUs = '$apiPrefix/contact';

  // ============ User Profile Endpoints ============
  static const String getUserProfile = "$apiPrefix/auth/getprofile";
  static const String editProfile = "$apiPrefix/auth/edit-profile";
  static const String updateUserProfile = "$apiPrefix/users/profile";
  static const String deleteUserAccount = "$apiPrefix/users/profile";
  static const String banners = "$apiPrefix/banners";

  // ============ Category Endpoints ============
  static const String categories = "$apiPrefix/categories/category-tree";
  static const String addCategory = "$apiPrefix/categories/add-category";
  static String getCategoryTree(String id) =>
      "$apiPrefix/categories/category-tree?id=$id";
  static String getCategoryById(String id) =>
      "$apiPrefix/categories/category/$id";
  // static String updateCategory(String id) => "$apiPrefix/categories/$id";
  // static String deleteCategory(String id) => "$apiPrefix/categories/$id";

  // ============ Product Endpoints ============
  static const String products = "$apiPrefix/products";
  static const String featuredProducts = "$apiPrefix/products/featured";
  static String getProductById(String id) =>
      '$apiPrefix/products/getProductById/$id';
  static String getVariantById(String id) =>
      '$apiPrefix/products/getVariantById/$id';
  // Public digital-product preview — watermarked/trimmed derivative only,
  // never the original file (see solvexo-api ProductsService.getProductPreview).
  static String getProductPreview(String productId) =>
      '$apiPrefix/products/preview/$productId';
  // ============ Product by Category Endpoint ============
  static String getProductsByCategory({
    String? categoryId,
    int page = 1,
    int limit = 10,
    String? productType,
    String? educationLevel,
    String? normalizedCustomLevel,
    double? minPrice,
    double? maxPrice,
    double? minRating,
    String? sortBy,
  }) {
    String url = '$apiPrefix/products/products-by-category';
    List<String> queryParams = [];

    if (categoryId != null && categoryId.isNotEmpty) {
      queryParams.add('id=$categoryId');
    }
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');
    if (productType != null && productType.isNotEmpty) {
      queryParams.add('productType=$productType');
    }
    if (educationLevel != null && educationLevel.isNotEmpty) {
      queryParams.add('educationLevel=$educationLevel');
    }
    if (normalizedCustomLevel != null && normalizedCustomLevel.isNotEmpty) {
      queryParams.add('normalizedCustomLevel=$normalizedCustomLevel');
    }
    if (minPrice != null) {
      queryParams.add('minPrice=$minPrice');
    }
    if (maxPrice != null) {
      queryParams.add('maxPrice=$maxPrice');
    }
    if (minRating != null) {
      queryParams.add('minRating=$minRating');
    }
    if (sortBy != null && sortBy.isNotEmpty) {
      queryParams.add('sortBy=$sortBy');
    }

    return '$url?${queryParams.join('&')}';
  }

  // Buyer-facing, unauthenticated facet counts backing the education-level
  // filter chips (Tier-1 `levels` + Tier-2 `otherLevels`).
  static const String educationFacets = '$apiPrefix/products/education/facets';

  // Seller-only autocomplete while typing a custom level on product creation.
  static String educationCustomLevelSuggestions(String q) =>
      '$apiPrefix/products/education/custom-level-suggestions?q=${Uri.encodeQueryComponent(q)}';

  // ============ Address Endpoints ============
  static const String addAdresses = "$baseUrl/address/add-address";
  static const String getAdresses = "$baseUrl/address/getMyAddresses";
  static const String updateAddress = "$baseUrl/address/update-address";
  static String deleteAddress(String id) =>
      "$baseUrl/address/delete-address/$id";
  static String getAddressById(String id) =>
      "$baseUrl/address/get-address-by-id/$id";
  static String setDefaultAddress(String id) =>
      "$baseUrl/address/setDefaultAddress/$id";

  // ============ Order Endpoints ============
  static const String orders = "$apiPrefix/orders";
  static const String myOrders = "$apiPrefix/orders/my-orders";
  static String getOrderById(String id) => "$apiPrefix/orders/$id";
  static String updateOrderToPaid(String id) => "$apiPrefix/orders/$id/pay";
  static String cancelOrder(String id) => "$apiPrefix/orders/cancel/$id";
  static String returnRequest(String orderId) =>
      "$apiPrefix/orders/return-request/$orderId";

  // ============ Refund Request Endpoints (item-level, supersedes return-request) ============
  static const String createRefundRequest = "$apiPrefix/refund-request";
  static String refundRequestsForOrder(String orderId) =>
      "$apiPrefix/refund-request/order/$orderId";
  static String refundRequestsForSeller(String storeId) =>
      "$apiPrefix/refund-request/seller/$storeId";
  static String approveRefundRequest(String id) =>
      "$apiPrefix/refund-request/$id/approve";
  static String rejectRefundRequest(String id) =>
      "$apiPrefix/refund-request/$id/reject";

  // Digital product delivery — signed, short-lived download tokens.
  // `endpoint` in each returned file is relative (e.g. "/api/orders/download-file"),
  // so it's joined with `baseUrl` (not `apiPrefix`, it already includes "/api").
  static const String ordersDownloadUrl = "$apiPrefix/orders/download-url";

  // ============ Rating / Review Endpoints ============
  static const String addReview = "$apiPrefix/rating/add-review";
  static const String myReviews = "$apiPrefix/rating/my-reviews";
  static String editReview(String reviewId) => "$apiPrefix/rating/$reviewId";
  static String deleteReview(String reviewId) => "$apiPrefix/rating/$reviewId";
  static String productReviews(String productId) =>
      "$apiPrefix/rating/product/$productId";
  static String reviewHelpful(String reviewId) =>
      "$apiPrefix/rating/$reviewId/helpful";
  static String storeReviews(String storeId) =>
      "$apiPrefix/rating/store-reviews/$storeId";
  static String replyToReview(String reviewId) =>
      "$apiPrefix/rating/reply/$reviewId";
  static String editReviewReply(String reviewId) =>
      "$apiPrefix/rating/edit-reply/$reviewId";

  // ============ Search Endpoints ============
  // Keyword product search + per-user recent searches / recently viewed
  // (`solvexo-api`'s `api/search/*`, SearchController).
  static const String searchProducts = '$apiPrefix/search/products';
  static const String recentSearches = '$apiPrefix/search/recent';
  static String deleteRecentSearch(String searchId) =>
      '$apiPrefix/search/recent/$searchId';
  static const String recentlyViewed = '$apiPrefix/search/recently-viewed';

  // Cart endpoints
  static const String getCart = '$apiPrefix/cart/get-cart';
  static const String clearCart = '$apiPrefix/cart/clear-cart';
  static const String cartCount = '$apiPrefix/cart/count';
  static const String addToCart = '$apiPrefix/cart/add-to-cart';
  static const String removeCartItem = '$apiPrefix/cart/remove-cart-item';
  static const String updateCartQuantity =
      '$apiPrefix/cart/update-cart-quantity';
  static const String clearWishList = '$apiPrefix/cart/clear-wishlist';
  static const String addToWishlist = '$apiPrefix/cart/add-to-wishlist';
  static const String getWishlist = '$apiPrefix/cart/get-wishlist';
  static const String getWishlistItem = '$apiPrefix/cart/get-wishlist-item';
  static const String removeFromWishlist =
      '$apiPrefix/cart/remove-from-wishlist';
  // ============ Checkout / Shipping Endpoints ============
  static const String createCheckout = "$apiPrefix/checkout/create-checkout";
  static const String addShippingInCheckout =
      "$apiPrefix/checkout/addShippingInCheckout";
  static const String applyCoupon = "$apiPrefix/checkout/apply-coupon";
  static String removeCoupon(String checkoutId) =>
      "$apiPrefix/checkout/remove-coupon/$checkoutId";
  static const String codPayment = "$apiPrefix/payment/cod-payment";
  static const String initiatePayment = "$apiPrefix/payment/initiate-payment";
  static const String paymentStatus = "$apiPrefix/payment/status";
  static const String getShippingZones = "$apiPrefix/checkout/getShippingZones";

  // ============ Manual Bank Transfer Endpoints (Pakistan) ============
  // The buyer's "pay into the platform's own bank account, upload proof"
  // alternative to Stripe — same {success, message, data} envelope as the
  // other `api/payment/*` routes above.
  static const String manualTransferBankDetails =
      "$apiPrefix/payment/manual-transfer/bank-details";
  static const String manualTransferSubmit =
      "$apiPrefix/payment/manual-transfer/submit";
  static const String manualTransferMyProofs =
      "$apiPrefix/payment/manual-transfer";
  static String manualTransferProofById(String proofId) =>
      "$apiPrefix/payment/manual-transfer/$proofId";
  static String manualTransferReupload(String proofId) =>
      "$apiPrefix/payment/manual-transfer/$proofId/reupload";
  // ============ Seller / Store Endpoints ============
  static const String createStore = "$apiPrefix/store/create-store";
  static const String updateStore = "$apiPrefix/store/update-store";
  static const String myStores = "$apiPrefix/store/my-stores";
  static String getStoreById(String id) => "$apiPrefix/store/getStoreById/$id";
  // Admin-configurable currencies a store's baseCurrency may be set to —
  // replaces the old hardcoded PKR/USD list.
  static const String enabledCurrencies =
      "$apiPrefix/store/public/enabled-currencies";
  // IP-detected country + a suggested (never enforced) currency, used to
  // pre-fill Onboarding's currency step before a store exists yet.
  static const String suggestLocation = "$apiPrefix/store/suggest-location";

  // ============ Store Verification (KYC) Endpoints — seller ============
  static String storeVerification(String storeId) =>
      "$apiPrefix/store/$storeId/verification";
  static String storeVerificationDocuments(String storeId) =>
      "$apiPrefix/store/$storeId/verification/documents";
  static String storeVerificationSubmit(String storeId) =>
      "$apiPrefix/store/$storeId/verification/submit";

  // ============ Public Storefront Endpoints ============
  static String publicStoreBySlug(String slug) =>
      "$apiPrefix/store/public/$slug";
  static String publicStoreProducts(String storeId) =>
      "$apiPrefix/store/public/$storeId/products";
  static String publicStoreFilters(String storeId) =>
      "$apiPrefix/store/public/$storeId/filters";

  // ============ Seller / Product Endpoints ============
  static const String addPhysicalProduct =
      "$apiPrefix/products/add-physical-product";
  static const String addDigitalProduct =
      "$apiPrefix/products/add-digital-product";
  static const String editProduct = "$apiPrefix/products/edit-product";
  static String deleteProduct(String productId) =>
      "$apiPrefix/products/delete-product/$productId";
  static String getMyProduct(String productId) =>
      "$apiPrefix/products/get-my-product/$productId";
  static String productVariants(String productId) =>
      "$apiPrefix/products/$productId/variants";
  static String productVariant(String productId, String variantId) =>
      "$apiPrefix/products/$productId/variants/$variantId";
  static String getStoreInventory(String storeId) =>
      "$apiPrefix/inventory/getStoreInventory/$storeId";
  static String lowStockSummary(String storeId) =>
      "$apiPrefix/inventory/low-stock-summary/$storeId";
  // Phase 2 (POS Customers): real past-buyers list for a store (paginated,
  // no search param) and a separate global registered-user search used to
  // attach a customer to a sale — see CustomerRepository.
  static String storeCustomers(String storeId) =>
      "$apiPrefix/store/$storeId/customers";
  static String customerSearch(String storeId) =>
      "$apiPrefix/draft-orders/$storeId/customers/search";
  static String sellerOrders(String storeId) =>
      "$apiPrefix/orders/seller-orders/$storeId";
  static String markOrderPaid(String orderId) =>
      "$apiPrefix/orders/mark-paid/$orderId";
  static const String updateOrderStatus = "$apiPrefix/orders/update-status";
  static const String sellerReturns = "$apiPrefix/orders/returns";
  static String returnAction(String orderId) =>
      "$apiPrefix/orders/return-action/$orderId";

  // ============ POS Endpoints ============
  // All GET endpoints below intentionally return a bare path — query params
  // are passed via BaseClient's `queryParameters:` map by the repository, not
  // string-interpolated here, so values are always properly encoded.
  static const String posPinLogin = '$apiPrefix/pos/pin-login';
  static const String posPinLogout = '$apiPrefix/pos/pin-logout';

  // Admin-managed POS plans + per-store purchase status (Stripe-backed,
  // fixed-term one-time purchase — no recurring subscription/billing
  // portal, see backend spec).
  static const String posPlans = '$apiPrefix/pos-plans';
  static String posSubscriptionStatus(String storeId) =>
      '$apiPrefix/pos-subscriptions/$storeId';
  static String posSubscriptionCheckoutSession(String storeId) =>
      '$apiPrefix/pos-subscriptions/$storeId/checkout-session';

  // Employees
  static String posEmployees(String storeId) =>
      '$apiPrefix/pos/employees/$storeId';
  static const String posEmployeesCreate = '$apiPrefix/pos/employees';
  static String posEmployeeLegacy(String employeeId) =>
      '$apiPrefix/pos/employees/$employeeId';
  static String posEmployeeV2(String storeId, String employeeId) =>
      '$apiPrefix/pos/employees/$storeId/$employeeId';
  static String posEmployeeResetPin(String storeId, String employeeId) =>
      '$apiPrefix/pos/employees/$storeId/$employeeId/reset-pin';

  // Registers
  static String posRegisters(String storeId) =>
      '$apiPrefix/pos/registers/$storeId';
  static String posRegisterById(String storeId, String registerId) =>
      '$apiPrefix/pos/registers/$storeId/$registerId';

  // Shifts
  static String posShifts(String storeId) => '$apiPrefix/pos/shifts/$storeId';
  static String posShiftById(String storeId, String shiftId) =>
      '$apiPrefix/pos/shifts/$storeId/$shiftId';

  // Sessions
  static const String posSessionsOpen = '$apiPrefix/pos/sessions/open';
  static const String posSessionsClose = '$apiPrefix/pos/sessions/close';
  static const String posSessionsActive = '$apiPrefix/pos/sessions/active';
  static const String posSessionsHistory = '$apiPrefix/pos/sessions/history';
  static String posSessionCashAdjustment(String sessionId) =>
      '$apiPrefix/pos/sessions/$sessionId/cash-adjustment';
  static String posSessionReport(String sessionId) =>
      '$apiPrefix/pos/sessions/$sessionId/report';
  static String posSessionForceClose(String sessionId) =>
      '$apiPrefix/pos/sessions/$sessionId/force-close';

  // Products (POS browse / search / barcode)
  static String posProducts(String storeId) =>
      '$apiPrefix/pos/products/$storeId';
  static const String posProductsSearch = '$apiPrefix/pos/products/search';
  static String posProductBarcode(String storeId, String barcode) =>
      '$apiPrefix/pos/products/barcode/$storeId/$barcode';

  // Sales
  static const String posSales = '$apiPrefix/pos/sales';
  static const String posSalesHeld = '$apiPrefix/pos/sales/held';
  static String posSaleById(String saleId) => '$apiPrefix/pos/sales/$saleId';
  static String posSaleComplete(String saleId) =>
      '$apiPrefix/pos/sales/$saleId/complete';
  static String posSaleDiscard(String saleId) =>
      '$apiPrefix/pos/sales/$saleId/discard';
  static String posSaleRefund(String saleId) =>
      '$apiPrefix/pos/sales/$saleId/refund';
  static String posSaleVoid(String saleId) =>
      '$apiPrefix/pos/sales/$saleId/void';
  static String posSaleItems(String saleId) =>
      '$apiPrefix/pos/sales/$saleId/items';

  // Reports
  static const String posReportsDaily = '$apiPrefix/pos/reports/daily';
  static const String posReportsDailyExport =
      '$apiPrefix/pos/reports/daily/export';
  static const String posReportsRange = '$apiPrefix/pos/reports/range';
  static String posReportsRegister(String registerId) =>
      '$apiPrefix/pos/reports/register/$registerId';
  static String posReportsEmployee(String employeeId) =>
      '$apiPrefix/pos/reports/employee/$employeeId';

  // Settings
  static String posSettings(String storeId) =>
      '$apiPrefix/pos/settings/$storeId';

  // Audit logs
  static String posAuditLogs(String storeId) =>
      '$apiPrefix/pos/audit-logs/$storeId';

  // ============ Activity Log Endpoints (store-wide, seller-only) ============
  static String activityLog(String storeId) =>
      '$apiPrefix/activity-log/$storeId';
  static String activityLogStats(String storeId) =>
      '$apiPrefix/activity-log/$storeId/stats';
  static String activityLogExport(String storeId) =>
      '$apiPrefix/activity-log/$storeId/export';

  // ============ Messaging Endpoints ============
  static const String startConversation = '$apiPrefix/messaging/conversations';
  static const String conversations = '$apiPrefix/messaging/conversations';
  static const String searchConversations =
      '$apiPrefix/messaging/conversations/search';
  static String conversationById(String id) =>
      '$apiPrefix/messaging/conversations/$id';
  static String archiveConversation(String id) =>
      '$apiPrefix/messaging/conversations/$id/archive';
  static String restoreConversation(String id) =>
      '$apiPrefix/messaging/conversations/$id/restore';
  static String pinConversation(String id) =>
      '$apiPrefix/messaging/conversations/$id/pin';
  static String muteConversation(String id) =>
      '$apiPrefix/messaging/conversations/$id/mute';
  static String deleteConversation(String id) =>
      '$apiPrefix/messaging/conversations/$id';
  static String conversationMessages(String convId) =>
      '$apiPrefix/messaging/conversations/$convId/messages';
  static String searchMessages(String convId) =>
      '$apiPrefix/messaging/conversations/$convId/messages/search';
  static String conversationAttachments(String convId) =>
      '$apiPrefix/messaging/conversations/$convId/attachments';
  static String editMessage(String id) => '$apiPrefix/messaging/messages/$id';
  static String deleteMessage(String id) => '$apiPrefix/messaging/messages/$id';
  static String markMessageSeen(String id) =>
      '$apiPrefix/messaging/messages/$id/seen';
  static const String blockUser = '$apiPrefix/messaging/block';
  static String unblockUser(String targetId) =>
      '$apiPrefix/messaging/block/$targetId';
  static const String reportTarget = '$apiPrefix/messaging/report';

  // ============ Upload Endpoints ============
  static const String uploadFile = '$apiPrefix/upload/file';
  static const String uploadPrivateFile = '$apiPrefix/upload/private-file';
  // static String get cartSync => null;

  // ============ Marketing (Coupons) Endpoints — seller ============
  static String coupons(String storeId) =>
      '$apiPrefix/marketing/$storeId/coupons';
  static String couponById(String storeId, String couponId) =>
      '$apiPrefix/marketing/$storeId/coupons/$couponId';

  // ============ Marketing (Campaigns) Endpoints — seller join/leave ========
  // Campaigns are platform/admin-created; sellers can only browse and
  // join/leave individual stores into them (never create/edit).
  static String joinableCampaigns(String storeId) =>
      '$apiPrefix/marketing/$storeId/campaigns';
  static String joinCampaign(String storeId, String campaignId) =>
      '$apiPrefix/marketing/$storeId/campaigns/$campaignId/join';
  static String leaveCampaign(String storeId, String campaignId) =>
      '$apiPrefix/marketing/$storeId/campaigns/$campaignId/leave';

  // ============ Public Marketing / Homepage Endpoints (unauthenticated) ====
  static const String publicActiveCampaigns =
      '$apiPrefix/public/marketing/campaigns';
  static const String publicPlatformStats =
      '$apiPrefix/store/public/platform-stats';
  static String publicTestimonials({int limit = 6}) =>
      '$apiPrefix/store/public/testimonials?limit=$limit';
  static String publicAnnouncements(String audience) =>
      '$apiPrefix/announcements/active?audience=$audience';
  static const String publicWorksheetTrial =
      '$apiPrefix/public/worksheet-builder/try-free';

  // ============ Loyalty & Rewards Endpoints — seller ============
  static String loyaltyOverview(String storeId) =>
      '$apiPrefix/loyalty/$storeId/overview';
  static String loyaltyProgram(String storeId) =>
      '$apiPrefix/loyalty/$storeId/program';
  static String loyaltyEarningRules(String storeId) =>
      '$apiPrefix/loyalty/$storeId/earning-rules';
  static String loyaltyTiers(String storeId) =>
      '$apiPrefix/loyalty/$storeId/tiers';
  static String loyaltyMembers(String storeId) =>
      '$apiPrefix/loyalty/$storeId/members';
  static String loyaltyMemberTransactions(String storeId, String memberId) =>
      '$apiPrefix/loyalty/$storeId/members/$memberId/transactions';
  static String loyaltyAwardPoints(String storeId, String memberId) =>
      '$apiPrefix/loyalty/$storeId/members/$memberId/award';
  // Seller's own management list — includes inactive rewards.
  static String loyaltyRewardsManage(String storeId) =>
      '$apiPrefix/loyalty/$storeId/rewards/manage';
  static String loyaltyRewardById(String storeId, String rewardId) =>
      '$apiPrefix/loyalty/$storeId/rewards/$rewardId';

  // ============ Loyalty & Rewards Endpoints — buyer ============
  // Public catalog — active rewards only.
  static String loyaltyRewards(String storeId) =>
      '$apiPrefix/loyalty/$storeId/rewards';
  static String loyaltyMyBalance(String storeId) =>
      '$apiPrefix/loyalty/$storeId/my-balance';
  static String loyaltyRedeem(String storeId) =>
      '$apiPrefix/loyalty/$storeId/redeem';

  // ============ Subscription Plans Endpoints — seller (store-scoped) ============
  static String subscriptionPlans(String storeId) =>
      '$apiPrefix/subscriptions/$storeId/plans';
  static String subscriptionPlanById(String storeId, String id) =>
      '$apiPrefix/subscriptions/$storeId/plans/$id';
  static String subscriptionsDashboard(String storeId) =>
      '$apiPrefix/subscriptions/$storeId/dashboard';
  static String subscriptionsList(String storeId) =>
      '$apiPrefix/subscriptions/$storeId/subscribers';
  static String subscriptionById(String storeId, String id) =>
      '$apiPrefix/subscriptions/$storeId/subscribers/$id';
  static String subscriptionPause(String storeId, String id) =>
      '$apiPrefix/subscriptions/$storeId/subscribers/$id/pause';
  static String subscriptionResume(String storeId, String id) =>
      '$apiPrefix/subscriptions/$storeId/subscribers/$id/resume';
  static String subscriptionCancel(
    String storeId,
    String id, {
    bool atPeriodEnd = false,
  }) =>
      '$apiPrefix/subscriptions/$storeId/subscribers/$id/cancel?atPeriodEnd=$atPeriodEnd';

  // ============ Seller Analytics Endpoints ============
  // All GET, storeId/range/from/to passed as query params via BaseClient's
  // `queryParameters` (same convention as coupons/loyalty/subscriptions).
  static const String analyticsToday = '$apiPrefix/seller/analytics/today';
  static const String analyticsOverview =
      '$apiPrefix/seller/analytics/overview';
  static const String analyticsRevenueOverTime =
      '$apiPrefix/seller/analytics/revenue-over-time';
  static const String analyticsOrdersOverTime =
      '$apiPrefix/seller/analytics/orders-over-time';
  static const String analyticsTrafficSources =
      '$apiPrefix/seller/analytics/traffic-sources';
  static const String analyticsTopProducts =
      '$apiPrefix/seller/analytics/top-products';
  static const String analyticsCustomers =
      '$apiPrefix/seller/analytics/customers';
  static const String analyticsProductPerformance =
      '$apiPrefix/seller/analytics/products/performance';
  static const String analyticsInventoryInsights =
      '$apiPrefix/seller/analytics/inventory-insights';
  static const String analyticsPaymentMethods =
      '$apiPrefix/seller/analytics/payment-methods';
  static const String analyticsRevenueBreakdown =
      '$apiPrefix/seller/analytics/revenue-breakdown';
  static const String analyticsExport = '$apiPrefix/seller/analytics/export';

  // ============ Seller Finance & Payouts Endpoints ============
  // Backed by `src/finance` on the API — note these routes do NOT use the
  // {success,message,data} envelope other modules use; the JSON body IS the
  // payload (see SellerFinanceRepository for how responses are parsed).
  static String financeDashboard(String storeId) =>
      '$apiPrefix/finance/$storeId/dashboard';
  static String financeTransactions(String storeId) =>
      '$apiPrefix/finance/$storeId/transactions';
  static String financeTransactionsExport(String storeId) =>
      '$apiPrefix/finance/$storeId/transactions/export';
  static String financeAnalytics(String storeId) =>
      '$apiPrefix/finance/$storeId/analytics';
  static String financePayoutRequest(String storeId) =>
      '$apiPrefix/finance/$storeId/payouts/request';
  static String financePayouts(String storeId) =>
      '$apiPrefix/finance/$storeId/payouts';
  static String financePayoutById(String storeId, String payoutId) =>
      '$apiPrefix/finance/$storeId/payouts/$payoutId';
  static String financePayoutMethods(String storeId) =>
      '$apiPrefix/finance/$storeId/payout-methods';
  static String financeSetDefaultPayoutMethod(
    String storeId,
    String methodId,
  ) => '$apiPrefix/finance/$storeId/payout-methods/$methodId/default';
  static String financePayoutMethodById(String storeId, String methodId) =>
      '$apiPrefix/finance/$storeId/payout-methods/$methodId';
  static String financePayoutSchedule(String storeId) =>
      '$apiPrefix/finance/$storeId/payout-schedule';
  static String financeTaxReportsGenerate(String storeId) =>
      '$apiPrefix/finance/$storeId/tax-reports/generate';
  static String financeTaxReports(String storeId) =>
      '$apiPrefix/finance/$storeId/tax-reports';

  // ============ Platform Plan Endpoints (seller pays marketplace) ============
  // The DB-managed PlatformPlan system (`src/platform-plans`) — distinct from
  // the seller-sells-to-buyers `seller/subscription*` endpoints above. Owns
  // plans, entitlements (usage vs limits), and add-on purchases.
  static const String platformPlansPublic = '$apiPrefix/platform-plans/public';
  static const String platformSellerOverview =
      '$apiPrefix/platform-plans/seller/overview';
  static String platformStorePlan(String storeId) =>
      '$apiPrefix/platform-plans/$storeId';
  static String platformEntitlements(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/entitlements';
  static String platformChangePlan(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/change-plan';
  static String platformInvoices(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/invoices';
  static String platformAddons(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/addons';
  static String platformCancelAddon(String storeId, String addonId) =>
      '$apiPrefix/platform-plans/$storeId/addons/$addonId';
  static String platformPreviewChangePlan(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/preview-change-plan';
  static String platformCancelPlan(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/cancel';
  static String platformReactivatePlan(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/reactivate';
  static String platformBillingPortal(String storeId) =>
      '$apiPrefix/platform-plans/$storeId/billing-portal';

  // ============ AI Studio Endpoints (seller-only) ============
  // Six AI tools + credits/history — backed by `src/ai-studio` on the API.
  // Credit top-up reuses platformAddons() above (addonType: extra_ai_credits).
  static String aiStudioCredits(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/credits';
  static String aiStudioGenerations(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/generations';
  static String aiStudioGeneration(String storeId, String generationId) =>
      '$apiPrefix/ai-studio/$storeId/generations/$generationId';
  static String aiStudioAcceptGeneration(String storeId, String generationId) =>
      '$apiPrefix/ai-studio/$storeId/generations/$generationId/accept';
  static String aiStudioListingWriter(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/listing-writer/generate';
  static String aiStudioSeoBooster(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/seo-booster/generate';
  static String aiStudioEmailCampaigns(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/email-campaigns/generate';
  static String aiStudioWorksheetBuilder(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/worksheet-builder/generate';
  static String aiStudioPriceOptimizer(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/price-optimizer/generate';
  static String aiStudioImageEnhancerGenerate(String storeId) =>
      '$apiPrefix/ai-studio/$storeId/image-enhancer/generate';
  static String aiStudioImageEnhancerJob(String storeId, String jobId) =>
      '$apiPrefix/ai-studio/$storeId/image-enhancer/jobs/$jobId';

  // ============ POS Multi-Location Endpoints (store branches) ============
  static String posLocations(String storeId) =>
      '$apiPrefix/pos/locations/$storeId';
  static String posLocationsOverview(String storeId) =>
      '$apiPrefix/pos/locations/$storeId/overview';
  static String posLocationById(String storeId, String locationId) =>
      '$apiPrefix/pos/locations/$storeId/$locationId';

  // ============ SEO Endpoints (seller-only, store-scoped) ============
  // Backed by `src/seo` on the API — store/product on-page SEO management.
  // Distinct from `aiStudioSeoBooster` above (an AI Studio content-generation
  // tool); this is the SEO dashboard/checklist/meta-editor/audit suite.
  static String seoDashboard(String storeId) =>
      '$apiPrefix/store/$storeId/seo/dashboard';
  static String seoStoreMeta(String storeId) =>
      '$apiPrefix/store/$storeId/seo/store';
  static String seoStoreChecklist(String storeId) =>
      '$apiPrefix/store/$storeId/seo/store/checklist';
  static String seoProducts(String storeId) =>
      '$apiPrefix/store/$storeId/seo/products';
  static String seoProductById(String storeId, String productId) =>
      '$apiPrefix/store/$storeId/seo/products/$productId';
  static String seoProductsBulkApplyTemplate(String storeId) =>
      '$apiPrefix/store/$storeId/seo/products/bulk-apply-template';
  static String seoProductsExport(String storeId) =>
      '$apiPrefix/store/$storeId/seo/products/export';

  // ============ Query Parameters Helper ============
  // For product filtering and search
  static String getProductsWithFilters({
    String? search,
    String? category,
    double? minPrice,
    double? maxPrice,
    String? brand,
    String? sort, // price_asc, price_desc, rating, newest
    int page = 1,
    int limit = 10,
  }) {
    String url = products;
    List<String> queryParams = [];

    if (search != null && search.isNotEmpty) {
      queryParams.add('search=$search');
    }
    if (category != null && category.isNotEmpty) {
      queryParams.add('category=$category');
    }
    if (minPrice != null) {
      queryParams.add('minPrice=$minPrice');
    }
    if (maxPrice != null) {
      queryParams.add('maxPrice=$maxPrice');
    }
    if (brand != null && brand.isNotEmpty) {
      queryParams.add('brand=$brand');
    }
    if (sort != null && sort.isNotEmpty) {
      queryParams.add('sort=$sort');
    }
    queryParams.add('page=$page');
    queryParams.add('limit=$limit');

    if (queryParams.isNotEmpty) {
      url += '?${queryParams.join('&')}';
    }

    return url;
  }

  // ============ Buyer membership endpoints ============
  // Buyer side of store memberships (`src/subscriptions`) — browse a store's
  // public plans, subscribe, and self-manage subscriptions/credits.
  static String buyerStorePlans(String storeId) =>
      '$apiPrefix/subscriptions/public/$storeId/plans';
  static const String buyerMembershipSubscribe =
      '$apiPrefix/subscriptions/subscribe';
  static const String buyerMyMemberships = '$apiPrefix/subscriptions/my';
  static String buyerMyMembershipById(String id) =>
      '$apiPrefix/subscriptions/my/$id';
  static String buyerMembershipPause(String id) =>
      '$apiPrefix/subscriptions/my/$id/pause';
  static String buyerMembershipResume(String id) =>
      '$apiPrefix/subscriptions/my/$id/resume';
  static String buyerMembershipCancel(String id, {bool atPeriodEnd = false}) =>
      '$apiPrefix/subscriptions/my/$id/cancel?atPeriodEnd=$atPeriodEnd';
  static String buyerMembershipBenefits(String storeId) =>
      '$apiPrefix/subscriptions/my/benefits/$storeId';
  static const String buyerMembershipCredits =
      '$apiPrefix/subscriptions/my/credits';

  // ============ Services & Bookings Endpoints — seller (store-scoped) ============
  // Backed by `src/bookings` on the API — sellers sell bookable appointments
  // and multi-session packages to buyers (distinct from products/checkout).
  static String sellerServices(String storeId) =>
      '$apiPrefix/bookings/$storeId/services';
  static String sellerServiceById(String storeId, String serviceId) =>
      '$apiPrefix/bookings/$storeId/services/$serviceId';
  static String sellerServiceAvailability(String storeId, String serviceId) =>
      '$apiPrefix/bookings/$storeId/services/$serviceId/availability';
  static String sellerServicePackages(String storeId, String serviceId) =>
      '$apiPrefix/bookings/$storeId/services/$serviceId/packages';
  static String sellerServicePackageById(
    String storeId,
    String serviceId,
    String packageId,
  ) => '$apiPrefix/bookings/$storeId/services/$serviceId/packages/$packageId';
  static String sellerBookingsDashboard(String storeId) =>
      '$apiPrefix/bookings/$storeId/bookings/dashboard';
  static String sellerBookings(String storeId) =>
      '$apiPrefix/bookings/$storeId/bookings';
  static String sellerBookingById(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id';
  static String sellerBookingConfirm(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id/confirm';
  static String sellerBookingComplete(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id/complete';
  static String sellerBookingCancel(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id/cancel';
  static String sellerBookingReschedule(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id/reschedule';
  static String sellerBookingMeetingLink(String storeId, String id) =>
      '$apiPrefix/bookings/$storeId/bookings/$id/meeting-link';

  // ============ Services & Bookings Endpoints — buyer ============
  static String buyerStoreServices(String storeId) =>
      '$apiPrefix/bookings/public/$storeId/services';
  static String buyerServiceById(String storeId, String serviceId) =>
      '$apiPrefix/bookings/public/$storeId/services/$serviceId';
  static String buyerServiceSlots(
    String storeId,
    String serviceId,
    String date,
  ) =>
      '$apiPrefix/bookings/public/$storeId/services/$serviceId/slots?date=$date';
  static const String bookAppointment = '$apiPrefix/bookings/book';
  static String purchasePackage(String packageId) =>
      '$apiPrefix/bookings/packages/$packageId/purchase';
  static const String myBookings = '$apiPrefix/bookings/my';
  static const String myPackages = '$apiPrefix/bookings/my/packages';
  static String myBookingById(String id) => '$apiPrefix/bookings/my/$id';
  static String myBookingCancel(String id) =>
      '$apiPrefix/bookings/my/$id/cancel';
  static String myBookingReschedule(String id) =>
      '$apiPrefix/bookings/my/$id/reschedule';

  // ============ Promotions Endpoints — seller (paid ad placements) ============
  static const String promotionsPreviewPrice =
      '$apiPrefix/promotions/preview-price';
  static String promotionsList(String storeId) =>
      '$apiPrefix/promotions/$storeId';
  static String promotionsCreate(String storeId) =>
      '$apiPrefix/promotions/$storeId';
  static String promotionsAnalytics(String storeId) =>
      '$apiPrefix/promotions/$storeId/analytics';
  static String promotionsPay(String id) => '$apiPrefix/promotions/$id/pay';
  static String promotionsConfirm(String id) =>
      '$apiPrefix/promotions/$id/confirm';
  static String promotionsCancel(String id) =>
      '$apiPrefix/promotions/$id/cancel';
  static String promotionsTimeline(String id) =>
      '$apiPrefix/promotions/$id/timeline';

  // ============ Promotions Endpoints — public tracking (anonymous-safe) =======
  static const String promotionTrackImpression =
      '$apiPrefix/promotions/track/impression';
  static const String promotionTrackClick = '$apiPrefix/promotions/track/click';

  // ============ Store Banner Endpoints — seller (free storefront hero) ========
  static String storeBanners(String storeId) =>
      '$apiPrefix/store-banner/$storeId';
  static String storeBannerById(String storeId, String bannerId) =>
      '$apiPrefix/store-banner/$storeId/$bannerId';
  static String storeBannerPause(String storeId, String bannerId) =>
      '$apiPrefix/store-banner/$storeId/$bannerId/pause';
  static String storeBannerResume(String storeId, String bannerId) =>
      '$apiPrefix/store-banner/$storeId/$bannerId/resume';
  static String storeBannerTimeline(String storeId, String bannerId) =>
      '$apiPrefix/store-banner/$storeId/$bannerId/timeline';

  // ============ Store Banner Endpoints — public (buyer storefront) ============
  static String publicStoreBanners(String storeId) =>
      '$apiPrefix/public/store-banners/$storeId';

  // ============ Store: Pinned Products + Announcement Bar — seller ============
  static String storePinnedProducts(String storeId) =>
      '$apiPrefix/store/$storeId/pinned-products';
  static String storeAnnouncement(String storeId) =>
      '$apiPrefix/store/$storeId/announcement';

  // ============ Products: Storefront Promotion Sections — buyer (public) ======
  static String productsPinned(String storeId) =>
      '$apiPrefix/products/store/$storeId/pinned';
  static String productsNewArrivals(String storeId, {int limit = 12}) =>
      '$apiPrefix/products/store/$storeId/new-arrivals?limit=$limit';
  static String productsBestSellers(String storeId, {int limit = 12}) =>
      '$apiPrefix/products/store/$storeId/best-sellers?limit=$limit';
  static String productsTrending(String storeId, {int limit = 12}) =>
      '$apiPrefix/products/store/$storeId/trending?limit=$limit';

  // ============ Notifications Endpoints ============
  static const String notifications = '$apiPrefix/notifications';
  static const String notificationsUnreadCount =
      '$apiPrefix/notifications/unread-count';
  static const String notificationsReadAll =
      '$apiPrefix/notifications/read-all';
  static String notificationMarkRead(String id) =>
      '$apiPrefix/notifications/$id/read';
  static String deleteNotification(String id) => '$apiPrefix/notifications/$id';
  static const String notificationDeviceToken =
      '$apiPrefix/notifications/device-token';
  static const String notificationPreferences =
      '$apiPrefix/notifications/preferences';

  // ============ Exchange Rate Endpoints (public) ============
  static const String exchangeRateCurrent = '$apiPrefix/exchange-rate/current';
}
