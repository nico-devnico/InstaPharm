import 'package:flutter/material.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/responsive.dart';
import '../models/enums.dart';
import '../models/order.dart';
import '../services/order_repository.dart';

class RatingScreen extends StatefulWidget {
  final MedicineOrder order;

  const RatingScreen({super.key, required this.order});

  @override
  State<RatingScreen> createState() => _RatingScreenState();
}

class _RatingScreenState extends State<RatingScreen> {
  int _delivery = 5;
  int _courier = 5;
  int _pharmacy = 5;
  final _comment = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _comment.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final uuid = widget.order.supabaseId;
    if (uuid == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Commande introuvable')),
      );
      return;
    }
    setState(() => _loading = true);
    try {
      await OrderRepository.instance.submitRating(
        orderUuid: uuid,
        deliveryRating: _delivery,
        courierRating: widget.order.fulfillment == FulfillmentType.delivery
            ? _courier
            : null,
        pharmacyRating: _pharmacy,
        comment: _comment.text.trim().isEmpty ? null : _comment.text.trim(),
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Merci pour votre avis !')),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('$e')),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNarrow = MediaQuery.sizeOf(context).width < 380;
    final isDelivery = widget.order.fulfillment == FulfillmentType.delivery;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('Noter la livraison'),
        backgroundColor: AppColors.background,
      ),
      body: Center(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: Responsive.isWide(context) ? 480 : double.infinity,
          ),
          child: ListView(
            padding: EdgeInsets.all(isNarrow ? 16 : 20),
            children: [
              Text(
                'Commande ${widget.order.id}',
                style: TextStyle(
                  fontSize: isNarrow ? 13 : 14,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                widget.order.pharmacyName,
                style: TextStyle(
                  fontSize: isNarrow ? 18 : 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 24),
              _stars(
                title: 'Qualité de la livraison',
                value: _delivery,
                onChanged: (v) => setState(() => _delivery = v),
                isNarrow: isNarrow,
              ),
              if (isDelivery) ...[
                const SizedBox(height: 20),
                _stars(
                  title:
                      'Livreur${widget.order.courierName != null ? ' (${widget.order.courierName})' : ''}',
                  value: _courier,
                  onChanged: (v) => setState(() => _courier = v),
                  isNarrow: isNarrow,
                ),
              ],
              const SizedBox(height: 20),
              _stars(
                title: 'Pharmacie',
                value: _pharmacy,
                onChanged: (v) => setState(() => _pharmacy = v),
                isNarrow: isNarrow,
              ),
              const SizedBox(height: 20),
              TextField(
                controller: _comment,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Commentaire (optionnel)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: _loading ? null : _submit,
                style: FilledButton.styleFrom(
                  padding: EdgeInsets.symmetric(vertical: isNarrow ? 12 : 14),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Envoyer mon avis'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stars({
    required String title,
    required int value,
    required ValueChanged<int> onChanged,
    required bool isNarrow,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(
            fontSize: isNarrow ? 13 : 14,
            fontWeight: FontWeight.w700,
          ),
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 8),
        Row(
          children: List.generate(5, (i) {
            final star = i + 1;
            return IconButton(
              onPressed: () => onChanged(star),
              visualDensity: VisualDensity.compact,
              icon: Icon(
                star <= value ? Icons.star_rounded : Icons.star_outline_rounded,
                color: AppColors.warning,
                size: isNarrow ? 28 : 32,
              ),
            );
          }),
        ),
      ],
    );
  }
}
