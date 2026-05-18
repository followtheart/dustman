import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../data/fileclaw/dto.dart';
import '../providers/auth_provider.dart';
import '../providers/billing_provider.dart';

/// 会员页：套餐列表 + 扫码支付弹窗。
/// 仅 Pro 版引用（kIsPro 守卫见 home_screen.dart）。
class MembershipScreen extends StatefulWidget {
  const MembershipScreen({super.key});

  @override
  State<MembershipScreen> createState() => _MembershipScreenState();
}

class _MembershipScreenState extends State<MembershipScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final billing = context.read<BillingProvider>();
      if (billing.skus.isEmpty) {
        billing.loadSkus();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('会员'), centerTitle: false),
      body: Consumer2<AuthProvider, BillingProvider>(
        builder: (context, auth, billing, _) {
          if (auth.state != AuthState.authenticated) {
            return const _LoginRequiredView();
          }
          return _MembershipBody(billing: billing);
        },
      ),
    );
  }
}

class _LoginRequiredView extends StatelessWidget {
  const _LoginRequiredView();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(32),
      child: Center(
        child: Text('请先登录账户后再开通会员'),
      ),
    );
  }
}

// ── 会员页主体 ──────────────────────────────────


class _MembershipBody extends StatelessWidget {
  const _MembershipBody({required this.billing});
  final BillingProvider billing;

  @override
  Widget build(BuildContext context) {
    if (billing.state == BillingState.loadingSkus) {
      return const Center(child: CircularProgressIndicator());
    }
    if (billing.skus.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('套餐加载失败'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: billing.loadSkus,
              child: const Text('重试'),
            ),
          ],
        ),
      );
    }
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const _QuotaSummary(),
        const SizedBox(height: 16),
        Text('选择套餐', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: 12),
        for (final sku in billing.skus)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _SkuCard(sku: sku),
          ),
        const SizedBox(height: 24),
        Text(
          '当前为测试期定价（¥0.01），仅用于验证支付通路与用户意愿。正式价格将在数据沉淀后调整。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }
}

class _QuotaSummary extends StatelessWidget {
  const _QuotaSummary();

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final profile = auth.profile;
    if (profile == null) return const SizedBox.shrink();
    final ratio = profile.quotaAllowance == 0
        ? 0.0
        : (profile.quotaUsed / profile.quotaAllowance).clamp(0.0, 1.0);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('当前套餐：${_planLabel(profile.subscriptionPlan)}'),
                const Spacer(),
                if (profile.subscriptionEnd != null)
                  Text(
                    '有效期至 ${_formatDate(profile.subscriptionEnd!)}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: ratio),
            const SizedBox(height: 8),
            Text(
              '余额：${profile.quotaRemaining} / ${profile.quotaAllowance} tokens',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _SkuCard extends StatelessWidget {
  const _SkuCard({required this.sku});
  final SkuInfo sku;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    sku.title,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Text(
                  sku.formattedPrice,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(sku.description, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                icon: const Icon(Icons.qr_code_2),
                label: const Text('立即开通'),
                onPressed: () => _purchase(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _purchase(BuildContext context) async {
    final billing = context.read<BillingProvider>();
    await billing.startOrder(skuCode: sku.code);
    if (!context.mounted) return;
    await _PaymentDialog.show(context);
    // 弹窗关闭后回到 idle 并刷新 /me（拿到新的 quota / plan）
    billing.dismissActive();
    final auth = context.read<AuthProvider>();
    await auth.reloadProfile();
  }
}

// ── 扫码支付弹窗 ──────────────────────────────


class _PaymentDialog extends StatelessWidget {
  const _PaymentDialog();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return ChangeNotifierProvider<BillingProvider>.value(
          value: context.read<BillingProvider>(),
          child: const _PaymentDialog(),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BillingProvider>(
      builder: (context, billing, _) {
        final order = billing.activeOrder;
        return AlertDialog(
          title: Text(_titleFor(billing.state)),
          content: SizedBox(
            width: 320,
            child: _content(context, billing, order),
          ),
          actions: [
            if (billing.state == BillingState.paid ||
                billing.state == BillingState.error ||
                billing.state == BillingState.canceled)
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('关闭'),
              )
            else
              TextButton(
                onPressed: () async {
                  await billing.cancelActive();
                  if (context.mounted) Navigator.of(context).pop();
                },
                child: const Text('取消订单'),
              ),
          ],
        );
      },
    );
  }

  Widget _content(BuildContext context, BillingProvider billing, OrderInfo? order) {
    if (billing.state == BillingState.paid) {
      return const _DialogStatus(
        icon: Icons.check_circle,
        color: Colors.green,
        message: '支付成功！会员权益已生效。',
      );
    }
    if (billing.state == BillingState.canceled) {
      return const _DialogStatus(
        icon: Icons.cancel,
        color: Colors.orange,
        message: '订单已取消',
      );
    }
    if (billing.state == BillingState.error || billing.lastError != null) {
      return _DialogStatus(
        icon: Icons.error_outline,
        color: Theme.of(context).colorScheme.error,
        message: billing.lastError ?? '订单出错',
      );
    }
    if (order == null || order.qrcodeUrl == null) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: QrImageView(
            data: order.qrcodeUrl!,
            version: QrVersions.auto,
            size: 240,
            backgroundColor: Colors.white,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          billing.state == BillingState.waitingPayment ? '等待支付…' : '请扫码支付',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        const SizedBox(height: 4),
        Text(
          '${(order.amountCents / 100).toStringAsFixed(2)} CNY · ${order.provider}',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  String _titleFor(BillingState s) => switch (s) {
        BillingState.paid => '支付成功',
        BillingState.canceled => '已取消',
        BillingState.error => '出错了',
        _ => '扫码支付',
      };
}

class _DialogStatus extends StatelessWidget {
  const _DialogStatus({
    required this.icon,
    required this.color,
    required this.message,
  });
  final IconData icon;
  final Color color;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 48, color: color),
          const SizedBox(height: 12),
          Text(message, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ── helpers ──────────────────────────────────────


String _planLabel(String plan) => switch (plan) {
      'monthly' => 'Pro 月付',
      'annual' => 'Pro 年付',
      _ => '免费',
    };

String _formatDate(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
