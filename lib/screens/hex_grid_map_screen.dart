import 'package:flutter/material.dart';
import '../models/hex_grid_cell.dart';
import '../models/level_specs.dart';
import '../utils/hex_grid_builder.dart';
import '../widgets/hex_cell.dart';
import '../main.dart';
import 'level_card_screen.dart';

class HexGridMapScreen extends StatefulWidget {
  const HexGridMapScreen({super.key});

  @override
  State<HexGridMapScreen> createState() => _HexGridMapScreenState();
}

class _HexGridMapScreenState extends State<HexGridMapScreen> {
  bool _unlockAll = false;
  late Future<List<List<HexGridCell>>> _gridFuture;

  @override
  void initState() {
    super.initState();
    _gridFuture = _loadGrid();
  }

  Future<List<List<HexGridCell>>> _loadGrid() async {
    final levels = await LevelSpecs.loadAll();
    final progress = await localProgressRepository.getAllProgress();
    return buildHexGrid(levels, progress);
  }

  void _toggleUnlockAll() {
    setState(() {
      _unlockAll = !_unlockAll;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Level Map'),
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(
              _unlockAll ? Icons.lock_open : Icons.lock_outline,
              size: 20,
              color: _unlockAll ? Colors.amber : Colors.white38,
            ),
            tooltip: 'Unlock all (testing)',
            onPressed: _toggleUnlockAll,
          ),
        ],
      ),
      body: FutureBuilder<List<List<HexGridCell>>>(
        future: _gridFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final grid = snapshot.data!;

          // Apply debug unlock if toggled.
          if (_unlockAll) {
            for (final row in grid) {
              for (final cell in row) {
                if (cell.hasLevels) cell.isUnlocked = true;
              }
            }
          }

          return _HexGridView(grid: grid);
        },
      ),
    );
  }
}

class _HexGridView extends StatelessWidget {
  final List<List<HexGridCell>> grid;
  const _HexGridView({required this.grid});

  static const double _cellSize = 90.0;
  static const double _headerHeight = 36.0;
  static const double _hGap = 6.0;
  static const double _vGap = 6.0;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Column headers.
          Row(
            mainAxisSize: MainAxisSize.min,
            children: List.generate(hexGridColumns, (col) {
              return SizedBox(
                width: _cellSize + _hGap,
                height: _headerHeight,
                child: Center(
                  child: Text(
                    '×${col + 1}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: col == 0 ? Colors.white54 : Colors.white24,
                    ),
                  ),
                ),
              );
            }),
          ),
          // Grid rows.
          for (int row = 0; row < grid.length; row++)
            Padding(
              padding: const EdgeInsets.only(bottom: _vGap),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int col = 0; col < hexGridColumns; col++)
                    Padding(
                      padding: EdgeInsets.only(right: col < hexGridColumns - 1 ? _hGap : 0),
                      child: Hero(
                        tag: 'hex_${row}_$col',
                        child: HexCell(
                          cell: grid[row][col],
                          size: _cellSize,
                          onTap: () => _onCellTapped(context, grid, row, col),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
        ),
      ),
    );
  }

  void _onCellTapped(BuildContext context, List<List<HexGridCell>> grid, int row, int col) {
    final cell = grid[row][col];
    if (!cell.isUnlocked || !cell.hasLevels) return;

    Navigator.push(
      context,
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 400),
        reverseTransitionDuration: const Duration(milliseconds: 300),
        pageBuilder: (context, animation, secondaryAnimation) {
          return LevelCardScreen(
            row: grid[row],
            initialColumn: col,
          );
        },
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}
