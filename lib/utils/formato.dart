// Formatadores usados nas telas de historico, escala e pedidos.

String doisDigitos(int n) => n.toString().padLeft(2, '0');

/// Minutos -> "8h30". Com [sinal], mostra "+0h30" / "-1h15".
String formatarMinutos(int? m, {bool sinal = false}) {
  if (m == null) return '—';
  final negativo = m < 0;
  final abs = m.abs();
  final texto = '${abs ~/ 60}h${doisDigitos(abs % 60)}';
  if (negativo) return '-$texto';
  if (sinal && m > 0) return '+$texto';
  return texto;
}

const List<String> _diasSemana = ['seg', 'ter', 'qua', 'qui', 'sex', 'sáb', 'dom'];
String diaDaSemana(DateTime d) => _diasSemana[d.weekday - 1];

const List<String> _meses = [
  'Janeiro', 'Fevereiro', 'Março', 'Abril', 'Maio', 'Junho',
  'Julho', 'Agosto', 'Setembro', 'Outubro', 'Novembro', 'Dezembro',
];
String nomeDoMes(DateTime d) => '${_meses[d.month - 1]} de ${d.year}';

/// "2026-11" para o parametro ?mes= da API.
String chaveMes(DateTime d) => '${d.year.toString().padLeft(4, '0')}-${doisDigitos(d.month)}';

/// "yyyy-MM-dd" (formato que a API usa para datas).
String dataIso(DateTime d) =>
    '${d.year.toString().padLeft(4, '0')}-${doisDigitos(d.month)}-${doisDigitos(d.day)}';

String dataCurta(DateTime d) => '${doisDigitos(d.day)}/${doisDigitos(d.month)}';

String hhmm(DateTime d) => '${doisDigitos(d.hour)}:${doisDigitos(d.minute)}';

/// Instante ISO (ex.: "2026-11-19T11:00:00Z") -> "08:00" no fuso do aparelho.
String hhmmDeIso(String? iso) {
  if (iso == null) return '--:--';
  final d = DateTime.tryParse(iso);
  if (d == null) return '--:--';
  return hhmm(d.toLocal());
}

/// "08:00:00" -> "08:00".
String horaCurta(String? h) {
  if (h == null || h.length < 5) return h ?? '--:--';
  return h.substring(0, 5);
}

const Map<String, String> rotulosTipoMarcacao = {
  'ENTRADA': 'Entrada',
  'SAIDA_INTERVALO': 'Saída (intervalo)',
  'RETORNO_INTERVALO': 'Retorno (intervalo)',
  'SAIDA': 'Saída',
};

const Map<String, String> rotulosOcorrencia = {
  'ATRASO': 'Atraso',
  'FALTA': 'Falta',
  'SAIDA_ANTECIPADA': 'Saída antecipada',
};

int? comoInt(dynamic v) => (v as num?)?.toInt();
