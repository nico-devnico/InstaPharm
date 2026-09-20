import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/constants/cameroon.dart';
import '../core/theme/app_colors.dart';
import '../core/theme/app_typography.dart';
import '../core/utils/currency.dart';
import '../models/enums.dart';
import '../models/medicine.dart';
import '../models/order.dart';
import '../models/pharmacy.dart';
import '../providers/app_config_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/location_providers.dart';
import '../providers/orders_provider.dart';
import '../services/order_repository.dart';

class OrderCheckoutSheet extends ConsumerStatefulWidget {
  final Pharmacy pharmacy;
  final Medicine medicine;
  final int? unitPriceXaf;

  const OrderCheckoutSheet({
    super.key,
    required this.pharmacy,
    required this.medicine,
    this.unitPriceXaf,
  });

  static Future<MedicineOrder?> show(
    BuildContext context, {
    required Pharmacy pharmacy,
    required Medicine medicine,
    int? unitPriceXaf,
  }) {
    return showModalBottomSheet<MedicineOrder>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => OrderCheckoutSheet(
        pharmacy: pharmacy,
        medicine: medicine,
        unitPriceXaf: unitPriceXaf,
      ),
    );
  }

  @override
  ConsumerState<OrderCheckoutSheet> createState() => _OrderCheckoutSheetState();
}

class _OrderCheckoutSheetState extends ConsumerState<OrderCheckoutSheet> {
  FulfillmentType _fulfillment = FulfillmentType.delivery;
  PaymentMethod _payment = PaymentMethod.mtnMomo;
  int _qty = 1;
  bool _express = false;
  bool _submitting = false;
  bool _hasPrescription = false;

  final _nameCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  String _city = 'Douala';
  String _neighborhood = 'Akwa';
  bool _profileLoaded = false;

  bool get _offersDelivery => true; // InstaPharm : livraison toujours proposée

  int get _unitPrice =>
      widget.unitPriceXaf ?? widget.medicine.priceXaf ?? 1500;

  int get _subtotal => _unitPrice * _qty;

  int get _deliveryFee {
    if (_fulfillment != FulfillmentType.delivery) return 0;
    final cfg = ref.read(appConfigValueProvider);
    final freeAbove = cfg.deliveryFreeAboveXaf;
    if (_subtotal >= freeAbove && freeAbove > 0) return 0;
    return _express ? cfg.deliveryExpressXaf : cfg.deliveryBaseXaf;
  }

  int get _total => _subtotal + _deliveryFee;

  List<String> get _neighborhoods => _city == 'Yaoundé'
      ? CameroonDefaults.yaoundeNeighborhoods
      : CameroonDefaults.doualaNeighborhoods;

  @override
  void initState() {
    super.initState();
    if (!_offersDelivery) _fulfillment = FulfillmentType.pickup;
    _hasPrescription = widget.medicine.requiresPrescription ?? false;
  }

  void _prefillFromProfile() {
    if (_profileLoaded) return;
    final profile = ref.read(profileProvider).valueOrNull;
    if (profile == null) return;
    _profileLoaded = true;
    if (_nameCtrl.text.isEmpty && (profile.fullName?.isNotEmpty ?? false)) {
      _nameCtrl.text = profile.fullName!;
    }
    if (_phoneCtrl.text.isEmpty && (profile.phone?.isNotEmpty ?? false)) {
      _phoneCtrl.text = profile.phone!;
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_fulfillment == FulfillmentType.delivery) {
      if (_nameCtrl.text.trim().isEmpty ||
          _phoneCtrl.text.trim().isEmpty ||
          _addressCtrl.text.trim().isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Complétez l’adresse de livraison')),
        );
        return;
      }
    }
    setState(() => _submitting = true);
    try {
      final item = OrderItem(
        medicineId: widget.medicine.id,
        medicineName: widget.medicine.name,
        brand: widget.medicine.brand,
        dosage: widget.medicine.dosage,
        quantity: _qty,
        unitPriceXaf: _unitPrice,
        requiresPrescription: widget.medicine.requiresPrescription ?? false,
      );

      final liveGps = ref.read(liveCoordinatesProvider);

      final order = await OrderRepository.instance.createOrder(
        pharmacy: widget.pharmacy,
        items: [item],
        fulfillment: _fulfillment,
        paymentMethod: _payment,
        express: _express,
        hasPrescription: _hasPrescription,
        delivery: _fulfillment == FulfillmentType.delivery
            ? DeliveryInfo(
                recipientName: _nameCtrl.text.trim(),
                phone: _phoneCtrl.text.trim(),
                city: _city,
                neighborhood: _neighborhood,
                addressDetail: _addressCtrl.text.trim(),
                destination: liveGps,
                fromLiveGps: liveGps != null,
              )
            : null,
      );

      ref.invalidate(myOrdersProvider);
      if (mounted) Navigator.of(context).pop(order);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(profileProvider);
    _prefillFromProfile();
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.only(bottom: bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: AppColors.border,
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Commander',
                    style: AppTypography.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
          ),
          Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              children: [
                _medicineCard(),
                const SizedBox(height: 18),
                Text('Mode de réception',
                    style: AppTypography.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: _choiceChip(
                        label: 'Livraison',
                        icon: Icons.delivery_dining_rounded,
                        selected: _fulfillment == FulfillmentType.delivery,
                        enabled: _offersDelivery,
                        onTap: () => setState(
                            () => _fulfillment = FulfillmentType.delivery),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _choiceChip(
                        label: 'Retrait',
                        icon: Icons.storefront_rounded,
                        selected: _fulfillment == FulfillmentType.pickup,
                        onTap: () => setState(
                            () => _fulfillment = FulfillmentType.pickup),
                      ),
                    ),
                  ],
                ),
                if (_fulfillment == FulfillmentType.delivery) ...[
                  const SizedBox(height: 12),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Livraison express (moto)'),
                    subtitle: Text(
                      '+${formatFcfa(CameroonDefaults.expressDeliveryFeeXaf - CameroonDefaults.baseDeliveryFeeXaf)}',
                      style: AppTypography.textTheme.bodySmall,
                    ),
                    value: _express,
                    activeThumbColor: AppColors.primaryBlue,
                    onChanged: (v) => setState(() => _express = v),
                  ),
                  const SizedBox(height: 8),
                  Text('Adresse de livraison',
                      style: AppTypography.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 10),
                  _field(_nameCtrl, 'Nom du destinataire', Icons.person_outline),
                  const SizedBox(height: 10),
                  _field(_phoneCtrl, 'Téléphone (+237)', Icons.phone_outlined),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: _dropdown(
                          value: _city,
                          items: const ['Douala', 'Yaoundé'],
                          onChanged: (v) {
                            setState(() {
                              _city = v!;
                              _neighborhood = _neighborhoods.first;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _dropdown(
                          value: _neighborhood,
                          items: _neighborhoods,
                          onChanged: (v) =>
                              setState(() => _neighborhood = v!),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  _field(_addressCtrl, 'Quartier / repère', Icons.home_outlined),
                ],
                if (widget.medicine.requiresPrescription == true) ...[
                  const SizedBox(height: 14),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AppColors.warning.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: AppColors.warning.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.medication_rounded,
                            color: AppColors.warning),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Ce médicament nécessite une ordonnance. '
                            'Le pharmacien la vérifiera avant préparation.',
                            style: AppTypography.textTheme.bodySmall,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    value: _hasPrescription,
                    onChanged: (v) =>
                        setState(() => _hasPrescription = v ?? false),
                    title: const Text('J’ai une ordonnance valide'),
                    controlAffinity: ListTileControlAffinity.leading,
                  ),
                ],
                const SizedBox(height: 16),
                Text('Paiement',
                    style: AppTypography.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 10),
                ...PaymentMethod.values.map((m) => _paymentTile(m)),
                const SizedBox(height: 16),
                _summaryBox(),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: _submitting ? null : _submit,
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                    ),
                    child: _submitting
                        ? const SizedBox(
                            height: 22,
                            width: 22,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : Text('Confirmer · ${formatFcfa(_total)}'),
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _medicineCard() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: AppColors.primaryBlue.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.medication_rounded,
                color: AppColors.primaryBlue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.medicine.fullName,
                  style: AppTypography.textTheme.titleSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                Text(
                  widget.pharmacy.name,
                  style: AppTypography.textTheme.bodySmall?.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
                Text(
                  formatFcfa(_unitPrice),
                  style: AppTypography.textTheme.labelLarge?.copyWith(
                    color: AppColors.primaryBlue,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          _qtyControl(),
        ],
      ),
    );
  }

  Widget _qtyControl() {
    return Row(
      children: [
        _qtyBtn(Icons.remove, () {
          if (_qty > 1) setState(() => _qty--);
        }),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Text('$_qty',
              style: AppTypography.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
        _qtyBtn(Icons.add, () => setState(() => _qty++)),
      ],
    );
  }

  Widget _qtyBtn(IconData icon, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.border),
        ),
        child: Icon(icon, size: 18),
      ),
    );
  }

  Widget _choiceChip({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
    bool enabled = true,
  }) {
    return Opacity(
      opacity: enabled ? 1 : 0.4,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.10)
                : AppColors.surfaceVariant,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(icon,
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: selected
                      ? AppColors.primaryBlue
                      : AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _paymentTile(PaymentMethod method) {
    final selected = _payment == method;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        onTap: () => setState(() => _payment = method),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? AppColors.primaryBlue : AppColors.border,
              width: selected ? 1.5 : 1,
            ),
            color: selected
                ? AppColors.primaryBlue.withValues(alpha: 0.06)
                : AppColors.surface,
          ),
          child: Row(
            children: [
              Icon(
                method == PaymentMethod.cash
                    ? Icons.payments_outlined
                    : Icons.phone_android_rounded,
                color: selected
                    ? AppColors.primaryBlue
                    : AppColors.textSecondary,
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(method.displayName)),
              Icon(
                selected
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: selected
                    ? AppColors.primaryBlue
                    : AppColors.textTertiary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(TextEditingController c, String hint, IconData icon) {
    return TextField(
      controller: c,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: AppColors.surfaceVariant,
      ),
    );
  }

  Widget _dropdown({
    required String value,
    required List<String> items,
    required ValueChanged<String?> onChanged,
  }) {
    return DropdownButtonFormField<String>(
      value: items.contains(value) ? value : items.first,
      items: items
          .map((e) => DropdownMenuItem(value: e, child: Text(e)))
          .toList(),
      onChanged: onChanged,
      decoration: const InputDecoration(
        filled: true,
        fillColor: AppColors.surfaceVariant,
        contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      ),
    );
  }

  Widget _summaryBox() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        children: [
          _sumRow('Sous-total', formatFcfa(_subtotal)),
          if (_deliveryFee > 0)
            _sumRow('Livraison', formatFcfa(_deliveryFee)),
          const Divider(height: 18),
          _sumRow('Total', formatFcfa(_total), bold: true),
        ],
      ),
    );
  }

  Widget _sumRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: bold
                ? AppTypography.textTheme.titleSmall
                    ?.copyWith(fontWeight: FontWeight.w700)
                : AppTypography.textTheme.bodyMedium,
          ),
          Text(
            value,
            style: bold
                ? AppTypography.textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: AppColors.primaryBlue,
                  )
                : AppTypography.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
