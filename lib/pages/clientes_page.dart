import 'package:flutter/material.dart';

import '../database/db_helper.dart';
import '../utils/helpers.dart';

class ClientesPage extends StatefulWidget {
  const ClientesPage({super.key});

  @override
  State<ClientesPage> createState() => _ClientesPageState();
}

class _ClientesPageState extends State<ClientesPage> {
  final _db = DatabaseHelper.instance;
  final _busca = TextEditingController();
  List<Linha> _clientes = [];
  bool _carregando = true;

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    super.dispose();
  }

  Future<void> _carregar() async {
    try {
      final r = await _db.listarClientes(busca: _busca.text);
      if (!mounted) return;
      setState(() {
        _clientes = r;
        _carregando = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _carregando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  Future<void> _abrirForm([Linha? cliente]) async {
    final salvou = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => ClienteFormPage(cliente: cliente)),
    );
    if (salvou == true) await _carregar();
  }

  Future<void> _excluir(Linha c) async {
    final ok = await confirmar(
      context,
      'Excluir cliente',
      'Deseja excluir "${c['nome']}"? Se ele já tiver vendas, será apenas inativado para preservar o histórico.',
    );
    if (!ok || !mounted) return;
    try {
      final fisico = await _db.excluirCliente(c['id'] as int);
      if (!mounted) return;
      mostrarMensagem(
        context,
        fisico ? 'Cliente excluído com sucesso.' : 'Cliente com vendas: foi inativado e o histórico foi preservado.',
      );
      await _carregar();
    } catch (e) {
      if (!mounted) return;
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _abrirForm(),
        icon: const Icon(Icons.person_add),
        label: const Text('Cliente'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: TextField(
              controller: _busca,
              decoration: InputDecoration(
                labelText: 'Pesquisar cliente',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () {
                    _busca.clear();
                    _carregar();
                  },
                ),
              ),
              onChanged: (_) => _carregar(),
            ),
          ),
          Expanded(
            child: _carregando
                ? const Center(child: CircularProgressIndicator())
                : _clientes.isEmpty
                    ? const Center(child: Text('Nenhum cliente encontrado.'))
                    : ListView.builder(
                        padding: const EdgeInsets.only(bottom: 88),
                        itemCount: _clientes.length,
                        itemBuilder: (context, i) {
                          final c = _clientes[i];
                          final partes = [
                            '${c['telefone'] ?? ''}',
                            '${c['email'] ?? ''}',
                            '${c['endereco'] ?? ''}',
                          ].where((s) => s.trim().isNotEmpty).join('\n');
                          return Card(
                            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            child: ListTile(
                              onTap: () => _abrirForm(c),
                              leading: const Icon(Icons.person, color: Colors.indigo),
                              title: Text('${c['nome']}'),
                              subtitle: partes.isEmpty ? null : Text(partes),
                              isThreeLine: partes.split('\n').length > 1,
                              trailing: PopupMenuButton<String>(
                                onSelected: (v) {
                                  if (v == 'editar') _abrirForm(c);
                                  if (v == 'excluir') _excluir(c);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'editar', child: Text('Editar')),
                                  PopupMenuItem(value: 'excluir', child: Text('Excluir')),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }
}

class ClienteFormPage extends StatefulWidget {
  final Linha? cliente;

  const ClienteFormPage({super.key, this.cliente});

  @override
  State<ClienteFormPage> createState() => _ClienteFormPageState();
}

class _ClienteFormPageState extends State<ClienteFormPage> {
  final _formKey = GlobalKey<FormState>();
  final _nome = TextEditingController();
  final _telefone = TextEditingController();
  final _email = TextEditingController();
  final _endereco = TextEditingController();
  bool _salvando = false;

  bool get _edicao => widget.cliente != null;

  @override
  void initState() {
    super.initState();
    final c = widget.cliente;
    if (c != null) {
      _nome.text = '${c['nome']}';
      _telefone.text = '${c['telefone'] ?? ''}';
      _email.text = '${c['email'] ?? ''}';
      _endereco.text = '${c['endereco'] ?? ''}';
    }
  }

  @override
  void dispose() {
    _nome.dispose();
    _telefone.dispose();
    _email.dispose();
    _endereco.dispose();
    super.dispose();
  }

  Future<void> _salvar() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _salvando = true);
    try {
      await DatabaseHelper.instance.salvarCliente(
        {
          'nome': _nome.text,
          'telefone': _telefone.text,
          'email': _email.text,
          'endereco': _endereco.text,
        },
        id: widget.cliente?['id'] as int?,
      );
      if (!mounted) return;
      mostrarMensagem(context, 'Cliente salvo com sucesso!');
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _salvando = false);
      mostrarMensagem(context, textoErro(e), erro: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_edicao ? 'Editar cliente' : 'Novo cliente')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nome,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(labelText: 'Nome *'),
              validator: obrigatorio('Informe o nome do cliente'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _telefone,
              keyboardType: TextInputType.phone,
              decoration: const InputDecoration(labelText: 'Telefone'),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _email,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'E-mail'),
              validator: (v) {
                final t = (v ?? '').trim();
                if (t.isEmpty) return null;
                return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t) ? null : 'E-mail inválido';
              },
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _endereco,
              maxLines: 2,
              decoration: const InputDecoration(labelText: 'Endereço'),
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _salvando ? null : _salvar,
              icon: const Icon(Icons.save),
              label: Text(_salvando ? 'Salvando...' : 'Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
