import 'package:flutter/material.dart';

typedef Linha = Map<String, Object?>;

const List<String> categoriasProduto = [
  'Rações',
  'Brinquedos',
  'Acessórios',
  'Higiene',
  'Cuidados',
];

class AppException implements Exception {
  final String message;
  AppException(this.message);

  @override
  String toString() => message;
}

String textoErro(Object e) =>
    e is AppException ? e.message : 'Erro inesperado: $e';

String moeda(num valor) => 'R\$ ${valor.toStringAsFixed(2).replaceAll('.', ',')}';

String dataHora(String iso) {
  final d = DateTime.tryParse(iso);
  if (d == null) return iso;
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.day)}/${p(d.month)}/${d.year} ${p(d.hour)}:${p(d.minute)}';
}

double? lerDouble(String? t) =>
    double.tryParse((t ?? '').trim().replaceAll(',', '.'));

int? lerInt(String? t) => int.tryParse((t ?? '').trim());

String? Function(String?) obrigatorio(String mensagem) {
  return (v) => (v == null || v.trim().isEmpty) ? mensagem : null;
}

String? validarPreco(String? v) {
  final n = lerDouble(v);
  if (n == null) return 'Informe um valor válido';
  if (n < 0) return 'O preço não pode ser negativo';
  return null;
}

String? validarInteiro(String? v) {
  final n = lerInt(v);
  if (n == null || n < 0) return 'Informe um número inteiro (0 ou mais)';
  return null;
}

void mostrarMensagem(BuildContext context, String texto, {bool erro = false}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Text(texto),
        backgroundColor: erro ? Colors.red.shade700 : Colors.green.shade700,
        behavior: SnackBarBehavior.floating,
      ),
    );
}

Future<bool> confirmar(BuildContext context, String titulo, String mensagem) async {
  final r = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(titulo),
      content: Text(mensagem),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Não'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Sim'),
        ),
      ],
    ),
  );
  return r ?? false;
}

/// Campo de seleção (dropdown) padronizado.
Widget campoDropdown<T>({
  required String rotulo,
  required T? valor,
  required List<DropdownMenuItem<T>> itens,
  required ValueChanged<T?> aoMudar,
}) {
  return InputDecorator(
    isEmpty: valor == null,
    decoration: InputDecoration(
      labelText: rotulo,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
    ),
    child: DropdownButtonHideUnderline(
      child: DropdownButton<T>(
        isExpanded: true,
        value: valor,
        items: itens,
        onChanged: aoMudar,
      ),
    ),
  );
}

/// RN10: pede a justificativa quando o preço de venda é menor que o custo.
Future<String?> pedirJustificativa(BuildContext context) {
  return showDialog<String>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _JustificativaDialog(),
  );
}

class _JustificativaDialog extends StatefulWidget {
  const _JustificativaDialog();

  @override
  State<_JustificativaDialog> createState() => _JustificativaDialogState();
}

class _JustificativaDialogState extends State<_JustificativaDialog> {
  final _controller = TextEditingController();
  String? _erro;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Justificativa obrigatória'),
      content: TextField(
        controller: _controller,
        maxLines: 2,
        decoration: InputDecoration(
          labelText: 'Motivo do preço abaixo do custo',
          errorText: _erro,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            final t = _controller.text.trim();
            if (t.length < 3) {
              setState(() => _erro = 'Informe a justificativa.');
              return;
            }
            Navigator.pop(context, t);
          },
          child: const Text('Confirmar'),
        ),
      ],
    );
  }
}
