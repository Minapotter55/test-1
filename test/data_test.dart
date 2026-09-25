import 'package:clientpro/data/sample_data.dart';
import 'package:clientpro/data/store.dart';
import 'package:clientpro/models/models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Invoice math', () {
    test('totals, tax, discount, balance and status', () {
      final inv = Invoice(
        items: [
          InvoiceItem(name: 'a', quantity: 2, unitPrice: 100),
          InvoiceItem(name: 'b', quantity: 1, unitPrice: 50),
        ],
        discount: 50,
        taxRate: 14,
        dueDate: DateTime.now().add(const Duration(days: 3)),
      );
      expect(inv.subtotal, 250);
      expect(inv.taxable, 200);
      expect(inv.taxAmount, closeTo(28, 0.001));
      expect(inv.total, closeTo(228, 0.001));
      expect(inv.status, InvoiceStatus.unpaid);
      inv.payments.add(Payment(amount: 100));
      expect(inv.status, InvoiceStatus.partial);
      expect(inv.balance, closeTo(128, 0.001));
      inv.payments.add(Payment(amount: 128));
      expect(inv.status, InvoiceStatus.paid);
    });

    test('overdue when past due and unpaid', () {
      final inv = Invoice(
        items: [InvoiceItem(name: 'a', unitPrice: 10)],
        dueDate: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(inv.status, InvoiceStatus.overdue);
      inv.state = InvoiceState.cancelled;
      expect(inv.status, InvoiceStatus.cancelled);
    });
  });

  test('repeating task moves to next occurrence instead of completing', () {
    final due = DateTime.now().subtract(const Duration(days: 1));
    final t = TaskItem(title: 'x', dueDate: due, repeat: RepeatRule.weekly);
    t.complete();
    expect(t.isDone, isFalse);
    expect(t.dueDate!.isAfter(DateTime.now()), isTrue);

    final once = TaskItem(title: 'y', dueDate: due);
    once.complete();
    expect(once.isDone, isTrue);
  });

  test('snapshot round-trips through JSON', () {
    final a = AppStore(persist: false);
    loadSampleData(a);
    final b = AppStore(persist: false)..replaceWith(a.snapshot());
    expect(b.customers.items.length, a.customers.items.length);
    expect(b.invoices.items.length, a.invoices.items.length);
    expect(b.tasks.items.length, a.tasks.items.length);
    final id = a.invoices.items.keys.first;
    expect(b.invoices.items[id]!.total, a.invoices.items[id]!.total);
    expect(b.business.nextInvoiceNumber, a.business.nextInvoiceNumber);
  });

  group('Sync merge between two devices', () {
    test('edits on different devices are combined, newest edit wins', () async {
      final phone = AppStore(persist: false);
      final c = Customer(name: 'أحمد');
      phone.upsert(phone.customers, c);

      // Second device starts from the phone's data.
      final tablet = AppStore(persist: false)..mergeFrom(phone.snapshot());
      expect(tablet.customers.items[c.id]!.name, 'أحمد');

      // Each device adds something, and the tablet edits the customer later.
      phone.upsert(phone.customers, Customer(name: 'من الموبايل'));
      await Future<void>.delayed(const Duration(milliseconds: 5));
      tablet.upsert(tablet.customers, Customer(name: 'من التابلت'));
      final edited = Customer.fromJson(tablet.customers.items[c.id]!.toJson())..name = 'أحمد محمود';
      tablet.upsert(tablet.customers, edited);

      phone.mergeFrom(tablet.snapshot());
      tablet.mergeFrom(phone.snapshot());

      for (final s in [phone, tablet]) {
        expect(s.customers.items.length, 3);
        expect(s.customers.items[c.id]!.name, 'أحمد محمود');
      }
    });

    test('deletions propagate and are not resurrected', () {
      final a = AppStore(persist: false);
      final c = Customer(name: 'سيُحذف');
      a.upsert(a.customers, c);
      final b = AppStore(persist: false)..mergeFrom(a.snapshot());

      a.delete(a.customers, c.id);
      // b still has the old copy; merging it back must not bring it back.
      a.mergeFrom(b.snapshot());
      expect(a.customers.items.containsKey(c.id), isFalse);

      b.mergeFrom(a.snapshot());
      expect(b.customers.items.containsKey(c.id), isFalse);
    });

    test('invoice numbering never goes backwards', () {
      final a = AppStore(persist: false);
      a.takeInvoiceNumber();
      a.takeInvoiceNumber();
      final b = AppStore(persist: false)..mergeFrom(a.snapshot());
      expect(b.business.nextInvoiceNumber, 3);
      b.takeInvoiceNumber();
      a.mergeFrom(b.snapshot());
      expect(a.business.nextInvoiceNumber, 4);
    });

    test('merge ignores unchanged data', () {
      final a = AppStore(persist: false);
      loadSampleData(a);
      final b = AppStore(persist: false)..mergeFrom(a.snapshot());
      expect(b.mergeFrom(a.snapshot()), isFalse);
    });
  });

  test('deleting a customer removes their invoices and keeps tasks', () {
    final s = AppStore(persist: false);
    final c = Customer(name: 'x');
    s.upsert(s.customers, c);
    s.upsert(s.invoices, Invoice(customerId: c.id));
    s.upsert(s.tasks, TaskItem(title: 't', customerId: c.id));
    s.deleteCustomer(c);
    expect(s.invoices.items, isEmpty);
    expect(s.tasks.items.values.single.customerId, isNull);
  });
}
