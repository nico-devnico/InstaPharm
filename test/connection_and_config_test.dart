import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:instapharm/core/config/supabase_config.dart';
import 'package:instapharm/core/constants/cameroon.dart';
import 'package:instapharm/core/utils/currency.dart';
import 'package:instapharm/models/enums.dart';
import 'package:instapharm/models/order.dart';
import 'package:instapharm/models/coordinates.dart';

void main() {
  group('SupabaseConfig', () {
    tearDown(() {
      dotenv.clean();
    });

    test('isConfigured = false avec placeholders', () async {
      dotenv.loadFromString(envString: '''
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
''');
      expect(SupabaseConfig.isConfigured, isFalse);
    });

    test('isConfigured = true avec URL et anon key valides', () async {
      dotenv.loadFromString(envString: '''
SUPABASE_URL=https://ulfuhauwqdgaucdekzhr.supabase.co
SUPABASE_ANON_KEY=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InVsZnVoYXV3cWRnYXVjZGVremhyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODk3NzQ4NjcsImV4cCI6MjEwNTM1MDg2N30.test
''');
      expect(SupabaseConfig.url, contains('ulfuhauwqdgaucdekzhr'));
      expect(SupabaseConfig.anonKey, startsWith('eyJ'));
      expect(SupabaseConfig.isConfigured, isTrue);
    });

    test('isConfigured = false si URL vide', () async {
      dotenv.loadFromString(envString: '''
SUPABASE_URL=
SUPABASE_ANON_KEY=eyJtest
''');
      expect(SupabaseConfig.isConfigured, isFalse);
    });
  });

  group('Chaîne métier Cameroun', () {
    test('frais livraison cohérents', () {
      expect(CameroonDefaults.baseDeliveryFeeXaf, greaterThan(0));
      expect(CameroonDefaults.expressDeliveryFeeXaf,
          greaterThan(CameroonDefaults.baseDeliveryFeeXaf));
    });

    test('format FCFA', () {
      final s = formatFcfa(1500);
      expect(s.contains('1'), isTrue);
      expect(s.toLowerCase().contains('fcfa') || s.contains('XAF') || s.contains('F'),
          isTrue);
    });
  });

  group('MedicineOrder / DeliveryInfo', () {
    test('total = subtotal + delivery fee', () {
      final order = MedicineOrder(
        id: 'CMD-1',
        pharmacyId: 'osm-1',
        pharmacyName: 'Pharmacie Test',
        items: const [
          OrderItem(
            medicineId: 'm1',
            medicineName: 'Paracétamol',
            quantity: 2,
            unitPriceXaf: 1500,
          ),
        ],
        fulfillment: FulfillmentType.delivery,
        paymentMethod: PaymentMethod.mtnMomo,
        status: OrderStatus.confirmed,
        subtotalXaf: 3000,
        deliveryFeeXaf: 1500,
        createdAt: DateTime(2026, 1, 1),
        supabaseId: 'uuid-order',
      );
      expect(order.totalXaf, 4500);
      expect(order.status.isActive, isTrue);
    });

    test('DeliveryInfo adresse complète', () {
      const d = DeliveryInfo(
        recipientName: 'Test',
        phone: '+237600000000',
        city: 'Douala',
        neighborhood: 'Akwa',
        addressDetail: 'Rue 1',
        destination: Coordinates(latitude: 4.05, longitude: 9.76),
        fromLiveGps: true,
      );
      expect(d.fullAddress, contains('Akwa'));
      expect(d.fromLiveGps, isTrue);
      expect(d.destination!.latitude, closeTo(4.05, 0.01));
    });

    test('statuts livraison progressent correctement', () {
      expect(OrderStatus.confirmed.index < OrderStatus.preparing.index, isTrue);
      expect(
          OrderStatus.preparing.index < OrderStatus.outForDelivery.index, isTrue);
      expect(
          OrderStatus.outForDelivery.index < OrderStatus.delivered.index, isTrue);
      expect(OrderStatus.delivered.isActive, isFalse);
    });
  });

  group('Architecture connexions', () {
    test('paiements Mobile Money Cameroun définis', () {
      expect(PaymentMethod.mtnMomo.displayName.toLowerCase(), contains('mtn'));
      expect(PaymentMethod.orangeMoney.displayName.toLowerCase(),
          contains('orange'));
      expect(PaymentMethod.cash.displayName.isNotEmpty, isTrue);
    });

    test('modes réception pickup et delivery', () {
      expect(FulfillmentType.delivery.displayName.isNotEmpty, isTrue);
      expect(FulfillmentType.pickup.displayName.isNotEmpty, isTrue);
    });
  });
}
