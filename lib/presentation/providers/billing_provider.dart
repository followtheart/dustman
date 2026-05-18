import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/utils/logger.dart';
import '../../data/fileclaw/api_exception.dart';
import '../../data/fileclaw/cloud_client.dart';
import '../../data/fileclaw/dto.dart';

/// 会员页订购流程状态机。
///
/// 流程：
///   idle → loadingSkus → idle           (启动时加载 SKU 目录)
///   idle → ordering    → showQrCode     (创建订单，等扫码)
///   showQrCode → waitingPayment  → paid (SSE 订单状态推送)
///   任意 → error
enum BillingState {
  idle,
  loadingSkus,
  ordering,
  showQrCode,
  waitingPayment,
  paid,
  canceled,
  error,
}

class BillingProvider extends ChangeNotifier {
  BillingProvider(this._client);

  final CloudClient _client;

  BillingState _state = BillingState.idle;
  List<SkuInfo> _skus = const [];
  OrderInfo? _activeOrder;
  String? _lastError;
  StreamSubscription<OrderInfo>? _sseSub;

  BillingState get state => _state;
  List<SkuInfo> get skus => _skus;
  OrderInfo? get activeOrder => _activeOrder;
  String? get lastError => _lastError;

  bool get isOrdering =>
      _state == BillingState.ordering ||
      _state == BillingState.showQrCode ||
      _state == BillingState.waitingPayment;

  // ── 启动：加载 SKU 目录 ──────────────────────

  Future<void> loadSkus() async {
    _set(BillingState.loadingSkus);
    try {
      _skus = await _client.listSkus();
      _state = BillingState.idle;
    } on ApiException catch (e) {
      _lastError = e.message;
      _state = BillingState.error;
    } finally {
      notifyListeners();
    }
  }

  // ── 创建订单 ────────────────────────────────

  Future<void> startOrder({required String skuCode, String provider = 'stub'}) async {
    _lastError = null;
    _set(BillingState.ordering);
    try {
      _activeOrder = await _client.createOrder(sku: skuCode, provider: provider);
      _state = BillingState.showQrCode;
      notifyListeners();
      // 订阅 SSE
      await _subscribeOrderEvents(_activeOrder!.id);
    } on ApiException catch (e) {
      _lastError = e.message;
      _state = BillingState.error;
      notifyListeners();
    }
  }

  // ── SSE 订阅 ─────────────────────────────────

  Future<void> _subscribeOrderEvents(String orderId) async {
    await _sseSub?.cancel();
    _state = BillingState.waitingPayment;
    notifyListeners();
    try {
      final stream = await _client.orderEvents(orderId);
      _sseSub = stream.listen(
        (order) {
          _activeOrder = order;
          if (order.isPaid) {
            _state = BillingState.paid;
          } else if (order.isCanceled) {
            _state = BillingState.canceled;
          }
          notifyListeners();
        },
        onError: (Object e) {
          AppLogger.warn('order SSE error: $e', tag: 'BillingProvider');
          _lastError = e.toString();
          _state = BillingState.error;
          notifyListeners();
        },
      );
    } on ApiException catch (e) {
      _lastError = e.message;
      _state = BillingState.error;
      notifyListeners();
    }
  }

  // ── 取消 ────────────────────────────────────

  Future<void> cancelActive() async {
    final order = _activeOrder;
    if (order == null) return;
    await _sseSub?.cancel();
    _sseSub = null;
    try {
      await _client.cancelOrder(order.id);
    } on ApiException catch (e) {
      AppLogger.warn('cancel order failed: $e', tag: 'BillingProvider');
    }
    _state = BillingState.canceled;
    notifyListeners();
  }

  /// 弹窗关闭时调用，回到 idle。
  void dismissActive() {
    _sseSub?.cancel();
    _sseSub = null;
    _activeOrder = null;
    _state = BillingState.idle;
    notifyListeners();
  }

  void _set(BillingState s) {
    _state = s;
    notifyListeners();
  }

  @override
  void dispose() {
    _sseSub?.cancel();
    super.dispose();
  }
}
