import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/order.dart';
import '../services/order_repository.dart';
import 'auth_provider.dart';

final myOrdersProvider = FutureProvider.autoDispose<List<MedicineOrder>>((ref) async {
  ref.watch(authStateProvider);
  if (ref.watch(currentUserProvider) == null) return [];
  return OrderRepository.instance.getMyOrders();
});

final orderByIdProvider =
    FutureProvider.autoDispose.family<MedicineOrder?, String>((ref, id) async {
  return OrderRepository.instance.getOrder(id);
});
