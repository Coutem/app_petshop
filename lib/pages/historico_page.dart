import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

class HistoricoPage extends StatefulWidget {
  const HistoricoPage({super.key});

  @override
  State<HistoricoPage> createState() => _HistoricoPageState();
}

class _HistoricoPageState extends State<HistoricoPage> {
  final _db = DatabaseHelper.instance;
  List<Linha> _vendas = [];
  String? _filtro;
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _db.listarVendas(status: _filtro);
      if (!mounted) return;
      setState(() {
        _vendas = r;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _detalhes(Linha v) async {
    try {
      final itens = await _db.itensDaVenda(v['id'] as int);
      if (!mounted) return;
      final cancelar = await showModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Venda #${v['id']}', style: Theme.of(ctx).textTheme.titleLarge),
                const SizedBox(height: 4),
                Text('Cliente: ${v['cliente_nome']}'),
                Text('Data: ${dataHora('${v['data_venda']}')}'),
                Text('Status: ${v['status']}'),
                const Divider(),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    children: [
                      for (final i in itens)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${i['nome']}'),
                          subtitle: Text('${i['quantidade']} x ${moeda(i['preco_unitario'] as num)}'),
                          trailing: Text(moeda(i['subtotal'] as num)),
                        ),
                    ],
                  ),
                ),
                const Divider(),
                Text(
                  'Total: ${moeda(v['valor_total'] as num)}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                if (v['status'] == 'CONFIRMADA')
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
                      onPressed: () => Navigator.pop(ctx, true),
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancelar venda'),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
      if (cancelar == true && mounted) await _cancelar(v);
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _cancelar(Linha v) async {
    final ok = await confirmar(
      context,
      'Cancelar venda',
      'Cancelar a venda #${v['id']}? As quantidades serão devolvidas ao estoque.',
    );
    if (!ok || !mounted) return;
    try {
      await _db.cancelarVenda(v['id'] as int);
      if (!mounted) return;
      mostrarMensagem(context, 'Venda #${v['id']} cancelada. Estoque restaurado.');
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
    await _carregar();
  }

  Widget _chip(String rotulo, String? valor) {
    return ChoiceChip(
      label: Text(rotulo),
      selected: _filtro == valor,
      onSelected: (_) {
        setState(() => _filtro = valor);
        _carregar();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Wrap(
            spacing: 8,
            children: [
              _chip('Todas', null),
              _chip('Confirmadas', 'CONFIRMADA'),
              _chip('Canceladas', 'CANCELADA'),
            ],
          ),
        ),
        Expanded(
          child: _carregando
              ? const Center(child: CircularProgressIndicator())
              : _vendas.isEmpty
                  ? const Center(child: Text('Nenhuma venda encontrada.'))
                  : RefreshIndicator(
                      onRefresh: _carregar,
                      child: ListView.builder(
                        itemCount: _vendas.length,
                        itemBuilder: (context, i) {
                          final v = _vendas[i];
                          final confirmada = v['status'] == 'CONFIRMADA';
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              onTap: () => _detalhes(v),
                              isThreeLine: true,
                              leading: Icon(
                                confirmada ? Icons.check_circle : Icons.cancel,
                                color: confirmada ? Colors.green : Colors.red,
                              ),
                              title: Text('Venda #${v['id']} • ${v['cliente_nome']}'),
                              subtitle: Text(
                                '${dataHora('${v['data_venda']}')}\n${moeda(v['valor_total'] as num)}',
                              ),
                              trailing: Text(
                                '${v['status']}',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: confirmada ? Colors.green.shade700 : Colors.red.shade700,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
        ),
      ],
    );
  }
}
