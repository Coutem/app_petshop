import 'package:flutter/material.dart';

import 'clientes_page.dart';
import 'dashboard_page.dart';
import 'estoque_page.dart';
import 'historico_page.dart';
import 'produtos_page.dart';
import 'vendas_page.dart';

/// Tela inicial: identificação do comércio e menu de navegação (RF01).
class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int _indice = 0;

  static const _titulos = [
    'Dashboard',
    'Produtos',
    'Clientes',
    'Nova venda',
    'Histórico de vendas',
    'Estoque',
  ];

  static const _icones = [
    Icons.dashboard,
    Icons.pets,
    Icons.people,
    Icons.point_of_sale,
    Icons.receipt_long,
    Icons.inventory,
  ];

  void _ir(int i) => setState(() => _indice = i);

  Widget _pagina() {
    switch (_indice) {
      case 0:
        return DashboardPage(onNavegar: _ir);
      case 1:
        return const ProdutosPage();
      case 2:
        return const ClientesPage();
      case 3:
        return const VendasPage();
      case 4:
        return const HistoricoPage();
      default:
        return const EstoquePage();
    }
  }

  @override
  Widget build(BuildContext context) {
    final cores = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(_titulos[_indice])),
      drawer: Drawer(
        child: ListView(
          padding: EdgeInsets.zero,
          children: [
            DrawerHeader(
              decoration: BoxDecoration(color: cores.primary),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Icon(Icons.pets, size: 40, color: cores.onPrimary),
                  const SizedBox(height: 8),
                  Text(
                    'Mundo Pet',
                    style: TextStyle(
                      color: cores.onPrimary,
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Text(
                    'PetShop Manager • Belo Horizonte, MG',
                    style: TextStyle(color: cores.onPrimary),
                  ),
                ],
              ),
            ),
            for (var i = 0; i < _titulos.length; i++)
              ListTile(
                leading: Icon(_icones[i]),
                title: Text(_titulos[i]),
                selected: i == _indice,
                onTap: () {
                  Navigator.pop(context);
                  _ir(i);
                },
              ),
          ],
        ),
      ),
      body: _pagina(),
    );
  }
}
