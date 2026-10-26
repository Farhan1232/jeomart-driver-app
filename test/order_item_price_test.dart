import 'package:driver/models/cart_product_model.dart';
import 'package:driver/utils/order_item_price.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the discount price when there is one, plus add-ons, times quantity', () {
    final product = CartProductModel(price: '500', discountPrice: '450', extrasPrice: '50', quantity: 2);
    expect(orderItemLineTotal(product), 1000);
  });

  test('falls back to the price when there is no discount', () {
    final product = CartProductModel(price: '450', discountPrice: '0', extrasPrice: '0', quantity: 1);
    expect(orderItemLineTotal(product), 450);
  });

  test('missing values count as zero instead of throwing', () {
    expect(orderItemLineTotal(CartProductModel()), 0);
  });
}
