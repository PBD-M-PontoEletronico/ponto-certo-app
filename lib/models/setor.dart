class Setor {
  final String id;
  final String nome;

  Setor({required this.id, required this.nome});

  Map<String, dynamic> toMap() {
    return {'id': id, 'nome': nome};
  }

  factory Setor.fromMap(Map<String, dynamic> map) {
    return Setor(
      id: map['id'] as String,
      nome: map['nome'] as String,
    );
  }
}
