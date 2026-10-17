import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

class DashboardPage extends StatefulWidget {
  final void Function(int) onNavegar;

  const DashboardPage({super.key, required this.onNavegar});

  @override
  State<DashboardPage> createState() => _DashboardPageState();
}

class _DashboardPageState extends State<DashboardPage> {
  final _db = DatabaseHelper.instance;
  Map<String, num> _resumo = {};
  List<Linha> _alertas = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  Future<void> _carregar() async {
    try {
      final r = await _db.resumo();
      final a = await _db.listarEstoqueBaixo();
      if (!mounted) return;
      setState(() {
        _resumo = r;
        _alertas = a;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _carregarExemplos() async {
    final ok = await confirmar(
      context,
      'Dados de exemplo',
      'Cadastrar 16 produtos (4 categorias) e 5 clientes para testes?',
    );
    if (!ok || !mounted) return;
    try {
      await _db.carregarExemplos();
      if (!mounted) return;
      mostrarMensagem(context, 'Dados de exemplo cadastrados com sucesso!');
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Widget _indicador(String titulo, String valor, IconData icone, Color cor) {
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icone, color: cor),
              const SizedBox(height: 8),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  valor,
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
                ),
              ),
              Text(titulo),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Center(child: CircularProgressIndicator());
    }
    final r = _resumo;
    return RefreshIndicator(
      onRefresh: _carregar,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            color: Colors.teal.shade50,
            child: const ListTile(
              leading: Icon(Icons.store, size: 36, color: Colors.teal),
              title: Text('Mundo Pet', style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('Gestão de comércio pet • Belo Horizonte, MG'),
            ),
          ),
          Row(
            children: [
              _indicador('Produtos', '${(r['produtos'] ?? 0).toInt()}', Icons.pets, Colors.teal),
              _indicador('Clientes', '${(r['clientes'] ?? 0).toInt()}', Icons.people, Colors.indigo),
            ],
          ),
          Row(
            children: [
              _indicador('Vendas confirmadas', '${(r['vendas'] ?? 0).toInt()}', Icons.receipt_long, Colors.orange),
              _indicador('Faturamento', moeda(r['faturamento'] ?? 0), Icons.attach_money, Colors.green),
            ],
          ),
          const SizedBox(height: 8),
          const Text('Atalhos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              FilledButton.icon(
                onPressed: () => widget.onNavegar(3),
                icon: const Icon(Icons.point_of_sale),
                label: const Text('Nova venda'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => widget.onNavegar(1),
                icon: const Icon(Icons.pets),
                label: const Text('Produtos'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => widget.onNavegar(2),
                icon: const Icon(Icons.people),
                label: const Text('Clientes'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => widget.onNavegar(5),
                icon: const Icon(Icons.inventory),
                label: const Text('Estoque'),
              ),
              FilledButton.tonalIcon(
                onPressed: () => widget.onNavegar(4),
                icon: const Icon(Icons.receipt_long),
                label: const Text('Histórico'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.warning_amber_rounded, color: Colors.red),
                      const SizedBox(width: 8),
                      Text(
                        'Alertas de estoque (${_alertas.length})',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (_alertas.isEmpty)
                    const Text('Nenhum produto com estoque baixo.')
                  else
                    for (final p in _alertas)
                      ListTile(
                        dense: true,
                        contentPadding: EdgeInsets.zero,
                        title: Text('${p['nome']}'),
                        subtitle: Text('Estoque: ${p['quantidade']} (mínimo: ${p['estoque_minimo']})'),
                        trailing: Icon(Icons.error_outline, color: Colors.red.shade700),
                      ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: _carregarExemplos,
            icon: const Icon(Icons.dataset),
            label: const Text('Carregar dados de exemplo'),
          ),
        ],
      ),
    );
  }
}
