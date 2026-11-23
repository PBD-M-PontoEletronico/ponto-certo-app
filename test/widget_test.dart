import 'package:flutter_test/flutter_test.dart';
import 'package:meu_ponto/utils/formato.dart';

void main() {
  test('formatarMinutos mostra horas e minutos com sinal', () {
    expect(formatarMinutos(510), '8h30');
    expect(formatarMinutos(-75, sinal: true), '-1h15');
    expect(formatarMinutos(30, sinal: true), '+0h30');
    expect(formatarMinutos(null), '—');
  });

  test('chaveMes e dataIso seguem o formato da API', () {
    expect(chaveMes(DateTime(2026, 11, 5)), '2026-11');
    expect(dataIso(DateTime(2026, 11, 5)), '2026-11-05');
  });

  test('horaCurta corta os segundos', () {
    expect(horaCurta('08:00:00'), '08:00');
  });
}
